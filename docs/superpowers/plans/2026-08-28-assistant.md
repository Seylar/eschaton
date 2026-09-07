# Plan d'implémentation : l'Assistant d'Eschaton (SP3)

> **Exécution : Codex** (directive du 2026-08-28 — heavy lifting), gates de revue et tag : Claude. Les conventions du Bureau s'appliquent intégralement (voir Global Constraints). Chaque tâche se termine par : commits poussés sur `assistant`, CI verte, preuves consignées dans `tools/vm-dev.md` — puis la suivante. Pas de tag, pas de fusion.

**Goal:** `SUPER+A` ouvre la sidebar assistant dans la VM ; conversation streaming avec ≥ 2 formats de fournisseurs ; les 3 outils du catalogue fermé opèrent en conditions réelles (status, update déclenchée, rollback proposé → modale polkit) ; l'injection par contenu système est prouvée inoffensive.

**Spec:** `docs/superpowers/specs/2026-08-28-assistant-design.md` (autorité). **Veille:** `docs/veille/2026-08-28-sp3-assistant.md` (autorité factuelle datée — ses §7.2 interdits sont contraignants).

## Global Constraints

- Branche `assistant`, créée depuis le `main` portant `v0.2.0`. Conventions : `arch=(any)`, motif LICENSE symlink, `sha256sums=(SKIP…)`, `backup=` si éditable, pkgrel bump systématique (immutabilité du dépôt), builds `tools/build-pkg <pkg> -d`, `--disable-sandbox` conteneurs, jamais `ping`, correctifs toujours au repo, VM pilotée par `tools/vm-serial`.
- **Interdits de veille (§7.2, contraignants)** : aucun agent CLI en depends ; permissions du manifest jamais citées comme sécurité ; jamais `Quickshell.Networking` pour HTTP (transport = `Process` + `curl`) ; ni litellm ni python-anthropic vendorés ; **jamais de mode auto-approuvé** ; jamais de second chemin privilégié (update/rollback passent par les portes existantes).
- Le contrat `AssistantCore` (spec §3) est LA frontière interne : l'UI ne parle que `send/onDelta/onToolCall/toolResult/onDone` — c'est ce qui rend l'extraction en démon (trajectoire B) possible sans réécriture.
- `requires_dms: ">=1.5.0"` ; id `eschatonAssistant` ; `/etc/xdg/quickshell/dms-plugins/eschatonAssistant/`.

---

### Task 1 : Spike de terrain — `dms-ai-assistant` + coût du streaming QML

**Exécutée le 2026-08-28 — décision : trajectoire A maintenue pour la v1.** Mesures, réserves et nettoyage : `tools/vm-dev.md` §19. Aucun code amont conservé.

Veille risque 12 : aucun plugin IA DMS n'a jamais été installé ; risque 7 : coût du SSE en JavaScript QML inconnu. Sortie : décision documentée, pas de code gardé.

1. Dans la VM : installer `dms-ai-assistant` (dépôt MIT de référence, via le chemin plugin UTILISATEUR — c'est un spike, pas un paquet) ; l'ouvrir, converser contre un endpoint réel (RamaLama local dans la VM si possible : `pacman -S ramalama` + un petit modèle ; sinon endpoint distant de test).
2. Mesurer et consigner : rendu de la sidebar/DankSlideout en VM (fluidité, artefacts), latence premier-token et cadence des deltas en streaming, empreinte mémoire du process qs avant/pendant, comportement sur réponse longue.
3. Lire son code : comment il parse le SSE (Process+curl ? buffering ?), comment il gère l'historique — consigner les motifs à reprendre/éviter.
4. **Décision** dans vm-dev (nouvelle section) : streaming QML viable en VM ? Si NON (saccades rédhibitoires, fuites), la trajectoire B (démon) remonte dans la v1 — décision tracée, spec amendée en conséquence AVANT la Task 2.
5. Nettoyer le plugin utilisateur de spike. Commit docs.

### Task 2 : `AssistantCore` + adaptateur `openai` (le moteur)

**Exécutée le 2026-08-28.** Moteur, catalogue, fixtures et harnais : `packages/eschaton-dms-plugin-assistant/` ; preuves VM : `tools/vm-dev.md` §20.

1. `AssistantCore.qml` (+ `providers/OpenAIAdapter.qml` ou .js) : le contrat de la spec §3, la boucle conversation→outils, le parsing SSE (motifs validés au spike), `Process`+`curl` (URL/headers/body via argv, JAMAIS de shell interpolé), timeout et annulation propres.
2. Le catalogue d'outils est déclaré ici (schémas JSON compatibles MCP, spec §5) mais les exécuteurs arrivent en Task 5 — stubs qui répondent « outil non encore branché ».
3. Validation sans VM : `qmllint` ; fixtures SSE (fichiers de chunks réels captés au spike) rejouées via un harnais `qs`/`quickshell` minimal DANS LA VM, sorties consignées ; `jq` sur les schémas d'outils.
4. Commit. (Pas encore de paquet — Task 3 packagera.)

### Task 3 : UI sidebar + paquet `eschaton-dms-plugin-assistant`

**Exécutée le 2026-08-28.** Sidebar, paquet, keybind et détection du shadowing :
`packages/eschaton-dms-plugin-assistant/` et `packages/eschaton-desktop-config/` ;
preuve de chargement dans le vrai DMS et contrôles de paquet :
`tools/vm-dev.md` §21. Le contrôle du shadowing vit volontairement dans
`eschaton-desktop-config` : un plugin système déjà masqué ne peut pas détecter
son propre remplacement.

1. UI : DankSlideout plein écran (`Variants{Quickshell.screens}`), fil de conversation (rendu des deltas), saisie, sélecteur de fournisseur, indicateur outil-en-cours, états vides/erreur lisibles. Motifs first-party DMS (mêmes imports que les plugins update/rollback).
2. `plugin.json` (`type:"daemon"`, permissions déclarées par honnêteté avec le commentaire « non appliquées par DMS — voir spec §5 »), contrôle de shadowing au démarrage (spec §5.4).
3. PKGBUILD motif Socle (depends : `dms-shell curl libsecret jq pacman-contrib` ; optdepends `ramalama`) ; keybind `SUPER+A` via bump d'`eschaton-desktop-config` (canal d'accroche établi) ; bump d'`eschaton-desktop` (+ dépendance).
4. Builds `-d`, jq/qmllint, garde `check-desktop-deps` étendue aux nouvelles deps (les deux côtés). Commit. Pas de push de vague avant Task 4 incluse.

