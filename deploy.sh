#!/usr/bin/env bash
# =============================================================================
# deploy.sh -- copia as configurações do repositório para $HOME/.config
# =============================================================================
#
# Uso:
#   ./deploy.sh              Copia repo -> ~/.config (backup do que for substituído)
#   ./deploy.sh --pull       Copia ~/.config -> repo (para commitar mudanças locais)
#   ./deploy.sh --generate   Depois de copiar, regenera as cores do tema atual
#   ./deploy.sh --prune      Remove em ~/.config arquivos que saíram do repo
#   ./deploy.sh --dry-run    Mostra o que seria feito, sem alterar nada
#   ./deploy.sh --help       Ajuda
#
# Não usa symlinks: os arquivos são copiados. Backups dos arquivos substituídos
# ficam em ~/.cache/cadrocspace/backups/<timestamp>/.
#
# Arquivos de tema gerados (cores do wallpaper) nunca são copiados do repo nem
# voltam no --pull; quando faltam em ~/.config são semeados a partir de
# defaults/, e --generate os regenera com a paleta atual.
#
# --pull copia apenas os diretórios gerenciados, exceto wallpapers pessoais:
# de ~/.config/wallpapers só o default-dark.png é versionado.
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cadrocspace"
TARGETS=(
    mango scripts swayidle wallpapers
    cava fastfetch fuzzel kitty swaylock swaync waybar zathura
)

# Arquivos de tema gerados a partir do wallpaper (run-scripts.sh).
# A fonte versionada fica em defaults/<app>/<arquivo>. O deploy nunca os copia
# do repo nem os traz de volta no --pull; se faltarem em ~/.config, são
# semeados a partir de defaults/ para o ambiente funcionar sem paleta.
GENERATED=(
    mango/theme.conf
    mango/waybar.jsonc
    mango/monitor.conf
    waybar/colors-waybar.css
    swaync/colors-swaync.css
    fuzzel/colors-fuzzel.ini
    kitty/colors-kitty.conf
    swaylock/config
    zathura/zathurarc
    cava/themes/colors
)

DEFAULTS_DIR="$REPO_DIR/defaults"

MODE="push"
DRY_RUN=0
GENERATE=0
PRUNE=0

usage() {
    sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^#//'
    exit 0
}

log() { printf '[deploy.sh] %s\n' "$*"; }
warn() { printf '[deploy.sh] AVISO: %s\n' "$*" >&2; }
err() { printf '[deploy.sh] ERRO: %s\n' "$*" >&2; exit 1; }

# Monta os --exclude do rsync para os arquivos gerados de um alvo.
generated_excludes() {
    local name="$1" rel
    for rel in "${GENERATED[@]}"; do
        if [[ "$rel" == "$name/"* ]]; then
            printf '%s\0' "--exclude=/${rel#"$name/"}"
        fi
    done
}

# Devolve em stdout os argumentos de exclusão já separados em linhas NUL.
collect_generated_excludes() {
    local name="$1" arg
    while IFS= read -r -d '' arg; do
        GEN_ARGS+=("$arg")
    done < <(generated_excludes "$name")
}

while (($#)); do
    case "$1" in
        --pull)     MODE="pull" ;;
        --generate) GENERATE=1 ;;
        --prune)    PRUNE=1 ;;
        --dry-run)  DRY_RUN=1 ;;
        --help|-h)  usage ;;
        *)          err "Opção desconhecida: $1 (use --help)" ;;
    esac
    shift
done

[[ "$MODE" == "pull" && "$GENERATE" -eq 1 ]] && err "--pull e --generate não podem ser usados juntos"
[[ "$MODE" == "pull" && "$PRUNE" -eq 1 ]] && err "--pull e --prune não podem ser usados juntos"

command -v rsync >/dev/null 2>&1 || err "rsync não encontrado (instale com: sudo pacman -S rsync)"

BACKUP_ROOT="$CACHE_DIR/backups/$(date +%Y%m%d-%H%M%S)-$$"

prepare_backup_dir() {
    [[ "$DRY_RUN" -eq 1 ]] && return
    mkdir -p "$BACKUP_ROOT"
}

