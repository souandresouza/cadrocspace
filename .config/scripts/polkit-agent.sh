#!/usr/bin/env bash
# =============================================================================
# polkit-agent.sh -- inicia o primeiro agente polkit disponível
# =============================================================================
#
# Chamado pelo mango em exec_once. Evita depender de um único agente (o
# polkit-kde-agent) e funciona com polkit-gnome, mate-polkit ou xfce-polkit.
# =============================================================================

set -u

AGENTS=(
    /usr/lib/polkit-kde-authentication-agent-1
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
    /usr/lib/polkit-gnome-authentication-agent-1
    /usr/lib/polkit-mate-authentication-agent-1
    /usr/lib/xfce-polkit/xfce-polkit
    /usr/libexec/polkit-gnome-authentication-agent-1
)

for agent in "${AGENTS[@]}"; do
    if [[ -x "$agent" ]]; then
        exec "$agent"
    fi
done

echo "polkit-agent: nenhum agente encontrado (instale polkit-kde-agent ou polkit-gnome)" >&2
exit 1
