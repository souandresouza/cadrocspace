#!/usr/bin/env bash
# =============================================================================
# convert.sh -- motor unificado de conversão (imagens, vídeo e frames)
# =============================================================================
#
# Uso:
#   convert.sh image  [opções] [arquivo|diretório ...]
#   convert.sh video  [opções] [arquivo|diretório ...]
#   convert.sh frames [opções] [arquivo|diretório ...]
#   convert.sh --help
#
# Princípios (inspirados no VERT):
#   - escolher o motor/conversão mais adequada por formato
#   - remuxar (copiar streams) antes de reencodar vídeo
#   - validar a saída e só então substituir/apagar o original
#   - escrita atômica e nomes de saída sem colisão
#   - um arquivo com problema não aborta o lote
#
# Os wrappers images_convert.sh e video_frames_extract.sh continuam existindo.
# =============================================================================

set -uo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || true)
if [[ -z "$SCRIPT_PATH" ]]; then
    SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"
fi
SCRIPT_DIR=$(dirname -- "$SCRIPT_PATH")

# shellcheck source=lib/convert-lib.sh
source "$SCRIPT_DIR/lib/convert-lib.sh"

# -----------------------------------------------------------------------------
# Limpeza de temporários
# -----------------------------------------------------------------------------
TMP_OUT=""
TMP_ERR=""
TMP_DEC=""

cleanup_tmp() {
    [[ -n "$TMP_OUT" && -e "$TMP_OUT" ]] && rm -f -- "$TMP_OUT"
    [[ -n "$TMP_ERR" && -e "$TMP_ERR" ]] && rm -f -- "$TMP_ERR"
    [[ -n "$TMP_DEC" && -e "$TMP_DEC" ]] && rm -f -- "$TMP_DEC"
}
trap cleanup_tmp EXIT
trap 'cleanup_tmp; exit 130' INT
trap 'cleanup_tmp; exit 143' TERM

# -----------------------------------------------------------------------------
# Ajuda
# -----------------------------------------------------------------------------
main_help() {
    cat <<'EOF'
convert.sh -- motor unificado de conversão

Uso:
  convert.sh image  [opções] [arquivo|diretório ...]
  convert.sh video  [opções] [arquivo|diretório ...]
  convert.sh frames [opções] [arquivo|diretório ...]

Exemplos:
  convert.sh image --to webp --max 1920x1080 --strip ~/Downloads
  convert.sh image --preset mobile foto.jpg
  convert.sh video --to mp4 --copy filme.mkv
  convert.sh video --to webm --crf 32 filme.mp4
  convert.sh frames --fps 1 --width 960 --format jpg video.mp4

Use "convert.sh image --help" (ou video/frames) para as opções de cada modo.

Princípios:
  - imagens: escolhe motor/fallback (ImageMagick, libvips, heif-convert, rsvg)
  - vídeo: tenta remux (-c copy) antes de reencodar
  - escrita atômica: só apaga/substitui o original depois de validar a saída
  - lotes continuam mesmo se um arquivo falhar; resumo e exit code no final
EOF
}

image_help() {
    cat <<'EOF'
convert.sh image -- converter imagens

Uso:
  convert.sh image [opções] [arquivo|diretório ...]
  (sem caminhos: usa ~/Downloads)

Opções:
  -t, --to FORMATO       auto|png|jpg|webp|avif|tiff|gif|bmp|jxl|ico [auto]
  -q, --quality N        qualidade 1-100 (default depende do formato)
  -m, --max LxA          reduzir para caber em LxA, sem ampliar [sem limite]
      --no-resize        não redimensionar
      --preset NOME      web|archive|mobile|social|icon
      --from LISTA       extensões de entrada (ex.: heic,jpg,webp)
      --recursive        incluir subdiretórios [padrão]
      --no-recursive     só o diretório informado
      --strip            remover metadados (EXIF, ICC, comentários)
      --keep-meta        manter metadados [padrão]
      --flatten          achatar transparência no fundo
      --keep-alpha       manter transparência quando o formato permitir [auto]
      --bg COR           cor de fundo ao achatar [white]
      --delete-originals apagar o original após conversão validada
      --keep-originals   manter o original [padrão do motor]
      --overwrite        sobrescrever destino existente
  -j, --jobs N           conversões em paralelo [4]
      --dry-run          mostrar o que seria feito
  -v, --verbose          log detalhado
  -h, --help             esta ajuda

Observações:
  - o modo image nunca apaga o original por padrão (use --delete-originals);
  - se o destino já existir, é criado "nome-1.ext" em vez de sobrescrever;
  - formatos animados preservam a animação só quando o destino suporta;
  - HEIC/AVIF/JXL/SVG têm fallback automático de decodificação.
EOF
}

video_help() {
    cat <<'EOF'
convert.sh video -- converter vídeo (com remux quando possível)

Uso:
  convert.sh video [opções] arquivo|diretório ...

Opções:
  -t, --to FORMATO       mp4|mkv|webm|mov|avi|m4v|flv|wmv|mpg|mpeg|ts|
                         m2ts|mts|3gp|3g2|ogv|vob|mxf|gif|divx [mp4]
      --copy             forçar cópia de streams (falha se incompatível)
      --reencode         forçar reencode
  -c, --video-codec C    codec de vídeo (h264, hevc, vp9, av1, mpeg4, ...)
  -a, --audio-codec C    codec de áudio (aac, opus, mp3, copy, ...)
      --crf N            qualidade (CRF) para x264/x265/vp9 [23]
      --bitrate B        bitrate de vídeo (ex.: 4M)
      --audio-bitrate B  bitrate de áudio [128k]
  -s, --preset NOME      preset x264/x265: ultrafast..veryslow [medium]
  -m, --max LxA          reduzir resolução, sem ampliar
      --fps N            forçar FPS
      --no-audio         remover áudio
      --strip            remover metadados
      --hw               tentar encoder de hardware (NVENC) com fallback
      --extra-args "..." argumentos extras para o ffmpeg
      --from LISTA       extensões de entrada
      --recursive        incluir subdiretórios [padrão]
      --no-recursive     só o diretório informado
      --delete-originals apagar o original após conversão validada
      --overwrite        sobrescrever destino existente
  -j, --jobs N           conversões em paralelo [1]
      --dry-run          mostrar o que seria feito
  -v, --verbose          log detalhado
  -h, --help             esta ajuda

Observações:
  - o motor tenta -c copy quando o codec já é compatível com o container;
  - 3GP/3G2, MPEG, WMV/ASF têm limites de resolução/FPS aplicados;
  - a saída é validada com ffprobe antes de substituir o original.
EOF
}

frames_help() {
    cat <<'EOF'
convert.sh frames -- extrair frames de vídeos

Uso:
  convert.sh frames [opções] arquivo|diretório ...
  (sem caminhos: usa ~/Downloads)

Opções:
      --fps N            frames por segundo [2]
      --scene N          extrair por mudança de cena (0-1); ignora --fps
      --max-frames N     máximo de frames por vídeo [100]
      --width N          largura máxima; 0 = original [1280]
      --format F         png|jpg|webp [png]
      --quality N        qualidade 1-100 para jpg/webp [90]
  -o, --output DIR       diretório raiz dos frames [~/Downloads/frames]
      --clean            apagar frames antigos do vídeo [padrão]
      --no-clean         manter frames antigos
      --hwaccel MODO     auto|cuda|vaapi|qsv|none [none]
      --max-size-mb N    ignorar vídeos maiores que N MB; 0 = sem limite [100]
      --max-duration N   ignorar vídeos mais longos que N s; 0 = sem limite [600]
      --from LISTA       extensões de entrada
      --recursive        incluir subdiretórios [padrão]
      --no-recursive     só o diretório informado
  -j, --jobs N           vídeos em paralelo [2]
      --dry-run          mostrar o que seria feito
  -v, --verbose          log detalhado
  -h, --help             esta ajuda
EOF
}

# -----------------------------------------------------------------------------
# Imagens
# -----------------------------------------------------------------------------
default_image_quality() {
    case "$1" in
        jpg|jpeg) echo 88 ;;
        webp)     echo 82 ;;
        avif)     echo 60 ;;
        jxl)      echo 90 ;;
        tiff)     echo 90 ;;
        gif)      echo 90 ;;
        *)        echo 90 ;;
    esac
}

