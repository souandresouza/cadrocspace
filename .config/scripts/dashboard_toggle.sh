#!/bin/bash
pkill -f dashboard.sh || kitty --app-id=dashboard -e bash "$HOME/.config/scripts/dashboard.sh"
