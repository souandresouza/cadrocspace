#!/usr/bin/env bash
set -euo pipefail

# ========= CONFIG =========
BASE_DIR="$HOME/Imagens/Screenshots"

DATE=$(date +%d-%m-%Y)
TIMESTAMP=$(date +%d%m%Y_%H%M%S)

DIR="$BASE_DIR/$DATE"
mkdir -p "$DIR"

# ========= DETECT COMPOSITOR =========
detect_compositor() {
  if command -v mango >/dev/null 2>&1; then
    echo "mango"
  else
    echo "unknown"
  fi
}

COMPOSITOR=$(detect_compositor)

# ========= GET ACTIVE WINDOW GEOMETRY =========
# O MangoWM expõe um socket IPC que responde JSON:
#   get focusing-client -> {"x":..,"y":..,"width":..,"height":..,...}
# Não existe CLI pronto, então falamos com o socket via python3.
mango_socket() {
  local pid
  pid=$(pgrep -x mango 2>/dev/null | head -1) || return 1
  [[ -n "$pid" ]] || return 1
  local sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mango-${pid}.sock"
  [[ -S "$sock" ]] || return 1
  printf '%s' "$sock"
}

get_window_geom() {
  case "$COMPOSITOR" in
    mango)
      local sock
      sock=$(mango_socket) || return 1

      local resp
      resp=$(printf 'get focusing-client\n' | timeout 2 python3 -c '
import socket, sys
sock = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(1.5)
s.connect(sock)
s.sendall(b"get focusing-client\n")
buf = b""
while not buf.endswith(b"\n"):
    chunk = s.recv(4096)
    if not chunk:
        break
    buf += chunk
sys.stdout.write(buf.decode(errors="replace"))
' "$sock" 2>/dev/null) || return 1

      [[ -n "$resp" ]] || return 1
      # Erro do WM (ex.: nenhuma janela focada). Usa 'if' porque com
      # '&& return 1' o último comando do case viraria o status da função.
      if [[ "$resp" == *'"error"'* ]]; then
        return 1
      fi

      printf '%s' "$resp" | python3 -c '
import json, sys
d = json.load(sys.stdin)
w, h = int(d["width"]), int(d["height"])
if w <= 0 or h <= 0:
    sys.exit(1)
print("%d,%d %dx%d" % (int(d["x"]), int(d["y"]), w, h))
' 2>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

# ========= HELP =========
usage() {
  echo "Uso: screenshot [all|monitor|region|window]"
  exit 1
}

# ========= MODES =========
case "${1:-}" in
  all)
    MODE="all"
    FILE="$DIR/screenshot_${MODE}_${TIMESTAMP}.png"
    grim "$FILE"
    ;;

  monitor)
    MONITOR=$(slurp -o -f "%o")
    MODE="$MONITOR"
    FILE="$DIR/screenshot_${MODE}_${TIMESTAMP}.png"
    grim -o "$MONITOR" "$FILE"
    ;;

  region)
    MODE="region"
    FILE="$DIR/screenshot_${MODE}_${TIMESTAMP}.png"
    GEOM=$(slurp)
    grim -g "$GEOM" "$FILE"
    ;;

  window)
    MODE="window"
    FILE="$DIR/screenshot_${MODE}_${TIMESTAMP}.png"

    GEOM=$(get_window_geom || true)

    if [[ -z "${GEOM:-}" ]]; then
      notify-send "Screenshot" "Erro ao obter janela ($COMPOSITOR)"
      exit 1
    fi

    grim -g "$GEOM" "$FILE"
    ;;

  *)
    usage
    ;;
esac

# ========= COPY =========
wl-copy < "$FILE"

# ========= FEEDBACK (SwayNC Thumbnail) =========
# O SwayNC processa nativamente o parâmetro -i como a prévia lateral se receber o caminho absoluto.
FILENAME=$(basename "$FILE")
notify-send -i "$FILE" "Screenshot Capturada" "$MODE • $FILENAME"
echo "Salvo em: $FILE"
