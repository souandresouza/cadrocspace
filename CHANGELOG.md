# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

### Adicionado

- `CHANGELOG.md` e aviso no README sobre inspiração no Omarchy (sem afiliação, sem Quickshell).
- Limpeza de 2026-11-11 no `deploy.sh`/`install.sh`: nome do projeto e cache passam a ser `cadrocspace`.

### Renomeado

- `mango-dotfiles` → **Cadroc** (`cadrocspace`): repositório, README, URLs de clone e diretório de cache
  (`~/.cache/cadrocspace`). O histórico do git é o mesmo.

### Alterado

- `scripts/exit.sh`: removido o ramo `hyprctl dispatch exit`; saída usa `mmsg dispatch quit` (mango) com fallback para `swaymsg`/`loginctl`.
- `scripts/random-wallpaper.sh`: resolução do monitor vem de `mmsg get all-monitors` (IPC do mango), com fallback `wlr-randr`; removidos `hyprctl` e `xrandr`.
- `scripts/color_picker.sh`: backend passou a ser `grim` + `slurp` + `imagemagick` (wlroots, sem Hyprland); conversão para HEX/RGB/HSV feita localmente, resultado copiado com `wl-copy`.
- `.config/mango/rule.conf`: removida a layer rule específica do `hyprpicker`.
- `lista_pacman.txt`: `hyprpicker` removido (pacote e `hyprutils` desinstalados do sistema).

### Removido

- Dependência de `hyprpicker` no conta-gotas; a stack não tem mais nada de Hyprland.

### Corrigido

- `scripts/color_picker.sh`: `--apply` apontava para `gen_style.sh`/`apply_style.sh`, que não existem mais; agora dispara `run-scripts.sh` (reaplica o tema a partir do wallpaper atual).
