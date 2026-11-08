#!/usr/bin/env bash
# =============================================================================
# convert-lib.sh -- funções compartilhadas pelos scripts de conversão
# =============================================================================
#
# Ideias adaptadas da arquitetura do VERT (https://github.com/VERT-sh/VERT):
#   - escolha de motor por formato, com fallback
#   - validação de saída antes de substituir/apagar o original
#   - escrita atômica (temporário + mv)
#   - nomes de saída sem colisão
#   - resumo por arquivo e por lote
#
# Este arquivo é feito para ser "sourced", não executado diretamente.
# =============================================================================

# Evita carregar duas vezes.
if [[ -n "${_CONVERT_LIB_LOADED:-}" ]]; then
    return 0
fi
_CONVERT_LIB_LOADED=1

# -----------------------------------------------------------------------------
# Cores e log
# -----------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET=$'\033[0m'
    C_RED=$'\033[0;31m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[0;34m'
    C_DIM=$'\033[2m'
else
    C_RESET="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_DIM=""
fi

log()   { printf '%s\n' "$*"; }
info()  { printf '%s[i]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()    { printf '%s[✓]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }
debug() {
    if [[ "${CV_VERBOSE:-0}" == "1" ]]; then
        printf '%s[d]%s %s\n' "$C_DIM" "$C_RESET" "$*" >&2
    fi
}

have() { command -v -- "$1" >/dev/null 2>&1; }

require() {
    local c
    local -a missing=()
    for c in "$@"; do
        have "$c" || missing+=("$c")
    done
    ((${#missing[@]} == 0)) || die "Dependência(s) ausente(s): ${missing[*]}"
}

# -----------------------------------------------------------------------------
# Utilidades gerais
# -----------------------------------------------------------------------------
now_ms() {
    local t
    t=$(date +%s%3N 2>/dev/null) || t=""
    if [[ "$t" =~ ^[0-9]+$ ]]; then
        printf '%s' "$t"
    else
        printf '%s000' "$(date +%s)"
    fi
}

human_size() {
    local n="${1:-0}"
    if have numfmt; then
        numfmt --to=iec-i --suffix=B -- "$n" 2>/dev/null || printf '%sB' "$n"
    else
        printf '%sB' "$n"
    fi
}

format_ms() {
    awk -v ms="${1:-0}" 'BEGIN {
        if (ms < 1000) printf "%dms", ms;
        else printf "%.1fs", ms / 1000;
    }'
}

job_count() {
    local n="${1:-0}"
    if [[ "$n" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s' "$n"
        return
    fi
    n=$(nproc 2>/dev/null || printf '4')
    [[ "$n" =~ ^[1-9][0-9]*$ ]] || n=4
    ((n > 8)) && n=8
    printf '%s' "$n"
}

# Extensão em minúsculas, sem o ponto.
ext_of() {
    local b
    b=$(basename -- "$1")
    [[ "$b" == *.* && "$b" != .* ]] || { printf ''; return; }
    printf '%s' "${b##*.}" | tr '[:upper:]' '[:lower:]'
}

# Normaliza variantes comuns.
canon_ext() {
    case "${1,,}" in
        jpeg|jpe|jfif) echo "jpg" ;;
        tif)           echo "tiff" ;;
        heif)          echo "heic" ;;
        svgz)          echo "svg" ;;
        yuv)           echo "yuv" ;;
        *)             echo "${1,,}" ;;
    esac
}

is_image_ext() {
    case "$(canon_ext "$1")" in
        jpg|png|webp|avif|heic|tiff|gif|bmp|svg|jxl|psd|ico|ppm|pgm|pbm|pnm|tga|dds|exr|hdr|qoi|jp2|j2k|dcm|\
        raw|cr2|cr3|nef|arw|dng|orf|rw2|raf|pef|srw|xcf|mrw|mef|nrw|erf|3fr|mos|dcr|crw)
            return 0 ;;
        *) return 1 ;;
    esac
}

is_video_ext() {
    case "${1,,}" in
        mp4|m4v|mkv|webm|mov|avi|flv|f4v|wmv|asf|mpg|mpeg|mpe|m2v|ts|mts|m2ts|3gp|3g2|ogv|ogx|vob|mxf|gxf|divx|h264|h265|hevc|nut|y4m|rm|rmvb|gif)
            return 0 ;;
        *) return 1 ;;
    esac
}

