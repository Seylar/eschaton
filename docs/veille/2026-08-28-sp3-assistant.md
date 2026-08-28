# Veille sous-projet 3 (Assistant IA) — passe datée du 2026-08-28

- **Objet** : confronter au réel les affirmations amont qui engagent le SP3 — [spec du Socle](../../../docs/superpowers/specs/2026-08-27-socle-design.md) §1 et §1.1 (« assistant IA omniprésent… agnostique du fournisseur »), [ADR 0001](../../../docs/decisions/0001-shell-du-bureau.md) §3.3 et §4 critère 1, [spec du Bureau](../../../docs/superpowers/specs/2026-08-28-bureau-design.md) §8 — conformément à l'[ADR 0002](../../../docs/decisions/0002-veille-avant-spec.md).
- **Date de la passe** : **2026-08-28**. Toute affirmation ci-dessous porte cette date sauf mention contraire.
- **Méthode** : API JSON `archlinux.org/packages/search/json/` ; **index de fichiers du miroir Arch Linux ARM** (`mirror.archlinuxarm.org/aarch64/{core,extra}/`, **13 187 paquets distincts** recensés ce jour — un `.pkg.tar.xz` présent *est* un paquet installable) ; RPC AUR v5 + lecture des `PKGBUILD` par `cgit` pour les champs `arch=()` et `source_*` ; **lecture du code source amont** (`gh api`) pour DankMaterialShell, Quickshell, Omarchy et end-4 ; API GitHub pour la santé des projets ; documentation upstream.
- **Limite assumée** : rien n'a été installé ni exécuté. Les constats de code sont des lectures de sources aux références indiquées (tag `v1.5.3` pour DMS quand la version d'`extra` est en jeu, `master`/`main` sinon, ce qui est signalé à chaque fois).
- **Rappel de cadrage** : la veille SP2 avait ordonné de **rejouer cette passe à l'ouverture du SP3** (SP2 §8 risque 8), le différenciateur étant « l'affirmation la plus volatile du projet ». C'est fait ici.

---

## 1. Synthèse — les affirmations amont face au réel

