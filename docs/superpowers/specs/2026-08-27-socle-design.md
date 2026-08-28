# Eschaton — Spec de conception : le Socle

- **Date** : 2026-08-27
- **Statut** : implémenté (v0.1.0) — 2026-08-28
- **Sous-projet** : 1/5 (Socle)

---

## 1. Vision du projet (contexte)

Eschaton est une distribution Linux basée sur Arch qui vise, à terme, le grand public : un système complet « qui juste marche » — installation simple, mises à jour gérées, retour arrière garanti, gaming (Steam/Proton) — avec deux différenciateurs identitaires :

1. **Un bureau moderne entièrement pilotable en interface graphique** (Hyprland + Quickshell) : les réglages du bureau, mais aussi les paquets, les mises à jour, les snapshots et le matériel — sans jamais ouvrir un terminal. Omarchy, à l'inverse, assume le TUI comme réponse aux interfaces système (« Hyprland → Alacritty → un TUI ») et fait éditer ses configs dans Neovim : c'est un choix de design revendiqué, pas une lacune temporaire.
2. **Un assistant IA omniprésent intégré au cœur du système**, agnostique du fournisseur (Claude, OpenAI, Ollama…, au choix de l'utilisateur).

Le **tactile est un nice-to-have**, pas un différenciateur : le parc de laptops tactiles est marginal, et l'état de l'art Wayland (hyprgrass en alpha, clavier virtuel non résolu) ne justifie pas d'en faire un objectif de v1.

Inspirations assumées : **Omarchy** (légèreté, fluidité, esthétique, AI-first, dépôt de paquets maison, filet de snapshots) et **CachyOS** (plomberie éprouvée : Limine + btrfs + Snapper, installeur qui marche, gaming). Ces deux projets ont convergé indépendamment vers les mêmes fondations techniques — Eschaton reprend cette voie balisée. Le territoire qu'aucun des deux ne couvre, et qu'Eschaton vise : **une distro pilotable en GUI de bout en bout — le bureau ET la plomberie système — avec une IA systémique, pour le grand public**.

> **Note de veille (2026-08-27)** — Omarchy 4 « Quattro » (14 août 2026) a migré tout son bureau sur Quickshell : un process unique remplace Waybar, Walker, Mako, SwayOSD, hyprlock, hypridle, swaybg et polkit-gnome, et l'intégration d'agents IA y est désormais poussée (suivi de consommation dans la barre, diagnostic de crash confié à l'agent). « Hyprland + Quickshell » et « IA intégrée » ne différencient donc plus Eschaton d'Omarchy en tant que tels — seul le **zéro-terminal / GUI de bout en bout** le fait.

> **Note de veille (2026-08-28, passe SP2)** — la formulation ci-dessus est à son tour périmée : Omarchy 4 installe et supprime des paquets Arch **et AUR depuis son menu graphique** (l'affirmation « Omarchy assume le TUI comme réponse aux interfaces système » est fausse pour les paquets — sa page TUI ne liste que des outils de développement), a adopté le modèle *fat packages* et un système de plugins ; CachyOS livre un gestionnaire de paquets GUI par défaut depuis avril 2026. Le territoire encore vide, reformulé ([veille SP2](../../veille/2026-08-28-sp2-bureau.md) §6) : **le rollback et l'administration système comme fonctions natives et unifiées du shell** — pas comme applications tierces juxtaposées — combinés à l'assistant IA systémique. Cette affirmation est la plus volatile du projet : la veille se rejoue à l'ouverture de chaque sous-projet.

### 1.1 Décisions macro actées

| Sujet | Décision |
|---|---|
| Stratégie v1 | Dogfooding : l'auteur utilise Eschaton au quotidien. Le grand public est le cap, pas le critère de la v1. |
| Machine de dev | VM UTM **aarch64** sur Mac (M1 Pro, 32 Go). Architecture cible officielle : **x86_64** (validée en émulation, puis sur vrai matériel). |
| Base | **Arch vanilla** (pas de fork d'Omarchy ni de CachyOS). Côté aarch64 : Arch Linux ARM (ALARM). |
| Stratégie distro | Séquencée : couche sur Arch d'abord (paquets + configs), migration vers un modèle atomique/immuable plus tard. Les choix du jour 1 (btrfs + snapshots, état déclaré dans des paquets) rendent cette migration possible sans réinstallation. |
| Bureau | Hyprland + Quickshell. Base de départ : **DankMaterialShell** étendu par des plugins Eschaton, shell maison à terme — voir [ADR 0001](../../decisions/0001-shell-du-bureau.md). Sous-projet 2. |
| IA | Assistant omniprésent, provider-agnostique — sous-projet 3. |
| Gaming | Steam/Proton, x86_64 uniquement — différé en dernier (non testable en VM ARM). |

### 1.2 Découpage en sous-projets

Chaque sous-projet suit son propre cycle spec → plan → implémentation.

1. **Socle** *(cette spec)* — le système de base bootable, reproductible, avec rollback.
2. **Bureau** — Hyprland + Quickshell : barre, launcher, centre de contrôle, thème, gestes tactiles, clavier virtuel.
3. **Assistant IA** — l'overlay omniprésent avec outils système, couche d'abstraction de providers.
4. **Grand public** — installeur graphique, onboarding, mises à jour atomiques, chiffrement.
5. **Gaming** — Steam, Proton, drivers GPU, sur vrai matériel x86_64.

### 1.3 Trajectoire vers le x86_64 grand public

Le x86_64 n'est pas un portage futur : c'est la cible officielle dès le jour 1, l'aarch64 n'étant que le banc d'essai quotidien. Concrètement :

- les paquets `[eschaton]` sont `arch=(any)` : les mêmes fichiers, servis par le même dépôt, s'installent sur les deux architectures ;
- `eschaton-install` contient les deux branches dès sa première version (§4.2) ; côté x86_64 il s'appuie sur l'ISO Arch officielle et les dépôts Arch officiels ;
- le smoke test x86_64 fait partie de la définition de « Socle terminé » (§7) : la cible officielle ne peut pas régresser silencieusement pendant que le développement se fait sur ARM.

Le passage réel au grand public x86_64 (sous-projet 4) n'est donc pas un problème de mécanique mais de périmètre : ISO custom, installeur graphique, dépôt signé, et surtout la largeur du support matériel réel (GPU — Nvidia en tête —, Wi-Fi, laptops variés), qui ne se valide que sur de vraies machines. C'est aussi ce qui place le Gaming (sous-projet 5) après lui. L'aarch64 reste ensuite le banc d'essai de dev — et une piste bonus (Eschaton en VM sur Apple Silicon pour développeurs), pas la cible publique.

---

## 2. Périmètre du Socle

**Livrable** : un système Arch bootable qui s'identifie comme Eschaton (`os-release`), installable de façon reproductible :

- en VM UTM aarch64 (machine de dev quotidienne) ;
- en VM x86_64 émulée (validation périodique de la cible officielle) ;

avec un retour arrière fonctionnel dès le premier jour (snapshots bootables), un dépôt de paquets hébergé, et une commande de mise à jour unifiée.

**Non-buts en v0** (assumés, revisités dans les sous-projets suivants) :

- installeur graphique et ISO custom (sous-projet 4) ;
- chiffrement disque (LUKS) — sans objet en VM, obligatoire avant le grand public ;
- dual-boot, support matériel large, multi-utilisateurs ;
- signature cryptographique des paquets du dépôt (dette consciente, voir §5.3) ;
- hibernation (swap en zram uniquement).

---

## 3. Principe directeur : *thin installer, fat packages*

L'installation ne fait que : partitionner, `pacstrap`, poser les meta-paquets `eschaton-*`, configurer le bootloader. **Toute l'identité du système vit dans des paquets pacman versionnés** — dépendances, fichiers de configuration, services activés, branding. Jamais dans des scripts qui mutent `/etc` à la main.

Pourquoi :

- « Mettre à jour Eschaton » = `pacman -Syu`, comme n'importe quel paquet. Pose, remplacement, retrait : tout est tracé par pacman et réversible par snapshot.
- Le système reste diffable : l'état attendu est lisible dans les PKGBUILDs, pas reconstitué en rejouant l'historique de scripts.
- C'est la condition de la migration future vers un modèle atomique.

Contre-modèle documenté : le système de « migrations » d'Omarchy (scripts bash datés exécutés à chaque update). Ça fonctionne, mais chaque migration est une mutation d'état non déclarative. Eschaton n'a **pas** de système de migrations : si un jour une vraie migration d'état est inévitable, elle vivra dans un hook alpm de paquet, versionnée et idempotente — l'exception, pas l'architecture.

---

## 4. Installation

### 4.1 Environnements live

| Architecture | Environnement live | Statut |
|---|---|---|
| x86_64 | ISO Arch officielle | Éprouvé, aucun risque. |
| aarch64 (VM UTM) | **archboot aarch64** | **Validé le 2026-08-27** (spike Task 1) : chemin nominal fonctionnel, le mode « convergence » de repli est donc sans objet et n'a pas été développé. Projet actif (mainteneur Tobias Powalowski, développeur Arch ; aarch64 supporté depuis janvier 2022, dernière mise à jour juillet 2026). |

### 4.2 `eschaton-install` : un seul script, déroulé

Lancé depuis l'environnement live. Étapes :

1. **Préconditions** : boot UEFI, réseau fonctionnel, choix du disque cible (tout le disque — pas de dual-boot en v0).
2. **Questions minimales** : hostname (défaut `eschaton`), nom d'utilisateur, mot de passe. Locale/clavier/fuseau posés par défaut (`fr_FR.UTF-8`, `fr`, `Europe/Paris`), modifiables par option.
3. **Partitionnement** GPT (voir §4.3), formatage, création des subvolumes btrfs, montages.
4. **`pacstrap`** : `base`, kernel, `eschaton-base`, `eschaton-branding`. Le dépôt `[eschaton]` est ajouté au `pacman.conf` de l'environnement live au préalable.
5. **Configuration en chroot** : fstab, locale, fuseau, hostname, utilisateur (groupe `wheel`, sudo), zram.
6. **Bootloader** : installation de Limine sur l'ESP, config générée, `limine-snapper-sync` activé.
   > **Invariant à tenir** — `limine-snapper-sync` ne devine pas le nom de l'entrée de démarrage : sans `TARGET_OS_NAME` explicite dans `/etc/limine-snapper-sync.conf`, il se rabat sur `PRETTY_NAME` puis `NAME` de `/etc/os-release`. **Le nom de l'entrée dans `limine.conf` doit donc être exactement le `PRETTY_NAME` livré par `eschaton-branding`** (`Eschaton` aujourd'hui, des deux côtés). Toute divergence — par exemple un `PRETTY_NAME` embelli en « Eschaton Linux » — fait cesser silencieusement la génération des entrées de snapshot, c'est-à-dire le filet de sécurité tout entier. Deux façons de sortir de ce couplage par convention : fixer `TARGET_OS_NAME` dans une configuration livrée par `eschaton-base`, ou utiliser le mécanisme `comment: machine-id=<machine-id>` de l'entrée Limine, indépendant du nom.
7. **Services** : NetworkManager, snapper (+ `snap-pac` via dépendances), sshd (utile en VM, désactivable).
8. Redémarrage sur Eschaton.

Les seules branches par architecture, isolées dans une fonction dédiée du script :

| | x86_64 | aarch64 |
|---|---|---|
| Kernel | `linux` | `linux-aarch64` |
| Microcode | `intel-ucode` / `amd-ucode` (détection) | aucun |
| Dépôts Arch | officiels x86_64 | miroirs ALARM |

En début de développement, tant que le dépôt `[eschaton]` n'est pas encore publié, les meta-paquets s'installent depuis un build local (`makepkg`) — le chemin nominal reste le dépôt publié.

### 4.3 Disque

Table GPT, deux partitions :

| Partition | Taille | Format | Rôle |
|---|---|---|---|
| ESP | **4 Gio** | FAT32, montée sur `/boot` | Limine, kernels, initramfs, entrées de snapshots |
| Système | reste du disque | btrfs | tout le reste |

Subvolumes btrfs (layout plat) :

| Subvolume | Monté sur | Dans le rollback ? |
|---|---|---|
| `@` | `/` | **Oui** — c'est lui qu'on snapshote et restaure |
| `@home` | `/home` | Non — les données de l'utilisateur survivent au rollback |
| `@log` | `/var/log` | Non — les logs racontent ce qui s'est passé, même après restauration |
| `@pkg` | `/var/cache/pacman/pkg` | Non — cache de téléchargement, inutile à snapshoter |
| `@snapshots` | `/.snapshots` | Non — le stockage des snapshots eux-mêmes |

> **Pourquoi 4 Gio et pas 2** — l'upstream de `limine-snapper-sync` recommande « au moins 4 Gio » pour l'ESP, et son `LIMIT_USAGE_PERCENT` vaut **85 % par défaut** : au-delà de ce seuil, **plus aucune entrée de snapshot n'est ajoutée à Limine** (et avec `MAX_SNAPSHOT_ENTRIES=auto`, les anciennes sont supprimées sans avertissement). Chaque snapshot amarré au menu y stocke son kernel et son initramfs ; avec la rétention visée (§6), 2 Gio franchissent le seuil avant même que la rétention ne se stabilise — le filet de sécurité s'arrêterait donc en silence, alors qu'il est le critère n° 2 de « Socle terminé » (§7). La marge est d'autant plus nécessaire que le sous-projet 5 (gaming) amène les pilotes Nvidia et DKMS, que l'upstream chiffre à plus de 300 Mio par version de kernel.

Swap : **zram** (`zram-generator`), pas de partition. Mémoire compressée en RAM — adapté aux VM, pas d'hibernation possible (non-but assumé).

---

## 5. Paquets et dépôt

### 5.1 Structure du dépôt git (monorepo)

```
Eschaton/
├── docs/superpowers/specs/   # specs de design
├── packages/                 # un dossier par paquet (PKGBUILD + fichiers livrés)
│   ├── eschaton-base/
│   └── eschaton-branding/
├── installer/
│   └── eschaton-install      # script d'installation (live env → système posé)
├── repo/                     # outillage de build/publication du dépôt pacman
└── tools/                    # scripts de dev (création VM, boucle d'itération)
```

### 5.2 Les meta-paquets v0

**`eschaton-base`** — le système. Dépendances : `base`, `networkmanager`, `btrfs-progs`, `snapper`, `snap-pac`, `limine`, `limine-snapper-sync`, `limine-mkinitcpio-hook`, `zram-generator`, `openssh`, `sudo`, `git`, outils de base (`vim`, `htop`, `man-db`), et `eschaton-branding`. Le kernel n'en fait volontairement pas partie : un paquet `arch=(any)` ne peut pas avoir de dépendances conditionnelles par architecture, c'est donc `eschaton-install` qui le pose (branche par arch, §4.2). Livre les configs par défaut : `pacman.conf` drop-in du dépôt `[eschaton]`, config snapper du subvolume racine (rétention bornée), config zram, et les commandes `eschaton-update` / `eschaton-rollback` (§6).

**`eschaton-branding`** — l'identité. `os-release` (`ID=eschaton`, `ID_LIKE=arch`, `NAME=Eschaton`) — c'est ce qui fait qu'un système « est » Eschaton aux yeux des outils —, message d'accueil. Plus tard : fonds d'écran, écran de démarrage.

Convention défendue partout : **les valeurs par défaut vivent dans `/usr/`**, les personnalisations de l'utilisateur dans `/etc/` et son home (mécanisme de drop-ins). Une mise à jour ne piétine jamais les réglages locaux.

Les paquets suivants (`eschaton-desktop`, `eschaton-ai`…) seront ajoutés par les sous-projets suivants selon le même modèle.

### 5.3 Le dépôt pacman `[eschaton]`

Deux modes de vie :

- **Dev local** : `makepkg` dans la VM, installation directe. Boucle courte pour itérer sur un paquet.
- **Publié** : à chaque push sur `main`, la CI (GitHub Actions) construit les paquets, génère l'index (`repo-add`) et publie le tout sur GitHub Pages. Chaque machine Eschaton a `[eschaton]` dans son `pacman.conf` → `pacman -Syu` ramène les mises à jour Eschaton comme celles d'Arch. (Même schéma que l'OPR d'Omarchy.)

Les meta-paquets et paquets de configs sont `arch=(any)` : un seul build sert aarch64 et x86_64. Les rares paquets compilés à venir (ex. composants du Bureau) seront construits par architecture — les runners ARM de GitHub Actions couvrent ce besoin **dès aujourd'hui** : `ubuntu-*-arm` est généralement disponible en dépôt public depuis août 2025, et en dépôt privé depuis le 29 janvier 2026 (imputé sur les minutes incluses du plan). Le besoin est déjà réel : les deux paquets vendorés (§8, risque 3) sont des binaires natifs, pas des paquets `any`.

**Dette consciente** : pas de signature GPG des paquets en v0 (`SigLevel = Optional` pour `[eschaton]` uniquement — les dépôts Arch gardent leur vérification). Obligatoire avant toute distribution à des tiers ; tracé comme prérequis du sous-projet 4.

---

## 6. Mises à jour et retour arrière

- **`eschaton-update`** : vérifie l'espace disque disponible → `pacman -Syu` (dépôts Arch + `[eschaton]`) → signale clairement si un redémarrage est nécessaire (changement de kernel). Le snapshot « avant » est automatique (`snap-pac` sur chaque transaction pacman).
- **`eschaton-rollback`** : liste les snapshots avec date et cause, restauration au choix + redémarrage. *(Amendé le 2026-08-28, constat Task 10 : `snapper rollback` exige la disposition de sous-volumes d'openSUSE et échoue sur notre layout plat Arch — la restauration s'implémente par la méthode « replace » : snapshot en lecture-écriture du snapshot cible substitué au subvolume `@` par défaut. Même garantie, mécanique différente.)*
- **Système qui ne démarre plus** : menu Limine → entrées de snapshots (générées par `limine-snapper-sync`) → boot sur un état antérieur, puis rollback définitif depuis le système restauré. La mécanique exacte de conservation des kernels par snapshot est celle de `limine-snapper-sync` (éprouvée par CachyOS et Omarchy) ; ses réglages précis sont fixés à l'implémentation.
- **Rétention** : bornée pour tenir dans un disque de VM (~64 Gio) — de l'ordre de 10 paires pre/post automatiques plus les snapshots manuels ; valeur exacte fixée à l'implémentation dans la config snapper livrée par `eschaton-base`.

---

## 7. Vérification — définition de « Socle terminé »

1. **Installation reproductible** : depuis le Mac, la procédure documentée/scriptée (`tools/`) produit une VM UTM aarch64 qui boote Eschaton — `os-release` l'affirme, le réseau fonctionne, un utilisateur existe, `eschaton-update` s'exécute sans erreur.
2. **Test de casse réel** : sabotage volontaire du système (suppression d'un binaire critique ou paquet cassé) → restauration par snapshot → système fonctionnel. Exécuté pour de vrai, pas sur le papier.
3. **Cible x86_64 prouvée** : le même `eschaton-install` déroulé dans une VM x86_64 émulée (lente — smoke test uniquement) produit un système qui boote.
4. **CI verte** : lint des scripts shell (shellcheck), lint des PKGBUILDs (namcap), build des paquets, dépôt publié et installable.

La vérification est une checklist manuelle en v0 ; son automatisation (tests d'installation scriptés sous QEMU) est un chantier ultérieur.

> **Les quatre critères sont atteints au 2026-08-28** (`v0.1.0`). Le dossier de preuves — pour chacun : la section de `tools/vm-dev.md` qui la porte, le rapport de tâche, le commit — est consolidé dans [`tools/vm-dev.md` §11](../../../tools/vm-dev.md). Ce qui reste dû malgré tout y est nommé (§11.5).

---

## 8. Risques et décisions différées

*Table revue le 2026-08-27 (passe de veille, voir [ADR 0002](../../decisions/0002-veille-avant-spec.md)) ; ligne 9 ajoutée le 2026-08-28 (constat Task 11).*

| # | Risque / question | Traitement |
|---|---|---|
| 1 | ~~archboot aarch64 non validé comme environnement live~~ | **Levé le 2026-08-27** (spike Task 1) : chemin nominal validé, le mode convergence de repli est sans objet. |
| 2 | **Santé d'Arch Linux ARM (ALARM)** — socle du banc d'essai quotidien | **Requalifié (aggravé)**. ALARM est une distribution *non affiliée* à Arch, portée par une équipe très réduite : sur son organisation GitHub, seuls `PKGBUILDs` et `wiki` bougent en 2026, et `archlinuxarm-keyring` n'a pas été touché depuis novembre 2022 ; la communauté rapporte des dépôts en retard de plusieurs semaines. Le risque n'est donc pas la « divergence de versions » mais un **gel**, et un keyring périmé casserait `pacman -Syu` sur le banc d'essai. Traitement : ALARM reste le choix v0 (prouvé fonctionnel par les spikes Task 1 et 6), la **surveillance devient explicite**, et deux portes de sortie sont identifiées — voir §8.1. |
| 3 | `limine-snapper-sync` et `limine-mkinitcpio-hook` absents des dépôts | Packagés dans `[eschaton]`. Confirmé côté ALARM par la Task 6 ; `limine` lui-même est bien présent (`extra/limine 12.6.1-1`, aarch64), aucune contingence nécessaire de ce côté. |
| 4 | Dépôt non signé | Dette v0 assumée, prérequis bloquant du sous-projet 4 (grand public). |
| 5 | Émulation x86_64 très lente sur Apple Silicon | Réservée aux smoke tests périodiques ; le vrai matériel x86_64 arrive avec les sous-projets 4–5. |
| 6 | **`gradle` inutilisable sur les deux architectures** — `makedepends` des deux paquets vendorés | Constaté le 2026-08-27 : absent des dépôts ALARM, et `extra/gradle 9.7.0-1` est cassé sur Arch x86_64 (module `gradle-public-api-legacy` manquant). Contournement en place : `tools/provision-gradle` installe la distribution officielle épinglée par somme SHA-256, sans modifier les PKGBUILDs vendorés. **Dette surveillée** : à retirer dès qu'Arch répare `extra/gradle` ; sa version et sa somme se maintiennent comme n'importe quelle dépendance épinglée. |
| 7 | **Comportements intrusifs hérités de `limine-mkinitcpio-hook`** | Le paquet installe un wrapper `mkinitcpio` dans `/usr/local/bin` (précède `/usr/bin` dans le `PATH`, **ne propage pas le code de retour** du vrai binaire, et son invite se déclenche toute seule sur EOF en contexte non interactif), plus un hook pacman dans `/etc/pacman.d/hooks/` qui **remplace celui de `mkinitcpio`** sans figurer dans `backup=()`. Ce ne sont pas des failles mais des choix upstream dont Eschaton hérite. Mitigation en place : `eschaton-install` se termine par une vérification explicite du contenu de `/boot`, précisément pour qu'un initramfs non généré ne passe pas pour un succès. |
| 8 | **Rupture silencieuse du filet de snapshots** | Deux mécanismes de `limine-snapper-sync` échouent sans bruit : le seuil `LIMIT_USAGE_PERCENT` (85 % de l'ESP) et le couplage du nom d'OS avec l'entrée `limine.conf` (§4.2 étape 6). Traitement : ESP portée à 4 Gio (§4.3) et invariant de nommage documenté. **Prouvé en conditions réelles le 2026-08-28** (§7.2 — casse, rollback, boot-sur-snapshot : voir [`tools/vm-dev.md` §9 et §11](../../../tools/vm-dev.md)). |
| 9 | **Double Limine sur x86_64** — `limine-entry-tool` installe son propre exemplaire (`/boot/EFI/limine/`) et une entrée NVRAM prioritaire, à côté de celui posé par l'installeur (`EFI/BOOT/BOOTX64.EFI`) | Constaté le **2026-08-28** (Task 11). Bénin tant que les binaires sont identiques (même paquet) ; dette surveillée si les chemins de mise à jour divergent un jour. Traitement : **surveillance**, consigné `tools/vm-dev.md` §10.6. |

### 8.1 Portes de sortie si ALARM décroche

Aucune n'est activée aujourd'hui ; elles sont identifiées pour que le décrochage d'ALARM soit un arbitrage et non une surprise.

- **Arch Linux Ports — aarch64** ([RFC 0032](https://rfc.archlinux.page/0032-arch-linux-ports/)) : banc d'essai officiellement reconnu par Arch pour les architectures non supportées, dépôts communautaires, images reconstruites tous les ~15 jours. Réserve : paquets bâtis pour **ARMv8.2-A minimum**, non signés par Arch, hors infrastructure Arch.
- **Holo Core** (Collabora / Valve, préview publique de juillet 2026) : port aarch64 d'Arch servant de base au Steam Frame, avec binaires, sources et conteneurs de développement publiés. Réserve : **pas de reconstruction complète du monde** — quelques milliers de paquets, ciblés sur les besoins du Steam Frame. À surveiller pour deux raisons : c'est le port aarch64 le mieux financé à ce jour, et il est directement adjacent au sous-projet 5 (gaming).
- **Arch Linux lui-même** n'a toujours **pas** d'aarch64 officiel (statut « unofficial », aucun RFC de promotion en cours au 2026-08-27). C'est le signal à guetter : il rendrait ces portes de sortie caduques.

---

## 9. Ce que le Socle prépare pour la suite

- **Bureau (sous-projet 2)** : s'ajoutera comme meta-paquet `eschaton-desktop` tiré par le socle, les extensions maison étant packagées séparément (`eschaton-dms-plugin-*`) conformément à l'[ADR 0001](../../decisions/0001-shell-du-bureau.md) ; la VM UTM sert de banc d'essai quotidien. Point de vigilance : ni Quickshell ni DankMaterialShell n'ont de binaires ALARM — tout se compile sur le banc d'essai aarch64.
- **Assistant IA (sous-projet 3)** : meta-paquet `eschaton-ai` ; la couche d'abstraction de providers fera l'objet de sa propre spec.
- **Atomique futur (sous-projet 4)** : la discipline « état = paquets » + btrfs rend la migration vers des mises à jour atomiques possible sans réinstallation.
- **ISO** : aucun ISO pendant le Socle (installation = ISO Arch officielle + `eschaton-install`, le chemin qu'Omarchy a suivi toute sa v1). Un premier ISO minimal x86_64 (archiso : boote et lance l'installeur) devient pertinent dès la fin du sous-projet 2, quand Eschaton est montrable. L'ISO grand public complet — session live, installeur graphique, paquets embarqués pour installation hors-ligne, dépôt signé — reste au sous-projet 4.
