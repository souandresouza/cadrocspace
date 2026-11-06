#!/usr/bin/env bash
# lock.sh — wrapper de bloqueio adaptado de srgvg/dotfiles (bin/swayidle.sh + bin/swaylock-image.sh)
# - debounce: ignora rajadas de sinal de lock (ex.: fonte desconhecida disparando ~25 sinais/s)
# - não empilha swaylock se já estiver rodando
# - liga o DND do SwayNC durante o bloqueio, mas só enquanto a tela estiver de
#   fato travada (ver AUTO_DND_FILE e o bloco pós-swaylock)
# - usa a config em ~/.config/swaylock/config (screenshot+blur+pywal); fallback p/ fundo preto

set -u

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/swayidle"
mkdir -p "$STATE_DIR"
DEBOUNCE_FILE="$STATE_DIR/lock-debounce"
DEBOUNCE_SECONDS=2

# Marca que o DND ligado aqui foi automático. unlock.sh só desliga o DND se esta
# flag existir: assim o DND que o usuário ligou na mão (SUPER,u ou o switch do
# painel) sobrevive a um ciclo de trava/destrava. Regra: DND ligado = tela
# travada OU ligado manualmente.
AUTO_DND_FILE="$STATE_DIR/auto-dnd"

# debounce
if [ -f "$DEBOUNCE_FILE" ]; then
    last=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    elapsed=$((now - last))
    if [ "$elapsed" -lt "$DEBOUNCE_SECONDS" ]; then
        echo "lock (ignorado: debounce, ${elapsed}s desde o último)"
        exit 0
    fi
fi

# já bloqueado?
if pgrep -x swaylock >/dev/null; then
    echo "lock (ignorado: swaylock já está rodando)"
    exit 0
fi

date +%s >"$DEBOUNCE_FILE"

# pausa notificações durante o bloqueio (best-effort).
# Equivalente no SwayNC: --dnd-on / --dnd-off (mako não é mais usado).
#
# Se o DND já estava ligado, foi o usuário (SUPER,u ou o switch do painel): não
# marca como automático, para o destrave não desligar o que é dele. Só liga
# (e marca) quando estava desligado antes.
if [ "$(swaync-client --get-dnd 2>/dev/null)" = "true" ]; then
    rm -f "$AUTO_DND_FILE"
else
    : >"$AUTO_DND_FILE"
    swaync-client --dnd-on >/dev/null 2>&1 || :
fi

# Trava de fato. `swaylock -f` é --daemonize: o comando volta assim que a tela
# trava e o swaylock segue rodando detached, então o sucesso se mede pelo
# processo de pé — e não pelo código de saída. Medir pelo exit code erraria:
# quem destrava é o swayidle, não este script.
if ! swaylock -f "$@" && ! pgrep -x swaylock >/dev/null; then
    # A config completa não levantou a tela: tenta o fundo preto simples.
    if ! swaylock -f -c 000000 "$@" && ! pgrep -x swaylock >/dev/null; then
        # Nem a completa nem o fallback travaram. Desfaz o DND em vez de
        # deixar ele preso ligado: sem trava não vem evento de unlock para
        # desligar, e o DND ficaria ligado sem ninguém ter pedido.
        rm -f "$AUTO_DND_FILE"
        swaync-client --dnd-off >/dev/null 2>&1 || :
        exit 1
    fi
fi

# A tela está travada. Quem desliga o DND automático é o unlock.sh, MAS ele
# responde ao evento `unlock` do swayidle, que vem do logind sinalizando
# destravamento de sessão — digitar a senha no swaylock não gera evento nenhum.
# Num lock manual (Super,l) o unlock.sh simplesmente nunca roda e o DND ficava
# ligado para sempre depois do destrave. Por isso este watcher: ele espera o
# swaylock terminar e desfaz o que foi ligado aqui.
# setsid desliga o watcher do compositor, então ele não segura o lock.sh.
# Se o DND for manual, não existe flag e o watcher não mexe.
setsid bash -c '
    while pgrep -x swaylock >/dev/null 2>&1; do sleep 1; done
    [ -f "$1" ] || exit 0
    rm -f "$1"
    swaync-client --dnd-off >/dev/null 2>&1 || :
' _ "$AUTO_DND_FILE" >/dev/null 2>&1 &

# Trava no lugar; lock.sh termina aqui.
exit 0