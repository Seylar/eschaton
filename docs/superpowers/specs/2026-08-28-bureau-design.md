# Eschaton — Spec de conception : le Bureau

- **Date** : 2026-08-28
- **Statut** : rédigée sur passe de veille datée ([rapport](../../veille/2026-08-28-sp2-bureau.md)) — publiée pour relecture, exécution autorisée par la directive du 2026-08-28
- **Sous-projet** : 2/5 (Bureau)
- **Amont** : [Spec du Socle](2026-08-27-socle-design.md), [ADR 0001](../../decisions/0001-shell-du-bureau.md) (+ addendum), [ADR 0002](../../decisions/0002-veille-avant-spec.md)

---

## 1. Position (post-veille du 2026-08-28)

La veille a rebattu deux cartes de l'ADR 0001 :

1. **La pile est déjà packagée partout.** `dms-shell` 1.5.3, `dms-shell-hyprland`, `quickshell` 0.3.1 et `dgop` sont dans `extra` d'Arch **et** d'ALARM, aux mêmes versions, en binaires natifs des deux architectures (vérifié 2026-08-28). Aucun vendoring, aucune compilation : le Bureau entier tient en meta-paquets `arch=(any)`.
2. **Le « zéro-terminal » brut ne différencie plus.** Omarchy 4 gère les paquets en GUI, CachyOS livre un gestionnaire graphique par défaut, `btrfs-assistant` existe dans `extra`. Ce qu'aucune distro Arch n'offre : **l'administration système intégrée nativement au shell** — en tête le **rollback graphique unifié** (snapshots + restauration + boot-into-snapshot, dans le shell, pas dans une app tierce juxtaposée). C'est le créneau du Bureau v1, l'assistant IA (SP3) le complétera.

Le Bureau v1 est donc : **Hyprland + DMS officiels, habillés Eschaton, plus deux plugins système qui font ce que personne ne fait — mettre à jour et restaurer le système depuis le shell.**

## 2. Périmètre

**Livrable** : la VM de dogfooding boote en session graphique complète — auto-login, bureau Hyprland + DMS thémé Eschaton, Control Center opérationnel (réseau, audio, affichage), et deux plugins Eschaton fonctionnels :

- **`eschaton-dms-plugin-update`** : badge de mises à jour disponibles + déclenchement d'`eschaton-update` (avec sortie visible et notification de reboot kernel) ;
- **`eschaton-dms-plugin-rollback`** : liste des snapshots snapper (date, description), restauration en deux gestes avec confirmation, invitation au reboot.

**Non-buts v1** (différés) : greeter graphique et écran de verrouillage soignés (SP4 — v1 : auto-login `greetd`), clavier virtuel/gestes tactiles (nice-to-have acté), multi-écrans avancé, thème clair (v1 : sombre seul), app store graphique (le plugin update n'est pas un gestionnaire de paquets), shell maison (critères ADR 0001 §4, affaiblis par l'addendum).

## 3. Architecture des paquets

Quatre paquets `arch=(any)`, mêmes conventions que le Socle (LICENSE symlink, defaults dans `/usr`, jamais de mutation de config) :

| Paquet | Rôle | Contenu principal |
|---|---|---|
| `eschaton-desktop` | Meta | Dépend : `hyprland`, `dms-shell-hyprland` (tire dms-shell, quickshell, dgop ; le compositeur reste substituable — `dms-shell-niri` fournit le même virtuel `dms-shell-compositor`), `pipewire`, `wireplumber`, `xdg-desktop-portal-hyprland`, `greetd`, `polkit`, **`btrfs-assistant`** (rollback graphique disponible dès le jour 1 — dette assumée : retiré quand le plugin natif §3 le remplace, condition de sortie explicite per ADR 0002), polices (`ttf-jetbrains-mono-nerd`, `noto-fonts`), `eschaton-desktop-config`, les deux plugins. |
| `eschaton-desktop-config` | Configs | Config Hyprland **en Lua** (voir §4), entrée de session Wayland, config greetd (auto-login → session Hyprland), `/etc/skel/.config/hypr/hyprland.lua` d'amorçage, drop-in preset (`greetd.service`). |
| `eschaton-dms-plugin-update` | Plugin DMS | `/etc/xdg/quickshell/dms-plugins/eschaton-update/` — QML + manifest, permission `process` (exécute `eschaton-update`), vérification périodique (`checkupdates`-équivalent en lecture seule). |
| `eschaton-dms-plugin-rollback` | Plugin DMS | `/etc/xdg/quickshell/dms-plugins/eschaton-rollback/` — QML + manifest. **Liste** des snapshots (date, description) : lecture seule via **snapperd D-Bus** (`org.opensuse.Snapper`), sans privilège. **Restauration** : le plugin orchestre la **méthode « replace »** — la logique d'`eschaton-rollback` ([Socle §6](2026-08-27-socle-design.md), amendé le 2026-08-28) — derrière polkit, puis invite au reboot. `snapper rollback` est **écarté** : réfuté par la Task 10 (« Cannot detect ambit » sur la disposition Arch), et snapperd n'expose de toute façon aucun rollback sur D-Bus. La surface privilégiée exacte — helper dédié, `pkexec`, ou service D-Bus maison — se tranche en tâche dédiée (§7, risque 5). Pas de sudo interactif, pas de terminal. |

`eschaton-branding` (Socle) gagne : un fond d'écran Eschaton + la valeur de thème DMS par défaut. `eschaton-base` ne change pas ; `eschaton-desktop` s'installe par-dessus un Socle existant (`pacman -S eschaton-desktop`) — c'est aussi le test d'upgrade du modèle fat packages.

## 4. Les deux pièges de configuration (veille §3, invariants)

