#!/usr/bin/env bash
# =============================================================================
# video_frames_extract.sh -- extrai frames de vídeos para ~/Downloads/frames
# =============================================================================
#
# Compatível com o comportamento antigo:
#   ./video_frames_extract.sh [arquivo|diretório]
#     extrai 2 fps, até 100 frames por vídeo, largura 1280, PNG,
#     ignorando vídeos com mais de 100 MB ou 600 s.
#
# Agora com as correções do motor convert.sh:
#   - aceita arquivo único ou diretório (padrão: ~/Downloads)
#   - nomes de pasta sem colisão e limpeza apenas da pasta do vídeo
#   - valida a saída e continua o lote se um vídeo falhar
#
# Uso:
#   ./video_frames_extract.sh [opções] [arquivo|diretório ...]
#
# Exemplos:
#   ./video_frames_extract.sh                       # ~/Downloads
#   ./video_frames_extract.sh video.mp4             # um arquivo
#   ./video_frames_extract.sh --fps 1 --width 960   # ajustar
#   ./video_frames_extract.sh --format jpg -o ~/frames
#   ./video_frames_extract.sh --help                # todas as opções
# =============================================================================

set -uo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || true)
if [[ -z "$SCRIPT_PATH" ]]; then
    SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"
fi
SCRIPT_DIR=$(dirname -- "$SCRIPT_PATH")

exec "$SCRIPT_DIR/convert.sh" frames \
    --fps 2 \
    --max-frames 100 \
    --width 1280 \
    --format png \
    --output "$HOME/Downloads/frames" \
    --max-size-mb 100 \
    --max-duration 600 \
    --clean \
    --jobs 2 \
    "$@"
