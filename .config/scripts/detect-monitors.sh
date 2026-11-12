#!/usr/bin/env bash
# =============================================================================
# detect-monitors.sh -- gera regras monitor_rule para o mango a partir da
# sessão atual (wlr-randr).
# =============================================================================
#
# Uso:
#   detect-monitors.sh            Mostra as regras na saída padrão
#   detect-monitors.sh --write    Grava em ~/.config/mango/monitor.conf
#   detect-monitors.sh --write -   Grava em outro arquivo (MONITOR_CONF=...)
#
# Depois de gravar, aplique com: mmsg dispatch reload_config
#
# Só monitores habilitados entram nas regras. O wlr-randr informa modo atual,
# posição e escala; a saída vira uma regra por monitor, na ordem dos outputs.
# =============================================================================

set -euo pipefail

MONITOR_CONF="${MONITOR_CONF:-$HOME/.config/mango/monitor.conf}"

WRITE=0
case "${1:-}" in
    --write) WRITE=1 ;;
    --help|-h)
        sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^#//'
        exit 0
        ;;
    "") ;;
    *) echo "Opção desconhecida: $1 (use --help)" >&2; exit 1 ;;
esac

command -v wlr-randr >/dev/null 2>&1 || {
    echo "erro: wlr-randr não encontrado (pacman -S wlr-randr)" >&2
    exit 1
}

rules="$(
    wlr-randr 2>/dev/null | awk '
        function flush() {
            if (name != "" && enabled && w != "" && r != "") {
                printf "monitor_rule=name:^%s$,width:%d,height:%d,refresh:%d,x:%d,y:%d,scale:%s,vrr:0,rr:0\n",
                       name, w, h, r + 0, x + 0, y + 0, scale
            }
            name = ""; enabled = 0; w = ""; h = ""; r = ""; x = ""; y = ""
        }
        # Início de um novo output: "NOME "..."
        /^[^[:space:]]/ {
            flush()
            name = $1
            gsub(/"/, "", name)
            enabled = 0; scale = "1"; x = "0"; y = "0"
            next
        }
        /^[[:space:]]+Enabled: yes/ { enabled = 1; next }
        /^[[:space:]]+Position: / {
            split($2, p, ",")
            x = p[1]; y = p[2]
            next
        }
        /^[[:space:]]+Scale: / { scale = $2 + 0; next }
        # Modo atual: "1920x1080 px, 100.000000 Hz (current)"
        /^[[:space:]]+[0-9]+x[0-9]+ px,/ {
            if ($0 ~ /\(.*current/) {
                split($1, dim, "x")
                w = dim[1]; h = dim[2]
                r = $3 + 0
            }
            next
        }
        END { flush() }
    '
)"

if [[ -z "$rules" ]]; then
    echo "erro: nenhum monitor habilitado encontrado pelo wlr-randr" >&2
    exit 1
fi

if [[ "$WRITE" -eq 0 ]]; then
    printf '%s\n' "$rules"
    exit 0
fi

{
    printf '# monitor.conf -- regras de monitor DESTA máquina (não versionado).\n'
    printf '# Gerado por detect-monitors.sh em %s.\n' "$(date '+%Y-%m-%d %H:%M')"
    printf '# Aplique com: mmsg dispatch reload_config\n\n'
    printf '%s\n' "$rules"
} > "$MONITOR_CONF"

echo "Regras gravadas em $MONITOR_CONF" >&2
echo "Aplique com: mmsg dispatch reload_config" >&2