1. **Lua d'entrée de jeu.** `hyprlang` disparaît « 1–2 versions après Hyprland 0.55 » ; la fenêtre est ~0.57 (octobre 2026). Toute config Hyprland d'Eschaton naît en **Lua**, et l'entrée de session packagée lance **`Hyprland -c <chemin du lua>`** — sans `-c`, la config Lua est ignorée silencieusement. Invariant testé par le plan.
2. **Propriété de `~/.config/hypr/`.** `dms setup` réécrit `~/.config/hypr/dms/*.lua` sans préavis. Règle de partage : **l'arbre `~/.config/hypr/dms/` appartient à DMS** (jamais un fichier Eschaton dedans) ; les défauts Eschaton vivent dans `/usr/share/eschaton/hypr/*.lua` (pacman-owned) ; le `hyprland.lua` de l'utilisateur (amorcé par `/etc/skel`, 3 lignes commentées) fait : `require` défauts Eschaton → `require` arbre DMS → overrides utilisateur. L'utilisateur possède son fichier d'entrée, les mises à jour Eschaton passent par `/usr/share`, DMS régénère son arbre sans rien casser.

## 5. Flux de session

`greetd` (preset enable) → auto-login utilisateur → session `eschaton` (entrée Wayland packagée) → `Hyprland -c ~/.config/hypr/hyprland.lua` → autostart DMS (`dms run` via la config) → barre + Control Center + plugins chargés depuis `/etc/xdg/quickshell/dms-plugins/`. Aucune étape terminal.

## 6. Vérification — définition de « Bureau terminé »

1. **Spike rendu** (tâche 1 du plan) : Quickshell/QtQuick rend correctement sous virtio-gpu dans la VM UTM — le seul risque aarch64 restant (veille §4). Critère : session DMS fluide en VM, pas d'artefacts bloquants.
2. Depuis un Socle §7.1 : `pacman -S eschaton-desktop` + reboot → session graphique auto-login complète.
3. Les deux plugins opèrent en conditions réelles : une mise à jour réelle déclenchée depuis le shell (snapshot pre/post à l'appui) ; un rollback réel depuis le shell, système restauré au reboot.
4. L'invariant Lua tient : `hyprctl version` + preuve que la config chargée est le Lua ; suppression volontaire du `-c` → constat que la config serait ignorée (documenté).
5. CI verte (paquets `any` publiés, installables des deux architectures).
6. Zéro terminal pour : régler réseau/audio/affichage, mettre à jour, restaurer.

## 7. Risques (table datée du 2026-08-28)

| # | Risque | Traitement |
|---|---|---|
| 1 | Rendu QtQuick sous virtio-gpu en VM inconnu | Spike en tâche 1 ; repli : rendu logiciel Qt (`QSG_RHI_BACKEND=software`) le temps du diagnostic. |
| 2 | Cadence DMS (1.x jeune) et **API de plugins non versionnée** (les plugins importent les internes `qs.*` et héritent de `PluginComponent` — aucune promesse de compatibilité) | Politique de version : suivre **`extra/dms-shell` uniquement** (jamais `-git` ni `master`, qui a ~440 commits d'avance) ; `requires_dms` **obligatoire** dans chaque `plugin.json` Eschaton ; smoke test CI de chargement des plugins ; les 12 plugins first-party servent de canari amont. |
| 3 | Fenêtre de suppression d'hyprlang (~0.57, oct. 2026) | Lua exclusif dès le premier commit (§4.1) — le risque devient nul pour nous. |
| 4 | `dms setup` écrase des configs | Règle de propriété §4.2 ; aucun fichier Eschaton sous `~/.config/hypr/dms/`. |
| 5 | Surface D-Bus/polkit du plugin rollback | Règle polkit scopée au groupe `wheel` et aux seules actions snapper nécessaires ; revue de la règle en tâche dédiée. |
| 6 | Auto-login = session ouverte sans mot de passe | Assumé en VM de dogfooding ; le greeter authentifiant est un livrable SP4 explicite. |
| 7 | Retard `hyprland` sur ALARM (0.56.1 vs 0.56.2) — critique si ALARM traîne quand 0.57 supprimera hyprlang | Intégré à la surveillance ALARM instaurée par le Socle §8 risque 2. |
| 8 | Night mode DMS inopérant en VM (gamma matériel, issue upstream #2061) | Hors critères d'acceptation SP2 tant que le test réel n'a pas tranché. |
| 9 | Bus factor Quickshell = 1 (`outfoxxed`) | Surveillance ; atténué par l'empaquetage `extra` et le couplage humain avec DMS (lead DMS = contributeur n°2 de Quickshell). Déclencheur le plus probable du critère 4 de l'ADR 0001. |

Vérification de non-régression bi-architecture (recommandation de veille) : un script CI léger interroge les deux index de dépôts (API Arch + index miroir ALARM) et échoue si une dépendance d'`eschaton-desktop` manque d'un côté — le pendant SP2 du smoke test x86_64 du Socle.

## 8. Ce que le Bureau prépare

- **SP3 (Assistant IA)** : l'assistant naît plugin DMS (`composite` + permission `process`), les types de plugins couvrent le besoin initial (veille §2) ; s'il en déborde, c'est le critère 1 de l'ADR 0001 §4 qui se déclenche — en connaissance de cause.
- **SP4** : greeter graphique, verrouillage, thème clair, gestionnaire de paquets graphique complet s'il s'avère nécessaire (le plugin update v1 n'en est volontairement pas un).
- Les briques GUI tierces recensées par la veille (btrfs-assistant, pamac…) restent des replis d'intégration si un plugin natif s'avérait trop coûteux — décision par plugin, tracée.
