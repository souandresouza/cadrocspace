#!/usr/bin/env bash

# This script records the screen (and audio) and manages the whole lifecycle.
#
# Two engines are available:
#   wl-screenrec  (default) - 3 audio modes: Only Sound, Micro and Sound, No Sound
#   gpu-screen-recorder (--gpu) - hardware encoder, used for games/CPU-heavy apps
#
# Without arguments it toggles: starts recording, or stops the active one.
# Options:
#   --gpu            Start with gpu-screen-recorder instead of wl-screenrec
#   -h, --help       Show this help message

# Load configurations
[ -f "$HOME/cadroccfg/setting.sh" ] && source "$HOME/cadroccfg/setting.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
Usage: record.sh [--gpu]
Record the screen with audio, or stop the recording that is running.

Options:
    --gpu            Use gpu-screen-recorder (hardware encoder) instead of wl-screenrec
    -h, --help       Show this help message
EOF
    exit 0
fi

# Defaults
SCREENREC_SAVE_DIR=${SCREENREC_SAVE_DIR:-"$HOME/Vídeos"}
REC_COMMAND=${REC_COMMAND:-"wl-screenrec"}
REC_OPTS=${REC_OPTS:-"--max-fps 60"}

PID_FILE="/tmp/recording_pid"
TIME_FILE="/tmp/recording_time"
AUDIO_MODULES_FILE="/tmp/recording_audio_modules"
KEEPALIVE_PID_FILE="/tmp/recording_keepalive_pid"
COMBINED_SINK_NAME="rec_combined_sink"
LOCKED_SAMPLE_RATE="${SCREENREC_LOCK_RATE:-48000}"
LOCKED_QUANTUM="${SCREENREC_LOCK_QUANTUM:-1024}"

# Print debug directly to terminal
debug_log() {
    if [ "${SCREENREC_DEBUG:-0}" = "1" ]; then
        echo "[$(date +%H:%M:%S) DEBUG] $*"
    fi
}

# Dependency checks (o motor gpu não precisa de pactl/wl-screenrec)
if [[ "${1:-}" == "--gpu" ]]; then
    command -v gpu-screen-recorder &> /dev/null || {
        notify-send -u critical "Recording System" "gpu-screen-recorder não encontrado!" -i dialog-error
        exit 1
    }
else
    if ! command -v "$REC_COMMAND" &> /dev/null || ! command -v pactl &> /dev/null; then
        notify-send -u critical "Recording System" "Dependências ausentes ($REC_COMMAND ou pactl)!" -i dialog-error
        exit 1
    fi
fi

mkdir -p "$SCREENREC_SAVE_DIR"

# Setup virtual null-sink and loopbacks for mic + system audio
setup_virtual_audio() {
    local mic_device="$1"
    local real_sink="$2"
    local system_monitor="${real_sink}.monitor"

    debug_log "Init virtual audio: mic=$mic_device | sink=$real_sink"
    if [ -z "$real_sink" ]; then return 1; fi

    rm -f "$AUDIO_MODULES_FILE"

    # 1. Create null-sink
    local null_sink_module_id
    null_sink_module_id=$(pactl load-module module-null-sink \
        sink_name="$COMBINED_SINK_NAME" \
        sink_properties=device.description="RecordingCombinedAudio" 2>/dev/null)

    if [ -z "$null_sink_module_id" ]; then return 1; fi
    echo "$null_sink_module_id" >> "$AUDIO_MODULES_FILE"

    # Force default sink back to real sink to prevent feedback loops
    pactl set-default-sink "$real_sink" 2>/dev/null

    # 2. Loopback mic to null-sink
    local loopback_mic_id
    loopback_mic_id=$(pactl load-module module-loopback \
        source="$mic_device" \
        sink="$COMBINED_SINK_NAME" \
        latency_msec=1 2>/dev/null)

    if [ -z "$loopback_mic_id" ]; then
        teardown_virtual_audio
        return 1
    fi
    echo "$loopback_mic_id" >> "$AUDIO_MODULES_FILE"

    # Prevent recursive loopback
    if [ "$system_monitor" = "${COMBINED_SINK_NAME}.monitor" ]; then
        teardown_virtual_audio
        return 1
    fi

    # 3. Loopback system audio to null-sink
    local loopback_sys_id
    loopback_sys_id=$(pactl load-module module-loopback \
        source="$system_monitor" \
        sink="$COMBINED_SINK_NAME" \
        latency_msec=1 2>/dev/null)

    if [ -z "$loopback_sys_id" ]; then
        teardown_virtual_audio
        return 1
    fi
    echo "$loopback_sys_id" >> "$AUDIO_MODULES_FILE"

    return 0
}

# Remove virtual audio modules
teardown_virtual_audio() {
    if [ -f "$AUDIO_MODULES_FILE" ]; then
        tac "$AUDIO_MODULES_FILE" | while read -r module_id; do
            [ -n "$module_id" ] && pactl unload-module "$module_id" 2>/dev/null
        done
        rm -f "$AUDIO_MODULES_FILE"
        debug_log "Virtual audio modules unloaded"
    fi
}

