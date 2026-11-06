#!/usr/bin/env bash
# unlock.sh — chamado pelo swayidle após o desbloqueio
# (eventos `unlock` e `after-resume` do swayidle/config).
#
# Só desliga o DND se foi o lock.sh que ligou: a flag auto-dnd é criada no lock
# e removida aqui. Sem a flag, o DND está ligado porque o usuário ligou na mão
# (SUPER,u ou o switch do painel do SwayNC) e é dele — este script não mexe.
# Regra: DND ligado = tela travada OU ligado manualmente.
set -u

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/swayidle"
AUTO_DND_FILE="$STATE_DIR/auto-dnd"

if [ -f "$AUTO_DND_FILE" ]; then
    rm -f "$AUTO_DND_FILE"
    swaync-client --dnd-off >/dev/null 2>&1 || :
fi
exit 0