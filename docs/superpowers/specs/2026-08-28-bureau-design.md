# Eschaton — Spec de conception : le Bureau

- **Date** : 2026-08-28
- **Statut** : **implémentée sur `bureau`, validée en VM le 2026-08-28 — revue Claude requise avant tag et fusion**
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
| `eschaton-desktop` | Meta | Dépend : `hyprland`, `dms-shell-hyprland`, `pipewire` + `pipewire-pulse` + `wireplumber`, portails Hyprland **et GTK** (FileChooser), `greetd`, `polkit`, polices (`ttf-jetbrains-mono-nerd`, `noto-fonts`), `eschaton-desktop-config`, les deux plugins. **`btrfs-assistant` a été retiré** : le plugin natif remplit sa condition de sortie et son rollback a été prouvé en VM. |
| `eschaton-desktop-config` | Configs | Config Hyprland **en Lua** (voir §4), entrée de session Wayland, config greetd (auto-login → session Hyprland), `/etc/skel/.config/hypr/hyprland.lua` d'amorçage, drop-in preset (`greetd.service`). |
| `eschaton-dms-plugin-update` | Plugin DMS | `/etc/xdg/quickshell/dms-plugins/eschatonUpdate/` — QML + manifest, badge via `checkupdates`, rafraîchissement périodique et à l'ouverture, lancement visible de `eschaton-update --yes` dans Foot. `fakeroot` est une dépendance explicite de `checkupdates`. |
| `eschaton-dms-plugin-rollback` | Plugin DMS | `/etc/xdg/quickshell/dms-plugins/eschatonRollback/` — QML + manifest. **Liste** via le client `snapper --jsonout` (lecture autorisée au groupe `wheel` par la config Snapper). **Restauration** : `pkexec /usr/bin/eschaton-rollback --yes NUMÉRO`, autorisé uniquement pour une session locale active du groupe `wheel` par l'action `org.eschaton.rollback`; le helper applique la méthode **replace**. `snapper rollback` reste écarté. Confirmation en deux gestes, puis invitation au reboot. |

`eschaton-branding` (Socle) gagne un fond d'écran Eschaton. Le provisioning initial le pose par l'IPC officiel DMS seulement si aucun choix utilisateur n'existe. `eschaton-base` gagne les interfaces non interactives strictes des helpers ; `eschaton-desktop` s'installe par-dessus un Socle existant (`pacman -S eschaton-desktop`) — c'est aussi le test d'upgrade du modèle fat packages.

## 4. Les deux pièges de configuration (veille §3, invariants)

1. **Lua d'entrée de jeu.** `hyprlang` disparaît « 1–2 versions après Hyprland 0.55 » ; la fenêtre est ~0.57 (octobre 2026). Toute config Hyprland d'Eschaton naît en **Lua**, et l'entrée de session packagée lance le lanceur amont : **`start-hyprland -- -c ~/.config/hypr/hyprland.lua`** *(forme constatée au spike Task 1 — confirmée par `[cfg] Config is lua, loading lua mgr`)*. Invariant testé par le plan. **Correction du 2026-08-28 (contre-test §6.4, vm-dev §18)** : cette ligne affirmait « sans `-c`, la config Lua est ignorée silencieusement » — c'est **faux** sur Hyprland 0.56.1. Amputé de son `-- -c`, `start-hyprland` charge quand même `~/.config/hypr/hyprland.lua` par découverte automatique (`[cfg] Regular config at …` / `[cfg] Using lua config found at …`), défauts Eschaton appliqués ; le Lua l'emporte même sur un `hyprland.conf` présent, et un compte vierge se voit générer un `hyprland.lua`, plus un `hyprland.conf`. Ce que le `-c` garantit n'est donc pas le chargement mais l'**explicite** : nommer le fichier au lieu de dépendre d'un ordre de découverte amont non contractuel, qui a déjà changé une fois avant la fenêtre 0.57. L'invariant est conservé à ce titre.
2. **Propriété de `~/.config/hypr/`** *(règle amendée le 2026-08-28 — le spike Task 1 a mesuré le comportement réel, vm-dev §12.6-12.7)*. Constat : `dms setup` possède **aussi `hyprland.lua`** (régénéré avec sauvegarde `.dms-backups/`), et réécrit `dms/binds.lua` sans condition ; seuls les six autres `dms/*.lua` sont sautés s'ils existent. L'amorce `/etc/skel` initialement prévue serait donc écrasée au premier `dms setup`. Règle amendée : **l'arbre `~/.config/hypr/` entier appartient à DMS** ; les défauts Eschaton vivent dans `/usr/share/eschaton/hypr/` (pacman-owned) et s'accrochent par le canal que la Task 2 établit **sur pièces** — candidats par ordre de préférence : (a) point d'inclusion offert par le `hyprland.lua` généré par DMS (à vérifier), (b) `dms/binds-user.lua` (sauté par setup, donc sûr) + variables d'environnement de session pour le reste, (c) ne jamais invoquer `dms setup` et générer l'équivalent nous-mêmes (dernier recours : reprend la migration Lua à notre charge). La décision et sa preuve (un `dms setup` volontaire ne détruit pas la config Eschaton) sont un critère de la Task 2.

