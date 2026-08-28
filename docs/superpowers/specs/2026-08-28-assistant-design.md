# Eschaton — Spec de conception : l'Assistant

- **Date** : 2026-08-28
- **Statut** : rédigée sur passe de veille datée ([rapport](../../veille/2026-08-28-sp3-assistant.md)) — publiée pour relecture ; exécution par Codex (handoff), gates de revue par Claude
- **Sous-projet** : 3/5 (Assistant IA)
- **Amont** : [Spec du Socle](2026-08-27-socle-design.md) §1 (note SP3), [Spec du Bureau](2026-08-28-bureau-design.md) (§8 corrigé), [ADR 0001](../../decisions/0001-shell-du-bureau.md) (+ addenda), [ADR 0002](../../decisions/0002-veille-avant-spec.md)

---

## 1. Position (post-veille du 2026-08-28)

Omarchy 4 a pris le terrain « agents intégrés » — mais son assistant est **un terminal lancé en mode auto-approuvé**, sans catalogue d'outils ni frontière (veille §2.1, §5.4). Le territoire encore vide, et le différenciateur d'Eschaton :

> **Un assistant intégré à la surface graphique du shell, disposant d'un catalogue fermé d'outils système qui passent par les mêmes portes privilégiées que l'interface — adossé au rollback qui rattrape ses erreurs.**

Les deux moitiés existent séparément (sidebars IA d'un côté, admin GUI de l'autre) ; personne ne les a reliées. L'assistant d'Eschaton n'est pas un chatbot posé sur le bureau : c'est le troisième panneau d'administration du shell, après update et rollback — il parle, il agit par les mêmes portes, et le filet §6 du Socle rattrape ce qu'il casse.

## 2. Périmètre v1

**Livrable** : dans la VM de dogfooding, `SUPER+A` ouvre une sidebar plein écran (DankSlideout) ; l'utilisateur converse avec le fournisseur de son choix (OpenAI-compatible ou Anthropic natif, local ou distant) ; l'assistant dispose du **catalogue d'outils v1** (§5) et peut : dire l'état du système (mises à jour en attente, snapshots, métriques), **déclencher une mise à jour** et **proposer un rollback** — chaque action privilégiée passant par la porte existante (terminal visible pour update, modale polkit pour rollback). Streaming des réponses, historique de session, clés dans le trousseau.

**Non-buts v1** : voix, multimodal, actions hors catalogue (aucun `exec` arbitraire), serveur MCP (schémas compatibles, serveur différé — veille §7.3), moniteur de quotas (terrain saturé), agents CLI (interdit de veille §7.2 — au mieux `optdepends` sans fonction v1), mémoire persistante inter-sessions (SP4).

## 3. Architecture : trajectoire A → B actée

La veille (§7.4) éclaire deux candidats viables ; la spec acte la **trajectoire** :

