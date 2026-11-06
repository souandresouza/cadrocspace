#!/usr/bin/env bash
# idle_start.sh — (re)inicia o swayidle.
#
# Substitui a versao antiga que vivia em ~/cadrocspace/src/core/sys/ e nunca
# foi instalada em ~/.local/bin. A versao antiga montava a propria cadeia de
# timeouts (timeout_dim/lock/dpms/suspend a partir de cadroccfg/setting.sh) e
# conflitava com o ~/.config/swayidle/config que o Mango ja sobe via
# exec_once. Aqui a unica fonte de verdade e o arquivo de config do swayidle.

CFG="${SWAYIDLE_CONFIG:-$HOME/.config/swayidle/config}"

# sem config, nao ha o que iniciar
if [[ ! -f "$CFG" ]]; then
    echo "idle_start: config do swayidle nao encontrado: $CFG" >&2
    exit 1
fi

# evita duas instancias: o pkill do idle_inhibit.sh ja mata, mas um toggle
# rapido demais pode deixar a anterior ainda morrendo
if pgrep -x swayidle >/dev/null 2>&1; then
    pkill -x swayidle
    # espera o processo realmente sair antes de subir outro
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x swayidle >/dev/null 2>&1 || break
        sleep 0.1
    done
fi

exec swayidle -w -C "$CFG"