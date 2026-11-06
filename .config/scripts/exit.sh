#!/usr/bin/env bash
# Menu de saída/bloqueio. Funciona em niri, Hyprland, Sway e mangowm.

set -euo pipefail

lock_cmd="$HOME/.config/scripts/lock.sh"

# Opções do fuzzel (versão >= 1.11)
conf="--dmenu --match-mode=exact --launch-prefix=<not set>"
options=("🔒\tBloquear\n" "⏸\tSuspender\n" "⏏\tSair\n" "🔄\tReiniciar\n" "⏻\tDesligar")

sel_option=$(echo -e "${options[@]}" | fuzzel $conf --lines=5 --prompt "Seleciona uma opção:  ")

if [[ -n ${sel_option:-} ]]; then
    action=$(echo "$sel_option" | awk '{print $NF}')

    confirm=$(echo -e "Não - cancelar\nSim - confirmar" | \
        fuzzel $conf --lines=2 --prompt "Confirmar $action ?  " | awk '{print $1}')

    if [[ ${confirm:-} == "Sim" ]]; then
        case $action in
            "Bloquear")
                "$lock_cmd"
                ;;
            "Suspender")
                systemctl suspend
                ;;
            "Sair")
                # Encerra o compositor atual de forma limpa.
                if command -v mmsg >/dev/null 2>&1 && pgrep -x mango >/dev/null 2>&1; then
                    mmsg dispatch quit
                elif [[ -n ${NIRI_SOCKET:-} ]] || pgrep -x niri >/dev/null 2>&1; then
                    niri msg action quit --skip-confirmation
                elif [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
                    hyprctl dispatch exit
                elif [[ -n ${SWAYSOCK:-} ]]; then
                    swaymsg exit
                else
                    loginctl terminate-session "${XDG_SESSION_ID:-}"
                fi
                ;;
            "Reiniciar")
                systemctl reboot
                ;;
            "Desligar")
                systemctl poweroff
                ;;
        esac
    fi
fi

exit 0
