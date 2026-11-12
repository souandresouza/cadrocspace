# Cadroc — relatório de viabilidade

**Pergunta:** vale criar um setup Arch Linux "omakase" baseado no **MangoWC**, com
ambição equivalente à do **Omarchy**, sem usar o nome/marca Omarchy e sem shell
pesada (Quickshell)?

**Resposta curta:** **sim (GO)** — mas não como clone do Omarchy. Como *setup
próprio*, com identidade (scrolling/tags), stack leve já validada e distribuição
por dotfiles + `install.sh`. O cenário "paridade 1:1 com o Omarchy 4" é **NO-GO**.

- Data: 2026-11-11
- Base analisada: `~/cadrocspace` (repo publicado), `~/.config/{mango,waybar,scripts}`
- Ambiente medido: Arch Linux, MangoWC (`mangowm-git`), eDP-1 1366×768 + HDMI-A-1 1920×1080@100

---

## 1. Sumário executivo

| Cenário | Escopo | Esforço | Veredito |
|---|---|---|---|
| **A — dotfiles publicáveis** | repo com config + tema + `install.sh`/`deploy.sh` + docs mínimas | 1–2 semanas | ✅ **GO** (80% já feito) |
| **B — "Omarchy-like" sem Quickshell** | A + portabilidade, `PKGBUILD`, presets de tema, menu do sistema, manual, deploy limpo | 1–2 meses | ✅ **GO condicionado** |
| **C — paridade 1:1 com o Omarchy 4** | B + shell Quickshell + plugins + ISO archiso + IAs integradas | equipe, não solo | ❌ **NO-GO** |

O ponto central: **o valor percebido do Omarchy não está no compositor**. Está na
curadoria, no tema, na documentação e na instalação. Desses quatro, o Cadroc já
tem os dois primeiros em produção — e os dois últimos são a parte barata.
A parte cara (shell unificada em Quickshell) **ficou de fora por decisão**,
apoiada em uso real: o próprio autor já manteve uma barra em Quickshell
(`cadrocbar`) e a considerou pesada.

---

## 2. O que é o Omarchy hoje (v4 "Quattro", 14/08/2026)

- Arch Linux + Hyprland 0.56, licença MIT, instalado por pacotes `pacman`;
  arquivos do sistema em `/usr/share/omarchy`, config do usuário em `~/.config`.
- **Shell unificada em um processo Quickshell**: barra, launcher, notificações,
  OSD, lock screen, idle, wallpaper e polkit — substituiu Waybar, Walker, Mako,
  SwayOSD, hyprlock, hypridle, swaybg e polkit-gnome.
- Config do compositor em **Lua** (`hyprland.lua`, `bindings.lua`, `monitors.lua`).
- Tema a partir de um `colors.toml` único, com templates `*.tpl` que geram configs
  de terminal, btop, Neovim, shell e Hyprland.
- Sistema de plugins + hub de temas; instalador via archiso, dual-boot, factory reset.
- Precedente relevante: **`moarchy`** porta o Omarchy 4.x para **Sway** (wlroots,
  PinePhone/GLES2). Lá o sistema de temas portou adicionando **um template**
  (`sway.conf.tpl`), e os 22 temas oficiais funcionaram sem retrabalho.

**Conclusão da camada:** o Omarchy é ~20% compositor e ~80% produto em volta dele.

## 3. O que é o Cadroc hoje (medido, não estimado)