- **v1 = Candidat A** : tout vit dans le plugin DMS `eschaton-dms-plugin-assistant` (`type:"daemon"`, `Variants{Quickshell.screens}` + `DankSlideout`). Transport `Process` + `curl` (JAMAIS `Quickshell.Networking` — ce n'est pas un client HTTP, veille risque 8). Le plugin dépend de `libsecret`/`secret-tool`, mais le test VM a invalidé l'hypothèse « libsecret suffit » : le meta bureau fournit aussi `gnome-keyring`, backend Secret Service de la session, conformément à l'[ADR 0003](../../decisions/0003-service-secrets-assistant.md).
- **B en cible** (`eschaton-assistantd`, démon utilisateur systemd, socket Unix `$XDG_RUNTIME_DIR`, JSON-lignes) : l'extraction se déclenche quand la boucle d'outils est stabilisée OU si l'API interne DMS casse (risque SP2 n°4). **Pour que l'extraction ne soit pas une réécriture, la v1 s'écrit dès maintenant contre un protocole interne** : un unique module QML `AssistantCore` expose `send(message)`, `onDelta(chunk)`, `onToolCall(name, argsJson)`, `toolResult(callId, resultJson)`, `onDone(status)` — l'UI ne parle QUE ce contrat ; en B, `AssistantCore` devient un client socket au même contrat.

### Paquets

| Paquet | Contenu |
|---|---|
| `eschaton-dms-plugin-assistant` | `/etc/xdg/quickshell/dms-plugins/eschatonAssistant/` — `plugin.json` (`type:"daemon"`, `requires_dms ">=1.5.0"`), `AssistantCore.qml`, UI (sidebar, fil, saisie, sélecteur de fournisseur), `Settings.qml`. `arch=(any)`, motif Socle (LICENSE symlink), depends : `dms-shell`, `curl`, `libsecret`, `jq`. `optdepends` : `ramalama` (inférence locale bi-arch — JAMAIS ollama, absent d'ALARM). |
| `eschaton-desktop-config` (bump) | Keybind `SUPER+A` → `dms ipc call plugins toggle eschatonAssistant`, via le canal d'accroche établi (defaults Eschaton, `dms/binds-user.lua`). |
| `eschaton-desktop` (bump) | + `eschaton-dms-plugin-assistant` et `gnome-keyring` dans depends. Le backend de secrets appartient à la session, jamais au plugin (ADR 0003 §8.1). |

## 4. Couche fournisseurs (provider-agnostique)

- **Patron Strategy indexé sur le *format de fil***, pas le fournisseur (veille §7.3) : adaptateur `openai` (`/v1/chat/completions`, SSE) qui sert OpenAI, Ollama, vLLM, LM Studio, RamaLama et l'endpoint compatible d'Anthropic ; adaptateur `anthropic` (`/v1/messages`) uniquement pour le function calling fiable (l'endpoint compatible ignore `strict` — veille §4.3).
- **La liste des fournisseurs est une CONFIGURATION** (fichier `providers.json` livré en défaut `/usr/share/eschaton/assistant/`, surcharge utilisateur), jamais une architecture : chaque entrée = nom, base_url, format (`openai`|`anthropic`), modèle par défaut. Volatilité prouvée (Gemini CLI mort en 2 mois, veille risque 6).
- **Clés** : `secret-tool` (client libsecret) sur le backend Secret Service `gnome-keyring` de la session, passées par variable d'environnement de processus à `curl`. AUCUNE clé dans la configuration ou les arguments. Sous l'autologin transitoire, l'UI interdit explicitement le piège du trousseau sans mot de passe, qui laisserait les secrets en clair au repos ; le déverrouillage PAM est une exigence ferme de SP4 (ADR 0003 §8).
- **Mode « local uniquement »** (repris d'end-4) : un réglage qui refuse tout endpoint non-localhost, avec message explicite — c'est aussi le mode hors-ligne et données sensibles.

## 5. Le catalogue d'outils v1 (fermé) et la sécurité

**Frontières réelles** (les `permissions` du manifest DMS sont décoratives — parsées, jamais appliquées ; veille risque 1 — elles se déclarent par honnêteté, jamais comme mesure) :

1. **Catalogue fermé** : l'assistant n'a QUE ces outils, décrits en schémas JSON compatibles MCP (serveur différé) :
   - `system_status()` — lecture : `checkupdates` (pacman-contrib), `snapper --jsonout list`, métriques `dgop`. Aucun privilège.
   - `trigger_update()` — ouvre le flux update EXISTANT (même chemin que le plugin update : terminal visible, sudo demandé à l'utilisateur). L'assistant déclenche, l'humain authentifie.
   - `propose_rollback(snapshot_id)` — invoque `pkexec /usr/bin/eschaton-rollback --yes N` : la **modale polkit** (auth_admin, prouvée SP2) est la confirmation. L'assistant propose, l'humain authentifie.
2. **Jamais de second chemin privilégié** : l'assistant passe par `eschaton-update`/`eschaton-rollback` par leurs portes existantes, ou il n'a pas l'outil. **Jamais de mode auto-approuvé** (l'anti-modèle d'Omarchy, veille §5.4) : chaque action privilégiée = une authentification humaine.
3. **Tout contenu système entrant dans le contexte est hostile par construction** : descriptions de snapshots (écrites par snap-pac depuis la ligne pacman), noms/descriptions de paquets, journaux, titres de fenêtres. Règle : aucun contenu système ne peut devenir une commande ni valoir approbation d'outil ; les arguments d'outils sont validés côté exécution (les portes polkit/CLI le font déjà : regex du numéro de snapshot, etc.).
4. **Shadowing** : un contrôle au démarrage du plugin signale si un plugin utilisateur porte l'id `eschatonAssistant` (remplacement système←utilisateur possible par design DMS, veille risque 9).

## 6. Vérification — définition de « Assistant terminé »

1. **Spike de terrain** (tâche 1 du plan) : `dms-ai-assistant` (MIT, modèle de référence) installé dans la VM — rendu de DankSlideout, latence de streaming QML, empreinte mesurés (veille risque 12 : aucune évaluation de terrain n'existe).
2. `pacman -S eschaton-desktop` (bump) → `SUPER+A` ouvre la sidebar ; conversation réelle en streaming avec ≥ 2 fournisseurs de formats différents (un `openai` — RamaLama local ou distant — et l'adaptateur `anthropic`).
3. Les 3 outils opèrent en conditions réelles : status lu ; une update déclenchée PAR l'assistant (terminal visible, snapshot pre/post) ; un rollback proposé PAR l'assistant → modale polkit → restauration vérifiée au reboot. Le tout consigné façon vm-dev.
4. Mode local-only prouvé (endpoint distant refusé avec message) ; clé stockée/relue par secret-tool ; aucun secret dans la configuration ou les arguments ; avertissement visible contre le trousseau sans mot de passe sous autologin (ADR 0003 §8.2).
5. Contenu hostile : une description de snapshot piégée (injection d'instructions) N'ALTÈRE ni les outils appelés ni leurs arguments — test documenté.
6. CI verte bi-arch (paquets `any`, garde `check-desktop-deps` étendue aux nouvelles dépendances), bats/qmllint/jq sur le nouveau code, chargement du plugin prouvé au boot frais (l'assertion de rendu SP2 s'applique).

## 7. Risques (table datée du 2026-08-28 — reprend et étend la veille §8)

| # | Risque | Traitement |
|---|---|---|
| 1 | Permissions DMS décoratives | Frontières réelles §5 ; jamais citées comme sécurité. |
| 2 | Injection par contenu système | Règle §5.3, test §6.5 obligatoire. |
| 3 | Ollama absent d'ALARM | Fournisseur local = URL de base ; `ramalama` en optdepends ; garde CI étendue. |
| 4 | python-anthropic absent des deux dépôts, AUR périmé | v1 en QML+curl n'en a pas besoin ; si B (Python) : adaptateur `/v1/messages` sur `python-httpx` — dette avec condition de sortie (remplacer si `python-anthropic` entre dans extra en `any`). |
| 5 | API interne DMS non versionnée + DankSlideout non garanti | `requires_dms` ; juger sur extra seul ; le contrat `AssistantCore` (§3) rend l'UI jetable et la logique extractible (trajectoire B). |
| 6 | Volatilité des fournisseurs | Configuration datée, jamais architecture (§4). |
| 7 | Streaming SSE en QML (JavaScript) — coût inconnu | **Le spike du 2026-08-28 lève le risque bloquant** (`tools/vm-dev.md` §19) : 256 tokens réels rendus sans artefact ni gel, trajectoire A maintenue. Réserve honnête : le high-water RSS a pris ~16 MiB pendant cette réponse ; la v1 doit regrouper les deltas par frame, borner l'historique et refaire un soak en Task 6. B remonte si le RSS croît sans borne ou si des frames sont perdues. |
| 8 | Érosion continue du différenciateur (Omarchy itère chaque semaine) | Formulation §1 datée ; veille rejouée à l'ouverture du SP4. |

## 8. Ce que l'Assistant prépare

- **SP4** : serveur MCP exposant le catalogue (schémas déjà compatibles), mémoire persistante, greeter/onboarding qui configure le premier fournisseur **et déverrouille le trousseau par PAM (module gnome-keyring — exigence héritée de l'ADR 0003 §8.3, critères §6 de l'ADR rejoués au login authentifié)** ; signature du dépôt avant toute distribution.
- **B** : l'extraction du démon quand la boucle d'outils est stable — le contrat §3 est écrit pour ça.