# Lock PipeWire rate/quantum to prevent renegotiation crashes during stream pause
lock_pipewire_rate() {
    if ! command -v pw-metadata &> /dev/null; then return 1; fi
    pw-metadata -n settings 0 clock.force-rate "$LOCKED_SAMPLE_RATE" 2>/dev/null
    pw-metadata -n settings 0 clock.force-quantum "$LOCKED_QUANTUM" 2>/dev/null
    debug_log "Locked rate=$LOCKED_SAMPLE_RATE, quantum=$LOCKED_QUANTUM"
}

unlock_pipewire_rate() {
    if command -v pw-metadata &> /dev/null; then
        pw-metadata -n settings 0 clock.force-rate 0 2>/dev/null
        pw-metadata -n settings 0 clock.force-quantum 0 2>/dev/null
        debug_log "Unlocked PipeWire rate and quantum"
    fi
}

# Prevent default sink from auto-suspending by feeding it silent data
start_keepalive_silence() {
    local real_sink="$1"
    if [ -z "$real_sink" ] || ! command -v pacat &> /dev/null; then return 1; fi

    ( pacat --device="$real_sink" --raw --rate=48000 --channels=2 --format=s16le < /dev/zero & echo $! > "$KEEPALIVE_PID_FILE" ) 2>/dev/null
    sleep 0.05
    debug_log "Keepalive started on $real_sink"
}

stop_keepalive_silence() {
    if [ -f "$KEEPALIVE_PID_FILE" ]; then
        kill "$(cat "$KEEPALIVE_PID_FILE")" 2>/dev/null
        rm -f "$KEEPALIVE_PID_FILE"
        debug_log "Keepalive stopped"
    fi
}

# Cleanup on exit or interrupt
trap 'teardown_virtual_audio; stop_keepalive_silence; unlock_pipewire_rate' EXIT INT TERM

stop_recording() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        kill -SIGINT "$PID" 2>/dev/null
        while ps -p "$PID" > /dev/null 2>&1; do sleep 0.1; done

        rm -f "$PID_FILE" "$TIME_FILE"
        teardown_virtual_audio
        stop_keepalive_silence
        unlock_pipewire_rate

        notify-send -u normal "Recording System" "Saved Video" -i video-display
        debug_log "Recording stopped and saved"
    fi
}

# wl-screenrec aborta com 2+ monitores se não receber --output/--geometry:
# neste caso pergunta qual monitor gravar (a menos que REC_OPTS já defina um).
pick_output() {
    if [[ " $REC_OPTS " =~ [[:space:]](-o|--output|-g|--geometry)([[:space:]=]) ]]; then return 0; fi
    command -v wlr-randr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0

    local outs=()
    mapfile -t outs < <(wlr-randr --json 2>/dev/null | jq -r '.[] | select(.enabled) | .name')
    (( ${#outs[@]} > 1 )) || return 0

    local out
    out=$(printf '%s\n' "${outs[@]}" | fuzzel --dmenu -p "Selecionar Monitor:")
    if [ -z "$out" ]; then exit 0; fi
    REC_OPTS="$REC_OPTS -o $out"
}

start_recording() {
    options="󰑊 Somente Som\n󰍬 Microfone e Som\n󰔊 Sem Som"
    chosen=$(echo -e "$options" | fuzzel --dmenu -p "Selecionar Modo:")
    if [ -z "$chosen" ]; then exit 0; fi

    pick_output

    FILENAME="recording_$(date +%d%m%Y_%H%M%S).mp4"
    FILEPATH="$SCREENREC_SAVE_DIR/$FILENAME"

    # Get actual default sink BEFORE creating virtual ones
    REAL_SINK=$(pactl get-default-sink 2>/dev/null)
    if [ -z "$REAL_SINK" ]; then
        notify-send -u critical "Recording System" "Default sink not found!" -i dialog-error
        exit 1
    fi

    debug_log "Starting record mode: $chosen | Real sink: $REAL_SINK"

    case "$chosen" in
        *"Somente Som"|*"Only Sound")
            lock_pipewire_rate
            start_keepalive_silence "$REAL_SINK"
            $REC_COMMAND $REC_OPTS --audio --audio-device "${REAL_SINK}.monitor" -f "$FILEPATH" &
            MSG="Recording: System Audio"
            ;;
        *"Microfone e Som"|*"Micro and Sound")
            # Filter for physical mics only
            AUDIO_DEVICE=$(pactl list short sources | awk '{print $2}' | grep -viE '\.monitor$' | fuzzel --dmenu -p "Selecionar Microfone/Fonte:")
            if [ -z "$AUDIO_DEVICE" ]; then exit 0; fi

            lock_pipewire_rate
            start_keepalive_silence "$REAL_SINK"

            if ! setup_virtual_audio "$AUDIO_DEVICE" "$REAL_SINK"; then
                stop_keepalive_silence
                unlock_pipewire_rate
                exit 1
            fi

            $REC_COMMAND $REC_OPTS --audio --audio-device "${COMBINED_SINK_NAME}.monitor" -f "$FILEPATH" &
            MSG="Recording: Mic + System Audio"
            ;;
        *"Sem Som"|*"No Sound")
            $REC_COMMAND $REC_OPTS -f "$FILEPATH" &
            MSG="Gravando: Sem Som"
            ;;
    esac

    echo $! > "$PID_FILE"
    notify-send "Sistema de Gravação" "$MSG" -i video-display -t 1000

    # Timer loop
    SEC=0
    while [ -f "$PID_FILE" ] && ps -p "$(cat "$PID_FILE")" > /dev/null 2>&1; do
        MIN=$((SEC / 60))
        S=$((SEC % 60))
        printf "%02d:%02d" $MIN $S > "$TIME_FILE"
        sleep 1
        SEC=$((SEC + 1))
    done

    # Cleanup if wl-screenrec exits on its own
    rm -f "$PID_FILE" "$TIME_FILE"
    teardown_virtual_audio
    stop_keepalive_silence
    unlock_pipewire_rate
}