# Divide uma lista separada por vírgula em um array global.
split_csv() {
    local csv="${1:-}"
    SPLIT_RESULT=()
    [[ -n "$csv" ]] || return 0
    local IFS=','
    local item
    for item in $csv; do
        item="${item//[[:space:]]/}"
        [[ -n "$item" ]] && SPLIT_RESULT+=("$item")
    done
}

# -----------------------------------------------------------------------------
# Coleta de arquivos
# -----------------------------------------------------------------------------
# Uso: collect_files <image|video> <recursive 0|1> <from-csv|""> <paths...>
# Escreve caminhos separados por NUL em stdout.
collect_files() {
    local kind="$1" recursive="$2" from_csv="$3"
    shift 3

    local -a exts=()
    if [[ -n "$from_csv" ]]; then
        split_csv "$from_csv"
        exts=("${SPLIT_RESULT[@]}")
    elif [[ "$kind" == "image" ]]; then
        exts=(jpg jpeg png webp avif heic heif tiff tif gif bmp svg svgz jxl psd ico
              ppm pgm pbm pnm tga dds exr hdr qoi jp2 j2k dcm
              raw cr2 cr3 nef arw dng orf rw2 raf pef srw xcf mrw mef nrw erf 3fr mos dcr crw)
    else
        exts=(mp4 m4v mkv webm mov avi flv f4v wmv asf mpg mpeg mpe m2v ts mts m2ts
              3gp 3g2 ogv ogx vob mxf gxf divx h264 h265 hevc nut y4m rm rmvb gif)
    fi

    local p
    for p in "$@"; do
        if [[ -f "$p" ]]; then
            printf '%s\0' "$p"
            continue
        fi

        if [[ ! -d "$p" ]]; then
            warn "Não existe ou não é arquivo/diretório: $p"
            continue
        fi

        local -a base=("$p")
        [[ "$recursive" == "1" ]] || base+=(-maxdepth 1)
        base+=(-type f)

        local -a pred=()
        local e first=1
        for e in "${exts[@]}"; do
            e="${e#.}"
            [[ -n "$e" ]] || continue
            if ((first)); then
                pred+=(-iname "*.$e")
                first=0
            else
                pred+=(-o -iname "*.$e")
            fi
        done
        ((${#pred[@]} > 0)) || continue

        find "${base[@]}" \( "${pred[@]}" \) -print0 2>/dev/null
    done
}

# Remove duplicatas do array global FILES (por caminho absoluto).
dedupe_files() {
    local -A seen=()
    local -a unique=()
    local f key
    for f in "${FILES[@]}"; do
        key=$(readlink -f -- "$f" 2>/dev/null || printf '%s' "$f")
        [[ -n "${seen[$key]:-}" ]] && continue
        seen[$key]=1
        unique+=("$f")
    done
    FILES=("${unique[@]}")
}

# -----------------------------------------------------------------------------
# Nomes de saída
# -----------------------------------------------------------------------------
# Caminhos de saída já reservados no lote atual. Evita que dois arquivos de
# entrada com o mesmo nome-base escolham o mesmo destino em execução paralela.
declare -gA CONVERT_RESERVED=()

# Define CONVERT_REPLY com um caminho livre. Se o alvo existir (ou já estiver
# reservado no lote), cria "nome-1.ext", "nome-2.ext", ...
unique_path_var() {
    local target="$1"

    local dir base stem ext i=1
    dir=$(dirname -- "$target")
    base=$(basename -- "$target")
    if [[ "$base" == *.* && "$base" != .* ]]; then
        ext=".${base##*.}"
        stem="${base%.*}"
    else
        ext=""
        stem="$base"
    fi

    local candidate="$target"
    while [[ -e "$candidate" || -n "${CONVERT_RESERVED[$candidate]:-}" ]]; do
        candidate="$dir/$stem-$i$ext"
        ((i++))
    done
    CONVERT_RESERVED[$candidate]=1
    CONVERT_REPLY="$candidate"
}

# Caminho temporário no mesmo diretório, com a extensão correta para que
# ImageMagick/FFmpeg reconheçam o formato de saída.
temp_output_path() {
    local final="$1"
    local dir base stem ext
    dir=$(dirname -- "$final")
    base=$(basename -- "$final")
    if [[ "$base" == *.* && "$base" != .* ]]; then
        ext=".${base##*.}"
        stem="${base%.*}"
    else
        ext=""
        stem="$base"
    fi
    printf '%s/.%s.part.%s.%s%s' "$dir" "$stem" "$$" "$RANDOM" "$ext"
}

# -----------------------------------------------------------------------------
# Validação
# -----------------------------------------------------------------------------
validate_dimensions() {
    [[ "${1:-}" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]
}

validate_int_range() {
    local value="$1" min="$2" max="$3"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    ((value >= min && value <= max))
}

validate_positive_int() {
    [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

im_format_name() {
    case "$(canon_ext "$1")" in
        jpg)  echo "JPEG" ;;
        png)  echo "PNG" ;;
        webp) echo "WEBP" ;;
        avif) echo "AVIF" ;;
        heic) echo "HEIC" ;;
        tiff) echo "TIFF" ;;
        gif)  echo "GIF" ;;
        bmp)  echo "BMP" ;;
        jxl)  echo "JXL" ;;
        ico)  echo "ICO" ;;
        svg)  echo "SVG" ;;
        psd)  echo "PSD" ;;
        *)    echo "${1^^}" ;;
    esac
}