push_target() {
    local name="$1"
    local src="$REPO_DIR/.config/$name"
    local dst="$CONFIG_DIR/$name"
    local -a GEN_ARGS=()

    [[ -d "$src" ]] || { warn "Origem não encontrada, ignorando: $src"; return; }
    collect_generated_excludes "$name"

    # Remove symlink antigo para nunca escrever dentro do repo.
    if [[ -L "$dst" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "Removeria o symlink: $dst"
        else
            prepare_backup_dir
            mkdir -p "$BACKUP_ROOT/$name"
            mv "$dst" "$BACKUP_ROOT/$name/$(basename "$dst").symlink"
            log "Symlink removido: $dst (guardado em $BACKUP_ROOT/$name/)"
        fi
    fi

    if [[ -e "$dst" && ! -d "$dst" ]]; then
        err "$dst existe e não é um diretório"
    fi

    local args=(-a "${GEN_ARGS[@]}" --backup --backup-dir="$BACKUP_ROOT/$name" --itemize-changes)
    [[ "$DRY_RUN" -eq 1 ]] && args+=(-n)
    # wallpapers nunca são podados: a pasta pode conter imagens pessoais.
    [[ "$PRUNE" -eq 1 && "$name" != "wallpapers" ]] && args+=(--delete)

    if [[ "$DRY_RUN" -eq 0 ]]; then
        prepare_backup_dir
        mkdir -p "$dst"
    fi

    log "Copiando $src -> $dst"
    rsync "${args[@]}" "$src/" "$dst/"
}

pull_target() {
    local name="$1"
    local src="$CONFIG_DIR/$name"
    local dst="$REPO_DIR/.config/$name"
    local -a GEN_ARGS=()

    [[ -d "$src" ]] || { warn "Origem não encontrada, ignorando: $src"; return; }
    collect_generated_excludes "$name"

    # Só o wallpaper padrão é versionado; os demais são pessoais.
    if [[ "$name" == "wallpapers" ]]; then
        if [[ -f "$src/default-dark.png" ]]; then
            if [[ "$DRY_RUN" -eq 1 ]]; then
                log "Copiaria $src/default-dark.png -> $dst/default-dark.png"
            else
                mkdir -p "$dst"
                cp -p "$src/default-dark.png" "$dst/default-dark.png"
                log "Copiado: default-dark.png"
            fi
        else
            warn "Wallpaper padrão não encontrado: $src/default-dark.png"
        fi
        return
    fi

    local args=(-a "${GEN_ARGS[@]}" --itemize-changes
        --exclude='*.bak-*' --exclude='*~' --exclude='*.tmp')
    [[ "$DRY_RUN" -eq 1 ]] && args+=(-n)
    [[ "$DRY_RUN" -eq 0 ]] && mkdir -p "$dst"

    log "Copiando $src -> $dst"
    rsync "${args[@]}" "$src/" "$dst/"
}

generate_theme() {
    local runner="$CONFIG_DIR/scripts/run-scripts.sh"

    if [[ ! -x "$runner" ]]; then
        warn "run-scripts.sh não encontrado em $runner; pulando geração de cores"
        return
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Rodaria $runner (gera as cores do wallpaper atual)"
        return
    fi

    log "Gerando cores do tema atual com run-scripts.sh"
    if ! "$runner"; then
        warn "run-scripts.sh falhou (há wallpaper e ferramenta de paleta configurados?)"
        warn "Rode manualmente: $runner [imagem]"
    fi
}

# Semeia os arquivos gerados que faltarem, a partir de defaults/. Assim um
# clone novo tem tema funcional mesmo antes da primeira geração de paleta.
seed_generated() {
    local rel src dst
    for rel in "${GENERATED[@]}"; do
        src="$DEFAULTS_DIR/$rel"
        dst="$CONFIG_DIR/$rel"
        [[ -f "$src" ]] || { warn "Default ausente: $src"; continue; }
        [[ -e "$dst" ]] && continue

        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "Semearia default: $rel"
        else
            mkdir -p "$(dirname "$dst")"
            cp -p "$src" "$dst"
            log "Default semeado: $rel"
        fi
    done
}

for target in "${TARGETS[@]}"; do
    if [[ "$MODE" == "pull" ]]; then
        pull_target "$target"
    else
        push_target "$target"
    fi
done

if [[ "$MODE" == "push" ]]; then
    seed_generated
    [[ "$GENERATE" -eq 1 ]] && generate_theme
fi

if [[ "$MODE" == "push" && "$DRY_RUN" -eq 0 && -d "$BACKUP_ROOT" ]]; then
    log "Backups desta execução: $BACKUP_ROOT"
fi
if [[ "$MODE" == "pull" ]]; then
    log "Pronto. Revise as mudanças com: git -C \"$REPO_DIR\" diff"
fi
