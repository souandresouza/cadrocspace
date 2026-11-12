#!/usr/bin/env bash
# =============================================================================
# check.sh -- valida sintaxe dos scripts e dependências do Cadroc
# =============================================================================
#
# Uso:
#   ./check.sh               Valida todos os scripts (sh -n / bash -n)
#   ./check.sh --shellcheck  Também roda shellcheck quando disponível
#   ./check.sh --deps        Verifica os comandos usados pelo ambiente
#   ./check.sh --all         Tudo acima

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0
USE_SHELLCHECK=0
CHECK_DEPS=0

while (($#)); do
    case "$1" in
        --shellcheck) USE_SHELLCHECK=1 ;;
        --deps)       CHECK_DEPS=1 ;;
        --all)        USE_SHELLCHECK=1; CHECK_DEPS=1 ;;
        --help|-h)
            sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^#//'
            exit 0
            ;;
        *) printf 'Opção desconhecida: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

if [[ "$CHECK_DEPS" -eq 1 ]]; then
    # Comandos exigidos pela sessão (todos vêm das listas de pacotes).
    REQUIRED=(
        mmsg waybar swaync fuzzel swaybg swayidle swaylock
        grim slurp wl-copy cliphist jq wlr-randr rsync notify-send
        kitty wlsunset
    )
    # Ferramentas pessoais/opcionais.
    OPTIONAL=(ruwall cadrocfile magick)

    printf 'Dependências obrigatórias:\n'
    for cmd in "${REQUIRED[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '  ok       %s\n' "$cmd"
        else
            printf '  FALTANDO %s\n' "$cmd"
            FAILED=1
        fi
    done

    printf 'Opcionais:\n'
    for cmd in "${OPTIONAL[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '  ok       %s\n' "$cmd"
        else
            printf '  ausente  %s\n' "$cmd"
        fi
    done
fi

for f in $(find "$REPO_DIR" -name "*.sh" -not -path "*/.git/*" | sort); do
    if head -1 "$f" | grep -q "/bin/sh"; then
        interpreter="sh"
    else
        interpreter="bash"
    fi

    if ! "$interpreter" -n "$f"; then
        printf 'ERRO (sintaxe): %s\n' "$f"
        FAILED=1
        continue
    fi

    if [[ "$USE_SHELLCHECK" -eq 1 ]] && command -v shellcheck >/dev/null 2>&1; then
        if ! shellcheck "$f"; then
            printf 'ERRO (shellcheck): %s\n' "$f"
            FAILED=1
        fi
    fi
done

if [[ "$FAILED" -eq 0 ]]; then
    printf 'OK: scripts e dependências válidos.\n'
fi
exit "$FAILED"
