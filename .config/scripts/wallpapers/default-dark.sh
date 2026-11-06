#!/usr/bin/env bash
# =============================================================================
# default-dark.sh -- gera o wallpaper padrão do setup
# =============================================================================
#
# Cria um fundo escuro com dois brilhos radiais suaves: laranja no canto
# inferior direito e azul no superior esquerdo. O ruwall extrai a paleta
# dessa imagem, então as cores dos apps acompanham o wallpaper.
#
# Uso:
#   ./default-dark.sh              # gera ~/.config/wallpapers/default-dark.png
#   ./default-dark.sh saida.png    # gera em outro caminho
#
# Requer ImageMagick (magick ou convert).

set -euo pipefail

OUT="${1:-$HOME/.config/wallpapers/default-dark.png}"
mkdir -p "$(dirname "$OUT")"

if command -v magick >/dev/null 2>&1; then
    IM=magick
elif command -v convert >/dev/null 2>&1; then
    IM=convert
else
    echo "erro: ImageMagick não encontrado (magick/convert)" >&2
    exit 1
fi

"$IM" -size 1920x1080 xc:'#0b0f17' \
    \( -size 1500x1500 radial-gradient:'#ff8a3d'-'#000000' \) \
    -geometry +1050+420 -compose screen -composite \
    \( -size 1300x1300 radial-gradient:'#2f6fed'-'#000000' \) \
    -geometry -300-260 -compose screen -composite \
    -blur 0x35 "$OUT"

echo "wallpaper gerado: $OUT"
