#!/usr/bin/env bash
# =============================================================================
# run-scripts.sh -- gera a paleta do wallpaper e atualiza o tema dos apps
# =============================================================================
#
# Uso:
#   run-scripts.sh              # usa o wallpaper atual (swaybg) ou o cache
#   run-scripts.sh <imagem>     # gera a paleta a partir da imagem
#   PALETTE_TOOL=wal run-scripts.sh ...
#
# A paleta é gravada em ~/.cache/wal (ruwall ou pywal). Depois, cada script em
# colors/ reescreve o tema do app correspondente e recarrega o app quando
# necessário.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COLOR_DIR="$SCRIPT_DIR/colors"

wallpaper_do_swaybg() {
    local pid
    pid="$(pgrep -x swaybg | head -1)"
    [[ -n "$pid" ]] || return 1
    tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null |
        awk 'p {print; exit} /^-i$|^--image$/ {p=1}'
}

WALLPAPER="${1:-$(wallpaper_do_swaybg)}"
WALLPAPER="${WALLPAPER:-$HOME/.cache/current_wallpaper.png}"

if [[ ! -f "$WALLPAPER" ]]; then
    echo "run-scripts: wallpaper não encontrado: $WALLPAPER" >&2
    exit 1
fi

PALETTE_TOOL="${PALETTE_TOOL:-ruwall}"
if command -v "$PALETTE_TOOL" >/dev/null 2>&1; then
    PALETTE="$(command -v "$PALETTE_TOOL")"
elif [[ -x "$HOME/.local/bin/$PALETTE_TOOL" ]]; then
    PALETTE="$HOME/.local/bin/$PALETTE_TOOL"
else
    echo "run-scripts: $PALETTE_TOOL não encontrado" >&2
    echo "  instale o ruwall em ~/.local/bin ou use PALETTE_TOOL=wal" >&2
    exit 1
fi

echo "run-scripts: paleta a partir de $WALLPAPER (via $PALETTE_TOOL)"

# -c limpa o cache de esquemas; -n não deixa a ferramenta trocar o wallpaper
# (quem aplica o fundo é o swaybg/random-wallpaper.sh); -e evita reloads de
# ambientes X11 que não usamos.
"$PALETTE" -c
"$PALETTE" -n -e -i "$WALLPAPER" || exit 1

run_color() {
    local name="$1"
    local script="$COLOR_DIR/${name}-colors.sh"
    [[ -x "$script" ]] || return 0
    "$script" || echo "run-scripts: aviso: ${name}-colors.sh falhou" >&2
}

apps=(cava cadroc fastfetch fuzzel kitty mango swaylock swaync waybar zathura)

for app in "${apps[@]}"; do
    run_color "$app"
done

# Opcionais: só rodam quando o app/tema correspondente está presente.
if [[ -f "$HOME/.config/qBittorrent/themes/pywal/stylesheet.qss.tpl" ]]; then
    run_color qbittorrent
fi
if command -v makoctl >/dev/null 2>&1; then
    run_color mako
fi
if command -v wal-telegram >/dev/null 2>&1 || pacman -Q wal-telegram-git >/dev/null 2>&1; then
    run_color telegram
fi

echo "run-scripts: concluído"