| # | Affirmation amont | Verdict | Constat (2026-08-28) | Source |
|---|---|---|---|---|
| 1 | **Spec Socle §1.2** : « un assistant IA omniprésent intégré au cœur du système, agnostique du fournisseur » est le **second différenciateur** d'Eschaton | **Nuancé — le créneau s'est déplacé, il n'a pas disparu** | Omarchy 4 livre **dix** agents CLI sélectionnables, un observateur de `systemd-coredump` qui confie le crash à l'agent, et un panneau de barre de suivi de quotas. Mais son assistant **est une fenêtre de terminal** (`omarchy-launch-tui --app-id=org.omarchy.agent`) : aucune surface graphique de conversation, aucun outil système structuré, **aucun MCP**. Ce qui reste vide : §2.4. | `basecamp/omarchy` `bin/omarchy-agent`, [manuel AI](https://omarchy.org/manual/ai/) |
| 2 | **Note de veille du 2026-08-27** (spec Socle §1) : Omarchy 4 pousse « suivi de consommation dans la barre, diagnostic de crash confié à l'agent » | **Confirmé, et les mécanismes sont maintenant connus** | Suivi : `omarchy agent usage-update` toutes les 900 s + plugin de barre first-party `shell/plugins/agents/` (`kinds:["bar-widget"]`, `category:"AI"`), sync multi-machines par dossier partagé. Crash : `journalctl -f -o json MESSAGE_ID=fc2e22bc…` → notification critique → `omarchy-agent-crash <pid>` → prompt + skill `diagnose-crash`. | `bin/omarchy-crash-watch`, `bin/omarchy-agent-crash`, `shell/plugins/agents/manifest.json` |
| 3 | **ADR 0001 §3.3** : « le modèle d'invocation de l'assistant » d'end-4 (sidebar multi-provider sur une keybind) est une **entrée directe** pour le SP3 | **Confirmé — et recyclable sans écrire une ligne de mécanique** | DMS livre le widget **`DankSlideout`** (présent **au tag `v1.5.3`**, celui d'`extra`) et l'IPC **`dms ipc call plugins toggle <id>`** qui appelle `instance.toggle()` sur une instance de plugin `daemon`. Un plugin tiers en production (`dms-ai-assistant` 1.7.0) fait exactement cela. La keybind Hyprland n'a plus qu'à appeler l'IPC. | `quickshell/Widgets/DankSlideout.qml@v1.5.3`, `quickshell/DMSShellIPC.qml`, `quickshell/Services/PluginService.qml` |
| 4 | **ADR 0001 §4 critère 1** : le passage au shell maison se déclenche si le modèle de plugins DMS bloque « l'assistant IA omniprésent, qui déborde d'un widget de barre » | **Infirmé pour cette raison-là** | Le débordement n'a pas lieu : un plugin `type:"daemon"` instancie `Variants { model: Quickshell.screens }` → `DankSlideout { slideoutWidth: 480; expandable: true; expandedWidthValue: 960 }`. La surface est un panneau plein écran latéral, par écran, pas un widget de barre. L'addendum du 2026-08-28 avait raison de l'affaiblir ; la veille SP3 le **clôt**. | `devnullvoid/dms-ai-assistant` `AIAssistantDaemon.qml` |
| 5 | **Spec Bureau §8** : « l'assistant naît plugin DMS (`composite` + permission `process`) » | **Nuancé sur les deux termes** | (a) Le type juste est **`daemon`**, pas `composite` : `composite` sert à déclarer plusieurs `components` par surface, alors que la sidebar est *une* surface daemon qui crée ses propres fenêtres. (b) **`permissions` n'est appliqué nulle part** : `PluginService.qml` le parse et le range (`info.permissions = perms.map(…)`) sans jamais le consulter ; `core/internal/plugins/manager.go` ne le mentionne pas. Le QML d'un plugin tourne avec **tous** les droits du processus DMS. « Permission `process` » est une étiquette, pas un bac à sable. | `PluginService.qml` l. 366-373, `manager.go` |
| 6 | **Spec Socle §1.1** : « Assistant omniprésent, provider-agnostique » (Claude, OpenAI, Ollama…) | **Confirmé sur le principe, nuancé sur le packaging** | Le dénominateur `/v1/chat/completions` est réel (Ollama, LM Studio, vLLM, `llama-server`, RamaLama). Anthropic a un endpoint OpenAI-compatible depuis mars 2026 — mais l'éditeur le déclare **non destiné à la production** et y **ignore le `strict` du function calling**. Côté paquets : `python-openai` et `python-mcp` sont `any` et **identiques sur les deux architectures** ; `python-anthropic` est **absent des deux**, `ollama` et `opencode` sont **absents d'ALARM**. §4. | §4.2, [OpenAI SDK compatibility](https://platform.claude.com/docs/en/api/openai-sdk) |
| 7 | **Spec Socle §1.1** : « Claude, OpenAI, Ollama…, au choix de l'utilisateur » — la liste des fournisseurs comme donnée stable | **Infirmé — la liste bouge sous nos pieds** | **Gemini CLI est mort le 2026-06-18** (arrêt de service pour les comptes gratuits/Pro/Ultra), remplacé par **Antigravity CLI**, binaire **Go closed-source**. `gemini-cli` a disparu de l'AUR ; `antigravity-cli` y est en `custom:proprietary`. Un fournisseur nommé dans une spec est une affirmation périssable. | [Google Developers Blog](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/) |
| 8 | **Veille SP2 §7.3** : « viser les types de plugin `daemon` et `composite` » | **Confirmé, précisé** | Les surfaces réellement reconnues par le code sont **quatre** : `pluginSurfaceKeys = ["widget","desktop","daemon","launcher"]`. Le champ **`capabilities` est de la métadonnée libre** — son unique usage dans le code est `capabilities.includes("launcher")`. Les valeurs `slideout`, `ai`, `agent` vues dans les manifestes du registre **ne changent rien au comportement**. | `PluginService.qml` l. 219, 299-303 |
| 9 | Implicite partout : le plugin système `/etc/xdg/…` est le mot final | **Infirmé — trou de substitution** | `shouldReplace = (!existing) \|\| (existing.source === "system" && sourceTag === "user")` : **un plugin utilisateur de même `id` remplace le plugin système**. Un `~/.config/DankMaterialShell/plugins/eschatonAssistant/` prendrait la place du nôtre, silencieusement. Bénin pour un badge de mises à jour ; pas pour un assistant qui manie `pkexec`. | `PluginService.qml` l. 386-390 |
| 10 | Le SP3 pourrait s'appuyer sur `Quickshell.Networking` pour ses appels HTTP (patron documenté par le skill amont de DMS) | **Infirmé — piège documenté** | `Quickshell.Networking` en 0.3.1 est **l'API NetworkManager** (14 types : `Networking`, `WifiDevice`, `NMSettings`, `WifiSecurityType`…). **Il n'existe aucun type `NetworkRequest` ni aucun client HTTP dans Quickshell.** Le fichier `.agents/skills/dms-plugin-dev/references/advanced-patterns.md` de DMS documente pourtant un `NetworkRequest { url: … }` : c'est faux. Le transport réel est `Process` + `curl` (ce que font end-4 **et** `dms-ai-assistant`). | [Quickshell.Networking v0.3.1](https://quickshell.org/docs/v0.3.1/types/Quickshell.Networking/), `DankMaterialShell/.agents/skills/…/advanced-patterns.md` |

**Conclusion de synthèse.** Aucun des trois documents amont n'est démenti sur le fond : le SP3 reste faisable **dans le modèle de plugins DMS**, et la sidebar-sur-keybind d'end-4 se recycle intégralement. Deux corrections sont dues : la spec Bureau §8 se trompe de type de plugin et surtout **surestime la portée du mot « permission »** ; la spec Socle §1 doit reformuler le différenciateur IA, qu'Omarchy a entamé sans le fermer. Deux découvertes changent le plan de packaging : **`ollama` n'existe pas sur ALARM** (§4.2), et **`RamaLama` si** (§4.4) — c'est la première fois qu'une brique d'inférence locale est disponible en `any` des deux côtés.

---

## 2. Axe 1 — Le paysage des assistants IA « OS-level »

### 2.1 Omarchy 4 « Quattro » (2026-08-14) — l'anatomie exacte

Lecture du dépôt `basecamp/omarchy` (32 946 étoiles, MIT, dernier push 2026-08-28).

**Ce qu'un utilisateur choisit.** `omarchy default agent <name>` ou menu `Super+Space` → *Setup > Defaults > Agent*. Dix agents sont câblés dans `bin/omarchy-agent` : `claude` (Claude Code), `codex`, `opencode`, `agy` (Antigravity CLI), `copilot`, `crush`, `grok`, `pi`, `omp` (Oh My Pi), `ori` (harness OpenRouter). Rien n'est installé tant que l'agent n'est pas utilisé : ce sont des **lanceurs paresseux dans `~/.local/bin/`, gérés par `mise`** (`omarchy-mise-install <paquet> [commande]`). Omarchy ne package donc **aucun** agent : il délègue à un gestionnaire de versions tiers, hors pacman. *(C'est exactement le contre-modèle du principe « fat packages » de la spec Socle §3 — à ne pas reprendre.)*

**Comment il est invoqué.** Keybind `Super + Shift + Ctrl + A` → `omarchy-agent` → `exec omarchy-launch-tui --app-id=org.omarchy.agent "${command[@]}"`. **L'assistant d'Omarchy est une fenêtre de terminal**, pas une surface du shell. Le seul élément graphique natif est le panneau de quotas (§2.1 suite). Il existe aussi `omarchy agent prompt "…"` (un tour non surveillé) et les alias `a`, `c`, `cx`, `cy`.

**Le cadrage de sécurité — et c'est le constat le plus lourd de cet axe.** Chaque agent est lancé **en mode auto-approuvant**, littéralement :

| Agent | Drapeau posé par `omarchy-agent` |
|---|---|
| `claude` | `--permission-mode auto` |
| `codex` | `--approve-for-me` |
| `opencode` | `--auto` |
| `agy` | `--dangerously-skip-permissions` |
| `grok` | `--permission-mode bypassPermissions` |
| `copilot` | `--allow-all` |
| `crush` | `--yolo` (interactif) |
| `omp` | `--auto-approve` |

Commentaire du code : *« Agents launched from the keybinding or menu run unattended, so each one starts with its own spelling of "don't stop to ask". »* Le seul garde-fou est un changement de répertoire (`[[ $PWD == "$HOME" && -d $HOME/Work ]] && cd "$HOME/Work"`), motivé non par la sécurité mais par le fait que « les agents refusent de mémoriser la confiance pour `$HOME` ». **Omarchy n'a donc pas de modèle de sécurité pour son agent : il a un modèle de commodité.** Les seules limites sont des phrases dans un skill (voir plus bas) — c'est-à-dire des consignes, pas des contrôles.

**Le diagnostic de crash.** `bin/omarchy-crash-watch` est un service utilisateur qui suit `journalctl -f -n 0 -o json "MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1"` (l'identifiant `systemd-coredump`). Il filtre sur `_UID == $UID` (« un démon qui *dump* est un problème d'administrateur »), déduplique par programme sur 60 s, se garde de s'annoncer lui-même, et durcit le nom du processus (`comm` est contrôlé par le processus qui plante — le code le réduit à un composant de chemin pour qu'un nom hostile ne devienne pas un chemin). La notification est émise **avec les détails passés en `argv` discrets**, explicitement *« so a hostile process name can't be reparsed as a command »*. Le clic exécute `omarchy-agent-crash <pid> <comm> <exe> <signal>`, qui compose un prompt et fait `exec omarchy-agent --prompt "$prompt"`. Bascule : `omarchy toggle crash-capture`.

> **Ce qu'Eschaton doit retenir de ce fichier** : c'est la meilleure démonstration publique qu'un « déclencheur système → assistant » se conçoit comme une **frontière d'injection**. Les données du système (nom de processus, chemin) sont hostiles par défaut et ne doivent jamais redevenir des commandes. Ce raisonnement manque partout ailleurs dans le paysage.

**Le suivi de consommation.** `bin/omarchy-agent-usage-{claude,codex,fireworks}` + `omarchy-agent-usage-update` régénèrent des enregistrements toutes les 900 s ; le rendu est un **plugin de barre first-party** (`shell/plugins/agents/{manifest.json,Panel.qml,Agent.qml,Main.qml}`, `kinds:["bar-widget"]`, `activation:"on-demand"`, `category:"AI"`), avec agrégation multi-machines par dossier synchronisé (Syncthing/Dropbox/rsync). Couverture annoncée : Claude Code, Codex, Fireworks.

**Les skills.** `default/agents/skills/` contient exactement **deux** skills : `omarchy` et `diagnose-crash`, symlinkés vers `~/.claude/skills`, `~/.codex/skills`, `~/.pi/agent/skills`, `~/.gemini/config/skills` et `~/.agents/skills`. Le skill `omarchy` est la surface « outils système » d'Omarchy — et c'est **du texte** : *« For end-user customization tasks, NEVER modify anything in `/usr/share/omarchy/` »*, plus une section « Privilege Escalation » qui dit d'utiliser `sudo` quand un terminal est disponible et `pkexec` sinon, et note qu'*« Omarchy may grant passwordless sudo access to particular commands »*. Aucune de ces règles n'est appliquée par le système. Le manuel qualifie lui-même le skill d'**expérimental** et recommande le mode plan, avec `omarchy reinstall configs` comme filet.

**Ce qu'Omarchy n'a pas.** Recherche de code sur tout le dépôt : **aucun MCP** (deux occurrences, toutes deux fortuites — `oomd.conf` et `omarchy-disk-speedtest`). Aucun serveur d'outils, aucun schéma de fonctions, aucun démon d'assistant. Le menu *Install > AI* pose des applications (`omarchy-{install,remove}-ai-*` : `chatgpt`, `grok-bot`, `lm-studio`, `ollama`, `t3-code`), pas une intégration.

### 2.2 Les agents CLI dominants et leur packaging bi-architecture

| Agent | Dépôt / statut | Arch officiel | AUR | `arch=()` du PKGBUILD | Remarque |
|---|---|---|---|---|---|
| **opencode** | `anomalyco/opencode`, **202 105 ★**, MIT, push 2026-08-28 | **`extra/opencode 1.18.23-1`** *(x86_64)*, 2026-08-25 | `opencode-bin 1.18.25-1`, 50 votes, mainteneur **`thdxr` (upstream)** | `('aarch64' 'x86_64')` | **Absent d'ALARM aarch64.** Le paquet officiel ne couvre qu'une architecture ; l'AUR couvre les deux. |
| **Claude Code** | `anthropics/claude-code`, 143 267 ★, push 2026-08-28 | absent | `claude-code 2.1.250-1`, 91 votes, pop. **12,30**, maj 2026-08-28 | `('x86_64' 'aarch64')`, `source_x86_64` / `source_aarch64` chez `downloads.claude.ai` | Licence `LicenseRef-claude-code` (**propriétaire**). Binaire natif, `depends=('bash')` seulement. |
| **Codex CLI** | `openai/codex`, 119 471 ★, Apache-2.0 | absent | `openai-codex-bin 0.150.1-1`, 26 votes, maj 2026-08-27 | `('x86_64' 'aarch64')` | Réécrit en Rust ; binaires amont pour les deux architectures. |
| **Antigravity CLI** | Google, **closed-source** | absent | `antigravity-cli 1.1.22_…`, 25 votes | `('x86_64' 'aarch64')` | `license=('custom:proprietary')`. **Remplace Gemini CLI**, retiré le 2026-06-18. |
| **Crush** | Charm | absent | `crush-bin 0.91.2-1`, 3 votes, mainteneur `caarlos0` | `('x86_64' 'aarch64')` *(déduit)* | Licence **FSL-1.1-MIT** (source-available à conversion différée). |
| **aider** | — | absent | `aider-chat 0.86.2-2`, **6 votes**, dernière maj **2026-03-16** | `any` | **Cinq mois sans maj.** À écarter. |
| **Gemini CLI** | **mort** | — | **absent de l'AUR** | — | Service coupé le **2026-06-18** pour gratuit/Pro/Ultra. |

**Trois lectures.**
1. **L'AUR est le seul chemin bi-architecture pour tous les agents CLI**, et il est de qualité inégale : `opencode-bin` est maintenu par l'upstream lui-même, `aider-chat` est à l'abandon relatif. Aucun de ces paquets n'est un `depends` acceptable pour `eschaton-ai` (la veille SP2 §7.2 interdit déjà de dépendre de l'AUR, absent d'ALARM et hors chemin nominal).
2. **`extra/opencode` est le seul agent en dépôt officiel** — et il est x86_64 uniquement, donc **inutilisable sur le banc d'essai aarch64**. Une architecture SP3 qui en dépendrait ne serait pas testable au quotidien.
3. **Le paysage des fournisseurs est instable à l'échelle du trimestre.** Un projet à 105 000 étoiles a été supprimé et remplacé par un binaire fermé en deux mois. Toute liste de fournisseurs écrite dans une spec Eschaton doit être **une donnée de configuration, pas une décision d'architecture**.

### 2.3 Les intégrations desktop existantes

| Environnement | État de l'IA « first-party » | Ce qui existe en pratique |
|---|---|---|
| **GNOME** | **Rien d'officiel.** | **Newelle** (`qwersyk/Newelle`, 1 450 ★, GPL-3.0, push 2026-08-25) — assistant tiers aligné GNOME : multi-fournisseurs (OpenAI, Gemini, Groq, LLM locaux, llama.cpp), système d'extensions, **outil d'exécution de commandes**, génération d'images. Packagé **AUR seul** (`newelle 1.4.5-1`, 4 votes, popularité 0,03). |
| **KDE Plasma** | **Rien d'officiel** (pas d'annonce KRunner-IA). | Plasmoïdes tiers : `Gemini-Kchat`, `novik133/jarvis` (llama.cpp + whisper.cpp + Piper, C++/QML). |
| **COSMIC** | **Rien d'officiel.** | Applet communautaire (`cosmic-utils`) de chat avec streaming et bascule de modèle. |
| **Wayland générique** | — | **`scottstav/aside`** (60 ★, MIT, créé 2026-02-27, dernier push 2026-07-28) : overlay GTK4 **layer-shell**, streaming, historique, **outils personnalisés**, STT/TTS optionnels. Le projet le plus proche conceptuellement — et un projet à un seul contributeur, quasi inconnu. |
| **Omarchy 4** | **Oui, et c'est le seul.** | §2.1 — mais l'assistant y est une fenêtre de terminal. |

### 2.4 Le différenciateur tient-il ? Ce qui reste réellement vide

**Le différenciateur brut « assistant IA intégré » ne tient plus** (Omarchy 4 l'a pris le 2026-08-14, la note de veille du 2026-08-27 l'avait déjà acté). Ce qui n'existe nulle part au 2026-08-28, en revanche, tient en trois points :

1. **Une surface graphique de conversation intégrée au shell *qui pilote le système*.** Les deux moitiés existent séparément : des sidebars graphiques qui ne touchent qu'à la configuration du shell (end-4 : `get_shell_config` / `set_shell_config` ; `dms-ai-assistant` : chat pur, aucun outil), et des agents CLI tout-puissants dans une fenêtre de terminal (Omarchy). **Personne n'a relié les deux.** `Francisdelca/dms-agent` a essayé — « floating chat panel for controlling your desktop with natural language » — et le dépôt est **né et mort le même jour (2026-04-07)**, 5 étoiles.
2. **Un catalogue d'outils système *déclaré, borné et audité*.** Omarchy donne l'ensemble du système à un agent en mode bypass et écrit les limites dans un fichier Markdown. Personne n'expose au modèle une liste **fermée** d'opérations (mettre à jour, lister/restaurer un snapshot, lire l'état du matériel) adossées à des exécutables packagés et à des actions polkit. **C'est exactement la matière que le SP1 et le SP2 ont déjà produite** (§5.3).
3. **Le lien avec le rollback.** Le créneau reformulé par la veille SP2 — « le rollback et l'administration système comme fonctions natives et unifiées du shell » — devient beaucoup plus fort avec un assistant : *un assistant qui peut casser le système et un système qui sait revenir en arrière depuis le même shell* est une combinaison que personne n'offre. C'est la formulation défendable du différenciateur au 2026-08-28.

---

## 3. Axe 2 — DMS côté IA

### 3.1 First-party : rien. Registre : beaucoup, et de faible qualité

**Les 12 plugins first-party (`AvengeMedia/dms-plugins`, 80 ★, MIT, push 2026-08-27)** sont : `DankActions`, `DankBatteryAlerts`, `DankClight`, `DankDesktopWeather`, `DankGifSearch`, `DankHooks`, `DankHyprlandWindows`, `DankKDEConnect`, `DankLauncherKeys`, `DankNotepadModule`, `DankPomodoroTimer`, `DankStickerSearch`. **Aucun n'est un plugin IA.**

**DMS lui-même n'a aucune IA.** Recherche de code sur le dépôt : `anthropic` → 2 fichiers (`.agents/skills/…/advanced-patterns.md` et `.github/workflows/claude-review.yml`) ; `openai` → 2 fichiers (les mêmes `.agents/skills/`) ; `ollama` → 1 fichier (une traduction espagnole). **Le terrain est libre côté amont.**

**Le registre `dms-plugin-registry` (88 ★, push 2026-08-28) contient 329 plugins**, dont une quinzaine touchent à l'IA, en quatre familles :

| Famille | Plugins | Enseignement |
|---|---|---|
| **Chat multi-fournisseurs** | `devnullvoid-ai-assistant` (« AI Assistant » 1.7.0, `type:"daemon"`, MIT, **22 ★**, dernier push 2026-07-20) ; `ss44-sathi-ai` (11 ★) ; `huangkaile22-prog-dank-hermes` (1 ★, poussé une seule fois) | Le patron est établi et fonctionne ; aucun n'a d'outils système. |
| **Assistant agentique** | **`francisdelca-dms-agent`** — « AI desktop assistant powered by Claude Code… open apps, switch windows, play music, search the web ». `plugin.json` : `type:"widget"`, `capabilities:["slideout","ai","agent"]`, `requires:["bash","curl","xdg-open","notify-send","claude"]`, `permissions:["settings_read","settings_write"]`. **5 ★, créé ET dernier push le 2026-04-07.** | **La preuve que l'idée est déjà tentée, et la preuve qu'elle n'a pas pris.** Noter : il déclare `claude` en `requires` (métadonnée informelle) et n'a **pas** demandé `process` — parce que ça ne sert à rien (§3.3). |
| **Quotas** | `agneswd-ai-quotas` (Claude, Codex, OpenCode, Antigravity, DeepSeek, Grok), `bogdan-velicu-claude-usage`, `titeya-claudecodeusage`, `zakstam-codexbar`, `feikowielsma-antigravity-usage` | **Cinq plugins concurrents** pour la fonction qu'Omarchy a mise en first-party. Marché saturé, faible valeur pour Eschaton. |
| **Voix / traduction** | `arqueon-dms-whisper`, `dwright134-whisperer`, `lucianosrp-hyprwhspr-voice-overlay`, `sakuratoerii-dank-translate-ai` | Périphérique. `dank-translate-ai` est notable pour son cadrage : « security-focused, one-shot input reads, local secret screening ». |

**Y a-t-il un plugin `launcher` avec `trigger` qui ferait palette d'invocation ?** Oui, deux, et ce sont des modèles directs : `devnullvoid-command-runner` (`capabilities:["launcher"]` — exécute des commandes shell depuis le launcher, avec historique et modes terminal/arrière-plan) et `devnullvoid-web-search` (23 moteurs, sélection par mot-clé). Le mécanisme `trigger` (préfixe dans le spotlight) est donc éprouvé — mais il est **complémentaire**, pas alternatif, à la sidebar : c'est la surface « une question courte » quand la sidebar est la surface « une conversation ».

### 3.2 Le mécanisme réel, lu dans le code

C'est le cœur de la veille. Quatre constats, tous vérifiés dans les sources.

**(a) Il y a quatre surfaces, et `capabilities` n'en fait pas partie.**
```
readonly property var pluginSurfaceKeys: ["widget", "desktop", "daemon", "launcher"]
```
`_deriveLegacySurface(type, capabilities)` n'utilise `capabilities` que pour un cas : `capabilities.includes("launcher")`. Les valeurs `slideout`, `ai`, `agent`, `ai-chat`, `ipc` observées dans les manifestes du registre sont **de la documentation, pas du comportement**. Un `composite` est simplement un manifeste qui déclare `components: {surface: fichier}` au lieu d'un `component` unique.

**(b) La sidebar de l'assistant est un plugin `daemon` qui crée ses propres fenêtres.** `dms-ai-assistant` (en production, MIT) :
```qml
type: "daemon"  →  AIAssistantDaemon.qml
    function toggle() { variants.instances[0].toggle() }
    AIAssistantService { id: aiLogic }        // logique globale, une seule instance
    Variants { model: Quickshell.screens
        delegate: DankSlideout { slideoutWidth: 480; expandable: true; expandedWidthValue: 960 } }
```
`DankSlideout` est un widget **de DMS** (`qs.Widgets`), présent **au tag `v1.5.3`**, la version d'`extra` — pas seulement sur `master`. Aucun besoin de réimplémenter la mécanique de panneau.

**(c) L'invocation par keybind existe nativement.** `DMSShellIPC.qml` expose un groupe `plugins` dont la fonction `toggle` appelle `PluginService.togglePlugin(pluginId)` :
```
const instance = launcherInstance || pluginDaemonInstances[pluginId];
if (!instance || typeof instance.toggle !== "function") return false;
instance.toggle();
```
Donc : `bind = SUPER, A, exec, dms ipc call plugins toggle eschatonAssistant` dans `dms/binds-user.lua` **est** le « modèle d'invocation de l'assistant » de l'ADR 0001 §3.3, obtenu sans une ligne de mécanique. *(Le plugin doit exposer une fonction `toggle()` sur la racine de sa surface `daemon` — c'est le seul contrat.)*

**(d) Les permissions ne sont pas des permissions.** Le mot `permission` apparaît **deux fois** dans `PluginService.qml` (l. 366 et 373) : lecture du manifeste, normalisation en tableau de chaînes, rangement dans `info.permissions`. **Aucun autre usage, nulle part.** `core/internal/plugins/manager.go` ne les mentionne pas du tout. Concrètement : un plugin QML peut instancier `Quickshell.Io.Process` et exécuter n'importe quoi avec les droits de l'utilisateur, qu'il déclare `process` ou non. Le manifeste de `dms-agent` le confirme par l'absurde — il pilote le bureau via `bash`/`claude` en ne déclarant que `settings_read`/`settings_write`.

> **Conséquence directe pour la spec Bureau §8** : la formule « plugin DMS (`composite` + permission `process`) » doit être corrigée en « plugin DMS `daemon` — étant entendu que **le modèle de plugins DMS n'offre aucun confinement** : toute limite réelle doit venir de l'extérieur (polkit, interface d'outil fermée, sandbox), jamais du manifeste ».

**(e) Un plugin utilisateur écrase le plugin système de même `id`.** `shouldReplace = (!existing) || (existing && existing.source === "system" && sourceTag === "user")`. Le sens amont est légitime (permettre à l'utilisateur de surcharger un plugin livré par la distribution) ; l'effet de bord pour Eschaton est qu'un répertoire déposé dans `~/.config/DankMaterialShell/plugins/eschatonAssistant/` **prend la place** du plugin possédé par pacman, sans avertissement autre qu'une ligne de log. Ce n'est pas une élévation de privilèges (le code s'exécutait déjà comme l'utilisateur) mais c'est une **rupture d'intégrité de la chaîne « ce que pacman a posé est ce qui tourne »**, qui vaut d'être écrite plutôt que découverte.

### 3.3 end-4 : ce qui se recycle réellement (ADR 0001 §3.3)

Lecture de `dots/.config/quickshell/ii/services/Ai.qml` (**917 lignes**) et de `services/ai/{ApiStrategy,GeminiApiStrategy,OpenAiApiStrategy,MistralApiStrategy}.qml`.

| Élément | Ce que fait end-4 | Verdict de recyclage |
|---|---|---|
| **Abstraction de fournisseurs** | Patron **Strategy indexé par `api_format`** (`"openai"` \| `"gemini"` \| `"mistral"`), chaque modèle déclarant `endpoint`, `model`, `key_id`, `requires_key`, `api_format`. | **À reprendre tel quel.** C'est la bonne granularité : on n'abstrait pas « le fournisseur » mais **le format de fil**, ce qui rend `openai` mutualisable entre OpenAI, Ollama, vLLM, LM Studio, RamaLama et l'endpoint compatible d'Anthropic. |
| **Transport** | `Process` exécutant `bash` + **`curl`** en streaming ; le corps et les en-têtes sont construits par la stratégie. | **À reprendre** — c'est aussi ce que fait `dms-ai-assistant`, et il n'y a pas d'alternative (§1 ligne 10 : Quickshell n'a pas de client HTTP). |
| **Secret** | La clé passe par **une variable d'environnement du processus** (`requester.environment[apiKeyEnvVarName]`), jamais sur la ligne de commande. Stockage via `services/KeyringStorage.qml` → **`secret-tool store`** (libsecret / Secret Service), un blob JSON sous le label « *illogical-impulse Safe Storage* ». | **À reprendre, et c'est la meilleure trouvaille de cet axe.** `libsecret 0.21.7-1` est en `core` sur **les deux** architectures, `gnome-keyring 50.0` et `keepassxc 2.7.12-4` en `extra` sur les deux. Aucune clé en clair dans un fichier de configuration. |
| **Modèles locaux** | Découverte des modèles Ollama par script, endpoint `http://localhost:11434/v1/chat/completions`. | À reprendre comme *forme*, mais pas la dépendance (§4.2 : pas d'Ollama sur ALARM). |
| **Outils (function calling)** | Trois fonctions : `switch_to_search_mode`, `get_shell_config`, `set_shell_config`. **La cible est la configuration du shell, jamais le système.** Et l'upstream écrit : *« For now functions only work with Gemini API format »*. | **La leçon est négative et utile** : celui qui a le plus d'avance sur l'IA dans un shell Quickshell **n'a pas franchi la ligne des outils système** et n'a pas réussi à rendre son *function calling* portable entre formats. L'ADR 0001 §3.3 avait raison de ne prendre que « le modèle d'invocation ». |
| **Politique** | `Config.options.policies.ai === 2` ⇒ modèles en ligne refusés, seul `localhost` passe, avec message explicite à l'utilisateur. | **À reprendre**. Précédent direct pour un mode « local seul », qui est aussi le mode « hors ligne » et le mode « données sensibles ». |

---

## 4. Axe 3 — La couche provider-agnostique

### 4.1 Le dénominateur : `/v1/chat/completions`

- **Serveurs locaux** : Ollama (`:11434`), LM Studio (`:1234`), vLLM, `llama-server` de llama.cpp et **RamaLama** (`:8080`/`:8000`) exposent tous des routes OpenAI. Réserve documentée : la couche de compatibilité d'Ollama **omet `logprobs`, `tool_choice` et `logit_bias`** — `tool_choice` est celui qui compte pour un assistant à outils.
- **Anthropic** : endpoint OpenAI-compatible depuis **mars 2026**. L'éditeur le présente comme destiné à **tester et comparer**, *« not considered a long-term or production-ready solution »*, avec deux limites qui touchent directement le SP3 : le paramètre **`strict` du function calling est ignoré** (le JSON d'appel d'outil n'est pas garanti conforme au schéma) et la température est plafonnée à 1.0. **Pour un appel d'outil fiable, il faut le format natif `/v1/messages`.**
- **Conclusion de format** : « OpenAI-compatible » suffit pour la **conversation**, pas pour les **outils**. Une couche à deux formats (`openai` + `anthropic`) est le minimum honnête — exactement le découpage d'end-4, moins `gemini` (mort côté CLI, vivant côté API mais c'est un troisième format).

### 4.2 Ce qui est packagé — des deux côtés

Vérifié le 2026-08-28 : API JSON Arch + index miroir ALARM aarch64.

| Brique | Arch officiel | ALARM aarch64 | Verdict |
|---|---|---|---|
| `python-openai` | `extra 2.53.0-1` **any** (2026-08-04) | `2.53.0-1` **any** (04-Aug-2026 15:14) | **Identique.** Le SDK de référence est disponible sans effort. |
| `python-mcp` | `extra 1.29.0-1` **any** (2026-07-28) | `1.29.0-1` **any** (29-Jul-2026) | **Identique — mais une majeure en retard.** L'amont a publié `v2.0.0` **le même jour** (2026-07-28) et en est à `v2.1.1` (2026-08-25). `extra` package la fin de la ligne 1.x. |
| `python-httpx` | `extra 0.28.1-7` any | identique | ok |
| `python-httpx-sse` | `extra 0.4.3-1` any | identique | ok — streaming SSE |
| `python-pydantic` | `extra` any | `2.13.4-1` any | ok |
| `python-tiktoken` | `extra 0.14.0-1` | `0.14.0-1` aarch64 | ok |
| `python-langchain` / `python-langchain-openai` | `extra 1.3.18-1` / `1.6.0-1` any | identiques | Disponibles ; **largement surdimensionnés** pour un démon système. |
| `python-keyring` | `extra 25.7.0-3` any | identique | ok |
| `libsecret` | `core 0.21.7-1` | `core 0.21.7-1` | ok |
| `gnome-keyring` / `keepassxc` | `extra 50.0-1` / `2.7.12-4` | identiques | ok (fournisseur Secret Service) |
| `bubblewrap` | `extra 0.12.0-1` | `0.12.0-1` | ok (bac à sable, si besoin) |
| `podman` | `extra 6.1.0-1` | `6.1.0-1` | ok |
| **`ramalama`** | **`extra 0.24.0-1` any** | **`0.24.0-1` any** (21-Aug-2026) | **Identique — voir §4.4.** |
| `nodejs` / `npm` | `extra 26.8.1-1` / `12.0.2-1` | identiques | ok |
| `uv` | `extra 0.12.7-1` | `0.12.6-1` | ~identique |
| **`python-anthropic`** | **absent** | **absent** | **AUR seul** : `0.107.1-1`, 4 votes, **marqué périmé depuis le 2026-07-29**. |
| **`ollama`** | `extra 0.32.15-1` **x86_64** | **absent** | **Asymétrie majeure.** AUR `ollama-bin 0.33.1-1` couvre les deux (`source_aarch64` chez l'upstream). |
| **`opencode`** | `extra 1.18.23-1` **x86_64** | **absent** | AUR `opencode-bin` couvre les deux. |
| `litellm` | absent | absent | AUR `1.98.0-1`, 7 votes, `arch=(any)`. |
| `llama.cpp` | absent | absent | — |
| `whisper.cpp` | absent | absent | — (la voix est hors périmètre v1 de toute façon) |

### 4.3 Verdict : « provider-agnostique sans vendoring », c'est possible — à condition de ne pas passer par Python

Trois chemins, trois verdicts.

1. **Tout en QML (le plugin appelle `curl` par `Process`)** — **aucun vendoring, aucune dépendance nouvelle sur aucune des deux architectures.** `curl` est en `core`, `Process` est dans Quickshell, `secret-tool` vient de `libsecret` (`core`). C'est ce que font end-4 et `dms-ai-assistant`. **Le choix « agnostique » de la spec Socle est réaliste par ce chemin, et seulement de façon confortable par ce chemin.**
2. **Un démon Python avec les SDK officiels** — `python-openai` est identique des deux côtés, donc l'axe OpenAI-compatible (incluant Ollama/vLLM/LM Studio/RamaLama et l'endpoint de compatibilité d'Anthropic) passe **sans vendoring**. Mais l'axe **Anthropic natif** — celui qui donne le *function calling* fiable — **exige de vendorer `python-anthropic`** (absent des deux dépôts, AUR périmé), ou d'écrire l'adaptateur `/v1/messages` à la main sur `httpx` (~200 lignes, zéro dépendance nouvelle, `python-httpx` et `python-httpx-sse` étant identiques des deux côtés). **Le second sous-chemin est clairement préférable au vendoring.**
3. **Une passerelle type LiteLLM** — `litellm` n'est ni dans Arch ni dans ALARM ; c'est un projet de 57 478 étoiles, très actif, mais **licence `NOASSERTION`** au sens de GitHub et un objet lourd (proxy, cost tracking, guardrails, load balancing) pour un poste de travail. **Vendoring obligatoire, pour un besoin qu'on n'a pas.** À écarter.

**Formulation défendable au 2026-08-28** : *le provider-agnostisme sans vendoring est acquis pour la conversation, et acquis pour les outils au prix d'un adaptateur Anthropic maison d'environ deux cents lignes. Il ne l'est pas si l'on décide de dépendre d'un SDK Anthropic packagé ou d'une passerelle.*

### 4.4 Le cas Ollama — et pourquoi RamaLama change la donne

La spec Socle nomme Ollama comme exemple de fournisseur local. Or **`ollama` n'existe pas sur ALARM aarch64** (index vérifié : aucune entrée `ollama*` dans `core` ni `extra`, sur 13 187 paquets) alors qu'il est dans `extra` x86_64 en `0.32.15-1`. Sur le banc d'essai quotidien, la pile locale d'Ollama n'est donc atteignable que par l'AUR (`ollama-bin`, 9 votes) — c'est-à-dire hors chemin nominal, et interdit par la doctrine de packaging héritée du SP2.

**`ramalama` est en `extra`, `arch=any`, en `0.24.0-1` sur les deux architectures** (ALARM : 21-Aug-2026). C'est le projet Red Hat qui exécute des modèles dans des conteneurs OCI via **Podman** (`6.1.0-1` des deux côtés) au-dessus de llama.cpp ou vLLM, et qui **sert une API OpenAI-compatible** (`ramalama serve` → `/v1/`). C'est, au 2026-08-28, **la seule brique d'inférence locale disponible en dépôt officiel sur les deux architectures d'Eschaton**.

> Conséquence : la spec SP3 ne doit **pas** faire d'Ollama une dépendance. Elle doit décrire un **fournisseur local = une URL de base OpenAI-compatible** (défaut raisonnable : `http://localhost:11434/v1` pour Ollama s'il est là, `http://localhost:8080/v1` pour RamaLama), et si un paquet doit être recommandé en `optdepends`, c'est **`ramalama`**, pas `ollama`.

---

## 5. Axe 4 — Le mécanisme « outils système » (la partie dangereuse)

### 5.1 Les trois familles observées, et ce qu'elles coûtent

| Famille | Qui l'utilise | Ce que l'assistant peut faire | Ce qui le borne | Coût |
|---|---|---|---|---|
| **A — Agent CLI en sous-processus** | **Omarchy 4** (les 10 agents), `Francisdelca/dms-agent` (Claude Code) | **Tout ce que l'utilisateur peut faire.** Lecture/écriture de fichiers, `sudo`, `pkexec`, réseau. | **Rien de technique.** Un skill en Markdown, et les drapeaux d'auto-approbation retirent même le garde-fou intégré de l'agent. | Aucun développement. Sécurité : nulle. Dépendance : un binaire hors dépôts officiels (§2.2). |
| **B — Function calling maison** | **end-4** (3 fonctions), la majorité des plugins de chat | **Exactement ce qu'on a écrit.** end-4 s'arrête à la configuration du shell. | La liste des fonctions **est** la frontière. Fermée par construction. | Le catalogue s'écrit à la main, et ne se transporte pas entre formats d'API (end-4 : « for now functions only work with Gemini API format »). |
| **C — MCP** | **Personne dans ce paysage.** Ni Omarchy, ni DMS, ni end-4, ni aucun des 329 plugins du registre. | Ce qu'exposent les serveurs branchés. | La configuration de l'hôte MCP + ce que le serveur autorise. | Un protocole, des transports, une autorisation — pour un besoin mono-machine, mono-utilisateur. |

### 5.2 MCP en 2026 — mûr, mais dimensionné pour autre chose

La révision **2026-07-28** de la spécification est *« la plus importante depuis le lancement »* : cœur **sans état** (la session et la poignée de main d'initialisation disparaissent), transports normalisés à **stdio** et **Streamable HTTP**, extensions **MCP Apps** (UI rendue par le serveur) et **Tasks** (travaux longs), autorisation alignée sur OAuth/OIDC, politique de dépréciation formelle. La gouvernance a quitté Anthropic : l'écosystème est hébergé par l'**Agentic AI Foundation** de la Linux Foundation. Les quatre SDK de premier rang parlent la révision.

Côté paquets : **`python-mcp` est dans `extra` en `any`, identique sur les deux architectures** — c'est la seule brique de la couche IA qui soit à la fois officielle et bi-architecture. Réserve : `extra` en est à **1.29.0**, l'amont à **2.1.1** ; la ligne 2.x, publiée le jour de la spec 2026-07-28, n'est pas packagée. Aucun **serveur** MCP n'est packagé dans Arch ni dans ALARM ; les serveurs d'administration Arch existants sont des projets individuels (`nihalxkumar/arch-mcp`, 55 ★, GPL-3.0, **dernier push 2026-03-10** — 5 mois).

**Lecture pour le SP3.** MCP résout un problème qu'Eschaton n'a pas encore : faire découvrir des outils **par des hôtes tiers**. Pour un assistant intégré qui appelle ses propres outils dans son propre processus, c'est une indirection sans contrepartie immédiate. Mais c'est le format dans lequel un catalogue d'outils **doit être décrit** si l'on veut, plus tard, que Claude Code ou Codex lancés dans un terminal Eschaton voient les mêmes outils que la sidebar. **Recommandation : concevoir le catalogue d'outils avec des schémas JSON compatibles MCP, et différer le serveur MCP lui-même.**

### 5.3 Les surfaces qu'Eschaton a déjà — le catalogue d'outils v1 est écrit

Le SP1 et le SP2 ont produit, sans le chercher, exactement la matière d'un catalogue d'outils borné. Tout ce qui suit existe et est packagé au 2026-08-28.

| Surface | Nature | Élévation | Devient l'outil |
|---|---|---|---|
| `checkupdates` (`pacman-contrib 1.13.1-1`, **les deux architectures**) | lecture | aucune | `list_pending_updates` |
| `/usr/bin/eschaton-update` (`eschaton-base`) | écriture | `sudo pacman -Syu` — **mot de passe demandé** (aucun `NOPASSWD` livré) ; snapshot pre/post automatique par `snap-pac` ; détecte le changement de kernel | `apply_updates` |
| `snapper --config root list --jsonout` | lecture | aucune — `ALLOW_GROUPS=wheel` dans la config Snapper livrée | `list_snapshots` |
| `/usr/bin/eschaton-rollback --yes <N>` | **écriture destructive** | `pkexec` + action polkit `org.eschaton.rollback`, `<defaults>` `no`/`no`/**`auth_admin`** sans `_keep` → **authentification à chaque appel**, via la modale de l'agent polkit de DMS. Refuse toute forme non interactive autre que `--yes N`. | `restore_snapshot` |
| `dgop` (`extra 0.2.3-1`, les deux architectures, déjà tiré par `dms-shell`) | lecture | aucune | `system_metrics` |
| `dms ipc call …` | écriture (bureau) | aucune | `set_wallpaper`, `set_theme`, `toggle_plugin`… |
| `journalctl` / `systemd-coredump` | lecture | l'utilisateur voit ses propres unités | `read_logs`, et le déclencheur « diagnostiquer ce crash » (précédent Omarchy §2.1) |

**Ce que cette table démontre** : Eschaton peut livrer un assistant à outils système **sans écrire un seul nouveau chemin privilégié**. Les deux opérations dangereuses passent déjà par des portes construites, revues et prouvées en VM — l'une demande un mot de passe `sudo`, l'autre une authentification polkit sans mémorisation. **Le catalogue d'outils v1 est la liste ci-dessus, et rien d'autre.**

### 5.4 Les précédents de sécurité — ce qu'il faut refuser

1. **Omarchy est un contre-modèle assumé sur ce point** (§2.1) : dix agents lancés en mode « ne demande jamais », des limites écrites en Markdown, un skill que le manuel qualifie d'expérimental. Eschaton ne peut pas reprendre ce modèle sans contredire sa propre posture — la politique `org.eschaton.rollback` du SP2 argumente explicitement, en tête de fichier, qu'*« une règle YES faisait de la RESTAURATION la SEULE action privilégiée du bureau à ne rien demander »*, et conclut : *« on part donc fermé »*. Un assistant qui appellerait `eschaton-rollback` en mode auto-approuvé annulerait cette décision en une ligne.
2. **Omarchy est en revanche un excellent modèle sur l'injection** : `omarchy-crash-watch` traite le nom du processus qui a planté comme une donnée hostile, le réduit à un composant de chemin, et passe les détails en `argv` discrets *« so a hostile process name can't be reparsed as a command »*. **Tout ce qui entre dans le contexte de l'assistant depuis le système — noms de paquets, descriptions de snapshots, journaux, titres de fenêtres — est du contenu non fiable.** Une description de snapshot est écrite par `snap-pac` à partir de la ligne de commande pacman : un nom de paquet AUR peut y contenir n'importe quoi.
3. **Le modèle de plugins DMS n'apporte aucun confinement** (§3.2 (d)). Si un confinement est voulu, les briques sont là sur les deux architectures : `bubblewrap 0.12.0-1`, `podman 6.1.0-1`, et surtout les unités systemd (`systemd 261.2-1`) avec leurs directives de durcissement. Mais c'est un choix à faire explicitement, pas un acquis du manifeste.
4. **Le stockage des secrets a un précédent propre** : `secret-tool` + variable d'environnement de processus (end-4). Pas de clé dans un fichier de configuration versionné, pas de clé sur une ligne de commande visible dans `/proc`.

---

## 6. Axe 5 — Santé des projets amont (2026-08-28)

Pour les briques que la spec SP3 engagerait dans l'une ou l'autre des architectures candidates.

| Projet | Étoiles | Licence | Créé | Dernier push | Cadence / packaging | Lecture |
|---|---|---|---|---|---|---|
| **DankMaterialShell** | 7 776 *(SP2)* | MIT | 2025-07-10 | 2026-08-27 | `extra` + ALARM, `1.5.3-1` | Inchangé depuis la veille SP2 : jeune, rapide, bus factor ≈ 2. `DankSlideout` présent au tag packagé. |
| **Quickshell** | 2 886 *(SP2)* | LGPL-3.0 | 2024-03-04 | 2026-08-26 | `extra` + ALARM `0.3.1-1` | **Bus factor 1**, 0.x, ruptures annoncées avant 1.0 avec guides de migration. **Pas de client HTTP** — et ce n'est pas prévu : `Quickshell.Networking` est l'API NetworkManager. |
| **`devnullvoid/dms-ai-assistant`** | **22** | MIT | 2026-01-16 | **2026-07-20** | plugin de registre | **Modèle de référence, pas dépendance.** Un seul auteur, 22 étoiles, cinq semaines sans commit. À lire, à ne pas dépendre. |
| **`Francisdelca/dms-agent`** | **5** | MIT | 2026-04-07 | **2026-04-07** | plugin de registre | **Mort-né.** Un seul jour d'activité. Valeur : la preuve que le créneau a été tenté et est libre. |
| **opencode** (`anomalyco/opencode`) | **202 105** | MIT | 2025-04-30 | 2026-08-28 | `extra` **x86_64 seul** ; AUR `opencode-bin` bi-arch (mainteneur upstream) | Le seul agent CLI en dépôt officiel, mais **pas sur ALARM** : inutilisable comme dépendance du banc d'essai. |
| **Claude Code** | 143 267 | **propriétaire** (`LicenseRef-claude-code`) | 2025-02-22 | 2026-08-28 | AUR `claude-code`, bi-arch, 91 votes, pop. 12,3 | Binaire propriétaire. Une distribution ne peut pas en faire un `depends`. `optdepends` au mieux. |
| **Codex CLI** | 119 471 | Apache-2.0 | 2025-04-13 | 2026-08-28 | AUR `openai-codex-bin`, bi-arch | Licence saine ; packaging AUR seul. |
| **MCP** (spéc. + `python-sdk`) | 9 072 / — | — | 2024-09-24 | 2026-08-28 | `extra/python-mcp 1.29.0` **any, les deux** | Gouvernance passée à la **Linux Foundation** (Agentic AI Foundation). Spéc. 2026-07-28. Paquet **une majeure en retard**. |
| **LiteLLM** | 57 478 | **NOASSERTION** | 2023-07-27 | 2026-08-28 | **ni Arch ni ALARM** ; AUR `litellm 1.98.0-1`, 7 votes | Très vivant, mais vendoring obligatoire et périmètre disproportionné. **À écarter.** |
| **Ollama** | 179 631 | MIT | 2023-06-26 | 2026-08-28 | `extra` **x86_64** ; **absent d'ALARM** ; AUR `ollama-bin` bi-arch | Sain en amont, **inutilisable en dépendance bi-arch**. |
| **RamaLama** | — | — | — | — | **`extra 0.24.0-1` `any`, les deux architectures** | La seule inférence locale packagée des deux côtés. Projet Red Hat, adossé à Podman/llama.cpp/vLLM. |
| **Newelle** | 1 450 | GPL-3.0 | 2023-06-11 | 2026-08-25 | AUR seul (4 votes) | Le concurrent GNOME le plus abouti. Pas une dépendance ; une référence fonctionnelle. |
| **`scottstav/aside`** | 60 | MIT | 2026-02-27 | 2026-07-28 | non packagé | Référence de design (overlay layer-shell + outils). Trop jeune et trop seul pour être une base. |
| **Omarchy** | 32 946 | MIT | 2025-06-01 | 2026-08-28 | — | Le concurrent. Son code d'observation des crashs est la meilleure référence publique sur la frontière d'injection. |

---

## 7. Conséquences pour la spec SP3

### 7.1 Ce que la veille **impose**

1. **Corriger la spec Bureau §8 avant d'écrire la spec SP3** (ADR 0002 §2). Deux corrections : le type de plugin est **`daemon`**, pas `composite` ; et surtout **« permission `process` » n'est pas un mécanisme de sécurité** — DMS ne l'applique nulle part (§3.2 (d)). La phrase « l'assistant naît plugin DMS (`composite` + permission `process`) » induit une garantie qui n'existe pas.
2. **Clore le critère 1 de l'ADR 0001 §4.** Il visait le débordement hors « widget de barre » ; `DankSlideout` + `type:"daemon"` + `Variants{Quickshell.screens}` couvrent la sidebar plein écran latérale, au tag `v1.5.3` d'`extra`, avec un précédent en production. Le critère ne se déclenchera pas pour cette raison. *(Les critères 2, 3 et 4 restent entiers.)*
3. **Reformuler le différenciateur (spec Socle §1.2).** « Un assistant IA omniprésent, agnostique du fournisseur » ne décrit plus un territoire vide depuis le 2026-08-14. La formulation défendable au 2026-08-28 : **« un assistant intégré à la surface graphique du shell, qui dispose d'un catalogue fermé d'outils système passant par les mêmes portes privilégiées que l'interface — et adossé au rollback qui rattrape ses erreurs »**. Les deux moitiés existent séparément ; personne ne les a reliées (§2.4).
4. **Écrire la liste des fournisseurs comme configuration, jamais comme architecture.** Gemini CLI, projet à 105 000 étoiles, a été supprimé et remplacé par un binaire fermé en deux mois (§2.2). Toute mention nominative dans la spec porte sa date de vérification.
5. **Écrire noir sur blanc que tout ce qui entre dans le contexte depuis le système est non fiable** : descriptions de snapshots (écrites par `snap-pac` depuis la ligne pacman), noms et descriptions de paquets, journaux, titres de fenêtres, noms de processus. C'est la leçon la mieux argumentée du code d'Omarchy (§5.4.2), et Eschaton la reçoit gratuitement en la lisant.
6. **Ne pas faire d'Ollama une dépendance.** Il n'existe pas sur ALARM (§4.2). Le fournisseur local se décrit par **une URL de base OpenAI-compatible** ; si un paquet est recommandé, c'est `ramalama` (`extra`, `any`, les deux architectures).

### 7.2 Ce que la veille **interdit**

- **Interdit de dépendre d'un agent CLI** (`claude-code`, `openai-codex-bin`, `opencode`, `crush-bin`, `antigravity-cli`) dans `depends=()` : tous sont AUR-seuls ou x86_64-seuls, et deux sont propriétaires. `optdepends` au mieux, et alors sans qu'aucune fonction v1 n'en dépende.
- **Interdit de traiter `permissions` du `plugin.json` comme une garantie.** Le champ est déclaratif. Il se renseigne par honnêteté documentaire ; il ne se cite jamais comme mesure de sécurité.
- **Interdit d'utiliser `Quickshell.Networking` pour les appels HTTP.** Ce module est l'API NetworkManager ; il n'existe aucun type `NetworkRequest`. Le patron contraire, documenté dans le skill amont `dms-plugin-dev`, est faux (§1 ligne 10). Le transport est `Process` + `curl`.
- **Interdit de vendorer `litellm`** (absent des deux dépôts, licence `NOASSERTION`, périmètre disproportionné) et **interdit de vendorer `python-anthropic`** (absent des deux dépôts, AUR marqué périmé depuis le 2026-07-29) : l'adaptateur `/v1/messages` sur `python-httpx` — présent des deux côtés — est moins cher que la dette.
- **Interdit de lancer quoi que ce soit en mode auto-approuvé.** Ni `--permission-mode auto`, ni `--yolo`, ni `--dangerously-skip-permissions` : cela annulerait, sans le dire, la décision argumentée de `org.eschaton.rollback.policy` (« on part donc fermé »).
- **Interdit d'ajouter un second chemin privilégié** pour l'assistant. Il utilise `eschaton-update` et `eschaton-rollback` par les portes existantes, ou il n'a pas cet outil.

### 7.3 Ce que la veille **recommande**

- **Livrer l'invocation par l'IPC natif** : `bind = SUPER, A, exec, dms ipc call plugins toggle eschatonAssistant`, déposé dans `dms/binds-user.lua` (le seul fichier que `dms setup` saute — règle de propriété de la spec Bureau §4.2).
- **Reprendre le patron Strategy d'end-4 indexé sur le *format de fil*** (`openai` | `anthropic`), pas sur le fournisseur. Un seul adaptateur `openai` sert OpenAI, Ollama, vLLM, LM Studio, RamaLama et l'endpoint de compatibilité d'Anthropic ; l'adaptateur `anthropic` natif n'existe que pour l'appel d'outils fiable.
- **Reprendre `secret-tool` pour les clés**, et le passage par variable d'environnement de processus (end-4). `libsecret` est en `core` des deux côtés ; `gnome-keyring` en `extra` des deux côtés. Aucune clé en clair dans un fichier de configuration.
- **Reprendre la politique `policies.ai` d'end-4** sous une forme Eschaton : un réglage « local uniquement » qui refuse tout endpoint non-`localhost`, avec message explicite. C'est aussi le mode hors ligne et le mode données sensibles.
- **Décrire le catalogue d'outils avec des schémas JSON compatibles MCP, sans livrer de serveur MCP en v1.** Coût nul aujourd'hui, porte ouverte demain vers « les agents CLI lancés dans un terminal Eschaton voient les mêmes outils ». `python-mcp` est packagé `any` des deux côtés si le besoin se concrétise — en gardant en tête qu'`extra` est **une majeure derrière** l'amont.
- **Confiner l'exécution des outils par systemd plutôt que par le manifeste**, si un démon est retenu : `bubblewrap` et les directives de durcissement systemd sont disponibles des deux côtés. C'est un choix explicite à écrire, pas une propriété héritée.
- **Traiter le shadowing système←utilisateur** (§3.2 (e)) : au minimum le documenter ; au mieux, un contrôle au démarrage qui signale qu'un plugin utilisateur porte l'`id` d'un plugin Eschaton.
- **Prévoir dès le premier paquet le test de non-régression bi-architecture** déjà instauré au SP2 : le script CI qui interroge l'API Arch et l'index ALARM doit couvrir les nouvelles dépendances de `eschaton-ai` — c'est précisément ce qui aurait attrapé l'absence d'Ollama sur ALARM avant qu'elle ne coûte quelque chose.
- **Ne pas construire de moniteur de quotas.** Cinq plugins concurrents dans le registre et une implémentation first-party chez Omarchy : c'est du terrain saturé, sans valeur différenciante.

### 7.4 Trois architectures candidates, esquissées

Toutes trois supposent le paquet `eschaton-dms-plugin-assistant` (`arch=(any)`, `/etc/xdg/quickshell/dms-plugins/eschatonAssistant/`, `requires_dms: ">=1.5.0"`) et diffèrent par ce qui vit derrière.

---

**Candidat A — Plugin DMS seul (« tout en QML »)**

`plugin.json` `type:"daemon"` → `Variants{Quickshell.screens}` → `DankSlideout`. Un service QML porte les stratégies d'API et les appels d'outils. Transport : `Process` + `curl`. Secrets : `secret-tool`. Outils : appels de `checkupdates`, `snapper --jsonout`, `dgop`, `dms ipc`, et pour les deux opérations privilégiées, `eschaton-update` (dans un terminal, comme le plugin update d'aujourd'hui) et `pkexec eschaton-rollback --yes N`.

| | |
|---|---|
| **Packaging bi-arch** | **Idéal.** Un paquet `any`, **aucune dépendance nouvelle** : `curl` (`core`), `libsecret` (`core`), `pacman-contrib`, `snapper`, `dgop`, `dms-shell` — tous présents et identiques des deux côtés. Rigoureusement zéro travail par architecture. |
| **Force** | Le chemin le plus court vers le différenciateur reformulé. Cohérent avec *fat packages*. Précédents en production (`dms-ai-assistant`) et code lisible chez end-4. |
| **Faiblesse** | Toute la logique vit **dans le processus DMS** : un plugin qui plante emmène le shell ; le parsing SSE et la boucle d'outils se font en JavaScript QML ; aucun confinement possible. Couplé à l'API interne non versionnée de DMS (risque SP2 n°4). |

---

**Candidat B — Plugin DMS mince + démon système (`eschaton-assistantd`)**

Le plugin ne fait que l'interface et parle à un démon **utilisateur** (unité systemd `--user`, socket Unix dans `$XDG_RUNTIME_DIR`, protocole JSON lignes). Le démon porte les fournisseurs, la boucle d'outils, l'historique et le catalogue. Écrit en Python (`python-openai` + `python-httpx`/`python-httpx-sse`, tous `any` des deux côtés) ou en Go (comme `dgop`, précédent DMS).

| | |
|---|---|
| **Packaging bi-arch** | **Python : `arch=(any)`, aucune dépendance manquante d'un côté** — sauf l'adaptateur Anthropic, à écrire sur `httpx` plutôt qu'à vendorer (§4.3). **Go : deux constructions**, ce qui rouvre la matrice de CI du Socle §5.3 (runners ARM disponibles) mais casse le confort `any` du SP2. |
| **Force** | Le crash du démon ne tue pas le shell. Confinement possible (directives systemd, `bubblewrap`). Le catalogue d'outils devient une frontière **de processus**, pas une convention interne. Chemin naturel vers un serveur MCP plus tard, et vers un déclencheur d'événements système (le `crash-watch` d'Omarchy est un précédent direct : un démon qui suit `journalctl`). Le plugin QML redevient jetable si DMS casse son API. |
| **Faiblesse** | Un composant de plus à écrire, versionner, tester. Un protocole de socket à définir. La tentation de faire du démon un chemin privilégié — **à interdire explicitement dans la spec** : le démon tourne en utilisateur et passe par `pkexec` comme le plugin. |

---

**Candidat C — Agent CLI réutilisé comme moteur**

Le plugin est une interface au-dessus d'un agent CLI existant en mode non interactif (`claude -p`, `codex exec`, `opencode run`), auquel on fournit un skill Eschaton et, éventuellement, un serveur MCP maison exposant le catalogue. C'est le modèle d'Omarchy, et de `Francisdelca/dms-agent`.

| | |
|---|---|
| **Packaging bi-arch** | **Le point de rupture.** `extra/opencode` est **x86_64 seul et absent d'ALARM** ; `claude-code`, `openai-codex-bin`, `crush-bin` sont **AUR seuls** (bi-arch, mais hors chemin nominal) ; `claude-code` et `antigravity-cli` sont **propriétaires**. Aucun `depends` acceptable. Le banc d'essai aarch64 ne pourrait pas faire tourner la fonction principale par les dépôts officiels. |
| **Force** | Zéro développement de boucle d'agent, de gestion de contexte, d'appel d'outils. On hérite d'un état de l'art très supérieur à ce qu'on écrirait. |
| **Faiblesse** | **Le provider-agnostisme est perdu** : on n'est pas agnostique du fournisseur, on est captif de l'agent (et Claude Code n'est pas provider-agnostique). L'ADR 0001 §3.3 notait déjà que la sidebar d'end-4 « n'est pas l'assistant omniprésent avec outils système » ; ici c'est l'inverse — on aurait les outils sans l'agnosticisme. Et pour être utile, l'agent doit tourner en mode auto-approuvé (§5.4.1), ce que la posture Eschaton interdit. **La seule mort connue de ce modèle dans l'écosystème DMS est un dépôt à 5 étoiles poussé une seule fois.** |

---

**Lecture comparée.** A et B ne diffèrent pas sur le résultat visible mais sur **où vit la frontière**. A la place à l'intérieur du processus du shell (donc nulle part) ; B la place à une frontière de processus, ce qui est la seule façon d'en faire quelque chose de vérifiable. C est éliminé par le packaging bi-architecture avant même d'être jugé sur la sécurité — et il l'est aussi sur la sécurité. **Une trajectoire A → B (le plugin d'abord, l'extraction du démon quand la boucle d'outils existe) est cohérente avec la manière dont le SP1 et le SP2 ont été menés** ; la spec doit alors écrire dès maintenant le protocole plugin↔logique de façon à ce que l'extraction ne soit pas une réécriture.

---

## 8. Risques

*Table établie le 2026-08-28 (passe de veille SP3, [ADR 0002](../../../docs/decisions/0002-veille-avant-spec.md)).*

| # | Risque / question | Traitement |
|---|---|---|
| 1 | **Le modèle de plugins DMS n'offre aucun confinement.** `permissions` du `plugin.json` est parsé et rangé, jamais consulté — ni dans `PluginService.qml`, ni dans `manager.go`. Le QML d'un plugin a tous les droits du processus DMS, donc de l'utilisateur. | **La spec ne doit citer aucune permission de manifeste comme mesure de sécurité.** Les seules frontières réelles disponibles : le catalogue d'outils fermé, les actions polkit existantes, et (candidat B) une frontière de processus durcie par systemd/`bubblewrap` — disponibles sur les deux architectures. Corriger la spec Bureau §8. |
| 2 | **Injection par le contenu système.** Descriptions de snapshots (écrites par `snap-pac` depuis la ligne pacman), noms/descriptions de paquets, journaux, noms de processus qui plantent : tout cela entre dans le contexte du modèle et est contrôlé par des tiers. | Traiter comme donnée hostile par construction, à la manière d'`omarchy-crash-watch` (durcissement du nom, passage en `argv` discrets). **Aucun contenu système ne doit pouvoir devenir une commande ni une approbation d'outil.** Cette règle s'écrit dans la spec, pas dans un commentaire de code. |
| 3 | **`ollama` absent d'ALARM aarch64** alors qu'il est dans `extra` x86_64 (`0.32.15-1`) — vérifié sur 13 187 paquets d'index. | Le fournisseur local se décrit par **une URL de base OpenAI-compatible**, jamais par un paquet. `optdepends` recommandé : **`ramalama`** (`extra 0.24.0-1`, `any`, **les deux architectures**). Ajouter les dépendances IA au test CI bi-architecture du SP2. |
| 4 | **`python-anthropic` absent d'Arch ET d'ALARM** ; AUR `0.107.1-1`, 4 votes, **marqué périmé depuis le 2026-07-29**. Or l'endpoint OpenAI-compatible d'Anthropic **ignore `strict`** pour le function calling et est déclaré non destiné à la production par l'éditeur. | Écrire l'adaptateur `/v1/messages` sur `python-httpx` / `curl` (présents et identiques des deux côtés) plutôt que vendorer un SDK. Dette avec condition de sortie : *à remplacer par `python-anthropic` s'il entre dans `extra` en `any`*. |
| 5 | **Aucun agent CLI n'est un `depends` acceptable.** `extra/opencode` est x86_64-seul et absent d'ALARM ; `claude-code` (propriétaire), `openai-codex-bin`, `crush-bin`, `antigravity-cli` (propriétaire) sont AUR-seuls. | Élimine le candidat C comme architecture v1. Si un agent CLI est un jour intégré, ce sera en `optdepends` et **aucune fonction v1 n'en dépendra**. |
| 6 | **Volatilité des fournisseurs.** Gemini CLI (105 000 ★, open source) supprimé le **2026-06-18**, remplacé par un binaire Go **fermé**. Deux des agents packagés sont propriétaires. | La liste des fournisseurs est **une donnée de configuration**, versionnée séparément de l'architecture. Chaque mention nominative dans la spec porte sa date de vérification. |
| 7 | **API interne de DMS non versionnée** (risque SP2 n°4, aggravé ici) : l'assistant importe `qs.Common`, `qs.Services`, `qs.Widgets` **et `DankSlideout`**, dont rien ne garantit la stabilité. `master` a ~440 commits d'avance sur `v1.5.3`. | `requires_dms: ">=1.5.0"` obligatoire ; ne juger que sur `extra/dms-shell` ; smoke test CI de chargement. **Argument supplémentaire pour le candidat B** : si la logique vit dans un démon, une rupture de DMS ne coûte qu'une interface. |
| 8 | **`Quickshell.Networking` n'est pas un client HTTP** — et la documentation amont de DMS (`.agents/skills/dms-plugin-dev/references/advanced-patterns.md`) prétend le contraire, avec un exemple `NetworkRequest { url: … }` qui n'existe pas. | Transport `Process` + `curl` (ce que font end-4 et `dms-ai-assistant`). **Ne jamais prendre les skills agent d'un projet amont pour de la documentation vérifiée** — c'est un constat général, à retenir au-delà du SP3. |
| 9 | **Substitution du plugin système par un plugin utilisateur** de même `id` (`PluginService.qml` : `existing.source === "system" && sourceTag === "user"` ⇒ remplacement). | Documenter ; ajouter un contrôle au démarrage qui signale la substitution. Ce n'est pas une élévation de privilèges, c'est une rupture de la chaîne « ce que pacman a posé est ce qui tourne ». |
| 10 | **Le différenciateur IA continue de s'éroder.** Omarchy 4 a pris le terrain « agents intégrés » le 2026-08-14 et itère chaque semaine (push quotidien, 32 946 ★). | Reformuler (§7.1.3) autour de la **surface graphique + catalogue d'outils borné + rollback**, et **rejouer cette veille à l'ouverture du SP4**. C'est, comme au SP2, l'affirmation la plus volatile du projet. |
| 11 | **`extra/python-mcp` est une majeure derrière l'amont** (1.29.0 contre 2.1.1 au 2026-08-25 ; la ligne 2.x est née le jour de la spéc. 2026-07-28). | Sans conséquence tant que le serveur MCP est différé (§7.3). À réévaluer si le SP4 le concrétise ; surveiller l'entrée de `python-mcp` 2.x dans `extra`. |
| 12 | **Aucune évaluation de terrain.** Aucun plugin IA DMS n'a été installé ; les jugements sur `DankSlideout`, sur le coût du streaming en QML et sur l'ergonomie d'une sidebar en VM aarch64 sont des lectures de code. | Première tâche du SP3 : installer `dms-ai-assistant` (MIT, modèle de référence) dans la VM et mesurer — rendu, latence de streaming, empreinte. Même discipline qu'au SP2, où la première tâche était d'installer DMS. |

---

## 9. Sources

**Dépôts et versions** *(interrogés le 2026-08-28)*
- API JSON Arch : `https://archlinux.org/packages/search/json/?name=<pkg>`
- Index miroir Arch Linux ARM : `http://mirror.archlinuxarm.org/aarch64/{core,extra}/` — **13 187 paquets distincts** recensés
- [RPC AUR v5](https://aur.archlinux.org/rpc/) + `PKGBUILD` via `https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=<pkg>`

**Omarchy 4**
- [Omarchy 4.0.0](https://github.com/basecamp/omarchy/releases/tag/v4.0.0) · [manuel — AI](https://omarchy.org/manual/ai/)
- `bin/omarchy-agent`, `bin/omarchy-agent-prompt`, `bin/omarchy-agent-crash`, `bin/omarchy-crash-watch`, `shell/plugins/agents/manifest.json`, `default/agents/skills/{omarchy,diagnose-crash}/SKILL.md`
- [itsfoss — Omarchy bets its future on AI agents](https://itsfoss.com/news/omarchy-ai-agent-focus/)

**DankMaterialShell / Quickshell**
- [`quickshell/Services/PluginService.qml`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/Services/PluginService.qml) · [`quickshell/DMSShellIPC.qml`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/quickshell/DMSShellIPC.qml) · [`core/internal/plugins/manager.go`](https://github.com/AvengeMedia/DankMaterialShell/blob/master/core/internal/plugins/manager.go) · `quickshell/Widgets/DankSlideout.qml` (**tag `v1.5.3`**) · `.agents/skills/dms-plugin-dev/references/advanced-patterns.md`
- [AvengeMedia/dms-plugins](https://github.com/AvengeMedia/dms-plugins) (12 plugins) · [AvengeMedia/dms-plugin-registry](https://github.com/AvengeMedia/dms-plugin-registry) (**329 plugins**)
- [devnullvoid/dms-ai-assistant](https://github.com/devnullvoid/dms-ai-assistant) · [Francisdelca/dms-agent](https://github.com/Francisdelca/dms-agent)
- [Quickshell — modules v0.3.1](https://quickshell.org/docs/v0.3.1/types/) · [Quickshell.Networking](https://quickshell.org/docs/v0.3.1/types/Quickshell.Networking/) · [FAQ v0.3.1](https://quickshell.org/docs/v0.3.1/guide/faq/) · [changelog](https://quickshell.org/changelog/)

**end-4**
- `dots/.config/quickshell/ii/services/Ai.qml`, `services/ai/{ApiStrategy,GeminiApiStrategy,OpenAiApiStrategy,MistralApiStrategy}.qml`, `services/KeyringStorage.qml` — [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)

**Fournisseurs, formats, protocole**
- [Claude — OpenAI SDK compatibility](https://platform.claude.com/docs/en/api/openai-sdk)
- [MCP — spécification 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28) · [blog MCP](https://blog.modelcontextprotocol.io/posts/2026-07-28/) · [python-sdk releases](https://github.com/modelcontextprotocol/python-sdk/releases)
- [Google Developers Blog — Transitioning Gemini CLI to Antigravity CLI](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/)
- [RamaLama — `serve`](https://ramalama.ai/docs/commands/ramalama/serve/) · [Red Hat — Run containerized AI models locally with RamaLama](https://www.redhat.com/en/blog/run-containerized-ai-models-locally-ramalama)
- [vLLM — OpenAI-compatible server](https://docs.vllm.ai/en/latest/serving/online_serving/)

**Paysage**
- [qwersyk/Newelle](https://github.com/qwersyk/Newelle) · [Phoronix — Newelle image gen](https://www.phoronix.com/news/GNOME-Newelle-Image-Gen)
- [scottstav/aside](https://github.com/scottstav/aside) · [novik133/jarvis](https://github.com/novik133/jarvis) · [COSMIC Utils](https://cosmic-utils.github.io/)
- [nihalxkumar/arch-mcp](https://github.com/nihalxkumar/arch-mcp)
- [anomalyco/opencode](https://github.com/anomalyco/opencode) · [anthropics/claude-code](https://github.com/anthropics/claude-code) · [openai/codex](https://github.com/openai/codex) · [BerriAI/litellm](https://github.com/BerriAI/litellm) · [ollama/ollama](https://github.com/ollama/ollama)