# Uso: validate_image <arquivo> [extensão esperada]
validate_image() {
    local f="$1" expected="${2:-}"
    [[ -s "$f" ]] || return 1
    have magick || return 0

    local actual
    actual=$(magick identify -format '%m' "${f}[0]" 2>/dev/null) || return 1
    [[ -n "$actual" ]] || return 1

    if [[ -n "$expected" ]]; then
        local want
        want=$(im_format_name "$expected")
        [[ "${actual^^}" == "${want^^}" ]] || {
            debug "formato inesperado em $f: $actual (esperado $want)"
            return 1
        }
    fi
    return 0
}

# Uso: validate_video <arquivo>
validate_video() {
    local f="$1"
    [[ -s "$f" ]] || return 1
    have ffprobe || return 0

    local has_video
    has_video=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=codec_type -of csv=p=0 "$f" 2>/dev/null | head -n1)
    [[ "$has_video" == "video" ]] || return 1

    local duration
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null | head -n1)
    [[ "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
    awk -v d="$duration" 'BEGIN { exit !(d > 0) }'
}

# -----------------------------------------------------------------------------
# Imagens: informações e motores
# -----------------------------------------------------------------------------
# Preenche IMG_W, IMG_H, IMG_ALPHA (0/1), IMG_FRAMES.
image_probe() {
    local f="$1"
    IMG_W=0 IMG_H=0 IMG_ALPHA=0 IMG_FRAMES=1

    local line w h channels frames
    line=$(magick identify -format '%w %h %[channels] %n\n' "${f}[0]" 2>/dev/null | head -n1) || return 1
    read -r w h channels frames <<<"$line"
    [[ "$w" =~ ^[0-9]+$ ]] && IMG_W="$w"
    [[ "$h" =~ ^[0-9]+$ ]] && IMG_H="$h"
    [[ "${channels,,}" == *a* ]] && IMG_ALPHA=1
    [[ "$frames" =~ ^[0-9]+$ ]] && ((frames > 1)) && IMG_FRAMES="$frames"

    # Alguns formatos não reportam %n de forma confiável no primeiro frame.
    case "$(canon_ext "$(ext_of "$f")")" in
        gif|webp|tiff|ico)
            local n
            n=$(magick identify -format '%n\n' "$f" 2>/dev/null | head -n1)
            if [[ "$n" =~ ^[0-9]+$ ]] && ((n > IMG_FRAMES)); then
                IMG_FRAMES="$n"
            fi
            ;;
    esac
    return 0
}

# Escolhe um destino "auto" razoável: preserva transparência e animação,
# e não transforma fotos em PNG gigantes sem necessidade.
auto_target_for() {
    local src="$1" ext="$2"
    case "$ext" in
        gif|webp|png|jpg|tiff) printf '%s' "$ext"; return ;;
        heic|heif|avif|raw|cr2|cr3|nef|arw|dng|orf|rw2|raf|pef|srw|jxl|psd)
            printf 'jpg'; return ;;
        svg) printf 'png'; return ;;
    esac

    if have magick && image_probe "$src" 2>/dev/null; then
        if ((IMG_ALPHA == 1)); then
            printf 'png'
        else
            printf 'jpg'
        fi
    else
        printf 'jpg'
    fi
}

