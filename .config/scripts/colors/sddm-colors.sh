#!/usr/bin/env bash
# =============================================================================
# sddm-colors.sh -- paleta do tema de login do Cadroc (SDDM)
# =============================================================================
#
# Gera ~/.local/state/cadrocspace/sddm/theme.conf a partir da paleta do
# wallpaper (pywal/ruwall: ~/.cache/wal/colors.css) e do estado do tema
# (~/.local/state/cadrocspace/state/state.env: ACCENT_COLOR/FONT_FAMILY).
#
# O arquivo gerado contém só as chaves controladas pelo Cadroc. O instalador do
# tema (sddm-cadroc-theme/installer.sh --recolor) mescla essas chaves no conf do
# tema, preservando o resto do comportamento definido no repositório.
#
# As cores são ajustadas para garantir contraste mínimo de leitura no formulário
# (texto >= 7:1, texto secundário >= 6:1, botão >= 4.5:1). Se a paleta do
# wallpaper não permitir, a cor é clareada/escurecida até passar.
#
# Uso:
#   sddm-colors.sh              # usa a paleta atual e o wallpaper atual
#   sddm-colors.sh /fundo.png   # também sugere esse wallpaper na tela de login

set -u

COLORS_FILE="$HOME/.cache/wal/colors.css"
THEME_LIB="$HOME/.config/scripts/cadroc_theme.sh"
OUT_DIR="$HOME/.local/state/cadrocspace/sddm"
OUT_FILE="$OUT_DIR/theme.conf"
WALLPAPER="${1:-${CADROC_WALLPAPER:-}}"

if [ ! -f "$COLORS_FILE" ]; then
    echo "ERRO: sem paleta em $COLORS_FILE"
    echo "Gere uma com:"
    echo "  ~/.config/scripts/run-scripts.sh            # usa o wallpaper atual"
    echo "  ~/.config/scripts/run-scripts.sh <imagem>   # de um arquivo"
    exit 1
fi

if [ ! -f "$THEME_LIB" ]; then
    echo "ERRO: biblioteca de tema não encontrada: $THEME_LIB" >&2
    exit 1
fi

# shellcheck source=/dev/null
. "$THEME_LIB"

extract_color() {
    grep -- "--color$1:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; '
}

background=$(grep -- "--background:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')
foreground=$(grep -- "--foreground:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')

if [ -z "$background" ] || [ -z "$foreground" ]; then
    echo "ERRO: a paleta em $COLORS_FILE não tem cores utilizáveis." >&2
    echo "Regere com: ~/.config/scripts/run-scripts.sh" >&2
    exit 1
fi

# Acentos e tons do pywal. O accent vem do estado do tema (atualizado por
# cadroc-colors.sh a partir da cor mais saturada da paleta).
ACCENT="${ACCENT_COLOR:-$THEME_DEFAULT_ACCENT}"
FONT="${FONT_FAMILY:-$THEME_DEFAULT_FONT}"

# Wallpaper: argumento explícito, CADROC_WALLPAPER (exportado pelo run-scripts)
# ou o que estiver registrado na paleta do pywal.
if [ -z "$WALLPAPER" ]; then
    WALLPAPER=$(grep -- "--wallpaper:" "$COLORS_FILE" | head -1 |
        sed -E 's/.*url\("?([^")]+)"?\).*/\1/')
fi

# Só sugere formatos que o tema sabe copiar.
case "${WALLPAPER,,}" in
    *.png|*.jpg|*.jpeg|*.webp) ;;
    *) WALLPAPER="" ;;
esac
if [ -n "$WALLPAPER" ] && [ ! -f "$WALLPAPER" ]; then
    WALLPAPER=""
fi

# Calcula as cores finais. A saída são linhas CHAVE=valor.
palette=$(python3 - "$background" "$foreground" "$ACCENT" "$(extract_color 0)" <<'PY'
import sys

def rgb(value):
    value = value.strip().lstrip('#')
    if len(value) == 3:
        value = ''.join(ch * 2 for ch in value)
    if len(value) != 6:
        raise SystemExit(f"cor inválida: {value!r}")
    return tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))

def hexs(color):
    return '#%02x%02x%02x' % tuple(max(0, min(255, round(c * 255))) for c in color)

def lum(color):
    def channel(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in color)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))

def ensure(color, base, target, towards_light=None):
    """Clareia/escurece `color` até contrastar `target` com `base`."""
    if contrast(color, base) >= target:
        return color
    if towards_light is None:
        towards_light = lum(base) < 0.5
    target_color = (1, 1, 1) if towards_light else (0, 0, 0)
    best = color
    for step in range(1, 21):
        best = mix(color, target_color, step / 20)
        if contrast(best, base) >= target:
            break
    return best

bg, fg = rgb(sys.argv[1]), rgb(sys.argv[2])
accent_in = rgb(sys.argv[3])
c0 = rgb(sys.argv[4])

# Cor de aviso (caps lock, falha de login): vermelho quente fixo, ajustado para
# contrastar com o fundo. pywal nem sempre coloca um vermelho utilizável em
# color1, então o tom é do Cadroc e não da paleta.
warn_in = (0.878, 0.541, 0.416)  # #e08a6a

# Fundo do formulário: o tom mais escuro da paleta que ainda comporte o texto.
base = c0
if lum(base) > 0.32 or contrast(fg, base) < 7:
    base = mix(bg, (0, 0, 0), 0.55)
