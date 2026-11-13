# Solução de problemas

Problemas reais encontrados ao instalar/rodar o Cadroc fora da máquina de
origem, e como resolver cada um. Se o seu caso não estiver aqui, rode
`./check.sh --all --lists` e `mango -p -c ~/.config/mango/config.conf` antes de
abrir issue: eles cobrem sintaxe, dependências, listas de pacotes e a própria
config do compositor.

## Instalação

**`install.sh --aur` falha com "target not found".**
Uma entrada da `lista_aur.txt` não existe mais no AUR (renomeada/removida) ou é
split package (ex.: `yay-bin-debug`, que não é instalável por nome). Rode
`./check.sh --lists` para achar qual, e `./install.sh --update-lists` se quiser
regenerar — revise o diff antes de commitar.

**Nenhum helper AUR instalado (yay/paru).**
O `install.sh` detecta a ausência e instala o `yay-bin` via `makepkg` (precisa
de `base-devel`). Se o `makepkg` reclamar de usuário root, rode como usuário
normal; o script chama `sudo` apenas onde precisa.

**`mangowm-git`/`waybar-git`/`mpv-full` demoram.**
São builds do AUR; a primeira instalação compila. É esperado, não é travamento.

## Sessão e tela

**Waybar/notificações não aparecem depois do primeiro deploy.**
Recarregue a sessão: `mmsg dispatch reload_config`. Se persistir, confira se o
`swaync`/`waybar` está vivo (`pgrep -a waybar`) e veja o log da sessão em
`~/.local/share/sddm/wayland-session.log`.

**Monitor errado, resolução errada ou tela desligada.**
As regras de monitor **não** ficam no git: `~/.config/mango/monitor.conf` é
gerado por máquina. Rode `~/.config/scripts/detect-monitors.sh --write` e
aplique com `mmsg dispatch reload_config`. Se o `wlr-randr` não listar a saída
esperada, o problema é de driver/conector, não do Cadroc.

**Texto estranho ou com "quadradinhos".**
O tema usa `FONT_FAMILY` (padrão `JetBrainsMono Nerd Font`) de
`~/.local/state/cadrocspace/state/state.env`. Instale a fonte e reaplique o
tema com `~/.config/scripts/run-scripts.sh`, ou troque a família no arquivo de
estado.

**Tema não mudou depois de trocar o wallpaper.**
Os arquivos de cor são gerados, não versionados. Rode `./deploy.sh --generate`
(ou `run-scripts.sh`) para reaplicar a paleta a partir do wallpaper atual.

## Navegador e compartilhamento

**Seletor de tela não abre, ou a captura fica preta.**
O seletor vem do `xdg-desktop-portal-gtk`; a captura, do
`xdg-desktop-portal-wlr` (roteado por `/usr/share/xdg-desktop-portal/mango-portals.conf`).
Confira os dois serviços ativos (`systemctl --user status xdg-desktop-portal-wlr`)
e se `pipewire`/`wireplumber` estão rodando. O `xdg-desktop-portal-wlr` loga
`wofi`/`rofi`/`bemenu`/`mew` ausentes em algumas versões — é ruído inofensivo,
o seletor do frontend GTK atende.

**Firefox: "Unhandled parent window type" ao abrir arquivo.**
Em compositores não-GNOME o file picker via portal pode falhar. Desabilite o
picker do portal nos perfis do Firefox com `./install.sh --firefox`. O navegador
padrão do Cadroc é o Brave (`SUPER+B`); o Firefox é opcional.

**Atalho do navegador não abre.**
O `SUPER+B` chama `brave`. Sem `brave-bin` instalado (está em `lista_aur.txt`)
o atalho não faz nada. Confira com `command -v brave`.

## Diagnóstico rápido

```sh
./check.sh --all --lists                  # scripts, deps e pacotes das listas
mango -p -c ~/.config/mango/config.conf   # config do compositor (exit 0 = ok)
mmsg get all-clients | jq -r '.clients[] | "\(.appid) xwayland=\(.is_xwayland)"'
mmsg get all-monitors                     # monitores vistos pelo compositor
pacman -Qdtq                              # pacotes órfãos
```
