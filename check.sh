#!/usr/bin/env bash
# =============================================================================
# check.sh -- valida sintaxe dos scripts e dependências do Cadroc
# =============================================================================
#
# Uso:
#   ./check.sh               Valida todos os scripts (sh -n / bash -n)
#   ./check.sh --shellcheck  Também roda shellcheck quando disponível
#   ./check.sh --deps        Verifica os comandos usados pelo ambiente
#   ./check.sh --lists       Confere se os pacotes das listas existem (repos/AUR)
#   ./check.sh --all         Tudo acima, menos --lists (que usa rede)

set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0
USE_SHELLCHECK=0
CHECK_DEPS=0
CHECK_LISTS=0

while (($#)); do
    case "$1" in
        --shellcheck) USE_SHELLCHECK=1 ;;
        --deps)       CHECK_DEPS=1 ;;
        --lists)      CHECK_LISTS=1 ;;
        --all)        USE_SHELLCHECK=1; CHECK_DEPS=1 ;;
        --help|-h)
            sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^#//'
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
        kitty wlsunset sddm
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

if [[ "$CHECK_LISTS" -eq 1 ]]; then
    # Confere se cada nome das listas existe de fato no repo/AUR. Usa rede
    # (AUR) e é opt-in: pega o erro mais comum de instalação limpa, que é um
    # pacote renomeado/removido ou um split package (*-debug) listado por engano.
    list_pkgs() { grep -v '^[[:space:]]*#' "$1" | grep -v '^[[:space:]]*$'; }

    printf 'Listas de pacotes:\n'
    if command -v pacman >/dev/null 2>&1; then
        while IFS= read -r pkg; do
            if ! pacman -Si "$pkg" >/dev/null 2>&1; then
                printf '  FALTANDO (repo) %s\n' "$pkg"
                FAILED=1
            fi
        done < <(list_pkgs "$REPO_DIR/lista_pacman.txt")
        printf '  repos oficiais conferidos\n'
    else
        printf '  ausente  pacman (não é Arch?), etapa pulada\n'
    fi

    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        query=""
        while IFS= read -r pkg; do
            query="$query&arg[]=$pkg"
        done < <(list_pkgs "$REPO_DIR/lista_aur.txt")

        if ! resp="$(curl -s --max-time 20 "https://aur.archlinux.org/rpc/v5/info?${query#&}")" || [[ -z "$resp" ]]; then
            printf '  sem resposta do AUR (offline?), etapa pulada\n'
        else
            while IFS= read -r pkg; do
                if ! printf '%s' "$resp" | jq -e --arg p "$pkg" '.results[] | select(.Name == $p)' >/dev/null 2>&1; then
                    printf '  FALTANDO (AUR) %s\n' "$pkg"
                    FAILED=1
                fi
            done < <(list_pkgs "$REPO_DIR/lista_aur.txt")
            printf '  AUR conferido\n'
        fi
    else
        printf '  ausente  curl/jq, etapa do AUR pulada\n'
    fi
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
    if [[ "$CHECK_LISTS" -eq 1 ]]; then
        printf 'OK: scripts, dependências e listas válidos.\n'
    else
        printf 'OK: scripts e dependências válidos.\n'
    fi
fi
exit "$FAILED"
