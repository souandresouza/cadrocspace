#!/bin/bash
# ~/.config/scripts/random-wallpaper.sh

set -euo pipefail

# Configuração
WALLPAPER_DIR="$HOME/.config/wallpapers"
CACHE_DIR="$HOME/.cache/wallpapers"
HISTORY_FILE="$CACHE_DIR/wallpaper_history.txt"
CYCLE_FILE="$CACHE_DIR/wallpaper_cycle.txt"
CURRENT_WALLPAPER="$HOME/.cache/current_wallpaper.png"
HISTORY_SIZE=10

# ============================================
# FUNÇÕES
# ============================================

# Detecta resolução da tela
detect_resolution() {
    local res=""

    if command -v hyprctl &>/dev/null && command -v jq &>/dev/null; then
        local hypr_output=$(hyprctl monitors -j 2>/dev/null 2>&1)
        if [[ -n "$hypr_output" ]] && echo "$hypr_output" | jq -e . >/dev/null 2>&1; then
            res=$(echo "$hypr_output" | jq -r '.[] | select(.focused == true) | "\(.width)x\(.height)"' 2>/dev/null | head -1)
        fi
    fi

    if [[ -z "$res" ]] && command -v wlr-randr &>/dev/null; then
        res=$(wlr-randr 2>/dev/null | grep -oP 'current mode: \K\d+x\d+' | head -1)
    fi

    if [[ -z "$res" ]] && command -v xrandr &>/dev/null; then
        res=$(xrandr --current 2>/dev/null | grep '*' | head -1 | awk '{print $1}')
    fi

    echo "${res:-1920x1080}"
}

# Verifica e cria diretórios necessários
ensure_directories() {
    mkdir -p "$CACHE_DIR"
    mkdir -p "$(dirname "$CURRENT_WALLPAPER")"
    touch "$HISTORY_FILE"
    touch "$CYCLE_FILE"
}