if lum(base) > 0.32:
    base = mix(base, (0, 0, 0), 0.7)

text = ensure(fg, base, 7.0)
deep = mix(base, (0, 0, 0), 0.45)
field = mix(base, text, 0.08)
muted = ensure(mix(base, text, 0.62), base, 6.0)
accent = ensure(accent_in, base, 3.0)
on_accent = (0, 0, 0) if contrast((0, 0, 0), accent) > contrast((1, 1, 1), accent) else (1, 1, 1)
accent = ensure(accent, on_accent, 4.5, towards_light=lum(accent) > 0.5)
on_accent = (0, 0, 0) if contrast((0, 0, 0), accent) > contrast((1, 1, 1), accent) else (1, 1, 1)
hover = mix(accent, (1, 1, 1) if lum(accent) < 0.5 else (0, 0, 0), 0.18)
warn = ensure(warn_in, base, 5.0)
border = mix(base, text, 0.25)

pairs = {
    'BASE': base,
    'DEEP': deep,
    'FIELD': field,
    'TEXT': text,
    'MUTED': muted,
    'ACCENT': accent,
    'ON_ACCENT': on_accent,
    'HOVER': hover,
    'WARN': warn,
    'BORDER': border,
}

def shell_quote(value):
    return '"%s"' % value.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')

for key, color in pairs.items():
    print(f'{key}={shell_quote(hexs(color))}')
print(f'CT_TEXT={contrast(text, base):.2f}')
print(f'CT_MUTED={contrast(muted, base):.2f}')
print(f'CT_BUTTON={contrast(on_accent, accent):.2f}')
PY
) || { echo "ERRO: falha ao calcular a paleta do SDDM." >&2; exit 1; }

declare -A P=()
while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    value="${value%\"}"
    value="${value#\"}"
    P["$key"]="$value"
done <<< "$palette"

mkdir -p "$OUT_DIR"

{
    echo "# Gerado por ~/.config/scripts/colors/sddm-colors.sh"
    echo "# NÃO EDITE — rode run-scripts.sh (ou este script) de novo."
    echo "# Aplicar no tema instalado: sddm-cadroc-theme/installer.sh --recolor"
    echo "#"
    echo "# Contraste: texto/fundo ${P[CT_TEXT]}:1, secundário/fundo ${P[CT_MUTED]}:1, botão/acento ${P[CT_BUTTON]}:1"
    echo
    echo "Font=\"${FONT//\"/\\\"}\""
    echo
    echo "HeaderTextColor=${P[TEXT]}"
    echo "DateTextColor=${P[MUTED]}"
    echo "TimeTextColor=${P[TEXT]}"
    echo
    echo "FormBackgroundColor=${P[BASE]}"
    echo "BackgroundColor=${P[BASE]}"
    echo "DimBackgroundColor=${P[DEEP]}"
    echo
    echo "LoginFieldBackgroundColor=${P[FIELD]}"
    echo "PasswordFieldBackgroundColor=${P[FIELD]}"
    echo "LoginFieldTextColor=${P[TEXT]}"
    echo "PasswordFieldTextColor=${P[TEXT]}"
    echo "UserIconColor=${P[ACCENT]}"
    echo "PasswordIconColor=${P[ACCENT]}"
    echo
    echo "PlaceholderTextColor=${P[MUTED]}"
    echo "WarningColor=${P[WARN]}"
    echo
    echo "LoginButtonTextColor=${P[ON_ACCENT]}"
    echo "LoginButtonBackgroundColor=${P[ACCENT]}"
    echo "SystemButtonsIconsColor=${P[TEXT]}"
    echo "SessionButtonTextColor=${P[TEXT]}"
    echo "VirtualKeyboardButtonTextColor=${P[TEXT]}"
    echo
    echo "DropdownTextColor=${P[ON_ACCENT]}"
    echo "DropdownSelectedBackgroundColor=${P[HOVER]}"
    echo "DropdownBackgroundColor=${P[ACCENT]}"
    echo
    echo "HighlightTextColor=${P[ON_ACCENT]}"
    echo "HighlightBackgroundColor=${P[ACCENT]}"
    echo "HighlightBorderColor=${P[BORDER]}"
    echo
    echo "HoverUserIconColor=${P[HOVER]}"
    echo "HoverPasswordIconColor=${P[HOVER]}"
    echo "HoverSystemButtonsIconsColor=${P[HOVER]}"
    echo "HoverSessionButtonTextColor=${P[HOVER]}"
    echo "HoverVirtualKeyboardButtonTextColor=${P[HOVER]}"
    echo
    if [ -n "$WALLPAPER" ]; then
        printf 'Wallpaper="%s"\n' "$WALLPAPER"
    fi
} > "${OUT_FILE}.tmp" && mv "${OUT_FILE}.tmp" "$OUT_FILE"

echo "✅ Paleta do SDDM gerada em $OUT_FILE"
echo "   texto/fundo ${P[CT_TEXT]}:1 · secundário ${P[CT_MUTED]}:1 · botão ${P[CT_BUTTON]}:1"
[ -n "$WALLPAPER" ] && echo "   wallpaper sugerido: $WALLPAPER"
echo "   aplique com: sudo sddm-cadroc-theme/installer.sh --recolor"