apply_image_preset() {
    case "$1" in
        web)
            [[ -z "$CV_TO" || "$CV_TO" == "auto" ]] && CV_TO="webp"
            [[ -z "$CV_QUALITY" ]] && CV_QUALITY=82
            [[ -z "$CV_MAX" ]] && CV_MAX="1920x1080"
            CV_STRIP=1
            CV_FLATTEN=auto
            ;;
        archive)
            [[ -z "$CV_QUALITY" ]] && CV_QUALITY=95
            CV_MAX=""
            CV_STRIP=0
            CV_FLATTEN=0
            ;;
        mobile)
            [[ -z "$CV_TO" || "$CV_TO" == "auto" ]] && CV_TO="jpg"
            [[ -z "$CV_QUALITY" ]] && CV_QUALITY=85
            [[ -z "$CV_MAX" ]] && CV_MAX="1280x1280"
            CV_STRIP=1
            CV_FLATTEN=1
            ;;
        social)
            [[ -z "$CV_TO" || "$CV_TO" == "auto" ]] && CV_TO="jpg"
            [[ -z "$CV_QUALITY" ]] && CV_QUALITY=90
            [[ -z "$CV_MAX" ]] && CV_MAX="1080x1350"
            CV_STRIP=1
            CV_FLATTEN=1
            ;;
        icon)
            [[ -z "$CV_TO" || "$CV_TO" == "auto" ]] && CV_TO="png"
            [[ -z "$CV_MAX" ]] && CV_MAX="256x256"
            [[ -z "$CV_QUALITY" ]] && CV_QUALITY=90
            CV_STRIP=1
            ;;
        *)
            die "Preset de imagem desconhecido: $1"
            ;;
    esac
}

build_magick_args() {
    local input="$1" in_ext="$2" target="$3" has_alpha="$4" animated="$5" quality="$6"
    local decoded="${7:-0}"

    MAGICK_ARGS=()

    if [[ "$decoded" != "1" ]]; then
        case "$in_ext" in
            svg) MAGICK_ARGS+=(-density 192 -background none) ;;
        esac
    fi

    MAGICK_ARGS+=("$input")

    [[ "${CV_AUTO_ORIENT:-1}" == "1" ]] && MAGICK_ARGS+=(-auto-orient)

    if [[ -n "${CV_MAX:-}" ]]; then
        MAGICK_ARGS+=(-resize "${CV_MAX}>")
    fi

    local flatten=0
    if [[ "${CV_FLATTEN:-auto}" == "1" ]]; then
        flatten=1
    elif [[ "${CV_FLATTEN:-auto}" == "auto" ]]; then
        case "$target" in
            jpg|jpeg|bmp|ppm|pgm|pbm|pnm)
                ((has_alpha == 1)) && flatten=1
                ;;
        esac
    fi
    if ((flatten == 1)); then
        MAGICK_ARGS+=(-background "${CV_BG:-white}" -alpha remove -alpha off)
    fi

    [[ "${CV_STRIP:-0}" == "1" ]] && MAGICK_ARGS+=(-strip)

    case "$target" in
        jpg|jpeg|webp|avif|jxl|tiff|gif)
            MAGICK_ARGS+=(-quality "$quality")
            [[ "$target" == "webp" ]] && MAGICK_ARGS+=(-define webp:method=6)
            ;;
        png)
            MAGICK_ARGS+=(-define png:compression-level=9)
            ;;
    esac

    if [[ "$target" == "gif" && "$animated" == "1" ]]; then
        MAGICK_ARGS+=(-layers Optimize)
    fi
}

convert_image_one() {
    local src="${1:-}"
    local started
    started=$(now_ms)

    if [[ -z "$src" || ! -f "$src" ]]; then
        status_line FAIL "${src:-?}" "" 0 0 "$(( $(now_ms) - started ))" "arquivo inexistente"
        return 1
    fi

    local in_bytes out_bytes
    in_bytes=$(stat -c%s -- "$src" 2>/dev/null || echo 0)

    local in_ext
    in_ext=$(canon_ext "$(ext_of "$src")")
    if [[ -z "$in_ext" ]]; then
        local detected
        detected=$(magick identify -format '%m' "${src}[0]" 2>/dev/null || true)
        in_ext=$(canon_ext "${detected,,}")
    fi
    if [[ -z "$in_ext" ]]; then
        status_line FAIL "$src" "" "$in_bytes" 0 "$(( $(now_ms) - started ))" "não foi possível detectar o formato"
        return 1
    fi

    local target="${CV_TO:-auto}"
    [[ "$target" == "auto" ]] && target=$(auto_target_for "$src" "$in_ext")
    target=$(canon_ext "$target")

    image_probe "$src" 2>/dev/null || true
    local alpha="${IMG_ALPHA:-0}"
    local nframes="${IMG_FRAMES:-1}"
    local width="${IMG_W:-0}"
    local height="${IMG_H:-0}"

    local animated_target=0
    case "$target" in
        gif|webp|tiff) animated_target=1 ;;
    esac

    local selector=""
    if ((nframes > 1)) && ((animated_target == 0)); then
        selector="[0]"
        warn "$(basename -- "$src"): $nframes quadros; usando só o primeiro (destino .$target)"
    fi

    local dir stem base out same=0
    dir=$(dirname -- "$src")
    base=$(basename -- "$src")
    if [[ "$base" == *.* && "$base" != .* ]]; then
        stem="${base%.*}"
    else
        stem="$base"
    fi

    if [[ -n "${2:-}" ]]; then
        out="$2"
        [[ "$out" == "$src" ]] && same=1
    elif [[ "$target" == "$in_ext" ]]; then
        out="$src"
        same=1
    else
        out="$dir/$stem.$target"
    fi

    if ((same == 0)) && [[ -z "${2:-}" && -e "$out" && "${CV_OVERWRITE:-0}" != "1" ]]; then
        unique_path_var "$out"
        out="$CONVERT_REPLY"
    fi

    # Nada a fazer: mesmo formato e nenhuma alteração pedida.
    if ((same == 1)) && [[ -z "${CV_MAX:-}" && "${CV_STRIP:-0}" != "1" && "${CV_FLATTEN:-auto}" == "auto" && -z "${CV_QUALITY:-}" ]]; then
        status_line SKIP "$src" "$out" "$in_bytes" "$in_bytes" "$(( $(now_ms) - started ))" "já está no formato de destino e nenhuma alteração foi pedida"
        return 0
    fi

    local quality="${CV_QUALITY:-}"
    [[ -n "$quality" ]] || quality=$(default_image_quality "$target")

    TMP_OUT=$(temp_output_path "$out")
    TMP_ERR=$(mktemp --tmpdir="$dir" ".${stem}.err.XXXXXX" 2>/dev/null || mktemp)

    local ok=0 reason=""

    build_magick_args "${src}${selector}" "$in_ext" "$target" "$alpha" "$animated_target" "$quality" 0
    debug "magick ${MAGICK_ARGS[*]} -> $TMP_OUT"

    if magick "${MAGICK_ARGS[@]}" "$TMP_OUT" 2>"$TMP_ERR"; then
        ok=1
    else
        reason=$(grep -v '^[[:space:]]*$' "$TMP_ERR" 2>/dev/null | tail -n1 | cut -c1-240)
        debug "magick falhou: ${reason:-sem mensagem}; tentando fallback"

        case "$in_ext" in
            heic|avif|jxl|svg)
                TMP_DEC="${out%.*}.decoded.$$.$RANDOM.png"
                if decode_fallback "$src" "$TMP_DEC" "$in_ext" "$quality" 2>>"$TMP_ERR"; then
                    build_magick_args "$TMP_DEC" "$in_ext" "$target" "$alpha" "$animated_target" "$quality" 1
                    debug "fallback: magick ${MAGICK_ARGS[*]} -> $TMP_OUT"
                    if magick "${MAGICK_ARGS[@]}" "$TMP_OUT" 2>>"$TMP_ERR"; then
                        ok=1
                        reason=""
                    else
                        reason=$(grep -v '^[[:space:]]*$' "$TMP_ERR" 2>/dev/null | tail -n1 | cut -c1-240)
                    fi
                else
                    reason="${reason:-falha ao decodificar $in_ext}"
                fi
                ;;
        esac
    fi

    if ((ok == 1)); then
        if ! validate_image "$TMP_OUT" "$target"; then
            ok=0
            reason="saída inválida ou vazia"
        fi
    fi

    if ((ok == 0)); then
        [[ -n "$TMP_OUT" && -e "$TMP_OUT" ]] && rm -f -- "$TMP_OUT"
        [[ -n "$TMP_DEC" && -e "$TMP_DEC" ]] && rm -f -- "$TMP_DEC"
        TMP_OUT="" TMP_DEC=""
        status_line FAIL "$src" "$out" "$in_bytes" 0 "$(( $(now_ms) - started ))" "${reason:-falha na conversão}"
        [[ -n "$TMP_ERR" && -e "$TMP_ERR" ]] && rm -f -- "$TMP_ERR"
        TMP_ERR=""
        return 1
    fi

    chmod --reference="$src" "$TMP_OUT" 2>/dev/null || true

    if ((same == 1)) || [[ "${CV_OVERWRITE:-0}" == "1" ]]; then
        if ! mv -f -- "$TMP_OUT" "$out"; then
            rm -f -- "$TMP_OUT" "$TMP_DEC"
            TMP_OUT="" TMP_DEC=""
            status_line FAIL "$src" "$out" "$in_bytes" 0 "$(( $(now_ms) - started ))" "não foi possível gravar o destino"
            [[ -n "$TMP_ERR" && -e "$TMP_ERR" ]] && rm -f -- "$TMP_ERR"
            TMP_ERR=""
            return 1
        fi
    else
        if ! mv -n -- "$TMP_OUT" "$out" || [[ ! -e "$out" ]]; then
            rm -f -- "$TMP_OUT" "$TMP_DEC"
            TMP_OUT="" TMP_DEC=""
            status_line FAIL "$src" "$out" "$in_bytes" 0 "$(( $(now_ms) - started ))" "destino não foi criado"
            [[ -n "$TMP_ERR" && -e "$TMP_ERR" ]] && rm -f -- "$TMP_ERR"
            TMP_ERR=""
            return 1
        fi
    fi
    TMP_OUT=""

    [[ -n "$TMP_DEC" && -e "$TMP_DEC" ]] && rm -f -- "$TMP_DEC"
    TMP_DEC=""
    [[ -n "$TMP_ERR" && -e "$TMP_ERR" ]] && rm -f -- "$TMP_ERR"
    TMP_ERR=""

    if [[ "${CV_DELETE:-0}" == "1" && "$out" != "$src" ]]; then
        rm -f -- "$src"
    fi

    out_bytes=$(stat -c%s -- "$out" 2>/dev/null || echo 0)
    status_line OK "$src" "$out" "$in_bytes" "$out_bytes" "$(( $(now_ms) - started ))" ""
    return 0
}

