#!/bin/bash
# Gera os arquivos de tema do cadrocspace a partir da paleta pywal e do estado
# do tema: o colors.css consumido pelo GTK e o kitty-style.conf consumido pelo
# terminal.
#
# ~/.config/gtk-3.0/gtk.css importa
# ~/.local/state/cadrocspace/theme/colors.css, que precisa definir @accent_color
# — a unica variavel que o gtk.css usa. Sem esse arquivo o GTK reclama em todo
# app: "Failed to import ... colors.css", e todo uso de @accent_color e ignorado.
#
# O accent vem do pywal (a cor mais saturada entre color1..color6, mesma regra do
# swaync-colors.sh), entao acompanha o wallpaper junto com o resto do tema.
#
# O estado (ACCENT_COLOR/FONT_FAMILY/FONT_SIZE) vai para state/state.env pela
# theme_save_state(), que e a fonte de verdade do cadroc_theme.sh.

COLORS_FILE="$HOME/.cache/wal/colors.css"
THEME_LIB="$HOME/.config/scripts/cadroc_theme.sh"

if [ ! -f "$COLORS_FILE" ]; then
    echo "ERRO: sem paleta em $COLORS_FILE"
    echo "Gere uma com:"
    echo "  ~/.config/scripts/run-scripts.sh            # usa o wallpaper atual"
    echo "  ~/.config/scripts/run-scripts.sh <imagem>   # de um arquivo"
    echo "  (PALETTE_TOOL=wal volta ao pywal)"
    echo "Execute '~/.config/scripts/run-scripts.sh' para gerar a paleta."
    exit 1
fi

if [ ! -f "$THEME_LIB" ]; then
    echo "ERRO: Biblioteca $THEME_LIB não encontrada!"
    exit 1
fi

# shellcheck source=/dev/null
. "$THEME_LIB"

extract_color() {
    grep -- "--color$1:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; '
}

background=$(grep -- "--background:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')
foreground=$(grep -- "--foreground:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')

# Accent = cor mais saturada entre color1..color6. O pywal nem sempre poe a cor
# mais viva na mesma posicao, entao o accent precisa ser escolhido, nao fixado.
accent=""
best_score=-1
for i in 1 2 3 4 5 6; do
    c=$(extract_color "$i")
    [ -z "$c" ] && continue
    h="${c#\#}"
    r=$((16#${h:0:2}))
    g=$((16#${h:2:2}))
    b=$((16#${h:4:2}))
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

if [ -z "$background" ] || [ -z "$foreground" ] || [ -z "$accent" ]; then
    echo "ERRO: a paleta em $COLORS_FILE não tem cores utilizáveis."
    echo "Regere com: ~/.config/scripts/run-scripts.sh"
    exit 1
fi

ACCENT_COLOR="$accent"
theme_save_state

mkdir -p "$THEME_RENDER_DIR"

{
    echo "/* Gerado por ~/.config/scripts/colors/cadroc-colors.sh a partir da paleta pywal."
    echo "   NÃO EDITE — edite o script e chame o run-scripts.sh de novo. */"
    echo
    echo "@define-color accent_color $accent;"
    echo "@define-color accent $accent;"
    echo "@define-color foreground $foreground;"
    echo "@define-color background $background;"
    echo
    for i in 0 1 2 3 4 5 6 7; do
        echo "@define-color color$i $(extract_color "$i");"
    done
} > "$THEME_RENDER_DIR/colors.css"

# theme/kitty-style.conf: o include do ~/.config/kitty/kitty.conf. O arquivo
# tambem nao existia, e e daqui que saem font_family/font_size do terminal. Vem
# do estado (nao do pywal): fonte e tamanho nao sao cor.
{
    echo "# Gerado por ~/.config/scripts/colors/cadroc-colors.sh a partir do estado do tema."
    echo "# NÃO EDITE — ajuste FONT_FAMILY/FONT_SIZE em state/state.env."
    echo
    echo "font_family $FONT_FAMILY"
    echo "font_size $FONT_SIZE"
} > "$THEME_RENDER_DIR/kitty-style.conf"

echo "✅ Cores do GTK atualizadas (accent: $accent)"
echo "✅ Fonte do kitty aplicada: $FONT_FAMILY $FONT_SIZE"

# O kitty so aplica fonte nova em processo vivo; recarrega pelas instancias
# abertas em todos os sockets.
if [[ -x "$HOME/.config/scripts/kitty-reload-colors" ]]; then
    "$HOME/.config/scripts/kitty-reload-colors" && echo "✅ Kitty recarregado"
fi