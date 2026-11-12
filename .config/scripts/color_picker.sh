#!/usr/bin/env bash

# Conta-gotas de cor com grim + slurp (wlroots, funciona no mangowm).
# Sem dependência de pacotes do ecossistema Hyprland.
# A notificação com preview fica aqui; o tema continua sendo gerado pelo
# pipeline de paleta em ~/.config/scripts/run-scripts.sh.

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: color_picker.sh [-hex|-rgb|-hsv] [--apply]
Pick a color from the screen and show it in a notification.

Options:
    -hex          Report the color as HEX (default)
    -rgb          Report the color as rgb(r,g,b)
    -hsv          Report the color as hsv(h,s%,v%)
    --apply       Re-render the current theme (palette comes from the wallpaper)
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

missing=()
for cmd in grim slurp magick wl-copy; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if ((${#missing[@]} > 0)); then
    msg="Faltando: ${missing[*]} (pacotes: grim, slurp, imagemagick, wl-clipboard)"
    echo "color_picker: $msg" >&2
    notify-send "Color picker" "$msg" -i dialog-error 2>/dev/null || true
    exit 1
fi

# Escolhe um pixel e devolve o hex (sem '#').
pick_hex() {
    local geom hex
    # grim espera "X,Y WxH" (o mesmo formato que o slurp imprime por padrão)
    geom=$(slurp -p -f '%x,%y %wx%h') || return 1
    hex=$(grim -g "$geom" -t png - 2>/dev/null |
        magick png:- -format '%[hex:p{0,0}]' info: 2>/dev/null) || return 1
    [[ -n "$hex" ]] && printf '%s\n' "$hex"
}

color="$(pick_hex)" || exit 1
color="${color#\#}"
color="${color,,}"
[[ "$color" =~ ^[0-9a-f]{6}$ ]] || {
    notify-send "Color picker" "Não foi possível ler a cor" -i dialog-error 2>/dev/null || true
    exit 1
}

r=$((16#${color:0:2}))
g=$((16#${color:2:2}))
b=$((16#${color:4:2}))

case "$FORMAT" in
    rgb) value="rgb($r,$g,$b)" ;;
    hsv) value=$(awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN {
            r /= 255; g /= 255; b /= 255
            mx = r; if (g > mx) mx = g; if (b > mx) mx = b
            mn = r; if (g < mn) mn = g; if (b < mn) mn = b
            d = mx - mn
            if (d == 0) h = 0
            else if (mx == r) h = 60 * (((g - b) / d) % 6)
            else if (mx == g) h = 60 * (((b - r) / d) + 2)
            else h = 60 * (((r - g) / d) + 4)
            if (h < 0) h += 360
            s = (mx == 0) ? 0 : d / mx
            printf "hsv(%d,%d%%,%d%%)\n", h + 0.5, s * 100 + 0.5, mx * 100 + 0.5
        }') ;;
    *) value="$color" ;;
esac

printf '%s' "$value" | wl-copy -n

# Preview da cor como ícone da notificação
preview="/tmp/color-picker-preview.png"
if command -v magick >/dev/null 2>&1; then
    magick -size 64x64 "xc:#$color" "$preview" 2>/dev/null || preview=""
fi

if $APPLY; then
    # O accent sai da paleta do wallpaper (regra do cadroc-colors.sh); não há
    # modo "cor solta". Então --apply apenas re-renderiza o tema atual.
    "$HOME/.config/scripts/run-scripts.sh" || true
    [[ -n "$preview" ]] && rm -f "$preview"
    exit 0
fi

[[ "$FORMAT" == "hex" ]] && label="HEX" || label="${FORMAT^^}"
notify_args=(-t 5000 "$label color picked" "$value" -a "Color picker")
[[ -n "$preview" ]] && notify_args+=(-i "$preview")
notify-send "${notify_args[@]}" 2>/dev/null || true
[[ -n "$preview" ]] && rm -f "$preview"

echo "$value"