compute_image_out() {
    local src="$1"
    local in_ext target out
    in_ext=$(canon_ext "$(ext_of "$src")")
    if [[ -z "$in_ext" ]]; then
        in_ext=$(magick identify -format '%m' "${src}[0]" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
        in_ext=$(canon_ext "$in_ext")
    fi
    target="${CV_TO:-auto}"
    [[ "$target" == "auto" ]] && target=$(auto_target_for "$src" "$in_ext")
    target=$(canon_ext "$target")

    if [[ "$target" == "$in_ext" ]]; then
        out="$src"
    else
        local dir stem base
        dir=$(dirname -- "$src")
        base=$(basename -- "$src")
        if [[ "$base" == *.* && "$base" != .* ]]; then
            stem="${base%.*}"
        else
            stem="$base"
        fi
        out="$dir/$stem.$target"
    fi

    # Garante unicidade contra arquivos existentes e contra outros itens do
    # mesmo lote (entradas homônimas), sem reservar duas vezes.
    if [[ -n "${CONVERT_RESERVED[$out]:-}" ]] ||
        { [[ "$out" != "$src" && -e "$out" && "${CV_OVERWRITE:-0}" != "1" ]]; }; then
        unique_path_var "$out"
        out="$CONVERT_REPLY"
    else
        CONVERT_RESERVED[$out]=1
    fi
    CONVERT_REPLY="$out"
}

cmd_image() {
    CV_TO="auto"
    CV_QUALITY=""
    CV_MAX=""
    CV_STRIP=0
    CV_FLATTEN=auto
    CV_BG="white"
    CV_DELETE=0
    CV_OVERWRITE=0
    CV_AUTO_ORIENT=1
    CV_FROM=""
    CV_RECURSIVE=1
    CV_VERBOSE="${CV_VERBOSE:-0}"
    local dry_run=0
    local jobs=""
    local -a paths=()

    while (($#)); do
        case "$1" in
            -h|--help) image_help; return 0 ;;
            -t|--to|--format)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_TO="${2,,}"
                shift 2
                ;;
            -q|--quality)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_int_range "$2" 1 100 || die "Qualidade inválida: $2 (use 1-100)"
                CV_QUALITY="$2"
                shift 2
                ;;
            -m|--max)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_dimensions "$2" || die "Dimensão inválida: $2 (use LxA, ex.: 1920x1080)"
                CV_MAX="$2"
                shift 2
                ;;
            --no-resize) CV_MAX=""; shift ;;
            --preset)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                apply_image_preset "$2"
                shift 2
                ;;
            --from)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_FROM="$2"
                shift 2
                ;;
            --recursive) CV_RECURSIVE=1; shift ;;
            --no-recursive) CV_RECURSIVE=0; shift ;;
            --strip) CV_STRIP=1; shift ;;
            --keep-meta) CV_STRIP=0; shift ;;
            --flatten) CV_FLATTEN=1; shift ;;
            --keep-alpha) CV_FLATTEN=0; shift ;;
            --bg)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_BG="$2"
                shift 2
                ;;
            --delete-originals) CV_DELETE=1; shift ;;
            --keep-originals) CV_DELETE=0; shift ;;
            --overwrite) CV_OVERWRITE=1; shift ;;
            -j|--jobs)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_positive_int "$2" || die "Número de jobs inválido: $2"
                jobs="$2"
                shift 2
                ;;
            --dry-run) dry_run=1; shift ;;
            -v|--verbose) CV_VERBOSE=1; shift ;;
            --) shift; paths+=("$@"); break ;;
            -*) die "Opção desconhecida: $1 (use --help)" ;;
            *) paths+=("$1"); shift ;;
        esac
    done

    CV_TO=$(canon_ext "$CV_TO")
    case "$CV_TO" in
        auto|png|jpg|webp|avif|tiff|gif|bmp|jxl|ico) ;;
        *) die "Formato de imagem não suportado: $CV_TO" ;;
    esac

    ((${#paths[@]} > 0)) || paths=("$HOME/Downloads")
    jobs=$(job_count "${jobs:-4}")

    local -a FILES=()
    mapfile -d '' FILES < <(collect_files image "$CV_RECURSIVE" "$CV_FROM" "${paths[@]}")
    dedupe_files

    if ((${#FILES[@]} == 0)); then
        info "Nenhuma imagem encontrada."
        return 0
    fi

    info "${#FILES[@]} imagem(ns) encontrada(s); destino: $CV_TO${CV_MAX:+, máx $CV_MAX}, jobs=$jobs"

    local f
    RUN_SRC=()
    RUN_DST=()
    for f in "${FILES[@]}"; do
        compute_image_out "$f"
        RUN_SRC+=("$f")
        RUN_DST+=("$CONVERT_REPLY")
    done

    if ((dry_run == 1)); then
        local i
        for ((i = 0; i < ${#RUN_SRC[@]}; i++)); do
            printf '  %s -> %s\n' "${RUN_SRC[i]}" "${RUN_DST[i]}"
        done
        return 0
    fi

    export CV_TO CV_QUALITY CV_MAX CV_STRIP CV_FLATTEN CV_BG CV_DELETE
    export CV_OVERWRITE CV_AUTO_ORIENT CV_FROM CV_VERBOSE

    summarize_results "imagens" "${#FILES[@]}" bytes < <(run_pairs __image_one "$jobs")
}

# -----------------------------------------------------------------------------
# Vídeo
# -----------------------------------------------------------------------------
canon_codec() {
    case "${1,,}" in
        h264|avc|avc1|libx264|libx264rgb|h264_nvenc|h264_qsv|h264_vaapi|h264_amf) echo h264 ;;
        hevc|h265|hev1|hvc1|libx265|hevc_nvenc|hevc_qsv|hevc_vaapi|hevc_amf) echo hevc ;;
        vp8|libvpx) echo vp8 ;;
        vp9|libvpx-vp9) echo vp9 ;;
        av1|libaom-av1|libsvtav1|av1_nvenc|av1_qsv|av1_vaapi|av1_amf) echo av1 ;;
        mpeg4|libxvid) echo mpeg4 ;;
        mpeg2video) echo mpeg2video ;;
        mpeg1video) echo mpeg1video ;;
        theora|libtheora) echo theora ;;
        prores|prores_ks|prores_aw) echo prores ;;
        mjpeg) echo mjpeg ;;
        aac) echo aac ;;
        mp3|libmp3lame|libshine) echo mp3 ;;
        opus|libopus) echo opus ;;
        vorbis|libvorbis) echo vorbis ;;
        flac) echo flac ;;
        alac) echo alac ;;
        ac3) echo ac3 ;;
        eac3) echo eac3 ;;
        mp2) echo mp2 ;;
        pcm_s16le|pcm_s24le|pcm_s32le|pcm_f32le|pcm_s16be|pcm_s24be|pcm_s32be|pcm_mulaw|pcm_alaw|pcm_u8) echo "${1,,}" ;;
        wmav2|wmav1) echo "${1,,}" ;;
        *) echo "${1,,}" ;;
    esac
}

