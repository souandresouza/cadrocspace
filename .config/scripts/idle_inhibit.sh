#!/usr/bin/env bash

# This script is designed to manage the idle state of the screen based on a state file and audio playback status.
# The main core is in swayidle, this script return value is used to determine

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cadroc_theme.sh"
STATE_FILE="$STATE_DIR/idle_inhibit"

# Ensure the directory exists
mkdir -p "$STATE_DIR"

# Audio checking logic
is_audio_playing() {
    local check_audio
    check_audio=$(pactl list sink-inputs 2>/dev/null | awk '
        /Sink Input/ { is_target=1; corked=0; muted=0 }
        is_target && /Corked: yes/ { corked=1 }
        is_target && /Mute: yes/ { muted=1 }
        is_target && /media.class = "Stream\/Output\/Audio"/ {
            if (corked == 0 && muted == 0) {
                found=1
            }
        }
        END { print (found == 1 ? "1" : "0") }
    ')

    local timestamp_file="/tmp/cadroc_audio_timestamp"
    local current_time=$(date +%s)
    local grace_period=5

    if [[ "$check_audio" == "1" ]]; then
        echo "$current_time" > "$timestamp_file"
        return 0
    fi

    if [[ -f "$timestamp_file" ]]; then
        local last_played=$(cat "$timestamp_file")
        if (( current_time - last_played < grace_period )); then
            return 0
        fi
    fi

    return 1
}

# Handle help argument
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        cat <<'EOF'
Usage: idle_inhibit.sh [OPTION]
Control screen idle prevention based on state and audio playback.

Options:
    --check             Check whether idle is inhibited
    --toggle            Toggle idle inhibition
    -h, --help          Show this help message
EOF
    exit 0
fi

# Handle the check logic for the state file
if [[ "$1" == "--check" ]]; then
    if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "1" ]]; then
        echo "Swayidle: Inibido (a tela não desliga)"
        echo "State: $(cat "$STATE_FILE")"
        exit 0
    fi

    echo "Swayidle: Permitido (a tela pode desligar)"
    exit 1
fi

# Handle the toggle logic
if [[ "$1" == "--toggle" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        CURRENT_STATE=$(cat "$STATE_FILE")
    else
        CURRENT_STATE="0"
    fi

    if [[ "$CURRENT_STATE" == "1" ]]; then
        echo "0" > "$STATE_FILE"
        echo "Swayidle: Permitido (a tela pode desligar)"
        notify-send "Swayidle" "Inibição desativada (a tela pode desligar)"
        nohup "$SCRIPT_DIR/idle_start.sh" >/dev/null 2>&1 &
    else
        echo "1" > "$STATE_FILE"
        echo "Swayidle: Inibido (a tela não desliga)"
        notify-send "Swayidle" "Inibição ativada (a tela NÃO desliga)"
        pkill -x swayidle
    fi
    exit 0
fi

# Check state
if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "1" ]]; then
    exit 1
fi

# Check if audio is playing
if is_audio_playing; then
    exit 1
fi

exit 0