# Decodifica formatos "difíceis" para PNG usando outro motor.
# Uso: decode_fallback <origem> <destino.png> <extensão> <qualidade>
decode_fallback() {
    local src="$1" dst="$2" ext="$3" quality="${4:-90}" engine
    local -a engines=()
    case "$ext" in
        heic) engines=(heif-convert vips rsvg-convert) ;;
        avif|jxl) engines=(vips heif-convert magick) ;;
        svg) engines=(rsvg-convert magick vips) ;;
        *) engines=(vips magick) ;;
    esac

    for engine in "${engines[@]}"; do
        have "$engine" || continue
        debug "fallback de decodificação: $engine ($src)"
        case "$engine" in
            heif-convert)
                # heif-convert aceita -q para saída JPEG; para PNG é lossless.
                if heif-convert -q "$quality" "$src" "$dst" >/dev/null 2>&1 && [[ -s "$dst" ]]; then
                    return 0
                fi
                ;;
            vips)
                if vips copy "$src" "$dst" >/dev/null 2>&1 && [[ -s "$dst" ]]; then
                    return 0
                fi
                ;;
            rsvg-convert)
                if rsvg-convert -d 192 -p 192 -b none "$src" -o "$dst" >/dev/null 2>&1 && [[ -s "$dst" ]]; then
                    return 0
                fi
                ;;
            magick)
                if magick "${src}[0]" -auto-orient "$dst" >/dev/null 2>&1 && [[ -s "$dst" ]]; then
                    return 0
                fi
                ;;
        esac
        rm -f -- "$dst"
    done
    return 1
}

# -----------------------------------------------------------------------------
# Status entre processos (uma linha TSV por arquivo)
# -----------------------------------------------------------------------------
# Formato: status<US>origem<US>destino<US>bytes_in<US>bytes_out<US>ms<US>motivo
# Usa o separador de unidade (0x1F) em vez de TAB porque campos vazios (destino
# de um arquivo ignorado, por exemplo) não podem ser lidos com IFS=TAB.
status_line() {
    local status="$1" src="$2" dst="$3" inb="$4" outb="$5" ms="$6" reason="${7:-}"
    reason="${reason//$'\x1f'/ }"
    reason="${reason//$'\n'/ }"
    reason="${reason//$'\r'/ }"
    printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s\n' \
        "$status" "$src" "$dst" "$inb" "$outb" "$ms" "$reason"
}

# Lê as linhas de status e imprime um resumo.
# Uso: summarize_results <rótulo-destino> <número-de-arquivos-esperados> <unidade>
# Retorna 1 se houve falhas (ou se faltou status de algum arquivo).
summarize_results() {
    local label="$1" expected="$2" unit="${3:-bytes}"
    local total=0 successes=0 failures=0 skipped=0
    local bytes_in=0 bytes_out=0
    local status src dst inb outb ms reason

    while IFS=$'\x1f' read -r status src dst inb outb ms reason; do
        [[ -n "$status" ]] || continue
        ((total++))
        case "$status" in
            OK)
                ((successes++))
                bytes_in=$((bytes_in + ${inb:-0}))
                if [[ "$unit" == "count" ]]; then
                    bytes_out=$((bytes_out + ${outb:-0}))
                    ok "$src -> $dst (${outb:-0} arquivo(s), $(format_ms "${ms:-0}"))"
                else
                    bytes_out=$((bytes_out + ${outb:-0}))
                    ok "$src -> $dst ($(human_size "${inb:-0}") -> $(human_size "${outb:-0}"), $(format_ms "${ms:-0}"))"
                fi
                ;;
            SKIP)
                ((skipped++))
                info "ignorado: $src${reason:+ ($reason)}"
                ;;
            *)
                ((failures++))
                err "falhou: $src${reason:+ — $reason}"
                ;;
        esac
    done

    if ((total < expected)); then
        local missing=$((expected - total))
        failures=$((failures + missing))
        warn "$missing arquivo(s) não reportaram status (processo interrompido?)"
    fi

    local extra=""
    if [[ "$unit" == "count" ]]; then
        extra="${bytes_out} frame(s)"
    else
        extra="$(human_size "$bytes_in") -> $(human_size "$bytes_out")"
    fi

    printf '\n%sResumo (%s)%s: %d processado(s), %d ok, %d ignorado(s), %d falha(s); %s\n' \
        "$C_BLUE" "$label" "$C_RESET" "$total" "$successes" "$skipped" "$failures" "$extra"

    ((failures == 0))
}