# ============================================================
# gpu-screen-recorder (codegen alternative, JOGO/CPU com encoder HW)
# Mesclado do antigo ~/.config/scripts/screen_recorder.sh.
# Usa os mesmos /tmp/recording_pid e /tmp/recording_time, então o
# módulo custom/recorder da waybar funciona igual para os dois motores.
# ============================================================
GPU_RECORD_DIR=${GPU_RECORD_DIR:-"$SCREENREC_SAVE_DIR/Recordings"}
GPU_TEMP_FILE="/tmp/screen_recorder_last.txt"
GPU_OPTS=${GPU_OPTS:-"-w screen -f 60 -q ultra -a default_output"}
GPU_SEND_VIA_LOCALSEND=${GPU_SEND_VIA_LOCALSEND:-true}

# comm do kernel tem só 15 caracteres (-f daria falsos positivos)
gpu_recording_active() { pgrep -x gpu-screen-reco >/dev/null; }

gpu_stop_recording() {
    local filename duration
    pkill -x gpu-screen-reco
    sleep 0.5
    notify-send "Recording" "Gravação salva em $GPU_RECORD_DIR" -t 3000

    if $GPU_SEND_VIA_LOCALSEND && command -v zenity >/dev/null 2>&1 && command -v localsend >/dev/null 2>&1; then
        if zenity --question --title="Enviar para celular?" \
                  --text="Deseja enviar a gravação para o celular via LocalSend?\n\nO arquivo continua salvo em:\n$GPU_RECORD_DIR" \
                  --ok-label="Enviar" --cancel-label="Não enviar" --width=400; then
            filename=$(cat "$GPU_TEMP_FILE" 2>/dev/null)
            if [[ -n "$filename" && -f "$GPU_RECORD_DIR/$filename" ]]; then
                if localsend send "$GPU_RECORD_DIR/$filename"; then
                    notify-send "Recording" "Enviado: $filename"
                else
                    notify-send "Recording" "Falha ao enviar; salvo em $GPU_RECORD_DIR/$filename"
                fi
            else
                notify-send "Recording" "Arquivo não encontrado"
            fi
        else
            notify-send "Recording" "Mantido localmente em $GPU_RECORD_DIR"
        fi
    else
        notify-send "Recording" "Mantido localmente em $GPU_RECORD_DIR"
    fi

    rm -f "$GPU_TEMP_FILE"
}

gpu_start_recording() {
    local filename
    mkdir -p "$GPU_RECORD_DIR"
    filename="Screen_recording_$(date +"%d%m%Y_%H%M%S").mkv"
    echo "$filename" > "$GPU_TEMP_FILE"
    notify-send "Recording" "Iniciada —.super+shift+F11 para parar" -t 2000

    # shellcheck disable=SC2086
    gpu-screen-recorder $GPU_OPTS -o "$GPU_RECORD_DIR/$filename" &
    local gsr_pid=$!

    echo "$gsr_pid" > "$PID_FILE"
    setsid -f bash -c '
        pid="$1"; s=0
        while kill -0 "$pid" 2>/dev/null; do
            printf "%02d:%02d" $((s / 60)) $((s % 60)) > /tmp/recording_time
            sleep 1; s=$((s + 1))
        done
        rm -f /tmp/recording_pid /tmp/recording_time
    ' _ "$gsr_pid" >/dev/null 2>&1

    # Fica no foreground até a gravação terminar (ícone da waybar sai junto)
    while kill -0 "$gsr_pid" 2>/dev/null; do sleep 1; done
    rm -f "$PID_FILE" "$TIME_FILE"
}

# ============================================================
# MAIN
# ============================================================

# O módulo custom/recorder da waybar chama este script ao clicar, então
# qualquer motor ativo é encerrado por aqui.
if gpu_recording_active; then
    gpu_stop_recording
    exit 0
fi

if [ -f "$PID_FILE" ]; then
    stop_recording
elif [[ "${1:-}" == "--gpu" ]]; then
    gpu_start_recording
else
    start_recording
fi
