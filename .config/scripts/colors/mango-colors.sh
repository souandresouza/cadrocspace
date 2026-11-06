#!/bin/sh
# ~/.config/scripts/colors/mango-colors.sh
# Gera ~/.config/mango/theme.conf a partir da paleta do wallpaper (ruwall/pywal).
# Chamado pelo run-scripts.sh. O theme.conf versionado é só o fallback inicial.

COLORS_FILE="$HOME/.cache/wal/colors.css"
MANGO_FILE="$HOME/.config/mango/theme.conf"

if [ ! -f "$COLORS_FILE" ]; then
    echo "ERRO: sem paleta em $COLORS_FILE"
    echo "Gere uma com:"
    echo "  ~/.config/scripts/run-scripts.sh            # usa o wallpaper atual"
    echo "  ~/.config/scripts/run-scripts.sh <imagem>   # de um arquivo"
    echo "  (PALETTE_TOOL=wal volta ao pywal)"
    exit 1
fi

# Extrair cores do formato Pywal/CSS (--color0: #xxx;)
extract_color() {
    grep -- "--color$1:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; '
}

background=$(grep -- "--background:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')
foreground=$(grep -- "--foreground:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')

color0=$(extract_color 0)
color1=$(extract_color 1)
color2=$(extract_color 2)
color3=$(extract_color 3)
color4=$(extract_color 4)
color5=$(extract_color 5)
color6=$(extract_color 6)
color7=$(extract_color 7)
color8=$(extract_color 8)
color9=$(extract_color 9)
color10=$(extract_color 10)
color11=$(extract_color 11)
color12=$(extract_color 12)
color13=$(extract_color 13)
color14=$(extract_color 14)
color15=$(extract_color 15)

# Limpar cores (remover colchetes, espaços e #)
clean_color() {
    echo "$1" | tr -d '[]# '
}

if [ -z "$color0" ] || [ -z "$foreground" ]; then
    echo "ERRO: a paleta em $COLORS_FILE não tem cores utilizáveis."
    echo "Regere com: ~/.config/scripts/run-scripts.sh"
    exit 1
fi

bg=$(clean_color "$background")
fg=$(clean_color "$foreground")
c0=$(clean_color "$color0")
c1=$(clean_color "$color1")
c4=$(clean_color "$color4")
c5=$(clean_color "$color5")
c6=$(clean_color "$color6")
c7=$(clean_color "$color7")

mkdir -p "$(dirname "$MANGO_FILE")"

# O mangowm usa 0xRRGGBBAA (alpha no final).
cat > "$MANGO_FILE" << EOF
# Gerado por ~/.config/scripts/colors/mango-colors.sh a partir do wallpaper.
# NÃO EDITE MANUALMENTE — rode ~/.config/scripts/run-scripts.sh para atualizar.

shadows_color=0x${c0}ff
root_color=0x${bg}ff
border_color=0x${c7}ff
drop_color=0x${c7}55
split_color=0x${c7}ff
focus_color=0x${c5}ff
maximized_screen_color=0x${c7}ff
urgent_color=0x${c1}ff
scratchpad_color=0x${c5}ff
global_color=0x${c5}ff
overlay_color=0x${c7}ff
EOF

# Recarrega a configuração do mango sem encerrar a sessão.
if command -v mmsg >/dev/null 2>&1 && pgrep -x mango >/dev/null 2>&1; then
    mmsg dispatch reload_config >/dev/null 2>&1 || true
fi

echo "✅ Tema do mangowm atualizado em $MANGO_FILE"
