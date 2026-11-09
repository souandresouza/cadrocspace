#!/bin/sh
# ~/.config/scripts/colors/waybar-colors.sh
# Gera a paleta do Waybar e as cores do calendário a partir do wallpaper atual
# (ruwall/pywal). Chamado pelo run-scripts.sh.

COLORS_FILE="$HOME/.cache/wal/colors.css"
WAYBAR_FILE="$HOME/.config/waybar/colors-waybar.css"
CALENDAR_FILE="$HOME/.config/mango/waybar.jsonc"

if [ ! -f "$COLORS_FILE" ]; then
    echo "ERRO: sem paleta em $COLORS_FILE"
    echo "Gere uma com:"
    echo "  ~/.config/scripts/run-scripts.sh            # usa o wallpaper atual"
    echo "  ~/.config/scripts/run-scripts.sh <imagem>   # de um arquivo"
    echo "  (PALETTE_TOOL=wal volta ao pywal)"
    echo "Sem paleta em ~/.cache/wal. Gere uma com:"
    echo "  ~/.config/scripts/run-scripts.sh            # usa o wallpaper atual"
    echo "  ~/.config/scripts/run-scripts.sh <imagem>   # de um arquivo"
    echo "  (ou PALETTE_TOOL=wal para voltar ao pywal)"
    exit 1
fi

# Extrair cores do formato Pywal/CSS (--color0: #xxx;)
extract_color() {
    grep -- "--color$1:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; '
}

# Extrair também background, foreground e cursor
background=$(grep -- "--background:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')
foreground=$(grep -- "--foreground:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')
cursor=$(grep -- "--cursor:" "$COLORS_FILE" | head -1 | awk -F': ' '{print $2}' | tr -d '; ')

# Extrair cores 0-15
color0=$(extract_color 0)
color1=$(extract_color 1)
color2=$(extract_color 2)
color3=$(extract_color 3)
color4=$(extract_color 4)
color5=$(extract_color 5)
color6=$(extract_color 6)
color7=$(extract_color 7)
color8=$(extract_color 8)
color9=$(extract_color 9)
color10=$(extract_color 10)
color11=$(extract_color 11)
color12=$(extract_color 12)
color13=$(extract_color 13)
color14=$(extract_color 14)
color15=$(extract_color 15)

# Verificar se as cores foram extraídas (color1/2/8 também alimentam o calendário)
if [ -z "$color0" ] || [ -z "$background" ] || [ -z "$foreground" ] ||
    [ -z "$color1" ] || [ -z "$color2" ] || [ -z "$color8" ]; then
    echo "ERRO: a paleta em $COLORS_FILE não tem cores utilizáveis."
    echo "Regere com: ~/.config/scripts/run-scripts.sh"
    exit 1
fi

mkdir -p "$(dirname "$WAYBAR_FILE")"

# Gerar arquivo no formato Waybar (sem aspas)
cat > "$WAYBAR_FILE" << EOF
@define-color foreground $foreground;
@define-color background $background;
@define-color cursor $color7;

@define-color color0 $color0;
@define-color color1 $color1;
@define-color color2 $color2;
@define-color color3 $color3;
@define-color color4 $color4;
@define-color color5 $color5;
@define-color color6 $color6;
@define-color color7 $color7;
@define-color color8 $color8;
@define-color color9 $color9;
@define-color color10 $color10;
@define-color color11 $color11;
@define-color color12 $color12;
@define-color color13 $color13;
@define-color color14 $color14;
@define-color color15 $color15;
EOF

echo "✅ Configuração gerada em $WAYBAR_FILE"

# Escolhe a primeira cor (hex #rrggbb) com contraste >= $1 contra o background.
# Nem toda cor da paleta é legível: color1..color6 variam de claro a escuro
# conforme o wallpaper. Usa $foreground como último recurso, pois o pywal
# garante contraste dele com o fundo.
# Uso: pick_color <min_contraste> <cor>...
pick_color() {
    min="$1"
    shift
    awk -v bg="$background" -v fallback="$foreground" -v min="$min" '
    function lin(c) { c /= 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4 }
    function lum(h,   r, g, b) {
        h = substr(h, 2)
        r = strtonum("0x" substr(h, 1, 2))
        g = strtonum("0x" substr(h, 3, 2))
        b = strtonum("0x" substr(h, 5, 2))
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    function ratio(a, b,   la, lb) {
        la = lum(a); lb = lum(b)
        return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05)
    }
    BEGIN {
        for (i = 1; i < ARGC; i++) {
            if (ARGV[i] ~ /^#[0-9a-fA-F]{6}$/ && ratio(ARGV[i], bg) >= min) {
                print ARGV[i]
                exit
            }
        }
        print fallback
    }' "$@"
}

# Cores do calendário: escolhe variantes legíveis e mantém a paleta quando ela
# já tem contraste. Sem isso, meses/dias da semana podem sumir em fundos escuros.
cal_months=$(pick_color 4.5 "$color2" "$color5" "$color7" "$foreground")
cal_days="$foreground"
cal_weeks=$(pick_color 3.0 "$color8" "$color7" "$foreground")
cal_weekdays=$(pick_color 3.0 "$color1" "$color8" "$color7" "$foreground")
cal_today=$(pick_color 4.5 "$color5" "$color7" "$foreground")

# O calendário do relógio usa os mesmos tokens da paleta, mas em hex fixo dentro
# do waybar.jsonc. Atualiza só os cinco campos do calendário, preservando o
# restante do arquivo e as permissões originais.
update_calendar_colors() {
    [ -f "$CALENDAR_FILE" ] || return 0

    tmp="$(mktemp "${CALENDAR_FILE}.XXXXXX")" || return 1

    if ! sed \
        -e "/\"months\":/s|color='#[0-9a-fA-F]\{6\}'|color='$cal_months'|" \
        -e "/\"days\":/s|color='#[0-9a-fA-F]\{6\}'|color='$cal_days'|" \
        -e "/\"weeks\":/s|color='#[0-9a-fA-F]\{6\}'|color='$cal_weeks'|" \
        -e "/\"weekdays\":/s|color='#[0-9a-fA-F]\{6\}'|color='$cal_weekdays'|" \
        -e "/\"today\":/s|color='#[0-9a-fA-F]\{6\}'|color='$cal_today'|" \
        "$CALENDAR_FILE" > "$tmp"; then
        rm -f "$tmp"
        echo "ERRO: não foi possível atualizar o calendário em $CALENDAR_FILE" >&2
        return 1
    fi

    if cmp -s "$CALENDAR_FILE" "$tmp"; then
        rm -f "$tmp"
        echo "ℹ️  Calendário da Waybar já está com a paleta atual"
    else
        cat "$tmp" > "$CALENDAR_FILE"
        rm -f "$tmp"
        echo "✅ Cores do calendário atualizadas em $CALENDAR_FILE"
    fi
}

update_calendar_colors

# Recarrega a Waybar se estiver em execução
if pgrep -x waybar >/dev/null 2>&1; then
    pkill -SIGUSR2 -x waybar 2>/dev/null || true
    echo "✅ Waybar recarregada"
else
    echo "ℹ️  Waybar não está em execução, configuração será aplicada no próximo início."
fi
