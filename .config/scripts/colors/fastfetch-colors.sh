#!/usr/bin/env bash
# ~/.config/scripts/colors/fastfetch-colors.sh
# Regenera a configuração do fastfetch de forma neutra (logo da distro e
# informações do sistema). A paleta do terminal vem do wal/ruwall, então o
# fastfetch acompanha o tema automaticamente.

set -eu

CONFIG_DIR="$HOME/.config/fastfetch"
CONFIG_FILE="$CONFIG_DIR/config.jsonc"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << 'EOF'
{
    "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    "display": {
        "separator": "  "
    },
    "logo": {
        "type": "file",
        "source": "~/.config/fastfetch/ascii.txt",
        "padding": {
            "top": 0,
            "left": 1,
            "right": 2
        }
    },
    "modules": [
        "title",
        "separator",
        "os",
        "kernel",
        "uptime",
        "shell",
        "wm",
        "terminal",
        "cpu",
        "memory",
        "disk",
        "packages",
        "break",
        "colors"
    ]
}
EOF

echo "fastfetch: configuração neutra atualizada em $CONFIG_FILE"
