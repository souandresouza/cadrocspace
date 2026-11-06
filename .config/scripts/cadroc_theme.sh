#!/usr/bin/env bash

# Cadroc Theme state and rendering model:
# - ~/.local/state/cadrocspace/state/state.env is the single source of truth for
#   ACCENT_COLOR, FONT_FAMILY, and FONT_SIZE. It is loaded when this library is
#   sourced and updated atomically by theme_save_state().

# - ~/.local/state/cadrocspace/theme/ contains generated CSS, conf, Lua, and KDL
#   files. These files are one-way render outputs and must never be parsed back
#   to recover theme values.

# - Scripts source this library to share paths, defaults, and state handling.
#   A script may modify ACCENT_COLOR, FONT_FAMILY, or FONT_SIZE, then call
#   theme_save_state() before rendering the dependent theme files.

# - Toggle and UI state files also live under the state directory, while
#   application-specific generated files remain isolated in the theme directory.

# - Keep defaults here so every theme-related script uses the same fallback
#   values and does not maintain its own copy of the configuration contract.

# Shared theme state and rendering paths.
THEME_ROOT="${HOME}/.local/state/cadrocspace"
THEME_RENDER_DIR="${THEME_ROOT}/theme"
STATE_DIR="${THEME_ROOT}/state"
THEME_STATE_FILE="${STATE_DIR}/state.env"

THEME_BTOP_DIR="${HOME}/.config/btop/themes"
# Referências ao labwc removidas (o compositor agora é o MangoWM).
# Antes: THEME_LABWC_OVERRIDE=~/.themes/cadroclab/labwc/themerc

# Default theme values.
# A fonte e a mesma que o resto dos configs usa (waybar, swaync, fuzzel) e o
# tamanho 12 era o valor do kitty.conf antes de os dois campos passarem a vir
# do theme/kitty-style.conf, renderizado pelo cadroc-colors.sh.
THEME_DEFAULT_ACCENT="#ffffff"
THEME_DEFAULT_FONT="JetBrainsMono Nerd Font"
THEME_DEFAULT_SIZE="12"

mkdir -p "$THEME_RENDER_DIR" "$STATE_DIR"

# Load only the canonical state file; rendered files are never read back.
theme_load_state() {
    ACCENT_COLOR="$THEME_DEFAULT_ACCENT"
    FONT_FAMILY="$THEME_DEFAULT_FONT"
    FONT_SIZE="$THEME_DEFAULT_SIZE"

    if [[ -f "$THEME_STATE_FILE" ]]; then
        # State is written by theme_save_state and contains shell-safe values.
        source "$THEME_STATE_FILE"
    fi
}

theme_save_state() {
    local state_tmp="${THEME_STATE_FILE}.tmp"
    {
        printf 'ACCENT_COLOR=%q\n' "$ACCENT_COLOR"
        printf 'FONT_FAMILY=%q\n' "$FONT_FAMILY"
        printf 'FONT_SIZE=%q\n' "$FONT_SIZE"
    } > "$state_tmp" && mv "$state_tmp" "$THEME_STATE_FILE"
}

theme_state_value() {
    case "$1" in
        accent|ACCENT_COLOR) printf '%s\n' "${ACCENT_COLOR:-$THEME_DEFAULT_ACCENT}" ;;
        font|FONT_FAMILY) printf '%s\n' "${FONT_FAMILY:-$THEME_DEFAULT_FONT}" ;;
        size|FONT_SIZE) printf '%s\n' "${FONT_SIZE:-$THEME_DEFAULT_SIZE}" ;;
        *) return 1 ;;
    esac
}

theme_load_state