container_video_ok() {
    local c="${1,,}" codec
    codec=$(canon_codec "$2")
    case "$c" in
        mp4|m4v|f4v|mov|3gp|3g2|ts|mts|m2ts)
            case "$codec" in h264|hevc|mpeg4|av1) return 0 ;; esac ;;
        mkv)
            case "$codec" in h264|hevc|vp8|vp9|av1|mpeg4|mpeg2video|theora|prores|mjpeg|ffv1|huffyuv) return 0 ;; esac ;;
        webm)
            case "$codec" in vp8|vp9|av1) return 0 ;; esac ;;
        avi)
            case "$codec" in mpeg4|h264|mjpeg|mpeg2video|dvvideo|huffyuv) return 0 ;; esac ;;
        mpg|mpeg|vob)
            case "$codec" in mpeg2video|mpeg1video) return 0 ;; esac ;;
        flv|f4v)
            case "$codec" in h264|flv1) return 0 ;; esac ;;
        wmv|asf)
            case "$codec" in wmv2|wmv1|msmpeg4v3) return 0 ;; esac ;;
        ogv|ogx)
            case "$codec" in theora|vp8) return 0 ;; esac ;;
        mxf|gxf)
            case "$codec" in mpeg2video|h264|dvvideo|mjpeg) return 0 ;; esac ;;
        nut)
            return 0 ;;
    esac
    return 1
}

container_audio_ok() {
    local c="${1,,}" codec
    codec=$(canon_codec "$2")
    case "$c" in
        mp4|m4v|f4v|mov|3gp|3g2|ts|mts|m2ts)
            case "$codec" in aac|mp3|ac3|eac3|alac) return 0 ;; esac ;;
        mkv)
            case "$codec" in aac|mp3|ac3|eac3|opus|vorbis|flac|alac|wavpack|tta|pcm_s16le|pcm_s24le|pcm_s32le|pcm_f32le|pcm_s16be|pcm_s24be|pcm_s32be|pcm_mulaw|pcm_alaw|pcm_u8) return 0 ;; esac ;;
        webm)
            case "$codec" in opus|vorbis) return 0 ;; esac ;;
        avi)
            case "$codec" in mp3|ac3|pcm_s16le|pcm_s24le) return 0 ;; esac ;;
        mpg|mpeg|vob)
            case "$codec" in mp2|mp3|ac3|pcm_s16le) return 0 ;; esac ;;
        flv|f4v)
            case "$codec" in aac|mp3) return 0 ;; esac ;;
        wmv|asf)
            case "$codec" in wmav2|wmav1|mp3) return 0 ;; esac ;;
        ogv|ogx)
            case "$codec" in vorbis|opus|flac|speex) return 0 ;; esac ;;
        nut)
            return 0 ;;
        gif)
            return 1 ;;
    esac
    return 1
}

probe_video_info() {
    local src="$1" key val
    VI_VCODEC=""
    VI_WIDTH=0
    VI_HEIGHT=0
    VI_PIXFMT=""
    VI_FPS_RAW=""
    VI_FPS=0
    VI_BITRATE=""
    VI_DURATION="0"
    VI_ACODECS=()
    VI_ACOUNT=0

    while IFS='=' read -r key val; do
        [[ -n "$key" ]] || continue
        case "$key" in
            codec_name) VI_VCODEC="$val" ;;
            width) VI_WIDTH="$val" ;;
            height) VI_HEIGHT="$val" ;;
            pix_fmt) VI_PIXFMT="$val" ;;
            r_frame_rate) VI_FPS_RAW="$val" ;;
            bit_rate) VI_BITRATE="$val" ;;
        esac
    done < <(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate,bit_rate \
        -of default=noprint_wrappers=1 "$src" 2>/dev/null)

    VI_DURATION=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$src" 2>/dev/null | head -n1)
    [[ "$VI_DURATION" =~ ^[0-9]+([.][0-9]+)?$ ]] || VI_DURATION=0

    if [[ -n "$VI_FPS_RAW" ]]; then
        VI_FPS=$(awk -v r="$VI_FPS_RAW" 'BEGIN {
            split(r, a, "/");
            if (a[2] && a[2] > 0) printf "%.3f", a[1] / a[2];
            else printf "%.3f", r;
        }')
    fi

    mapfile -t VI_ACODECS < <(ffprobe -v error -select_streams a \
        -show_entries stream=codec_name -of csv=p=0 "$src" 2>/dev/null | sed '/^[[:space:]]*$/d')
    VI_ACOUNT=${#VI_ACODECS[@]}

    [[ -n "$VI_VCODEC" ]]
}

all_audio_compatible() {
    local target="$1" codec
    for codec in "${VI_ACODECS[@]}"; do
        container_audio_ok "$target" "$codec" || return 1
    done
    return 0
}

default_video_encoder_for() {
    case "${1,,}" in
        webm) echo libvpx-vp9 ;;
        ogv|ogx) echo libtheora ;;
        avi|divx) echo mpeg4 ;;
        mpg|mpeg|vob) echo mpeg2video ;;
        wmv|asf) echo wmv2 ;;
        gif) echo gif ;;
        *) echo libx264 ;;
    esac
}

default_audio_encoder_for() {
    case "${1,,}" in
        webm) echo libopus ;;
        ogv|ogx) echo libvorbis ;;
        avi|divx) echo libmp3lame ;;
        mpg|mpeg|vob) echo mp2 ;;
        wmv|asf) echo wmav2 ;;
        gif) echo none ;;
        *) echo aac ;;
    esac
}

encoder_for_codec() {
    case "$(canon_codec "$1")" in
        h264) echo libx264 ;;
        hevc) echo libx265 ;;
        vp8) echo libvpx ;;
        vp9) echo libvpx-vp9 ;;
        av1) echo libsvtav1 ;;
        mpeg4) echo mpeg4 ;;
        mpeg2video) echo mpeg2video ;;
        theora) echo libtheora ;;
        prores) echo prores_ks ;;
        aac) echo aac ;;
        mp3) echo libmp3lame ;;
        opus) echo libopus ;;
        vorbis) echo libvorbis ;;
        *) echo "$1" ;;
    esac
}

# Define VC_MAX_W, VC_MAX_H, VC_FPS, VC_AR, VC_AC, VC_ABR
video_constraints() {
    VC_MAX_W=0
    VC_MAX_H=0
    VC_FPS=0
    VC_AR=0
    VC_AC=0
    VC_ABR=0
    case "${1,,}" in
        amv)
            VC_MAX_W=320 VC_MAX_H=240 VC_FPS=30 VC_AR=22050 VC_AC=1 VC_ABR=32000 ;;
        3gp|3g2)
            VC_MAX_W=320 VC_MAX_H=240 VC_FPS=30 VC_AR=22050 VC_AC=2 VC_ABR=16000 ;;
        wmv|asf)
            VC_MAX_W=640 VC_MAX_H=480 VC_FPS=30 VC_AR=44100 VC_AC=2 VC_ABR=128000 ;;
        mpg|mpeg|vob)
            VC_MAX_W=720 VC_MAX_H=576 VC_FPS=30 VC_AR=48000 VC_ABR=192000 ;;
        swf)
            VC_MAX_W=640 VC_MAX_H=480 VC_FPS=30 VC_AR=22050 VC_ABR=128000 ;;
        mxf)
            VC_AR=48000 ;;
        gxf)
            VC_MAX_W=720 VC_MAX_H=576 VC_AR=48000 VC_AC=1 ;;
    esac
}

target_format_args() {
    case "${1,,}" in
        divx) echo "-f avi" ;;
        ogx) echo "-f ogg" ;;
        h264) echo "-f h264" ;;
        h265|hevc) echo "-f hevc" ;;
        m2ts|mts|ts) echo "-f mpegts" ;;
        y4m) echo "-f yuv4mpegpipe" ;;
        *) echo "" ;;
    esac
}

build_video_encoder_args() {
    local encoder="$1" crf="$2" bitrate="$3" preset="$4"
    VENC_ARGS=()
    case "$encoder" in
        h264_nvenc|hevc_nvenc)
            VENC_ARGS+=(-c:v "$encoder" -preset p4 -rc vbr -cq "$crf")
            if [[ -n "$bitrate" ]]; then
                VENC_ARGS+=(-b:v "$bitrate")
            else
                VENC_ARGS+=(-b:v 0)
            fi
            VENC_ARGS+=(-pix_fmt yuv420p)
            ;;
        libx264|libx265)
            VENC_ARGS+=(-c:v "$encoder" -preset "$preset" -pix_fmt yuv420p)
            if [[ -n "$bitrate" ]]; then
                VENC_ARGS+=(-b:v "$bitrate")
            else
                VENC_ARGS+=(-crf "$crf")
            fi
            ;;
        libvpx|libvpx-vp9)
            VENC_ARGS+=(-c:v "$encoder" -row-mt 1 -pix_fmt yuv420p)
            if [[ -n "$bitrate" ]]; then
                VENC_ARGS+=(-b:v "$bitrate")
            else
                VENC_ARGS+=(-crf "$crf" -b:v 0)
            fi
            ;;
        mpeg4|mpeg2video|wmv2)
            VENC_ARGS+=(-c:v "$encoder" -q:v 3)
            [[ -n "$bitrate" ]] && VENC_ARGS+=(-b:v "$bitrate")
            ;;
        libtheora)
            VENC_ARGS+=(-c:v libtheora -q:v 7)
            ;;
        prores_ks)
            VENC_ARGS+=(-c:v prores_ks -profile:v 3)
            ;;
        *)
            VENC_ARGS+=(-c:v "$encoder")
            ;;
    esac
}