# Obtém o wallpaper atual do histórico
get_current_wallpaper() {
    if [[ -f "$HISTORY_FILE" ]]; then
        head -n 1 "$HISTORY_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Lista todos os wallpapers disponíveis
list_available_wallpapers() {
    if [[ ! -d "$WALLPAPER_DIR" ]]; then
        return 1
    fi

    find -L "$WALLPAPER_DIR" -maxdepth 1 -type f \( \
        -iname "*.jpg" -o -iname "*.jpeg" \
        -o -iname "*.png" -o -iname "*.gif" \
        -o -iname "*.webp" -o -iname "*.bmp" \
    \) -print0 2>/dev/null | sort -z | xargs -0 -n1 echo
}

# Seleciona um wallpaper aleatório sem repetir até esgotar o ciclo.
# O ciclo é persistido em CYCLE_FILE para sobreviver a reinícios; quando todos
# os wallpapers já foram usados, um novo ciclo começa (sem repetir o último).
select_wallpaper() {
    local all_wallpapers=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && all_wallpapers+=("$file")
    done < <(list_available_wallpapers)

    if [[ ${#all_wallpapers[@]} -eq 0 ]]; then
        echo "❌ Nenhum wallpaper encontrado em: $WALLPAPER_DIR" >&2
        return 1
    fi

    echo "📸 Encontrados ${#all_wallpapers[@]} wallpapers" >&2

    local current
    current="$(get_current_wallpaper)"
    if [[ -n "$current" ]]; then
        echo "🖼️  Wallpaper atual: $(basename "$current")" >&2
    fi

    # Wallpapers já usados no ciclo atual (ignora entradas que não existem mais)
    local used=()
    local line w u found
    if [[ -f "$CYCLE_FILE" ]]; then
        while IFS= read -r line; do
            if [[ -z "$line" ]]; then
                continue
            fi
            found=0
            for w in "${all_wallpapers[@]}"; do
                if [[ "$line" == "$w" ]]; then
                    found=1
                    break
                fi
            done
            if (( found )); then
                used+=("$line")
            fi
        done < "$CYCLE_FILE"
    fi

    # Disponíveis = todos - usados no ciclo atual
    local available=()
    for w in "${all_wallpapers[@]}"; do
        found=0
        for u in "${used[@]}"; do
            if [[ "$w" == "$u" ]]; then
                found=1
                break
            fi
        done
        if (( ! found )); then
            available+=("$w")
        fi
    done

    if [[ ${#available[@]} -eq 0 ]]; then
        # Ciclo esgotado: começa outro, evitando o último wallpaper aplicado
        if [[ ${#all_wallpapers[@]} -gt 1 ]]; then
            echo "🔁 Ciclo completo, começando novo ciclo" >&2
        fi
        used=()
        for w in "${all_wallpapers[@]}"; do
            if [[ "$w" != "$current" ]]; then
                available+=("$w")
            fi
        done
        if [[ ${#available[@]} -eq 0 ]]; then
            available=("${all_wallpapers[@]}")
        fi
    elif [[ ${#available[@]} -gt 1 && -n "$current" ]]; then
        # Ainda no ciclo, mas evita repetir o aplicado agora (ex.: troca manual)
        local filtered=()
        for w in "${available[@]}"; do
            if [[ "$w" != "$current" ]]; then
                filtered+=("$w")
            fi
        done
        if [[ ${#filtered[@]} -gt 0 ]]; then
            available=("${filtered[@]}")
        fi
    fi

    local idx=$((RANDOM % ${#available[@]}))
    local selected="${available[$idx]}"

    # Persiste o ciclo já com o wallpaper escolhido
    {
        if [[ ${#used[@]} -gt 0 ]]; then
            printf '%s\n' "${used[@]}"
        fi
        printf '%s\n' "$selected"
    } > "$CYCLE_FILE"

    echo "🎯 Selecionado: $(basename "$selected")" >&2
    echo "$selected"
}

# Atualiza o histórico
update_history() {
    local wallpaper="$1"

    echo "📝 Atualizando histórico..." >&2

    local history_lines=()
    if [[ -f "$HISTORY_FILE" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && history_lines+=("$line")
        done < <(tail -n +2 "$HISTORY_FILE" 2>/dev/null | head -n $((HISTORY_SIZE - 1)))
    fi

    {
        echo "$wallpaper"
        printf '%s\n' "${history_lines[@]}"
    } > "$HISTORY_FILE"

    echo "✅ Histórico atualizado" >&2
}

# Aplica wallpaper
apply_wallpaper() {
    local wallpaper="$1"

    if [[ ! -f "$wallpaper" ]]; then
        echo "❌ Wallpaper não encontrado: $wallpaper" >&2
        return 1
    fi

    pkill -x swaybg 2>/dev/null || true

    if command -v swaybg &>/dev/null; then
        swaybg -i "$wallpaper" -m fill 2>/dev/null &
        echo "✅ Wallpaper aplicado com swaybg" >&2
        return 0
    fi

    if command -v feh &>/dev/null; then
        feh --bg-fill "$wallpaper" 2>/dev/null
        echo "✅ Wallpaper aplicado com feh" >&2
        return 0
    fi

    echo "❌ Nenhum backend encontrado" >&2
    return 1
}

# ============================================
# MAIN
# ============================================

main() {
    echo "🚀 Iniciando troca de wallpaper..." >&2

    ensure_directories

    SELECTED=$(select_wallpaper)

    if [[ -z "$SELECTED" ]]; then
        echo "❌ Falha ao selecionar wallpaper" >&2
        exit 1
    fi

    echo "📌 Aplicando: $(basename "$SELECTED")" >&2

    RESOLUTION=$(detect_resolution)
    echo "🖥️  Resolução: $RESOLUTION" >&2

    apply_wallpaper "$SELECTED"

    update_history "$SELECTED"

    # Cria cópia do wallpaper
    cp "$SELECTED" "$CURRENT_WALLPAPER" 2>/dev/null || true

    # Gera a paleta e atualiza as cores de todos os apps (uma única fonte).
    "$HOME/.config/scripts/run-scripts.sh" "$SELECTED"
    echo "✨ Concluído!" >&2
}

# Executa
main "$@"
