#!/usr/bin/env bash
# =============================================================================
# check.sh -- valida sintaxe de todos os scripts .sh do repositório
# =============================================================================
#
# Uso:
#   ./check.sh               Valida todos os scripts (sh -n / bash -n)
#   ./check.sh --shellcheck  Também roda shellcheck quando disponível

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0
USE_SHELLCHECK=0

[[ "${1:-}" == "--shellcheck" ]] && USE_SHELLCHECK=1

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
    printf 'OK: todos os scripts válidos.\n'
fi
exit "$FAILED"