build_audio_encoder_args() {
    local encoder="$1" bitrate="$2" rate="$3" channels="$4"
    AENC_ARGS=()
    [[ "$encoder" == "none" ]] && return 0
    AENC_ARGS+=(-c:a "$encoder")
    [[ -n "$bitrate" ]] && AENC_ARGS+=(-b:a "$bitrate")
    if [[ "$rate" =~ ^[1-9][0-9]*$ ]]; then
        AENC_ARGS+=(-ar "$rate")
    fi
    if [[ "$channels" =~ ^[1-9][0-9]*$ ]]; then
        AENC_ARGS+=(-ac "$channels")
    elif [[ "$encoder" == "libopus" ]]; then
        AENC_ARGS+=(-ac 2)
    fi
}

convert_video_one() {
    local src="${1:-}"
    local started
    started=$(now_ms)

    if [[ -z "$src" || ! -f "$src" ]]; then
        status_line FAIL "${src:-?}" "" 0 0 "$(( $(now_ms) - started ))" "arquivo inexistente"
        return 1
    fi

    local in_bytes
    in_bytes=$(stat -c%s -- "$src" 2>/dev/null || echo 0)

    if ! probe_video_info "$src"; then
        status_line FAIL "$src" "" "$in_bytes" 0 "$(( $(now_ms) - started ))" "ffprobe não encontrou stream de vídeo"
        return 1
    fi

    local in_ext target
    in_ext=$(canon_ext "$(ext_of "$src")")
    target="${CV_VIDEO_TO:-mp4}"
    target=$(canon_ext "$target")

    local dir stem base out
    dir=$(dirname -- "$src")
    base=$(basename -- "$src")
    if [[ "$base" == *.* && "$base" != .* ]]; then
        stem="${base%.*}"
    else
        stem="$base"
    fi
    if [[ -n "${2:-}" ]]; then
        out="$2"
    elif [[ "$target" == "$in_ext" ]]; then
        out="$src"
    else
        out="$dir/$stem.$target"
        if [[ -e "$out" && "${CV_OVERWRITE:-0}" != "1" ]]; then
            unique_path_var "$out"
            out="$CONVERT_REPLY"
        fi
    fi

    # Nada a fazer.
    if [[ "$target" == "$in_ext" && -z "${CV_MAX:-}" && -z "${CV_FPS:-}" && -z "${CV_VIDEO_CODEC:-}" && -z "${CV_BITRATE:-}" && "${CV_CRF_SET:-0}" != "1" && "${CV_STRIP:-0}" != "1" && "${CV_NO_AUDIO:-0}" != "1" ]]; then
        status_line SKIP "$src" "$out" "$in_bytes" "$in_bytes" "$(( $(now_ms) - started ))" "já está no formato de destino e nenhuma alteração foi pedida"
        return 0
    fi

    # Decide remux x reencode.
    local can_remux=1 mode="encode"
    container_video_ok "$target" "$VI_VCODEC" || can_remux=0
    if ((VI_ACOUNT > 0)); then
        all_audio_compatible "$target" || can_remux=0
    fi
    [[ -n "${CV_MAX:-}" || -n "${CV_FPS:-}" || -n "${CV_VIDEO_CODEC:-}" || -n "${CV_BITRATE:-}" || "${CV_CRF_SET:-0}" == "1" ]] && can_remux=0
    [[ "${CV_REENCODE:-0}" == "1" ]] && can_remux=0

    if [[ "${CV_COPY:-0}" == "1" ]]; then
        if ((can_remux == 1)); then
            mode="copy"
        else
            warn "$(basename -- "$src"): --copy solicitado, mas os codecs não são compatíveis com .$target; reencodando"
            mode="encode"
        fi
    elif ((can_remux == 1)); then
        mode="copy"
    fi

    # Limites do container.
    video_constraints "$target"
    local max_w=0 max_h=0 fps="" crf="${CV_CRF:-23}" bitrate="${CV_BITRATE:-}"
    if [[ -n "${CV_MAX:-}" ]]; then
        max_w="${CV_MAX%x*}"
        max_h="${CV_MAX#*x}"
    fi
    if ((VC_MAX_W > 0)); then
        if ((max_w == 0 || max_w > VC_MAX_W)); then max_w=$VC_MAX_W; fi
        if ((max_h == 0 || max_h > VC_MAX_H)); then max_h=$VC_MAX_H; fi
    fi
    fps="${CV_FPS:-}"
    if ((VC_FPS > 0)); then
        if [[ -z "$fps" ]] || ((fps > VC_FPS)); then
            fps="$VC_FPS"
        fi
    fi

    local audio_rate="${CV_AUDIO_RATE:-}"
    [[ -n "$audio_rate" ]] || audio_rate=$VC_AR
    local audio_channels="${CV_AUDIO_CHANNELS:-}"
    [[ -n "$audio_channels" ]] || audio_channels=$VC_AC
    local audio_bitrate="${CV_AUDIO_BITRATE:-128k}"
    ((VC_ABR > 0)) && [[ -z "${CV_AUDIO_BITRATE:-}" ]] && audio_bitrate="${VC_ABR}"

    TMP_OUT=$(temp_output_path "$out")
    TMP_ERR=$(mktemp --tmpdir="$dir" ".${stem}.err.XXXXXX" 2>/dev/null || mktemp)

    local -a args=(-hide_banner -loglevel error -nostdin -y -i "$src")
    local -a extra=()
    if [[ -n "${CV_EXTRA_ARGS:-}" ]]; then
        read -r -a extra <<<"${CV_EXTRA_ARGS}"
        args+=("${extra[@]}")
    fi

    local vf=""
    if ((max_w > 0 && max_h > 0)) && [[ "$target" != "gif" ]]; then
        vf="scale='min(${max_w},iw)':'min(${max_h},ih)':force_original_aspect_ratio=decrease:force_divisible_by=2"
    fi

    local video_copy=0
    if [[ "$mode" == "encode" && "$target" != "gif" ]] &&
        [[ -z "${CV_MAX:-}" && -z "${CV_FPS:-}" && -z "${CV_VIDEO_CODEC:-}" &&
           -z "${CV_BITRATE:-}" && "${CV_CRF_SET:-0}" != "1" &&
           "${CV_HW:-0}" != "1" && "${CV_REENCODE:-0}" != "1" ]]; then
        container_video_ok "$target" "$VI_VCODEC" && video_copy=1
    fi
    ((video_copy == 1)) && mode="reencode-audio"

    if [[ "$target" == "gif" ]]; then
        local gif_w=$max_w
        ((gif_w > 0)) || gif_w=320
        local gif_fps="$fps"
        [[ -n "$gif_fps" ]] || gif_fps=15
        local gif_filter="[0:v]fps=${gif_fps},scale=${gif_w}:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256[p];[s1][p]paletteuse=dither=bayer[gif]"
        args+=(-filter_complex "$gif_filter" -map "[gif]" -loop 0)
        args+=(-an)
    elif [[ "$mode" == "copy" ]]; then
        args+=(-map 0:v:0 -map '0:a?' -c copy)
        if [[ "$target" =~ ^(mp4|m4v|mov)$ ]] && [[ "$(canon_codec "$VI_VCODEC")" == "hevc" ]]; then
            args+=(-tag:v hvc1)
        fi
        [[ "${CV_NO_AUDIO:-0}" == "1" ]] && args+=(-an)
    else
        args+=(-map 0:v:0)
        if [[ "${CV_NO_AUDIO:-0}" == "1" ]] || ((VI_ACOUNT == 0)); then
            args+=(-an)
        else
            args+=(-map '0:a?')
        fi

        [[ -n "$vf" ]] && args+=(-vf "$vf")
        [[ -n "$fps" ]] && args+=(-r "$fps")

        if ((video_copy == 1)); then
            # O vídeo já é compatível com o container: copia os streams de
            # vídeo e reencoda só o áudio, se necessário.
            args+=(-c:v copy)
            if [[ "$target" =~ ^(mp4|m4v|mov)$ ]] && [[ "$(canon_codec "$VI_VCODEC")" == "hevc" ]]; then
                args+=(-tag:v hvc1)
            fi
        else
            local video_encoder="${CV_VIDEO_CODEC:-}"
            if [[ -z "$video_encoder" ]]; then
                video_encoder=$(default_video_encoder_for "$target")
            else
                video_encoder=$(encoder_for_codec "$video_encoder")
            fi

            if [[ "${CV_HW:-0}" == "1" && "$(canon_codec "$video_encoder")" == "h264" ]]; then
                if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q 'h264_nvenc' &&
                    have nvidia-smi && nvidia-smi -L >/dev/null 2>&1 &&
                    ffmpeg -hide_banner -loglevel error -f lavfi -i color=size=64x64:rate=1 \
                        -frames:v 1 -c:v h264_nvenc -f null - >/dev/null 2>&1; then
                    video_encoder="h264_nvenc"
                    debug "usando h264_nvenc"
                else
                    debug "NVENC indisponível; mantendo $video_encoder"
                fi
            fi

            build_video_encoder_args "$video_encoder" "$crf" "$bitrate" "${CV_VIDEO_PRESET:-medium}"
            args+=("${VENC_ARGS[@]}")
            if [[ "$target" =~ ^(mp4|m4v|mov)$ ]] && [[ "$(canon_codec "$video_encoder")" == "hevc" ]]; then
                args+=(-tag:v hvc1)
            fi
        fi

        if [[ "${CV_NO_AUDIO:-0}" != "1" ]] && ((VI_ACOUNT > 0)); then
            local audio_encoder="${CV_AUDIO_CODEC:-}"
            if [[ -z "$audio_encoder" && -z "${CV_AUDIO_BITRATE:-}" ]] && all_audio_compatible "$target"; then
                args+=(-c:a copy)
            else
                [[ -n "$audio_encoder" ]] || audio_encoder=$(default_audio_encoder_for "$target")
                [[ "$audio_encoder" == "copy" ]] && audio_encoder=$(default_audio_encoder_for "$target")
                audio_encoder=$(encoder_for_codec "$audio_encoder")
                build_audio_encoder_args "$audio_encoder" "$audio_bitrate" "$audio_rate" "$audio_channels"
                args+=("${AENC_ARGS[@]}")
            fi
        fi
    fi

    if [[ "${CV_STRIP:-0}" == "1" ]]; then
        args+=(-map_metadata -1 -map_chapters -1)
    else
        args+=(-map_metadata 0 -map_chapters 0)
    fi

    case "$target" in
        mp4|m4v|mov) args+=(-movflags +faststart) ;;
        ts|mts|m2ts|mpegts) args+=(-avoid_negative_ts make_zero) ;;
    esac

    local fmt_args
    fmt_args=$(target_format_args "$target")
    if [[ -n "$fmt_args" ]]; then
        read -r -a extra <<<"$fmt_args"
        args+=("${extra[@]}")
    fi

    args+=("$TMP_OUT")
    debug "ffmpeg ${args[*]}"

    local reason=""
    if ! ffmpeg "${args[@]}" 2>"$TMP_ERR"; then
        reason=$(grep -v '^[[:space:]]*$' "$TMP_ERR" 2>/dev/null | tail -n1 | cut -c1-240)
        rm -f -- "$TMP_OUT"
        TMP_OUT=""
        status_line FAIL "$src" "$out" "$in_bytes" 0 "$(( $(now_ms) - started ))" "${reason:-ffmpeg falhou}"
        [[ -n "$TMP_ERR" && -e "$TMP_ERR" ]] && rm -f -- "$TMP_ERR"
        TMP_ERR=""
        return 1
    fi

    if ! validate_video "$TMP_OUT"; then
        reason=$(grep -v '^[[:space:]]*$' "$TMP_ERR" 2>/dev/null | tail -n1 | cut -c1-240)
        rm -f -- "$TMP_OUT"
        TMP_OUT=""
        status_line FAIL "$src" "$out" "$in_bytes" 0 "$(( $(now_ms) - started ))" "saída inválida: ${reason:-ffprobe rejeitou o arquivo}"
        [[ -n "$TMP_ERR" && -e "$TMP_ERR" ]] && rm -f -- "$TMP_ERR"
        TMP_ERR=""
        return 1
    fi

    chmod --reference="$src" "$TMP_OUT" 2>/dev/null || true
    if [[ "${CV_OVERWRITE:-0}" == "1" || "$out" == "$src" ]]; then
        mv -f -- "$TMP_OUT" "$out"
    else
        mv -n -- "$TMP_OUT" "$out"
    fi
    TMP_OUT=""
    [[ -n "$TMP_ERR" && -e "$TMP_ERR" ]] && rm -f -- "$TMP_ERR"
    TMP_ERR=""

    if [[ "${CV_DELETE:-0}" == "1" && "$out" != "$src" ]]; then
        rm -f -- "$src"
    fi

    local out_bytes
    out_bytes=$(stat -c%s -- "$out" 2>/dev/null || echo 0)
    status_line OK "$src" "$out" "$in_bytes" "$out_bytes" "$(( $(now_ms) - started ))" "$mode"
    return 0
}

