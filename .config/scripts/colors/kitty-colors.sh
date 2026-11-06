#!/bin/sh
# ~/.config/scripts/colors/kitty-colors.sh
# Gera configuração de cores do Kitty baseado no wallpaper atual (via Pywal)

COLORS_FILE="$HOME/.cache/wal/colors.css"
KITTY_FILE="$HOME/.config/kitty/colors-kitty.conf"

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

# Extrair também background, foreground e cursor
background=$(grep -- "--background:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')
foreground=$(grep -- "--foreground:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')
cursor=$(grep -- "--cursor:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')

# Extrair cores 0-15
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

# Verificar se as cores foram extraídas
if [ -z "$color0" ] || [ -z "$background" ] || [ -z "$foreground" ] || [ -z "$cursor" ]; then
    echo "ERRO: a paleta em $COLORS_FILE não tem cores utilizáveis."
    echo "Regere com: ~/.config/scripts/run-scripts.sh"
    exit 1
fi

mkdir -p "$(dirname "$KITTY_FILE")"

# Gerar arquivo no formato do Kitty
cat > "$KITTY_FILE" << EOF
foreground $foreground
background $background
cursor      $cursor

color0  $color0
color1  $color1
color2  $color2
color3  $color3
color4  $color4
color5  $color5
color6  $color6
color7  $color7
color8  $color8
color9  $color9
color10 $color10
color11 $color11
color12 $color12
color13 $color13
color14 $color14
color15 $color15

selection_foreground $foreground
selection_background $color4

active_border_color   $color7
inactive_border_color $color0

active_tab_foreground   $foreground
active_tab_background   $background
inactive_tab_foreground $color7
inactive_tab_background $color0
EOF

echo "✅ Configuração gerada em $KITTY_FILE"

# Recarrega o Kitty se estiver em execução
if pgrep -x kitty >/dev/null 2>&1; then
    # 'load-config' relê o kitty.conf inteiro, já seguindo os includes.
    # Precisa de allow_remote_control + listen_on no kitty.conf.
    if kitty @ load-config >/dev/null 2>&1; then
        echo "✅ Kitty recarregado"
    else
        pkill -SIGUSR1 -x kitty 2>/dev/null || true
        echo "✅ Kitty recarregado (SIGUSR1)"
    fi
else
    echo "ℹ️  Kitty não está em execução, configuração será aplicada no próximo início."
fi
