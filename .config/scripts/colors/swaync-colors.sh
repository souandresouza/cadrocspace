#!/bin/bash
# Gera cores do SwayNC baseado no wallpaper atual (via Pywal)
# Escreve ~/.config/swaync/colors-swaync.css, importado por style.css

COLORS_FILE="$HOME/.cache/wal/colors.css"
SWAYNC_DIR="$HOME/.config/swaync"
SWAYNC_FILE="$SWAYNC_DIR/colors-swaync.css"

if [ ! -f "$COLORS_FILE" ]; then
    echo "ERRO: sem paleta em $COLORS_FILE"
    echo "Gere uma com:"
    echo "  ~/.config/scripts/run-scripts.sh            # usa o wallpaper atual"
    echo "  ~/.config/scripts/run-scripts.sh <imagem>   # de um arquivo"
    echo "  (PALETTE_TOOL=wal volta ao pywal)"
    echo "Sem paleta em ~/.cache/wal. Gere uma com:"
    echo "  ~/.config/scripts/run-scripts.sh            # usa o wallpaper atual"
    echo "  ~/.config/scripts/run-scripts.sh <imagem>   # de um arquivo"
    echo "  (ou PALETTE_TOOL=wal para voltar ao pywal)"
    exit 1
fi

# Extrair cores do formato Pywal/CSS (--color0: #xxx;)
extract_color() {
    grep -- "--color$1:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; '
}

background=$(grep -- "--background:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')
foreground=$(grep -- "--foreground:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')

color1=$(extract_color 1)
color2=$(extract_color 2)
color6=$(extract_color 6)

# Converte #rrggbb em "r, g, b" para uso em rgba()
hex_to_rgb() {
    local h="${1#\#}"
    printf '%d, %d, %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

# Escolhe a cor de destaque: a mais saturada entre color1..color6.
# Garante um accent utilizável em qualquer wallpaper (o pywal nem
# sempre coloca a cor mais viva na mesma posição).
accent=""
best_score=-1
for i in 1 2 3 4 5 6; do
    c=$(extract_color "$i")
    [ -z "$c" ] && continue
    read -r r g b <<< "$(hex_to_rgb "$c" | tr ',' ' ')"
    max=$r
    min=$r
    for v in "$g" "$b"; do
        (( v > max )) && max=$v
        (( v < min )) && min=$v
    done
    score=$(( max - min ))
    if (( score > best_score )); then
        best_score=$score
        accent="$c"
    fi
done

# Verificar se as cores foram extraídas
if [ -z "$background" ] || [ -z "$foreground" ] || [ -z "$accent" ]; then
    echo "ERRO: a paleta em $COLORS_FILE não tem cores utilizáveis."
    echo "Regere com: ~/.config/scripts/run-scripts.sh"
    exit 1
fi

bg_rgb=$(hex_to_rgb "$background")
fg_rgb=$(hex_to_rgb "$foreground")
accent_rgb=$(hex_to_rgb "$accent")
surface_rgb=$(hex_to_rgb "$color1")
surface2_rgb=$(hex_to_rgb "$color2")

mkdir -p "$SWAYNC_DIR"

# Heredoc sem aspas: as variáveis do Pywal são expandidas na geração.
cat > "$SWAYNC_FILE" << EOF
/* Gerado por ~/.config/scripts/colors/swaync-colors.sh a partir do Pywal.
   NÃO EDITE MANUALMENTE — edite style.css ou o script. */

@define-color bg          $background;
@define-color fg          $foreground;
@define-color muted       $color6;
@define-color accent      $accent;
@define-color surface     $color1;
@define-color surface-2   $color2;

/* Variantes translúcidas */
@define-color bg-solid    $background;
@define-color bg-cc       rgba($bg_rgb, 0.94);
@define-color bg-hover    rgba($surface_rgb, 0.32);
@define-color bg-active   rgba($surface_rgb, 0.45);
@define-color border      rgba($surface_rgb, 0.55);
@define-color border-soft rgba($surface_rgb, 0.30);
@define-color accent-soft rgba($accent_rgb, 0.22);
@define-color accent-mid  rgba($accent_rgb, 0.55);
@define-color fg-dim      rgba($fg_rgb, 0.55);
@define-color fg-faint    rgba($fg_rgb, 0.12);
EOF

echo "✅ Configuração gerada em $SWAYNC_FILE"
echo "   accent: $accent (background: $background)"

# Recarrega o SwayNC se estiver em execução
if pgrep -x swaync >/dev/null; then
    swaync-client --reload-css >/dev/null 2>&1 || true
    echo "✅ SwayNC recarregado"
else
    echo "ℹ️  SwayNC não está em execução, configuração será aplicada no próximo início."
fi