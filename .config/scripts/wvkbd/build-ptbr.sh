#!/usr/bin/env bash
set -euo pipefail

# ========= WVKBD COM Ç DEDICADO =========
# Compila o wvkbd (layout mobintl) adicionando uma tecla ç/Ç ao lado do L,
# como no ABNT2. O layout do sistema não é usado: o wvkbd embute o próprio
# keymap, então a tecla é incorporada no binário.
#
# Instala em ~/.local/bin/wvkbd-ptbr (sem sudo). O osk.sh prefere esse binário
# automaticamente quando ele existe.
#
# Uso: ./build-ptbr.sh [diretório-de-instalação]

VERSION="${WVKBD_VERSION:-0.21}"
URL="https://git.sr.ht/~proycon/wvkbd/archive/v${VERSION}.tar.gz"
DEST="${1:-$HOME/.local/bin}"
OUT="$DEST/wvkbd-ptbr"

missing=()
for c in curl tar make gcc wayland-scanner pkg-config; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if ((${#missing[@]})); then
    echo "Faltam comandos: ${missing[*]}" >&2
    exit 1
fi

if ! pkg-config --exists wayland-client xkbcommon pangocairo; then
    echo "Faltam headers de desenvolvimento (wayland, xkbcommon, pango, cairo)." >&2
    exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Baixando wvkbd v$VERSION..."
curl -fsSL "$URL" | tar xz -C "$work" --strip-components=1

# Adiciona ç/Ç depois da tecla L em todas as camadas principais.
sed -i \
    '/{"l", "L", 1.0, Code, KEY_L, &layouts\[ComposeL\]},/a\  {"ç", "Ç", 1.0, Copy, 0x00E7, 0, 0x00C7},' \
    "$work/layout.mobintl.h"

if ! grep -q '"ç", "Ç"' "$work/layout.mobintl.h"; then
    echo "ERRO: patch do ç não foi aplicado." >&2
    exit 1
fi

# Compila só o binário: o alvo "all" também gera o manpage e exigiria scdoc.
make -C "$work" LAYOUT=mobintl wvkbd-mobintl

install -Dm755 "$work/wvkbd-mobintl" "$OUT"
echo "Instalado: $OUT"
