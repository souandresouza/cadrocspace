#!/usr/bin/env bash
set -euo pipefail

# ========= TECLADO VIRTUAL (wvkbd) =========
# Alterna um teclado na tela para quando estiver usando só o notebook (teclas
# quebradas) ou para evitar teclas físicas (keylogger de hardware).
#
#   - se não estiver rodando, inicia visível
#   - se estiver rodando, SIGRTMIN esconde/mostra
#
# Instalação: yay -S wvkbd   (o pacote instala o binário wvkbd-mobintl)
# Ajustes: WVKBD_BIN (layout) e WVKBD_HEIGHT (altura em landscape)

BIN="${WVKBD_BIN:-wvkbd-mobintl}"
HEIGHT="${WVKBD_HEIGHT:-280}"

if pgrep -x "$BIN" >/dev/null 2>&1; then
    # wvkbd responde a SIGRTMIN alternando entre visível e escondido.
    pkill -RTMIN -x "$BIN"
    exit 0
fi

if ! command -v "$BIN" >/dev/null 2>&1; then
    notify-send -u normal -a "osk" "Teclado virtual" \
        "$BIN não encontrado. Instale com: yay -S wvkbd"
    exit 1
fi

# --no-popup: não mostra o balão ampliado da tecla que está sendo pressionada
#             (evita expor visualmente a tecla tocada).
# -L: altura do teclado em modo horizontal/landscape.
setsid "$BIN" -L "$HEIGHT" --no-popup >/dev/null 2>&1 &