compute_video_out() {
    local src="$1"
    local in_ext target out mode="encode"
    in_ext=$(canon_ext "$(ext_of "$src")")
    target=$(canon_ext "${CV_VIDEO_TO:-mp4}")
    if probe_video_info "$src"; then
        container_video_ok "$target" "$VI_VCODEC" && all_audio_compatible "$target" && mode="copy"
        [[ -n "${CV_MAX:-}" || -n "${CV_FPS:-}" || -n "${CV_VIDEO_CODEC:-}" || -n "${CV_BITRATE:-}" || "${CV_CRF_SET:-0}" == "1" ]] && mode="encode"
        [[ "${CV_REENCODE:-0}" == "1" ]] && mode="encode"
    fi
    [[ "${CV_COPY:-0}" == "1" ]] && mode="copy"
    local dir stem base out
    dir=$(dirname -- "$src")
    base=$(basename -- "$src")
    if [[ "$base" == *.* && "$base" != .* ]]; then
        stem="${base%.*}"
    else
        stem="$base"
    fi
    if [[ "$target" == "$in_ext" ]]; then
        out="$src"
    else
        out="$dir/$stem.$target"
    fi
    if [[ -n "${CONVERT_RESERVED[$out]:-}" ]] ||
        { [[ "$out" != "$src" && -e "$out" && "${CV_OVERWRITE:-0}" != "1" ]]; }; then
        unique_path_var "$out"
        out="$CONVERT_REPLY"
    else
        CONVERT_RESERVED[$out]=1
    fi
    CONVERT_REPLY="$out"
    CONVERT_MODE="$mode"
}

