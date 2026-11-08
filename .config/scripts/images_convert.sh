#!/usr/bin/env bash
# =============================================================================
# images_convert.sh -- converte imagens de ~/Downloads para PNG
# =============================================================================
#
# Compatível com o comportamento antigo:
#   ./images_convert.sh
#     processa ~/Downloads (recursivo), converte HEIC/HEIF/JPG/JPEG/WEBP
#     para PNG em 1920x1080, qualidade 90, e apaga os originais.
#
# Agora com as correções do motor convert.sh:
#   - não sobrescreve PNG existente (cria nome-1.png)
#   - só apaga o original depois de validar a saída
#   - um arquivo com problema não aborta o lote
#   - fallback para HEIC/AVIF/SVG
#
# Uso:
#   ./images_convert.sh [opções] [arquivo|diretório ...]
#
# Exemplos:
#   ./images_convert.sh                       # ~/Downloads, padrão antigo
#   ./images_convert.sh ~/Pictures            # outro diretório
#   ./images_convert.sh --keep-originals      # não apaga os originais
#   ./images_convert.sh --to webp --quality 82
#   ./images_convert.sh --help                # todas as opções
# =============================================================================

set -uo pipefail

SCRIPT_PATH=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null || true)
if [[ -z "$SCRIPT_PATH" ]]; then
    SCRIPT_PATH="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"
fi
SCRIPT_DIR=$(dirname -- "$SCRIPT_PATH")

exec "$SCRIPT_DIR/convert.sh" image \
    --from "heic,heif,jpg,jpeg,webp" \
    --to png \
    --max "1920x1080" \
    --quality 90 \
    --delete-originals \
    --recursive \
    --jobs 4 \
    "$@"
