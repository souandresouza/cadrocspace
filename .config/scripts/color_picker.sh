#!/usr/bin/env bash

# Conta-gotas de cor com hyprpicker.
# A notificação com preview fica aqui; a aplicação da cor como destaque do
# tema usa os utilitários em ~/.local/bin (apply_style.sh/gen_style.sh).

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: color_picker.sh [-hex|-rgb|-hsv] [--apply]
Pick a color with hyprpicker and show it in a notification.

Options:
    -hex          Report the color as HEX (default)
    -rgb          Report the color as rgb(r,g,b)
    -hsv          Report the color as hsv(h,s,v)
    --apply       Apply the picked color as the desktop accent color
    -h, --help    Show this help message
USAGE
    exit 0
fi

FORMAT="hex"
APPLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -hex) FORMAT="hex" ;;
        -rgb) FORMAT="rgb" ;;
        -hsv) FORMAT="hsv" ;;
        --apply) APPLY=true ;;
        -h|--help)
            # o bloco de ajuda acima já cobre este caso
            sed -n '2,20p' "$0" >&2
            exit 0
            ;;
        *)
            echo "Usage: $(basename "$0") [-hex|-rgb|-hsv] [--apply]" >&2
            exit 1
            ;;
    esac
    shift
done

# Dependências
for cmd in hyprpicker wl-paste notify-send; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "$cmd is not installed. Please install it to use this script." >&2
        notify-send "Color picker" "$cmd is not installed" -i dialog-error 2>/dev/null || true
        exit 1
    }
done

# hyprpicker escreve o valor no clipboard com -a -n
hyprpicker -a -n -f "$FORMAT" || exit 1
sleep 0.1
color="$(wl-paste)"
[[ -n "$color" ]] || exit 1

# Preview da cor como ícone da notificação
preview="/tmp/color-picker-preview.png"
if command -v magick >/dev/null 2>&1; then
    case "$FORMAT" in
        rgb) magick -size 64x64 xc:"rgb($color)" "$preview" 2>/dev/null ;;
        hsv) magick -size 64x64 xc:"hsv($color)" "$preview" 2>/dev/null ;;
        *)   magick -size 64x64 xc:"$color" "$preview" 2>/dev/null ;;
    esac
fi

if $APPLY; then
    [[ "$FORMAT" == "hex" ]] || {
        hex=$(magick "$preview" -format '%[hex:p{0,0}]' info: 2>/dev/null)
        color="${hex:-$color}"
    }
    # pywal nao tem modo "paleta a partir de uma cor solida" (o -c dele limpa o
    # cache), entao o --apply nao pode regerar o tema. Fica como na era pywal:
    # reaplica o estilo atual (recarga apps/fonte via apply_style.sh) sem
    # prometer mudanca de paleta.
    if [[ -f "$HOME/.local/bin/gen_style.sh" ]]; then
        "$HOME/.local/bin/gen_style.sh" "$color" || true
    fi
    if [[ -x "$HOME/.local/bin/apply_style.sh" ]]; then
        "$HOME/.local/bin/apply_style.sh"
    fi
    rm -f "$preview"
    exit 0
fi

[[ "$FORMAT" == "hex" ]] && label="HEX" || label="${FORMAT^^}"
notify-send -t 5000 "$label color picked" "$color" -i "$preview" -a "Color picker"
rm -f "$preview"

echo "$color"