| Camada | Situação |
|---|---|
| Compositor | MangoWC (`dwl` + wlroots + scenefx), **tags** em vez de workspaces, layouts por tag |
| Barra | Waybar com módulos `mango/*` (tags, título, layout) |
| Launcher / notificações / lock / idle | Fuzzel / SwayNC / swaylock-effects / swayidle |
| Tema | `cadroc_theme.sh`: fonte única (`ACCENT_COLOR`, `FONT_FAMILY`, `FONT_SIZE`) + **13 renderizadores** (mango, waybar, swaync, swaylock, fuzzel, kitty, cava, fastfetch, qbittorrent, telegram, zathura, mako, cadroc) + constante de cores |
| Paleta | `ruwall`/pywal por wallpaper → `run-scripts.sh` re-renderiza tudo |
| Wallpaper | `random-wallpaper.sh` com histórico e ciclo persistido, sem repetir |
| Utilitários | screenshot com OCR/QR, gravação, dashboard, teclado virtual, clipboard (`cliphist`), calendário, bateria, `wlsunset` |
| Atalhos | **111** binds (teclado + mouse) |
| Repositório | 93 arquivos versionados, ~6.300 linhas de shell, `install.sh` (listas pacman/AUR), `deploy.sh` (repo ⇄ `~/.config`), `check.sh` |
| Pegada (RSS) | mango 95 MB · waybar 66 MB · swaync 97 MB · polkit-kde 50 MB · wlsunset 3 MB |
| Higiene | zero pacote `hypr*` no sistema; nenhuma referência a Hyprland no repo |

## 4. Matriz comparativa por camada

| Camada | Omarchy 4 | Cadroc | Lacuna |
|---|---|---|---|
| Base | Arch + Hyprland | Arch + MangoWC | — |
| Instalação de pacotes | `pacman` + manifesto | `install.sh` + listas | OK |
| Deploy de configs | pacotes + `~/.config` | `deploy.sh` (cópia, com backup/`--pull`/`--prune`) | OK; falta modo "instalação limpa" testado |
| Shell | 1 processo Quickshell | Waybar+Fuzzel+SwayNC+swaylock/swayidle | funcional; menos "coeso" visualmente |
| Tema | `colors.toml` → templates | estado único → 13 renderizadores | **equivalente**; falta presets prontos |
| Temas prontos | 22 oficiais + hub | paleta derivada do wallpaper | falta catálogo de wallpapers/paletas |
| Launcher | integrado à shell | Fuzzel | OK |
| OSD de volume/brilho | integrado | não há OSD (usa notificação/teclas) | opcional |
| Lock/idle | integrados | swaylock/swayidle + scripts | OK |
| Tela de login | tema do SDDM próprio | `sddm-cadroc-theme` (projeto à parte) | integrar ao repo |
| Instalador/ISO | archiso + dual-boot + reset | não há | fora de escopo (cenário C) |
| Plugins | sistema + hub | não há | fora de escopo |
| IA/agentes | integrados | não | fora de escopo |
| Docs | manual completo | README extenso (13 KB) | falta manual + troubleshooting |
| Marca/comunidade | consolidada | Cadroc, 5 repos próprios no GitHub | tempo |

## 5. MangoWC × Hyprland para este projeto

**Onde o MangoWC ganha**

- Pegada e build: binário C, compila em segundos; sem processo de shell pesada.
- **Diferencial de workflow**: scrolling layout (horizontal/vertical) + tags com
  layout próprio — o Omarchy/Hyprland não entrega isso de fábrica. É a razão
  honesta para existir.
- Config em texto, previsível, com hot-reload; sem migração recente de gramática
  (Hyprland 0.56 mudou para Lua).
- Sem ABI de plugins, sem ecossistema em churn.

**Onde perde**

- Ecossistema: parte do tooling "de rice" assume Hyprland; aqui restou apenas
  trocar `hyprpicker` por `grim`+`slurp` (feito) e reescrever 3 scripts (feito).
- Portais: `xdg-desktop-portal-wlr` no lugar do portal do Hyprland — screen share
  precisa de teste real (Meet/Zoom/OBS).
- Recursos "adultos" menos provados: VRR, tearing, HDR, escala mista.
- QA é seu: cada release 0.17.x do compositor é risco assumido.

## 6. Riscos

| Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|
| Screen share falhar em app real | média | alto | testar Meet/Zoom/OBS via portal-wlr antes do anúncio |
| Hardware de terceiros (escala mista, VRR, HDR) | alta | médio | declarar suporte testado; parametrizar `monitor_rule` |
| Config hoje é pessoal (2 monitores específicos, `polkit-kde`, caminhos) | alta | alto | camada de variáveis + detecção no deploy |
| Arquivos gerados versionados (`colors-*.css/conf/ini`) geram drift | certa | médio | `.gitignore` + gerar no deploy |
| Manutenção solo (bus factor 1) | certa | médio | docs de decisão, CHANGELOG, testes em VM |
| Expectativa de "clone" | média | médio | README descreve o Cadroc pelo que ele é, sem citar a marca de origem |
| Marca | baixa | baixo | nome próprio já usado; o repo não cita nem usa marca de terceiros |

## 7. Custos (cenário B, revisados)

| Etapa | Estimativa |
|---|---|
| Gerados fora do git + deploy reproduzível | 2–3 dias |
| Portabilidade (monitores, fontes, paths, polkit, wallpapers padrão) | 1 semana |
| `PKGBUILD` do Cadroc (ou pacote `cadrocspace-git`) | 2–3 dias |
| Presets de tema + catálogo de wallpapers | 3–5 dias |
| Manual (instalação, atalhos, tema, troubleshooting) | 1 semana |
| Teste de instalação limpa (Arch VM) + screen share | 3–5 dias |
| **Total** | **~1–1,5 mês de trabalho esporádico** |

## 8. Recomendação

**GO para A → B**, com três condições:

1. **Não** perseguir paridade com a shell do Omarchy. O produto é "Arch + MangoWC
   opinativo, leve, com scrolling/tags" — não "Omarchy com outro nome".
2. **Portabilidade explícita**: o que é seu (monitores, wallpapers, fontes) vira
   variável/default; o resto vira instalação reproduzível em VM limpa.
3. **Deploy reprodutível**: nada gerado no git; `deploy.sh` gera o tema a partir
   do wallpaper/paleta, e `check.sh` valida.

**Licenciamento:** repo MIT (igual `cadrocfile`/`ruwall`); MangoWC é GPL-3.0 e
**não** é vendorizado nem forkado; nenhuma marca de terceiros em nome, logo,
domínio ou documentos públicos.

## 9. Perguntas em aberto (para decidir o escopo)

1. Público: uso próprio, dotfiles públicos (estado atual) ou "distro" com ISO?
2. Portabilidade: aceita generalizar (monitores/paths) ou publica "como está"?
3. Apetite: semanas (A) ou 1–1,5 mês (B)?
4. Entra um OSD de volume/brilho próprio ou fica como está?

## 10. Plano mínimo se GO (4 semanas)

| Semana | Entrega |
|---|---|
| 1 | gerados fora do git; `deploy.sh` regenera tema; `check.sh` no CI/local |
| 2 | portabilidade (variáveis de monitor/wallpaper/fonte) + `PKGBUILD` |
| 3 | presets de tema, wallpapers padrão, integração do `sddm-cadroc-theme` |
| 4 | manual + instalação limpa em VM + teste de screen share; release `v0.1` |

## 11. Evidências e fontes

- Omarchy: <https://omarchy.org> · manual, tema e versão 4 (Quattro, 2026-08-14)
- MangoWC: <https://github.com/mangowm/mango> · <https://mangowm.github.io/docs>
- Precedente de porte (Omarchy → Sway): <https://github.com/SimonSchubert/moarchy>
- `cadrocbar` (Quickshell/Hyprland, referência visual): <https://github.com/souandresouza/cadrocbar>
- `sddm-cadroc-theme`: <https://github.com/souandresouza/sddm-cadroc-theme>
- Medições locais de 2026-11-11: `mmsg get all-monitors`, `ps -eo rss,comm`,
  `deploy.sh --dry-run`, `check.sh`, teste do conta-gotas com pixel real
  (`#171a13` → `rgb(23,26,19)` → `hsv(86,27%,10%)`).