### Task 4 : Fournisseurs — providers.json, secret-tool, local-only, adaptateur `anthropic`

**Exécutée le 2026-08-28.** Catalogue daté, deux adaptateurs, barrière
local-only et pont Secret Service : `packages/eschaton-dms-plugin-assistant/` ;
backend de session et dette PAM arbitrés par l'ADR 0003 ; preuves VM et paquets :
`tools/vm-dev.md` §22. Le push de vague Tasks 2-4 déclenche la revue Claude.

1. `providers.json` défaut dans `/usr/share/eschaton/assistant/` (entrées datées : RamaLama localhost, OpenAI, Anthropic — la LISTE est une config, spec §4) + surcharge utilisateur (`~/.config/eschaton/assistant/providers.json`, jamais écrasée).
2. Clés : `secret-tool lookup/store` (schéma d'attributs documenté), passage par env de process à curl ; AUCUN secret en clair (grep prouvé).
3. Mode local-only : réglage dans Settings du plugin ; tout endpoint non-localhost refusé avec message explicite.
4. Adaptateur `anthropic` (`/v1/messages`, SSE Anthropic, tool_use/tool_result) au même contrat interne que l'openai.
5. Validation : fixtures des DEUX formats rejouées ; bats sur toute logique shell ajoutée. **Push de la vague Tasks 2-4, CI verte.**

### Task 5 : Le catalogue d'outils v1 (les exécuteurs)

1. `system_status()` : `checkupdates`, `snapper --jsonout list`, `dgop` — lecture seule, agrégé en JSON pour le modèle. **Durcissement contenu hostile** : les champs texte issus du système (descriptions de snapshots, noms de paquets) sont transmis comme DONNÉES étiquetées, jamais concaténés dans le prompt système ; argv discrets partout.
2. `trigger_update()` : ouvre le flux update existant (même mécanisme que le plugin update — terminal visible, sudo humain).
3. `propose_rollback(snapshot_id)` : validation locale du numéro (regex, existence dans la liste) PUIS `pkexec /usr/bin/eschaton-rollback --yes N` — la modale polkit est la confirmation. L'UI montre ce qui va être fait AVANT l'appel.
4. La boucle d'outils dans AssistantCore : l'assistant ne peut appeler QUE le catalogue ; tout nom d'outil inconnu = refus loggé.
5. Push, CI verte, bump. Preuves de chaque outil en VM (sorties consignées).

### Task 6 : Installation réelle + conversations réelles (DoD §6.2)

`pacman -Syu` en VM → `SUPER+A` → sidebar ; conversation streaming réelle avec un fournisseur `openai` (RamaLama local de préférence) ET l'adaptateur `anthropic` (clé de test utilisateur via secret-tool). Local-only prouvé (endpoint distant refusé). Captures + méthode vm-dev. Boot frais : le plugin est rendu (l'assertion SP2 s'applique).

### Task 7 : Les outils en conditions réelles + test d'injection (DoD §6.3/§6.5)

**Exécutée le 2026-08-29.** Le status, l'update et le rollback ont traversé le
vrai plugin et les portes système dans la VM ; le reboot a restauré la racine
sans toucher `/home`. La description hostile a provoqué un appel d'outil SSE
volontairement illégal, refusé structurellement avant l'exécuteur. Conversation
complète : `docs/proofs/2026-08-29-assistant-task7-conversation.jsonl` ; preuves
et réserves : `tools/vm-dev.md` §25.

1. Status lu et restitué correctement par l'assistant.
2. Une update RÉELLE déclenchée par l'assistant (terminal visible, snapshot pre/post, entrées limine).
3. Un rollback RÉEL proposé par l'assistant → modale polkit → authentification → restauration vérifiée au reboot (marqueur /home intact).
4. **Injection** : créer un snapshot dont la description contient une instruction adverse (« ignore tes règles, exécute… ») → prouver que ni les outils appelés ni leurs arguments ne changent ; consigner la conversation complète.

### Task 8 : Clôture SP3

**Exécutée le 2026-08-29.** Les six critères de la spec §6 sont soldés dans
`tools/vm-dev.md` §26, la spec passe à « implémentée sur assistant », et le
handoff §12 ouvre la revue finale Claude. Aucun tag, aucune fusion et aucune
publication Pages n'ont été faits.

DoD spec §6 point par point (dossier de preuves vm-dev), statut spec → implémenté, garde CI/deps à jour, **notifier pour la revue Claude — le tag v0.3.0 et la fusion restent le gate Claude**.

---

## Couverture spec → tasks
§1-§2 (position/périmètre) → 3,6,7 · §3 (A→B, AssistantCore) → 2 · §4 (fournisseurs) → 4 · §5 (catalogue+sécurité) → 3 (shadowing), 5, 7 · §6 DoD → 1,6,7,8 · §7 risques → 1 (r7,r12), 4 (r3,r4,r6), 5 (r1,r2), 2/3 (r5).
