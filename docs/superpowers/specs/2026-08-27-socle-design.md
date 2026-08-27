# Eschaton — Spec de conception : le Socle

- **Date** : 2026-08-27
- **Statut** : validé en brainstorming — en attente de relecture finale
- **Sous-projet** : 1/5 (Socle)

---

## 1. Vision du projet (contexte)

Eschaton est une distribution Linux basée sur Arch qui vise, à terme, le grand public : un système complet « qui juste marche » — installation simple, mises à jour gérées, retour arrière garanti, gaming (Steam/Proton) — avec deux différenciateurs identitaires :

1. **Une expérience bureau fluide et belle, pensée tactile ET souris** (Hyprland + Quickshell), là où Omarchy est clavier/terminal-first.
2. **Un assistant IA omniprésent intégré au cœur du système**, agnostique du fournisseur (Claude, OpenAI, Ollama…, au choix de l'utilisateur).

Inspirations assumées : **Omarchy** (légèreté, fluidité, esthétique, AI-first, dépôt de paquets maison, filet de snapshots) et **CachyOS** (plomberie éprouvée : Limine + btrfs + Snapper, installeur qui marche, gaming). Ces deux projets ont convergé indépendamment vers les mêmes fondations techniques — Eschaton reprend cette voie balisée. Le territoire qu'aucun des deux ne couvre, et qu'Eschaton vise : **bureau tactile designé d'un bloc + IA systémique + grand public**.

### 1.1 Décisions macro actées

| Sujet | Décision |
|---|---|
| Stratégie v1 | Dogfooding : l'auteur utilise Eschaton au quotidien. Le grand public est le cap, pas le critère de la v1. |
| Machine de dev | VM UTM **aarch64** sur Mac (M1 Pro, 32 Go). Architecture cible officielle : **x86_64** (validée en émulation, puis sur vrai matériel). |
| Base | **Arch vanilla** (pas de fork d'Omarchy ni de CachyOS). Côté aarch64 : Arch Linux ARM (ALARM). |
| Stratégie distro | Séquencée : couche sur Arch d'abord (paquets + configs), migration vers un modèle atomique/immuable plus tard. Les choix du jour 1 (btrfs + snapshots, état déclaré dans des paquets) rendent cette migration possible sans réinstallation. |
| Bureau | Hyprland + Quickshell — sous-projet 2. |
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
| aarch64 (VM UTM) | **archboot aarch64** (candidat) | À valider par un test réel — première tâche du plan. Repli : image Arch Linux ARM préfabriquée, amenée à l'état Eschaton par un mode « convergence » de `eschaton-install` (mêmes étapes sans partitionnement ni pacstrap) — mode développé uniquement si archboot échoue. |

### 4.2 `eschaton-install` : un seul script, déroulé

Lancé depuis l'environnement live. Étapes :

1. **Préconditions** : boot UEFI, réseau fonctionnel, choix du disque cible (tout le disque — pas de dual-boot en v0).
2. **Questions minimales** : hostname (défaut `eschaton`), nom d'utilisateur, mot de passe. Locale/clavier/fuseau posés par défaut (`fr_FR.UTF-8`, `fr`, `Europe/Paris`), modifiables par option.
3. **Partitionnement** GPT (voir §4.3), formatage, création des subvolumes btrfs, montages.
4. **`pacstrap`** : `base`, kernel, `eschaton-base`, `eschaton-branding`. Le dépôt `[eschaton]` est ajouté au `pacman.conf` de l'environnement live au préalable.
5. **Configuration en chroot** : fstab, locale, fuseau, hostname, utilisateur (groupe `wheel`, sudo), zram.
6. **Bootloader** : installation de Limine sur l'ESP, config générée, `limine-snapper-sync` activé.
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
| ESP | 2 Gio | FAT32, montée sur `/boot` | Limine, kernels, initramfs, entrées de snapshots |
| Système | reste du disque | btrfs | tout le reste |

Subvolumes btrfs (layout plat) :

| Subvolume | Monté sur | Dans le rollback ? |
|---|---|---|
| `@` | `/` | **Oui** — c'est lui qu'on snapshote et restaure |
| `@home` | `/home` | Non — les données de l'utilisateur survivent au rollback |
| `@log` | `/var/log` | Non — les logs racontent ce qui s'est passé, même après restauration |
| `@pkg` | `/var/cache/pacman/pkg` | Non — cache de téléchargement, inutile à snapshoter |
| `@snapshots` | `/.snapshots` | Non — le stockage des snapshots eux-mêmes |

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

**`eschaton-base`** — le système. Dépendances : `base`, `btrfs-progs`, `networkmanager`, `snapper`, `snap-pac`, `limine`, `limine-snapper-sync`, `zram-generator`, `openssh`, `sudo`, `git`, outils de base (`vim`, `htop`, `man-db`). Le kernel n'en fait volontairement pas partie : un paquet `arch=(any)` ne peut pas avoir de dépendances conditionnelles par architecture, c'est donc `eschaton-install` qui le pose (branche par arch, §4.2). Livre les configs par défaut : `pacman.conf` drop-in du dépôt `[eschaton]`, config snapper du subvolume racine (rétention bornée), config zram, et les commandes `eschaton-update` / `eschaton-rollback` (§6).

**`eschaton-branding`** — l'identité. `os-release` (`ID=eschaton`, `ID_LIKE=arch`, `NAME=Eschaton`) — c'est ce qui fait qu'un système « est » Eschaton aux yeux des outils —, message d'accueil. Plus tard : fonds d'écran, écran de démarrage.

Convention défendue partout : **les valeurs par défaut vivent dans `/usr/`**, les personnalisations de l'utilisateur dans `/etc/` et son home (mécanisme de drop-ins). Une mise à jour ne piétine jamais les réglages locaux.

Les paquets suivants (`eschaton-desktop`, `eschaton-ai`…) seront ajoutés par les sous-projets suivants selon le même modèle.

### 5.3 Le dépôt pacman `[eschaton]`

Deux modes de vie :

- **Dev local** : `makepkg` dans la VM, installation directe. Boucle courte pour itérer sur un paquet.
- **Publié** : à chaque push sur `main`, la CI (GitHub Actions) construit les paquets, génère l'index (`repo-add`) et publie le tout sur GitHub Pages. Chaque machine Eschaton a `[eschaton]` dans son `pacman.conf` → `pacman -Syu` ramène les mises à jour Eschaton comme celles d'Arch. (Même schéma que l'OPR d'Omarchy.)

Les meta-paquets et paquets de configs sont `arch=(any)` : un seul build sert aarch64 et x86_64. Les rares paquets compilés à venir (ex. composants du Bureau) seront construits par architecture — les runners ARM de GitHub Actions couvrent ce besoin le moment venu.

**Dette consciente** : pas de signature GPG des paquets en v0 (`SigLevel = Optional` pour `[eschaton]` uniquement — les dépôts Arch gardent leur vérification). Obligatoire avant toute distribution à des tiers ; tracé comme prérequis du sous-projet 4.

---

## 6. Mises à jour et retour arrière

- **`eschaton-update`** : vérifie l'espace disque disponible → `pacman -Syu` (dépôts Arch + `[eschaton]`) → signale clairement si un redémarrage est nécessaire (changement de kernel). Le snapshot « avant » est automatique (`snap-pac` sur chaque transaction pacman).
- **`eschaton-rollback`** : liste les snapshots avec date et cause, restauration au choix (`snapper rollback` + redémarrage).
- **Système qui ne démarre plus** : menu Limine → entrées de snapshots (générées par `limine-snapper-sync`) → boot sur un état antérieur, puis rollback définitif depuis le système restauré. La mécanique exacte de conservation des kernels par snapshot est celle de `limine-snapper-sync` (éprouvée par CachyOS et Omarchy) ; ses réglages précis sont fixés à l'implémentation.
- **Rétention** : bornée pour tenir dans un disque de VM (~64 Gio) — de l'ordre de 10 paires pre/post automatiques plus les snapshots manuels ; valeur exacte fixée à l'implémentation dans la config snapper livrée par `eschaton-base`.

---

## 7. Vérification — définition de « Socle terminé »

1. **Installation reproductible** : depuis le Mac, la procédure documentée/scriptée (`tools/`) produit une VM UTM aarch64 qui boote Eschaton — `os-release` l'affirme, le réseau fonctionne, un utilisateur existe, `eschaton-update` s'exécute sans erreur.
2. **Test de casse réel** : sabotage volontaire du système (suppression d'un binaire critique ou paquet cassé) → restauration par snapshot → système fonctionnel. Exécuté pour de vrai, pas sur le papier.
3. **Cible x86_64 prouvée** : le même `eschaton-install` déroulé dans une VM x86_64 émulée (lente — smoke test uniquement) produit un système qui boote.
4. **CI verte** : lint des scripts shell (shellcheck), lint des PKGBUILDs (namcap), build des paquets, dépôt publié et installable.

La vérification est une checklist manuelle en v0 ; son automatisation (tests d'installation scriptés sous QEMU) est un chantier ultérieur.

---

## 8. Risques et décisions différées

| # | Risque / question | Traitement |
|---|---|---|
| 1 | archboot aarch64 non validé comme environnement live | Première tâche du plan = test réel. Repli : image ALARM préfabriquée + mode convergence de `eschaton-install`. |
| 2 | Divergence ALARM ↔ Arch x86_64 (dépôts distincts, versions décalées) | Acceptée : la VM ARM ne sert qu'à itérer sur des couches arch-agnostiques ; smoke tests x86_64 réguliers. |
| 3 | `limine-snapper-sync` absent des dépôts Arch officiels | Packagé dans `[eschaton]` (c'est précisément le rôle du dépôt). |
| 4 | Dépôt non signé | Dette v0 assumée, prérequis bloquant du sous-projet 4 (grand public). |
| 5 | Émulation x86_64 très lente sur Apple Silicon | Réservée aux smoke tests périodiques ; le vrai matériel x86_64 arrive avec les sous-projets 4–5. |

---

## 9. Ce que le Socle prépare pour la suite

- **Bureau (sous-projet 2)** : s'ajoutera comme meta-paquet `eschaton-desktop` tiré par le socle ; la VM UTM sert de banc d'essai quotidien.
- **Assistant IA (sous-projet 3)** : meta-paquet `eschaton-ai` ; la couche d'abstraction de providers fera l'objet de sa propre spec.
- **Atomique futur (sous-projet 4)** : la discipline « état = paquets » + btrfs rend la migration vers des mises à jour atomiques possible sans réinstallation.