cmd_video() {
    CV_VIDEO_TO="mp4"
    CV_VIDEO_CODEC=""
    CV_AUDIO_CODEC=""
    CV_CRF="23"
    CV_CRF_SET=0
    CV_BITRATE=""
    CV_AUDIO_BITRATE=""
    CV_AUDIO_RATE=""
    CV_AUDIO_CHANNELS=""
    CV_VIDEO_PRESET="medium"
    CV_MAX=""
    CV_FPS=""
    CV_NO_AUDIO=0
    CV_STRIP=0
    CV_COPY=0
    CV_REENCODE=0
    CV_HW=0
    CV_EXTRA_ARGS=""
    CV_DELETE=0
    CV_OVERWRITE=0
    CV_FROM=""
    CV_RECURSIVE=1
    CV_VERBOSE="${CV_VERBOSE:-0}"
    local dry_run=0 jobs=""
    local -a paths=()

    while (($#)); do
        case "$1" in
            -h|--help) video_help; return 0 ;;
            -t|--to|--format)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_VIDEO_TO="${2,,}"
                shift 2
                ;;
            --copy) CV_COPY=1; shift ;;
            --reencode) CV_REENCODE=1; shift ;;
            -c|--video-codec)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_VIDEO_CODEC="$2"
                shift 2
                ;;
            -a|--audio-codec)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_AUDIO_CODEC="$2"
                shift 2
                ;;
            --crf)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_int_range "$2" 0 63 || die "CRF inválido: $2 (use 0-63)"
                CV_CRF="$2"
                CV_CRF_SET=1
                shift 2
                ;;
            --bitrate)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_BITRATE="$2"
                shift 2
                ;;
            --audio-bitrate)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_AUDIO_BITRATE="$2"
                shift 2
                ;;
            -s|--preset)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_VIDEO_PRESET="$2"
                shift 2
                ;;
            -m|--max)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_dimensions "$2" || die "Dimensão inválida: $2 (use LxA)"
                CV_MAX="$2"
                shift 2
                ;;
            --fps)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_positive_int "$2" || die "FPS inválido: $2"
                CV_FPS="$2"
                shift 2
                ;;
            --no-audio) CV_NO_AUDIO=1; shift ;;
            --strip) CV_STRIP=1; shift ;;
            --hw) CV_HW=1; shift ;;
            --extra-args)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_EXTRA_ARGS="$2"
                shift 2
                ;;
            --from)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_FROM="$2"
                shift 2
                ;;
            --recursive) CV_RECURSIVE=1; shift ;;
            --no-recursive) CV_RECURSIVE=0; shift ;;
            --delete-originals) CV_DELETE=1; shift ;;
            --overwrite) CV_OVERWRITE=1; shift ;;
            -j|--jobs)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_positive_int "$2" || die "Número de jobs inválido: $2"
                jobs="$2"
                shift 2
                ;;
            --dry-run) dry_run=1; shift ;;
            -v|--verbose) CV_VERBOSE=1; shift ;;
            --) shift; paths+=("$@"); break ;;
            -*) die "Opção desconhecida: $1 (use --help)" ;;
            *) paths+=("$1"); shift ;;
        esac
    done

    CV_VIDEO_TO=$(canon_ext "$CV_VIDEO_TO")
    case "$CV_VIDEO_TO" in
        mp4|mkv|webm|mov|avi|m4v|flv|wmv|mpg|mpeg|ts|m2ts|mts|3gp|3g2|ogv|ogx|vob|mxf|gif|divx|f4v|asf|nut)
            ;;
        *) die "Formato de vídeo não suportado: $CV_VIDEO_TO" ;;
    esac

    ((${#paths[@]} > 0)) || die "Informe ao menos um arquivo ou diretório (ex.: convert.sh video --to mp4 video.mkv)"
    jobs=$(job_count "${jobs:-1}")

    local -a FILES=()
    mapfile -d '' FILES < <(collect_files video "$CV_RECURSIVE" "$CV_FROM" "${paths[@]}")
    dedupe_files

    if ((${#FILES[@]} == 0)); then
        info "Nenhum vídeo encontrado."
        return 0
    fi

    info "${#FILES[@]} vídeo(s) encontrado(s); destino: $CV_VIDEO_TO, jobs=$jobs"

    local f
    RUN_SRC=()
    RUN_DST=()
    local -a modes=()
    for f in "${FILES[@]}"; do
        compute_video_out "$f"
        RUN_SRC+=("$f")
        RUN_DST+=("$CONVERT_REPLY")
        modes+=("$CONVERT_MODE")
    done

    if ((dry_run == 1)); then
        local i
        for ((i = 0; i < ${#RUN_SRC[@]}; i++)); do
            printf '  %s -> %s [%s]\n' "${RUN_SRC[i]}" "${RUN_DST[i]}" "${modes[i]}"
        done
        return 0
    fi

    export CV_VIDEO_TO CV_VIDEO_CODEC CV_AUDIO_CODEC CV_CRF CV_CRF_SET
    export CV_BITRATE CV_AUDIO_BITRATE CV_AUDIO_RATE CV_AUDIO_CHANNELS
    export CV_VIDEO_PRESET CV_MAX CV_FPS CV_NO_AUDIO CV_STRIP CV_COPY CV_REENCODE
    export CV_HW CV_EXTRA_ARGS CV_DELETE CV_OVERWRITE CV_FROM CV_VERBOSE

    summarize_results "vídeos" "${#FILES[@]}" bytes < <(run_pairs __video_one "$jobs")
}

# -----------------------------------------------------------------------------
# Frames
# -----------------------------------------------------------------------------
extract_frames_one() {
    local src="${1:-}"

    # Defaults também valem para chamadas internas diretas (__frames_one).
    FV_FPS="${FV_FPS:-2}"
    FV_SCENE="${FV_SCENE:-}"
    FV_MAX_FRAMES="${FV_MAX_FRAMES:-100}"
    FV_WIDTH="${FV_WIDTH:-1280}"
    FV_FORMAT="${FV_FORMAT:-png}"
    FV_QUALITY="${FV_QUALITY:-90}"
    FV_OUTPUT="${FV_OUTPUT:-$HOME/Downloads/frames}"
    FV_CLEAN="${FV_CLEAN:-1}"
    FV_HWACCEL="${FV_HWACCEL:-none}"
    FV_MAX_SIZE_MB="${FV_MAX_SIZE_MB:-100}"
    FV_MAX_DURATION="${FV_MAX_DURATION:-600}"

    local started
    started=$(now_ms)

    if [[ -z "$src" || ! -f "$src" ]]; then
        status_line FAIL "${src:-?}" "" 0 0 "$(( $(now_ms) - started ))" "arquivo inexistente"
        return 1
    fi

    local in_bytes size_mb
    in_bytes=$(stat -c%s -- "$src" 2>/dev/null || echo 0)
    size_mb=$((in_bytes / 1024 / 1024))

    if ((FV_MAX_SIZE_MB > 0 && size_mb > FV_MAX_SIZE_MB)); then
        status_line SKIP "$src" "" "$in_bytes" 0 "$(( $(now_ms) - started ))" "grande: ${size_mb}MB > ${FV_MAX_SIZE_MB}MB"
        return 0
    fi

    local duration
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$src" 2>/dev/null | head -n1 || true)
    [[ "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]] || duration=0
    local duration_int="${duration%.*}"
    [[ -n "$duration_int" ]] || duration_int=0

    if ((FV_MAX_DURATION > 0 && duration_int > FV_MAX_DURATION)); then
        status_line SKIP "$src" "" "$in_bytes" 0 "$(( $(now_ms) - started ))" "longo: ${duration_int}s > ${FV_MAX_DURATION}s"
        return 0
    fi

    local base stem safe
    base=$(basename -- "$src")
    if [[ "$base" == *.* && "$base" != .* ]]; then
        stem="${base%.*}"
    else
        stem="$base"
    fi
    safe=$(printf '%s' "$stem" | sed 's/[^a-zA-Z0-9._-]/_/g; s/^_*//; s/_*$//')
    [[ -n "$safe" ]] || safe="video"

    local video_out="${2:-}"
    if [[ -z "$video_out" ]]; then
        video_out="$FV_OUTPUT/$safe"
    fi
    mkdir -p -- "$video_out" || {
        status_line FAIL "$src" "$video_out" "$in_bytes" 0 "$(( $(now_ms) - started ))" "não foi possível criar $video_out"
        return 1
    }

    if [[ "$FV_CLEAN" == "1" ]]; then
        find "$video_out" -maxdepth 1 -type f \
            \( -name '*.png' -o -name '*.jpg' -o -name '*.webp' \) -delete 2>/dev/null || true
    fi

    local vf=""
    if [[ -n "$FV_SCENE" ]]; then
        vf="select='gt(scene,${FV_SCENE})'"
    else
        vf="fps=${FV_FPS}"
    fi
    if ((FV_WIDTH > 0)); then
        vf="${vf},scale='min(${FV_WIDTH},iw)':-2:flags=lanczos"
    fi

    local fmt="$FV_FORMAT"
    local -a codec_args=()
    case "$fmt" in
        png)
            codec_args=(-c:v png -compression_level 9)
            ;;
        jpg)
            local qscale=$((31 - (FV_QUALITY * 29 / 100)))
            ((qscale < 2)) && qscale=2
            codec_args=(-c:v mjpeg -q:v "$qscale")
            ;;
        webp)
            codec_args=(-c:v libwebp -quality "$FV_QUALITY" -compression_level 6)
            ;;
    esac

    local date_tag
    date_tag=$(date +"%d-%m-%Y")
    local pattern="$video_out/${safe}_${date_tag}_frame%04d.${fmt}"

    local -a args=(-hide_banner -loglevel error -nostdin -y)
    if [[ -n "$FV_HWACCEL" && "$FV_HWACCEL" != "none" ]]; then
        args+=(-hwaccel "$FV_HWACCEL")
    fi
    args+=(-i "$src" -vf "$vf" -frames:v "$FV_MAX_FRAMES" "${codec_args[@]}" -an)
    [[ -n "$FV_SCENE" ]] && args+=(-fps_mode vfr)
    args+=("$pattern")

    TMP_ERR=$(mktemp 2>/dev/null || printf '/tmp/cv-frames-%s.err' "$$")
    local reason=""
    if ! ffmpeg "${args[@]}" 2>"$TMP_ERR"; then
        reason=$(grep -v '^[[:space:]]*$' "$TMP_ERR" 2>/dev/null | tail -n1 | cut -c1-240)
        rm -f -- "$TMP_ERR"
        TMP_ERR=""
        local partial
        partial=$(find "$video_out" -maxdepth 1 -type f -name "*.${fmt}" 2>/dev/null | wc -l)
        if [[ -n "$FV_SCENE" ]] && ((partial == 0)); then
            status_line SKIP "$src" "$video_out" "$in_bytes" 0 "$(( $(now_ms) - started ))" "nenhuma mudança de cena detectada"
            return 0
        fi
        status_line FAIL "$src" "$video_out" "$in_bytes" 0 "$(( $(now_ms) - started ))" "${reason:-ffmpeg falhou}"
        return 1
    fi
    rm -f -- "$TMP_ERR"
    TMP_ERR=""

    local count
    count=$(find "$video_out" -maxdepth 1 -type f -name "*.${fmt}" 2>/dev/null | wc -l)

    if ((count == 0)); then
        status_line FAIL "$src" "$video_out" "$in_bytes" 0 "$(( $(now_ms) - started ))" "nenhum frame gerado"
        return 1
    fi

    status_line OK "$src" "$video_out" "$in_bytes" "$count" "$(( $(now_ms) - started ))" "${duration_int}s"
    return 0
}

compute_frames_out() {
    local src="$1"
    local base stem safe out
    base=$(basename -- "$src")
    if [[ "$base" == *.* && "$base" != .* ]]; then
        stem="${base%.*}"
    else
        stem="$base"
    fi
    safe=$(printf '%s' "$stem" | sed 's/[^a-zA-Z0-9._-]/_/g; s/^_*//; s/_*$//')
    [[ -n "$safe" ]] || safe="video"
    out="$FV_OUTPUT/$safe"
    if [[ -n "${CONVERT_RESERVED[$out]:-}" ]]; then
        local i=1
        while [[ -n "${CONVERT_RESERVED[$out-$i]:-}" ]]; do
            ((i++))
        done
        out="$out-$i"
    fi
    CONVERT_RESERVED[$out]=1
    CONVERT_REPLY="$out"
}

cmd_frames() {
    FV_FPS=2
    FV_SCENE=""
    FV_MAX_FRAMES=100
    FV_WIDTH=1280
    FV_FORMAT="png"
    FV_QUALITY=90
    FV_OUTPUT="$HOME/Downloads/frames"
    FV_CLEAN=1
    FV_HWACCEL="none"
    FV_MAX_SIZE_MB=100
    FV_MAX_DURATION=600
    CV_FROM=""
    CV_RECURSIVE=1
    CV_VERBOSE="${CV_VERBOSE:-0}"
    local dry_run=0 jobs=""
    local -a paths=()

    while (($#)); do
        case "$1" in
            -h|--help) frames_help; return 0 ;;
            --fps)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "FPS inválido: $2"
                FV_FPS="$2"
                shift 2
                ;;
            --scene)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                awk -v v="$2" 'BEGIN { exit !(v >= 0 && v <= 1) }' || die "Valor de cena inválido: $2 (use 0-1)"
                FV_SCENE="$2"
                shift 2
                ;;
            --max-frames)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_positive_int "$2" || die "Máximo de frames inválido: $2"
                FV_MAX_FRAMES="$2"
                shift 2
                ;;
            --width)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                [[ "$2" =~ ^[0-9]+$ ]] || die "Largura inválida: $2"
                FV_WIDTH="$2"
                shift 2
                ;;
            --format)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                case "${2,,}" in
                    png|jpg|jpeg|webp) FV_FORMAT=$(canon_ext "${2,,}") ;;
                    *) die "Formato de frame não suportado: $2 (use png, jpg ou webp)" ;;
                esac
                shift 2
                ;;
            --quality)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_int_range "$2" 1 100 || die "Qualidade inválida: $2"
                FV_QUALITY="$2"
                shift 2
                ;;
            -o|--output)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                FV_OUTPUT="$2"
                shift 2
                ;;
            --clean) FV_CLEAN=1; shift ;;
            --no-clean) FV_CLEAN=0; shift ;;
            --hwaccel)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                case "${2,,}" in
                    auto|cuda|vaapi|qsv|none) FV_HWACCEL="${2,,}" ;;
                    *) die "hwaccel inválido: $2 (use auto, cuda, vaapi, qsv ou none)" ;;
                esac
                shift 2
                ;;
            --max-size-mb)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                [[ "$2" =~ ^[0-9]+$ ]] || die "Valor inválido: $2"
                FV_MAX_SIZE_MB="$2"
                shift 2
                ;;
            --max-duration)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                [[ "$2" =~ ^[0-9]+$ ]] || die "Valor inválido: $2"
                FV_MAX_DURATION="$2"
                shift 2
                ;;
            --from)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                CV_FROM="$2"
                shift 2
                ;;
            --recursive) CV_RECURSIVE=1; shift ;;
            --no-recursive) CV_RECURSIVE=0; shift ;;
            -j|--jobs)
                [[ $# -ge 2 ]] || die "Falta valor para $1"
                validate_positive_int "$2" || die "Número de jobs inválido: $2"
                jobs="$2"
                shift 2
                ;;
            --dry-run) dry_run=1; shift ;;
            -v|--verbose) CV_VERBOSE=1; shift ;;
            --) shift; paths+=("$@"); break ;;
            -*) die "Opção desconhecida: $1 (use --help)" ;;
            *) paths+=("$1"); shift ;;
        esac
    done

    ((${#paths[@]} > 0)) || paths=("$HOME/Downloads")
    jobs=$(job_count "${jobs:-2}")

    local -a FILES=()
    mapfile -d '' FILES < <(collect_files video "$CV_RECURSIVE" "$CV_FROM" "${paths[@]}")
    dedupe_files

    if ((${#FILES[@]} == 0)); then
        info "Nenhum vídeo encontrado."
        return 0
    fi

    info "${#FILES[@]} vídeo(s) encontrado(s); frames em: $FV_OUTPUT, jobs=$jobs"

    local f
    RUN_SRC=()
    RUN_DST=()
    for f in "${FILES[@]}"; do
        compute_frames_out "$f"
        RUN_SRC+=("$f")
        RUN_DST+=("$CONVERT_REPLY")
    done

    if ((dry_run == 1)); then
        local i
        for ((i = 0; i < ${#RUN_SRC[@]}; i++)); do
            printf '  %s -> %s/ (%s, width=%s, %s)\n' \
                "${RUN_SRC[i]}" "${RUN_DST[i]}" \
                "${FV_SCENE:+scene=$FV_SCENE}${FV_SCENE:-fps=$FV_FPS}" \
                "$FV_WIDTH" "$FV_FORMAT"
        done
        return 0
    fi

    export FV_FPS FV_SCENE FV_MAX_FRAMES FV_WIDTH FV_FORMAT FV_QUALITY
    export FV_OUTPUT FV_CLEAN FV_HWACCEL FV_MAX_SIZE_MB FV_MAX_DURATION
    export CV_FROM CV_VERBOSE

    summarize_results "frames" "${#FILES[@]}" count < <(run_pairs __frames_one "$jobs")
}

# -----------------------------------------------------------------------------
# Execução em paralelo
# -----------------------------------------------------------------------------
# Os pares origem/destino são calculados no processo pai para que nomes
# homônimos não colidam entre processos paralelos.
declare -ga RUN_SRC=()
declare -ga RUN_DST=()

run_pairs() {
    local mode="$1" jobs="$2"
    local i count=${#RUN_SRC[@]}
    ((count > 0)) || return 0

    if ((jobs <= 1)); then
        for ((i = 0; i < count; i++)); do
            "$SCRIPT_PATH" "$mode" "${RUN_SRC[i]}" "${RUN_DST[i]}"
        done
    else
        for ((i = 0; i < count; i++)); do
            printf '%s\0%s\0' "${RUN_SRC[i]}" "${RUN_DST[i]}"
        done | xargs -0 -r -P "$jobs" -n 2 "$SCRIPT_PATH" "$mode"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local cmd="${1:-}"
    (($# > 0)) && shift

    case "$cmd" in
        image|img|imagem) cmd_image "$@" ;;
        video|vid|vídeo) cmd_video "$@" ;;
        frames|frame|quadros) cmd_frames "$@" ;;
        __image_one)
            [[ $# -ge 1 ]] || die "uso interno: __image_one <arquivo> [destino]"
            convert_image_one "$1" "${2:-}"
            ;;
        __video_one)
            [[ $# -ge 1 ]] || die "uso interno: __video_one <arquivo> [destino]"
            convert_video_one "$1" "${2:-}"
            ;;
        __frames_one)
            [[ $# -ge 1 ]] || die "uso interno: __frames_one <arquivo> [destino]"
            extract_frames_one "$1" "${2:-}"
            ;;
        -h|--help|help|"") main_help ;;
        --version) printf 'convert.sh 1.0\n' ;;
        *)
            err "Comando desconhecido: $cmd"
            main_help
            exit 2
            ;;
    esac
}

main "$@"
