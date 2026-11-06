#!/usr/bin/env bash
# ~/.config/scripts/colors/qbittorrent-colors.sh
# Gera o tema do qBittorrent a partir da paleta pywal (tema de pasta).
#
# O qBittorrent le o tema SOMENTE na inicializacao (UIThemeManager no
# construtor), entao aqui regeneramos os arquivos e avisamos via notify-send.
# O restart fica a cargo do usuario para nao interromper downloads.

COLORS_FILE="$HOME/.cache/wal/colors.css"
THEME_DIR="$HOME/.config/qBittorrent/themes/pywal"
TEMPLATE="$THEME_DIR/stylesheet.qss.tpl"

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

if [ ! -f "$TEMPLATE" ]; then
    echo "ERRO: Template $TEMPLATE não encontrado!"
    exit 1
fi

mkdir -p "$THEME_DIR"

python3 - "$COLORS_FILE" "$TEMPLATE" "$THEME_DIR" <<'PYEOF'
import json, re, sys, colorsys

colors_file, template, theme_dir = sys.argv[1:4]

# ------------------------------------------------- le a paleta do pywal
css = open(colors_file, encoding='utf-8').read()

def var(name):
    m = re.search(r'--%s:\s*(#[0-9a-fA-F]{3,8})' % re.escape(name), css)
    return m.group(1) if m else None

py = {n: var(n) for n in ['background', 'foreground', 'cursor']}
py.update({'color%d' % i: var('color%d' % i) for i in range(16)})

missing = [k for k, v in py.items() if not v]
if missing:
    sys.exit('ERRO: pywal nao gerou: %s' % ', '.join(missing))

# ------------------------------------------------- helpers de cor
def rgb(h):
    h = h.lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))

def hexc(r, g, b):
    return '#%02x%02x%02x' % (
        max(0, min(255, round(r * 255))),
        max(0, min(255, round(g * 255))),
        max(0, min(255, round(b * 255))))

def shift(h, dl=0.0, ds=0.0):
    """Ajusta luminosidade/saturacao de uma cor (HSL)."""
    r, g, b = rgb(h)
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)
    ll = max(0.0, min(1.0, ll + dl))
    ss = max(0.0, min(1.0, ss + ds))
    return hexc(*colorsys.hls_to_rgb(hh, ll, ss))

bg, fg = py['background'], py['foreground']

# A hierarquia de fundo (painel/handle/borda) e derivada do wallpaper por
#clareamento: o pywal nao garante tons distintos, e usar color0 direto
#achataria os paineis no fundo.
colors = {
    'BG':        bg,
    'BG_PANEL':  shift(bg, dl=+0.035),
    'BG_PANEL2': shift(bg, dl=+0.070),
    'BG_HANDLE': shift(bg, dl=+0.105),
    'BORDER':    shift(bg, dl=+0.090),
    'TEXT':      fg,
    'TEXT_DIM':  shift(fg, dl=-0.28),
    'TEXT_MUTED': shift(fg, dl=-0.12),
    'ACCENT':      py['color12'],
    'ACCENT_DIM':  py['color4'],
    'ST_DL':      py['color10'],
    'ST_STALL':   py['color11'],
    'ST_UP':      py['color12'],
    'ST_PAUSE':   py['color9'],
    'ST_QUEUE':   py['color14'],
    'ST_ALLOC':   py['color7'],
    'ST_ERROR':   py['color9'],
}

# ------------------------------------------------- config.json
config = {
    'colors': {
        'Palette.Window': colors['BG'],
        'Palette.WindowText': colors['TEXT'],
        'Palette.Base': colors['BG'],
        'Palette.AlternateBase': colors['BG_PANEL'],
        'Palette.Text': colors['TEXT'],
        'Palette.ToolTipBase': colors['BG_PANEL2'],
        'Palette.ToolTipText': colors['TEXT'],
        'Palette.BrightText': py['color15'],
        'Palette.Highlight': colors['ACCENT'],
        'Palette.HighlightedText': colors['TEXT'],
        'Palette.Button': colors['BG_PANEL'],
        'Palette.ButtonText': colors['TEXT'],
        'Palette.Link': colors['ACCENT'],
        'Palette.LinkVisited': colors['ACCENT_DIM'],
        'Palette.Light': shift(bg, dl=+0.14),
        'Palette.Midlight': shift(bg, dl=+0.10),
        'Palette.Mid': shift(bg, dl=+0.06),
        'Palette.Dark': shift(bg, dl=-0.04),
        'Palette.Shadow': shift(bg, dl=-0.07),
        'Palette.WindowTextDisabled': colors['TEXT_DIM'],
        'Palette.TextDisabled': colors['TEXT_DIM'],
        'Palette.ToolTipTextDisabled': colors['TEXT_DIM'],
        'Palette.BrightTextDisabled': colors['TEXT_DIM'],
        'Palette.HighlightedTextDisabled': colors['TEXT'],
        'Palette.ButtonTextDisabled': colors['TEXT_DIM'],
        'TransferList.Downloading': colors['ST_DL'],
        'TransferList.ForcedDownloading': colors['ST_DL'],
        'TransferList.DownloadingMetadata': colors['ST_DL'],
        'TransferList.Allocating': colors['ST_ALLOC'],
        'TransferList.StalledDownloading': colors['ST_STALL'],
        'TransferList.StalledUploading': colors['ST_STALL'],
        'TransferList.Uploading': colors['ST_UP'],
        'TransferList.ForcedUploading': colors['ST_UP'],
        'TransferList.PausedDownloading': colors['ST_PAUSE'],
        'TransferList.PausedUploading': colors['ST_PAUSE'],
        'TransferList.Error': colors['ST_ERROR'],
        'TransferList.MissingFiles': colors['ST_ERROR'],
        'TransferList.QueuedDownloading': colors['ST_QUEUE'],
        'TransferList.QueuedUploading': colors['ST_QUEUE'],
        'TransferList.CheckingDownloading': colors['ST_QUEUE'],
        'TransferList.CheckingUploading': colors['ST_QUEUE'],
        'TransferList.CheckingResumeData': colors['ST_QUEUE'],
        'TransferList.Moving': colors['ST_QUEUE'],
    }
}

with open(theme_dir + '/config.json', 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
    f.write('\n')

# ------------------------------------------------- stylesheet.qss
qss = open(template, encoding='utf-8').read()
qss = re.sub(r'\{\{(\w+)\}\}',
             lambda m: colors.get(m.group(1), '#ff00ff'), qss)
left = re.findall(r'\{\{(\w+)\}\}', qss)
if left:
    sys.exit('ERRO: tokens sem cor no template: %s' % ', '.join(sorted(set(left))))

with open(theme_dir + '/stylesheet.qss', 'w', encoding='utf-8') as f:
    f.write(qss)

print('  bg=%s  fg=%s  accent=%s' % (colors['BG'], colors['TEXT'], colors['ACCENT']))
PYEOF

if [ $? -ne 0 ]; then
    echo "ERRO: falha ao gerar o tema."
    exit 1
fi

echo "✅ Tema gerado em $THEME_DIR"

# O qBittorrent só lê o tema no startup, então avisamos em vez de reiniciar.
if pgrep -x qbittorrent >/dev/null 2>&1; then
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a qBittorrent "Tema pywal" \
            "Cores atualizadas. Reinicie o qBittorrent para aplicar."
    fi
    echo "ℹ️  qBittorrent em execução: reinicie para aplicar o tema."
else
    echo "ℹ️  qBittorrent não está em execução, tema aplicado no próximo início."
fi