## 5. Flux de session

`greetd` (preset enable) → auto-login utilisateur → session `eschaton` (entrée Wayland packagée) → `start-hyprland -- -c ~/.config/hypr/hyprland.lua` (§4.1) → autostart DMS (`dms run` via la config) → barre + Control Center + plugins chargés depuis `/etc/xdg/quickshell/dms-plugins/`. Aucune étape terminal.

## 6. Vérification — définition de « Bureau terminé »

1. **Spike rendu** (tâche 1 du plan) : Quickshell/QtQuick rend correctement sous virtio-gpu dans la VM UTM — le seul risque aarch64 restant (veille §4). Critère : session DMS fluide en VM, pas d'artefacts bloquants.
2. Depuis un Socle §7.1 : `pacman -S eschaton-desktop` + reboot → session graphique auto-login complète.
3. Les deux plugins opèrent en conditions réelles : une mise à jour réelle déclenchée depuis le shell (snapshot pre/post à l'appui) ; un rollback réel depuis le shell, système restauré au reboot.
4. L'invariant Lua tient : `hyprctl version` + preuve que la config chargée est le Lua ; suppression volontaire du `-c` → constat, documenté, de ce qui se passe alors. *(Énoncé amendé le 2026-08-28 : il disait « constat que la config serait ignorée » — le contre-test a montré qu'elle ne l'est pas. Le critère porte désormais sur le constat lui-même, pas sur son résultat attendu.)*
5. CI verte (paquets `any` publiés, installables des deux architectures).
6. Zéro terminal pour : régler réseau/audio/affichage, mettre à jour, restaurer.

### 6.1 Résultat de la validation VM du 2026-08-28

| Critère | Verdict | Preuve synthétique |
|---|---|---|
| 1. Rendu virtio-gpu | **OK** | DMS 1.5.3 et Hyprland rendent sans artefact bloquant ; captures 1280×800. `LIBGL_ALWAYS_SOFTWARE=1` reste un réglage de cette VM seulement. |
| 2. Installation et reboot | **OK** | `pacman -S eschaton-desktop`, reboot, auto-login greetd sur `seat0`; `dms.service` actif. |
| 3. Update + rollback réels | **OK** | Update depuis le widget : `pacman -Syu --noconfirm`, snapshots 32/33 et entrées Limine. Rollback depuis le widget vers 33 : `cowsay` absent après reboot, marqueur `/home` conservé, racine `/dev/vda2[/@]`. *(Ce rollback-là s'est élevé sans mot de passe — c'était la règle polkit du paquet 0.1.0-2. Depuis 0.1.0-3 le même parcours ouvre la modale d'authentification DMS, rejouée et capturée en VM le 2026-08-28 : vm-dev §14.4.)* |
| 4. Lua | **OK, les deux membres** | Session lancée par `eschaton-session`; l'accroche Eschaton vit dans `dms/binds-user.lua`, résiste à `dms setup`; la disposition française vient de l'environnement XKB de session. **Contre-test fait le 2026-08-28 (vm-dev §18)** : quatre instances jetables imbriquées, `-c` retiré — la config Lua est **quand même chargée** (`[cfg] Using lua config found at …/hyprland.lua`), y compris en présence d'un `hyprland.conf` leurre ; sur un `HOME` vierge, Hyprland génère un `hyprland.lua`. La justification de l'invariant §4.1 est corrigée en conséquence ; la forme `-- -c` est conservée pour l'explicite. Session de référence intacte, inventaire de `~/.config/hypr` identique après nettoyage. |
| 5. CI bi-architecture | **OK** | Builds et publication x86_64/aarch64 verts sur `bureau`; les archives de même version sont désormais immuables. |
| 6. Zéro terminal | **OK pour update/rollback et surfaces DMS ; seule réserve : matériel audio absent de la VM** | Les parcours update/rollback ont été faits à la souris. Réseau et affichage sont exposés dans le Control Center. La VM est lancée avec `-audio none` : elle ne peut pas prouver le réglage d'un périphérique audio réel, seulement la présence de PipeWire/WirePlumber et de l'interface. **Réserve de rendu levée le 2026-08-28 (vm-dev §14.5)** : `eschaton-desktop-config` 0.1.0-9 détecte le décalage entre `settings.json` et le `barConfigs` en mémoire de DMS 1.5.3, puis demande une unique recomposition non bloquante. Deux boots consécutifs depuis le paquet Pages montrent les pastilles update et rollback, le second sans nouvelle recomposition. |

Le tag `v0.2.0` n'est volontairement **pas créé** à ce stade : le demandeur a
exigé une revue Claude de la branche complète avant publication finale. Tagger
avant cette revue donnerait un faux signal d'immutabilité et compliquerait une
correction éventuelle. La fusion vers `main` et le tag appartiennent donc à la
revue finale, pas à cette exécution.

## 7. Risques (table datée du 2026-08-28)

| # | Risque | Traitement |
|---|---|---|
| 1 | ~~Rendu QtQuick sous virtio-gpu en VM inconnu~~ | **Levé le 2026-08-28** (spike Task 1, vm-dev §12) : Quickshell/DMS rendent nativement sans variable ; seul Hyprland exige `LIBGL_ALWAYS_SOFTWARE=1` (réglage du banc d'essai VM, hors paquets). Errata : le repli `QSG_RHI_BACKEND=software` initialement nommé ici **n'existe pas** en Qt 6.11 (« Unknown key ») — le vrai serait `QT_QUICK_BACKEND=software` (dégradé : fond d'écran perdu), inutile en pratique. |
| 2 | Cadence DMS (1.x jeune) et **API de plugins non versionnée** (les plugins importent les internes `qs.*` et héritent de `PluginComponent` — aucune promesse de compatibilité) | Politique de version : suivre **`extra/dms-shell` uniquement** (jamais `-git` ni `master`, qui a ~440 commits d'avance) ; `requires_dms` **obligatoire** dans chaque `plugin.json` Eschaton ; smoke test CI de chargement des plugins ; les 12 plugins first-party servent de canari amont. |
| 3 | Fenêtre de suppression d'hyprlang (~0.57, oct. 2026) | Lua exclusif dès le premier commit (§4.1) — le risque devient nul pour nous. |
| 4 | `dms setup` écrase des configs | Règle de propriété §4.2 (amendée le 2026-08-28) : aucun fichier Eschaton sous `~/.config/hypr/` tout entier — accroche des défauts établie sur pièces en Task 2. |
| 5 | Surface D-Bus/polkit du plugin rollback | **Revue faite le 2026-08-28 (vague de fix pré-tag).** La règle `rules.d` qui rendait `polkit.Result.YES` pour `wheel`-actif-local est **supprimée** (`eschaton-dms-plugin-rollback` 0.1.0-3) : les `<defaults>` de l'action `org.eschaton.rollback` — `no` / `no` / `auth_admin`, sans `_keep` — exigent désormais une authentification à chaque restauration, par la modale de l'agent polkit de DMS (prouvée en Task 2, vm-dev §12.9). La surface restante est une action unique, annotée sur l'exécutable exact `/usr/bin/eschaton-rollback`, qui refuse toute forme non interactive autre que `--yes NUMÉRO`. La lecture des snapshots reste hors polkit (`ALLOW_GROUPS=wheel` de Snapper). Justification complète en tête de `org.eschaton.rollback.policy`. |
| 6 | Auto-login = session ouverte sans mot de passe | Assumé en VM de dogfooding ; le greeter authentifiant est un livrable SP4 explicite. |
| 7 | Retard `hyprland` sur ALARM (0.56.1 vs 0.56.2) — critique si ALARM traîne quand 0.57 supprimera hyprlang | Intégré à la surveillance ALARM instaurée par le Socle §8 risque 2. |
| 8 | Night mode DMS inopérant en VM (gamma matériel, issue upstream #2061) | Hors critères d'acceptation SP2 tant que le test réel n'a pas tranché. |
| 9 | Bus factor Quickshell = 1 (`outfoxxed`) | Surveillance ; atténué par l'empaquetage `extra` et le couplage humain avec DMS (lead DMS = contributeur n°2 de Quickshell). Déclencheur le plus probable du critère 4 de l'ADR 0001. |
| 10 | ~~Build `extra` de quickshell sans le module Polkit~~ | **Levé le 2026-08-28** (Task 2, investigation C) : « Not available » était un faux négatif de `dms doctor` — le greffon est lié dans le `qs` d'extra, la modale DMS fonctionne et l'élévation aboutit (matrice pkcheck mesurée). Aucun agent polkit externe requis ; `polkit` seul suffit au meta. |

Vérification de non-régression bi-architecture (recommandation de veille) : un script CI léger interroge les deux index de dépôts (API Arch + index miroir ALARM) et échoue si une dépendance d'`eschaton-desktop` manque d'un côté — le pendant SP2 du smoke test x86_64 du Socle.

## 8. Ce que le Bureau prépare

- **SP3 (Assistant IA)** : l'assistant naît plugin DMS (`composite` + permission `process`), les types de plugins couvrent le besoin initial (veille §2) ; s'il en déborde, c'est le critère 1 de l'ADR 0001 §4 qui se déclenche — en connaissance de cause.
- **SP4** : greeter graphique, verrouillage, thème clair, gestionnaire de paquets graphique complet s'il s'avère nécessaire (le plugin update v1 n'en est volontairement pas un).
- Les briques GUI tierces recensées par la veille (btrfs-assistant, pamac…) restent des replis d'intégration si un plugin natif s'avérait trop coûteux — décision par plugin, tracée.
