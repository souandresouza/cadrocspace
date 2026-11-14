# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

### Adicionado

- `colors/sddm-colors.sh`: gera `~/.local/state/cadrocspace/sddm/theme.conf`
  (cores, fonte e wallpaper) para o tema de login do Cadroc, com contraste
  mínimo garantido (texto 7:1, secundário 6:1, botão 4.5:1) e sugestão do
  wallpaper atual. O tema aplica o arquivo com `installer.sh --recolor`.
- `run-scripts.sh` exporta `CADROC_WALLPAPER` e inclui `sddm` na lista de
  renderizadores (depois de `cadroc`, que atualiza o `ACCENT_COLOR`).
- `docs/troubleshooting.md`: problemas reais de instalação e de sessão
  (listas, monitores, fontes, screen share, file picker) com diagnóstico.
- `check.sh --lists`: confere se cada pacote de `lista_pacman.txt` existe nos
  repos oficiais e se cada um de `lista_aur.txt` existe no AUR (rede
  necessária; fora do `--all` para não quebrar uso offline). Foi o que pegou o
  `yay-bin-debug` inexistente.
- `defaults/`: fonte versionada dos arquivos de tema gerados (cores, waybar,
  monitor) que deixam de ser versionados em `.config`.
- `deploy.sh`: semeia de `defaults/` os arquivos gerados que faltarem e os
  exclui do push/pull/`--prune` (fim do drift a cada troca de wallpaper).
- `scripts/detect-monitors.sh`: gera `monitor_rule` a partir do `wlr-randr`.
- `scripts/polkit-agent.sh`: inicia o primeiro agente polkit disponível
  (KDE, GNOME, MATE, XFCE).
- `CHANGELOG.md` para registrar as mudanças do projeto.
- Limpeza de 2026-11-11 no `deploy.sh`/`install.sh`: nome do projeto e cache passam a ser `cadrocspace`.

### Portabilidade

- Monitores saem do `config.conf` para `~/.config/mango/monitor.conf`, fora do
  git e gerado por máquina (o repo não fixa mais `eDP-1`/`HDMI-A-1`).
- `battery_tracker.sh` e a Waybar detectam a primeira bateria em
  `/sys/class/power_supply` (sem `BAT1` fixo); log vai para
  `~/.local/state/cadrocspace/battery/`.
- `wlsunset.sh`: coordenadas e temperaturas configuráveis por
  `WLSUNSET_LAT`/`WLSUNSET_LON`/`WLSUNSET_DAY`/`WLSUNSET_NIGHT`.
- Fonte do zathura vem do estado do tema (`FONT_FAMILY`/`FONT_SIZE`) em vez de
  `inconsolata 15`, que não estava nas listas de pacotes.
- Polkit deixa de depender do caminho fixo do agente do KDE.

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

- `.config/mango/rule.conf`: removida a `window_rule` de `app_id:obs` (OBS fora do escopo).
- `VIABILIDADE.md` saiu do repositório: era um documento interno de avaliação,
  não parte do projeto publicado. O conteúdo permanece no histórico do git.
- Dependência de `hyprpicker` no conta-gotas; a stack não tem mais nada de Hyprland.
- Bind `SUPER+SHIFT+B` (Firefox) e as `window_rule` exclusivas do Firefox: o
  navegador padrão é o Brave, já coberto por `SUPER+B` e pelas regras genéricas.

### Corrigido

- `lista_aur.txt`/`install.sh --update-lists`: pacotes `*-debug` de split
  packages (`yay-bin-debug`) não entram mais nas listas — não existem como
  entrada no AUR e fariam `install.sh --aur` falhar em máquina limpa.
- `scripts/colors/telegram-colors.sh`: remoção do `xrandr` (X11) no cálculo do
  tamanho do fundo — usa `mmsg get all-monitors`; e ImageMagick 7 chamado como
  `magick`/`magick identify` (sem o verbo `convert` depreciado).
- `scripts/color_picker.sh`: `--apply` apontava para `gen_style.sh`/`apply_style.sh`, que não existem mais; agora dispara `run-scripts.sh` (reaplica o tema a partir do wallpaper atual).
