#!/bin/sh
# Gera cores do swaylock baseado no wallpaper atual (via Pywal)

COLORS_FILE="$HOME/.cache/wal/colors.css"
SWAYLOCK_FILE="$HOME/.config/swaylock/config"

if [ ! -f "$COLORS_FILE" ]; then
    echo "ERRO: sem paleta em $COLORS_FILE"
    echo "Gere uma com:"
    echo "  ~/.config/scripts/run-scripts.sh            # usa o wallpaper atual"
    echo "  ~/.config/scripts/run-scripts.sh <imagem>   # de um arquivo"
    echo "  (PALETTE_TOOL=wal volta ao pywal)"
    exit 1
fi

extract_color() {
    grep -- "--color$1:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d ';# '
}

bg=$(grep -- "--background:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d ';# ')
fg=$(grep -- "--foreground:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d ';# ')
c1=$(extract_color 1)
c6=$(extract_color 6)
c3=$(extract_color 3)

# Substitui apenas as linhas de cor, preservando o resto do config
sed -i \
    -e "s/^key-hl-color=.*/key-hl-color=${c6}/" \
    -e "s/^ring-color=.*/ring-color=${c1}D9/" \
    -e "s/^ring-clear-color=.*/ring-clear-color=${c6}D9/" \
    -e "s/^ring-caps-lock-color=.*/ring-caps-lock-color=${c3}D9/" \
    -e "s/^ring-ver-color=.*/ring-ver-color=${c3}D9/" \
    -e "s/^ring-wrong-color=.*/ring-wrong-color=${c1}D9/" \
    -e "s/^line-color=.*/line-color=${c6}/" \
    -e "s/^inside-color=.*/inside-color=00000000/" \
    -e "s/^text-color=.*/text-color=${fg}/" \
    -e "s/^bs-hl-color=.*/bs-hl-color=${c1}FF/" \
    "$SWAYLOCK_FILE"
