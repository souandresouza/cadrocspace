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
# ficam em ~/.cache/mango-dotfiles/backups/<timestamp>/.
#
# --pull copia apenas os diretórios gerenciados, exceto wallpapers pessoais:
# de ~/.config/wallpapers só o default-dark.png é versionado.
#
# Compatibilidade: o config.jsonc do Waybar do niri e o niri-colors.sh não são
# gerenciados por este repositório. Eles são preservados mesmo com --prune e
# ignorados no --pull.
# =============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/mango-dotfiles"
TARGETS=(
    mango scripts swayidle wallpapers
    cava fastfetch fuzzel kitty swaylock swaync waybar zathura
)

MODE="push"
DRY_RUN=0
GENERATE=0
PRUNE=0

usage() {
    sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^#//'
    exit 0
}

log() { printf '[deploy.sh] %s\n' "$*"; }
warn() { printf '[deploy.sh] AVISO: %s\n' "$*" >&2; }
err() { printf '[deploy.sh] ERRO: %s\n' "$*" >&2; exit 1; }

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

# Arquivos que pertencem a outros setups (niri) e não devem ser apagados/puxados.
target_excludes() {
    local name="$1"
    case "$name" in
        scripts) echo "--exclude=colors/niri-colors.sh" ;;
        waybar)  echo "--exclude=config.jsonc" ;;
        *)       echo "" ;;
    esac
}

push_target() {
    local name="$1"
    local src="$REPO_DIR/.config/$name"
    local dst="$CONFIG_DIR/$name"

    [[ -d "$src" ]] || { warn "Origem não encontrada, ignorando: $src"; return; }

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

    local args=(-a --backup --backup-dir="$BACKUP_ROOT/$name" --itemize-changes)
    local exclude
    exclude="$(target_excludes "$name")"
    [[ -n "$exclude" ]] && args+=("$exclude")
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

    [[ -d "$src" ]] || { warn "Origem não encontrada, ignorando: $src"; return; }

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

    local args=(-a --itemize-changes
        --exclude='*.bak-*' --exclude='*~' --exclude='*.tmp')
    local exclude
    exclude="$(target_excludes "$name")"
    [[ -n "$exclude" ]] && args+=("$exclude")
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

for target in "${TARGETS[@]}"; do
    if [[ "$MODE" == "pull" ]]; then
        pull_target "$target"
    else
        push_target "$target"
    fi
done

[[ "$GENERATE" -eq 1 && "$MODE" == "push" ]] && generate_theme

if [[ "$MODE" == "push" && "$DRY_RUN" -eq 0 && -d "$BACKUP_ROOT" ]]; then
    log "Backups desta execução: $BACKUP_ROOT"
fi
if [[ "$MODE" == "pull" ]]; then
    log "Pronto. Revise as mudanças com: git -C \"$REPO_DIR\" diff"
fi
