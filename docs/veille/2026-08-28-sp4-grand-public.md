# Veille sous-projet 4 (Grand public) — passe datée du 2026-08-28/29

- **Date de la passe** : 2026-08-28 (recherches menées le 2026-08-28, sources horodatées jusqu'au 2026-08-28)
- **Cadre** : [ADR 0002 — veille avant spec](../../../docs/decisions/0002-veille-avant-spec.md)
- **Portée** : sous-projet 4 « Grand public » — ISO, installeur graphique, onboarding, greeter, signature du dépôt, mises à jour atomiques, chiffrement, support matériel
- **Statut** : rapport de recherche. **Aucune modification du dépôt.** Le SP3 s'exécutait en parallèle ; rien n'a été touché.
- **Durée de validité** : cette veille **sera rejouée à l'ouverture réelle du SP4** (deltas). Les affirmations les plus périssables sont listées en §10.

---

## 1. Synthèse — les affirmations amont face au réel

| # | Affirmation amont | Verdict | Constat daté | Source |
|---|---|---|---|---|
| 1 | Spec Socle §9 : « L'ISO grand public complet — session live, **installeur graphique**, paquets embarqués pour installation hors-ligne, dépôt signé — reste au sous-projet 4 » | **Confirmé comme périmètre, mais le mot « graphique » est à réexaminer** | Le concurrent le plus proche, **Omarchy 4 « Quattro »**, n'a **pas** écrit d'installeur graphique : son « Configurator » est un script bash d'environ 1 000 lignes utilisant `gum` (UI **terminal**), qui écrit `user_configuration.json` / `user_credentials.json` et **délègue l'installation à `archinstall`**. Constaté 2026-08-28 dans `configs/airootfs/root/configurator` (branche `quattro`). | [omacom/omarchy-iso](https://github.com/omacom/omarchy-iso), [DeepWiki — Installation System](https://deepwiki.com/omacom-io/omarchy-iso/3-installation-system) |
| 2 | Spec Socle §9 : « Un premier ISO minimal x86_64 (archiso : boote et lance l'installeur) devient pertinent dès la fin du sous-projet 2 » | **Jamais fait — et à requalifier** | Rien n'a été produit. Requalification proposée : un **ISO en ligne ≤ 2 GiO** (hébergeable sur GitHub Releases) est le vrai premier jalon ; l'ISO hors-ligne complet est un chantier distinct, contraint par l'hébergement (§2.6). | Constat local ; [limites GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits) |
| 3 | Spec Socle §5.3 / §8 risque 4 : « pas de signature GPG des paquets en v0 […] prérequis bloquant du sous-projet 4 » | **Confirmé, et le patron de résolution est désormais public et daté** | **Le 2026-08-24**, Omarchy a basculé `[omarchy]` de `SigLevel = Optional TrustAll` vers l'héritage du global `Required DatabaseOptional`, via une migration auto-réparante qui **nomme explicitement le problème d'amorçage**. Texte verbatim en §4.1. CachyOS (`cachyos-keyring`, clé `F3B607488DB35A47`) et EndeavourOS (`endeavouros-keyring`) appliquent le même patron depuis des années. | [migration `1787589206.sh`](https://github.com/basecamp/omarchy) (lue via l'API GitHub le 2026-08-28) |
| 4 | ADR 0003 §8 (amendement 3) : « le greeter authentifié du SP4 hérite d'une exigence ferme — module PAM `gnome-keyring` configuré, déverrouillage au login prouvé » | **Confirmé, et la cause racine est désormais établie** | `greetd` en **autologin contourne entièrement la pile `auth` de PAM** : aucun module de type `pam_gnome_keyring` ne peut y capter le mot de passe. L'exigence n'est donc pas un raffinement, c'est la **conséquence mécanique** de l'abandon de l'autologin. | [NixOS Discourse, fil greetd + gnome-keyring](https://discourse.nixos.org/t/automatically-unlocking-the-gnome-keyring-using-luks-key-with-greetd-and-hyprland/54260) |
| 5 | Spec Bureau §non-buts : « greeter graphique et écran de verrouillage soignés (SP4) » | **Nuancé — le coût est bien plus faible qu'anticipé** | Le greeter DMS **est déjà livré par `extra/dms-shell`** (`/usr/share/quickshell/dms/Modules/Greetd/assets/dms-greeter`), donc disponible sur x86_64 et aarch64 sans AUR ; et **`archinstall` 4.x le câble officiellement** (`GreeterType.GreetdDms`). L'écran de verrouillage est déjà dans DMS (remplace hyprlock/hypridle). | [liste de fichiers `dms-shell`](https://archlinux.org/packages/extra/x86_64/dms-shell/files/), `archinstall/lib/profile/profiles_handler.py` |
| 6 | Spec Socle §1.1 : « migration vers un modèle atomique/immuable plus tard » ; §9 : « la discipline “état = paquets” + btrfs rend la migration vers des mises à jour atomiques possible » | **Nuancé — l'atomique n'est pas le bon objectif v1** | La différence réelle entre `snapper`+`snap-pac` et `transactional-update` n'est pas le rollback (les deux l'ont) mais **le lieu d'application** : l'un applique dans le système vivant et répare après coup, l'autre applique dans un snapshot isolé et n'active qu'en cas de succès. Le pas intermédiaire utile est donc l'**application hors-ligne**, pas l'A/B. Position détaillée en §5.4. | [openSUSE/transactional-update](https://github.com/openSUSE/transactional-update) |
| 7 | Spec Socle §1.3 : « la largeur du support matériel réel (GPU — Nvidia en tête —, Wi-Fi, laptops variés) […] ne se valide que sur de vraies machines » | **Confirmé, et le plancher est maintenant chiffrable** | Arch a **retiré `nvidia` et `nvidia-dkms` de ses dépôts** au profit de `nvidia-open` / `nvidia-open-dkms` ; le pilote 590 **abandonne Maxwell (GTX 900) et Pascal (GTX 10xx)** (annonce Arch du 2025-12-20). Vérifié dans l'index Arch le 2026-08-28 : aucun paquet `nvidia` ni `nvidia-dkms`. **Le plancher matériel Nvidia d'Eschaton v1 est donc Turing (RTX 20xx / GTX 16xx).** | [index Arch `nvidia`](https://archlinux.org/packages/?q=nvidia), [Phoronix](https://www.phoronix.com/news/Arch-LInux-NVIDIA-Open-Default), [TechPowerUp](https://www.techpowerup.com/344385/arch-linux-drops-support-for-nvidia-pascal-and-older-gpus) |
| 8 | Spec Socle §2 non-buts : « chiffrement disque (LUKS) — sans objet en VM, obligatoire avant le grand public » | **Confirmé — et notre layout est déjà le bon** | Le README de `limine-snapper-sync` **recommande explicitement** de garder kernel/initramfs/UKI **hors** de la partition chiffrée, pour un déchiffrement rapide et une invite Plymouth graphique. Notre ESP FAT32 de 4 GiO montée sur `/boot` (spec §4.3) est exactement cette disposition — décidée pour la rétention, elle se trouve être aussi la bonne décision de chiffrement. | [README limine-snapper-sync](https://gitlab.com/Zesko/limine-snapper-sync) |
| 9 | Différés routés SP4 (bilan d'exécution) : `partprobe`/`udevadm settle`, validation d'arguments installeur, `visudo -cf` en CI, `sshd` par défaut, actions CI épinglées par SHA | **Tous confirmés comme dus — et l'un d'eux change de nature** | L'épinglage des actions par SHA cesse d'être une hygiène pour devenir un **prérequis de sécurité** dès que la clé de signature approche la CI (§4.4). `sshd` activé par défaut est à re-peser dans le même mouvement : un système grand public livré avec un service d'écoute est une décision, pas un reliquat de VM. | [bilan SP1](../../../docs/superpowers/bilans/2026-08-28-socle-execution.md) §18 ; [guide de durcissement GitHub Actions, Wiz](https://www.wiz.io/blog/github-actions-security-guide) |
| 10 | Spec Bureau risque 6 : « auto-login = session ouverte sans mot de passe — assumé en VM » | **Confirmé, avec une conséquence non anticipée** | Sous autologin, non seulement la session est ouverte sans mot de passe, mais **le trousseau ne peut structurellement pas être déverrouillé par PAM** (cf. #4). Les deux dettes — session non authentifiée et secrets en clair au repos — sont **une seule dette**, et un seul livrable les solde. | idem #4 ; [ADR 0003 §8](../../../docs/decisions/0003-service-secrets-assistant.md) |

---

## 2. Axe 1 — ISO & installeur graphique : l'état de l'art Arch 2026

### 2.1 `archiso` — l'outil, et ce qu'il sait faire

`extra/archiso 89-1` (`any`, mis à jour le **2026-07-27**) ; `extra/mkinitcpio-archiso 73-1` (2025-11-17). Le mode d'emploi n'a pas changé : on copie un profil de `/usr/share/archiso/configs/<profil>/` (`releng` ou `baseline`), on édite `packages.x86_64`, on dépose des fichiers dans `airootfs/`, on construit avec `mkarchiso`.

**Dépôt local embarqué pour installation hors-ligne : oui, et le patron est établi.** Il consiste à (1) télécharger les paquets et leurs dépendances avec `pacman -Syw` dans un répertoire de l'`airootfs`, (2) construire l'index avec `repo-add`, (3) fournir un `pacman.conf` de remplacement qui pointe sur ce répertoire, (4) le *bind-mount* pendant le `chroot` pour qu'il reste visible côté cible. C'est exactement ce que fait `builder/build-iso.sh` d'Omarchy, avec en prime `prune-offline-mirror.sh` qui élague le miroir aux seules archives retenues.

**Ce que `archiso` ne fait pas** : le **Secure Boot**. Le média d'installation officiel d'Arch ne le supporte pas — et n'a rien supporté depuis 2016. Le seul environnement live Arch avec Secure Boot est **archboot** (depuis octobre 2021), que nous utilisons déjà côté aarch64 (spec §4.1). C'est une donnée à intégrer : un ISO Eschaton bâti sur `archiso` ne bootera pas sur une machine grand public dont le Secure Boot n'est pas désactivé.

### 2.2 Omarchy 4 « Configurator » — l'anatomie exacte (l'infirmation la plus utile de cette passe)

Dépôt : [`omacom/omarchy-iso`](https://github.com/omacom/omarchy-iso) — 235 ★, MIT, créé le 2025-07-27, dernier push **2026-08-28** (branche par défaut `quattro`, 493 commits). Contenu de premier niveau : `.github/ bin/ builder/ configs/ manifests/ plans/ test/` + un sous-module `archiso`.

Ce qui a été lu directement :

- **`configs/airootfs/root/configurator`** — ~1 000 lignes de **bash**, UI **`gum`** (`gum choose`, `gum confirm`, `gum input`, `gum style`, `gum spin`, `gum table`). Il collecte : clavier, nom d'utilisateur, mot de passe, identité (nom complet + e-mail, facultatifs), hostname, fuseau (auto-détecté par `tzupdate`), disque cible (les disques sont énumérés avec vendeur/modèle/taille/partitions, le média de boot est exclu), mode d'installation (**disque entier** ou **espace libre**), et **chiffrement LUKS2 ou non**.
- Il **ne pilote pas archiso ni pacstrap directement** : il écrit `user_configuration.json` et `user_credentials.json`, et un script orchestrateur appelle ensuite **`archinstall`** en mode silencieux, puis exécute la personnalisation Omarchy dans le chroot.
- **Dual-boot partiel** : en mode « espace libre », il détecte l'ESP Windows existante et **crée toujours son propre ESP dédiée** plutôt que d'adopter celle de Windows. En mode disque entier : « *Everything will be overwritten. There is no recovery possible.* »
- **Mode OEM** : `Ctrl+C` sur le premier écran bascule en « provisionnement différé » — le système s'installe, et la configuration finale (utilisateur, etc.) a lieu **au premier démarrage**. C'est le précédent d'onboarding le plus directement réutilisable pour Eschaton.
- **Auto-installation** : un fichier de configuration sur un second disque étiqueté `cidata` déclenche une installation sans interaction (compatible Proxmox, libvirt, Packer).

Le dépôt `omacom/omarchy-configurator` (42 ★, **Shell**, dernier push **2025-09-14**) est l'ancêtre, désormais figé — confirmation supplémentaire que la technologie est le bash, pas une interface graphique.

> **Conséquence directe** : la phrase de la spec Socle §1 (« Omarchy assume le TUI comme réponse aux interfaces système »), déjà **infirmée pour les paquets** par la veille SP2, reste en revanche **exacte pour l'installation**. Personne, dans la famille Arch « moderne », n'a d'installeur graphique maison.

### 2.3 `archinstall` — le composant qui change le calcul « acheter vs construire »

Cadence 2026 : **4.0** le 2026-03-30 (bascule de `curses` vers **Textual**, TUI asynchrone), **4.1** le 2026-03-31, **4.2** le 2026-04-15, **4.3** le 2026-04-20, **4.4** le **2026-06-28** (profil `niri` + DankMaterialShell, contribué par le lead DMS — déjà relevé par la veille SP2).

Ce que la configuration JSON couvre aujourd'hui (lu dans `examples/config-sample.json`, `docs/cli_parameters/config/config_options.csv` et `archinstall/lib/models/`) :

| Besoin d'Eschaton | Couvert par archinstall ? | Détail |
|---|---|---|
| Bootloader **Limine** | **Oui** | `Bootloader.Limine` dans `models/bootloader.py`, aux côtés de Systemd-boot, Grub, Efistub, Refind. `removable: true` installe dans `/EFI/BOOT/` plutôt qu'en NVRAM — **exactement notre chemin actuel** (`EFI/BOOT/BOOTX64.EFI`). `uki: true` disponible (systemd-boot/limine seulement). |
| btrfs + subvolumes | **Oui** | `disk_config` décrit partitions et subvolumes ; layout btrfs suggéré depuis 3.0.5. |
| **Snapper** | **Oui** | `SnapshotType = {Snapper, Timeshift}`, `SnapshotConfig` dans `models/device.py`. |
| **LUKS2** | **Oui** | `disk_encryption`, appliqué par-dessus `disk_config`. |
| Dépôt `[eschaton]` avec son `SigLevel` | **Oui** | `mirror_config.custom_repositories: [{name, url, sign_check, sign_option}]` — `sign_check` = `Required`, `sign_option` = `TrustAll`… ce sont littéralement les deux moitiés d'une ligne `SigLevel`. |
| Paquets `eschaton-*` | **Oui** | `packages: []`. |
| Provisioning post-install | **Oui** | `custom_commands` (exécutées en chroot). |
| Greeter DMS | **Oui** | `GreeterType.GreetdDms = 'dms-greeter'` (§3.2). |
| Installation silencieuse pilotée par fichier | **Oui** | `silent: true` + `script: guided|minimal|only_hdd`, plus un mode bibliothèque Python. |
| Locale/clavier/fuseau/hostname/utilisateur | **Oui** | `locale_config`, `timezone`, `hostname`. |
| Miroirs personnalisés | **Oui** | `mirror_config.custom_servers`. |

**Ce que la spec Socle a écrit à la main et qu'archinstall sait déjà faire : à peu près tout, sauf trois choses** — l'imbrication exacte de `limine.conf` qu'exige `limine-snapper-sync` (spec §4.2, découverte en Task 9), la vérification post-install de `/boot` (risque 7), et la branche aarch64/ALARM (archinstall est un outil Arch x86_64).

### 2.4 Calamares — santé, modèle, et pourquoi il ne colle pas naturellement

- **Le dépôt GitHub `calamares/calamares` est ARCHIVÉ** (dernier push 2025-05-06, dernière release GitHub `v3.3.14` du 2025-02-20). Le développement a migré sur **Codeberg**.
- Sur Codeberg : **3.4.2 le 2026-03-10**, décrite comme « la première release réellement taguée depuis Codeberg », avec une **nouvelle clé de signature des archives pour 2026**. 3.4.0 (2025-07-21) était une « test release ». **Une seule release en 2026** au 2026-08-28 — projet vivant, mais à cadence lente, porté majoritairement par des développeurs KDE.
- **Le modèle d'installation ne correspond pas au nôtre** : Calamares installe en **déballant un squashfs** de l'ISO (module `unpackfs`), c'est-à-dire « l'ISO *est* l'image système ». Notre principe directeur est l'inverse (spec §3) : *thin installer, fat packages* — on `pacstrap` des paquets. Adopter Calamares, c'est soit adopter le modèle image (et perdre la traçabilité pacman de l'état initial), soit écrire un module de remplacement.
- **Côté positif pour la cohérence DMS** : Calamares supporte des **modules de vue en QML**, et le branding peut remplacer la barre latérale et la navigation par du QML (`calamares-sidebar.qml`, `calamares-navigation.qml`). Une identité Eschaton en QML dans Calamares est donc possible sans fork.
- **Côté négatif packaging** : Calamares n'est **pas dans les dépôts Arch officiels** — seulement AUR (`calamares`, `calamares-git`), avec un historique documenté de casse liée aux versions de Qt6 (commentaires AUR non datés dans les résultats consultés — **à re-vérifier à l'ouverture**). CachyOS le maintient dans ses propres dépôts.
- **CachyOS** est la référence Calamares du monde Arch : ISO de **janvier 2026** — sélection du bootloader déplacée dans Calamares avec **Limine par défaut**, snapshots btrfs **activés par défaut** dès que Limine ou GRUB est choisi avec btrfs, détection d'architecture en début d'installation (−1 Go de téléchargement) ; ISO de mars 2026 — aperçus animés dans la page de sélection de bureau.
- **ALCI** (`arch-linux-calamares-installer`, 21 dépôts) est le précédent « archiso + Calamares sur Arch pur », avec des variantes par kernel. Utile comme référence de profil, sans plus.

### 2.5 Un installeur maison en QML/Quickshell : coût, et absence de précédent

**Aucun précédent d'installeur de distribution écrit en QML/Quickshell n'a été trouvé.** Ce qui existe et qui s'en approche le plus :

1. **`dms-greeter`** — une application **Quickshell** qui tourne comme **interface système avant toute session utilisateur**, sous greetd, avec authentification PAM. C'est la preuve que la pile Quickshell fonctionne hors session ; un installeur serait la même forme d'objet.
2. **Les vues QML de Calamares** — l'esthétique sans le moteur.

Le coût réel d'un installeur maison n'est pas l'interface, c'est la mécanique (partitionnement, détection matérielle, chiffrement, bootloader, gestion d'erreurs à mi-parcours) : c'est précisément ce qu'`archinstall` a et que nous n'avons pas. **À quoi s'ajoute un risque propre à Quickshell** : il s'appuie sur des **API privées de Qt** et doit être reconstruit à chaque version de Qt sous peine de crash par incompatibilité d'ABI. Sur un ISO — média figé, non mis à jour — c'est acceptable ; sur un ISO qu'on regénère rarement pendant que Qt avance, c'est une source de casse silencieuse.

### 2.6 La contrainte d'hébergement, qui n'apparaît dans aucune spec

| Hébergement | Limite | Conséquence |
|---|---|---|
| **GitHub Pages** (notre dépôt `[eschaton]` aujourd'hui) | **1 Go** par site publié, **100 Go/mois** de bande passante (limite souple), 10 builds/h (sans objet : on publie par workflow) | Le dépôt de paquets tient largement (11 Mio aujourd'hui, dont 11 Mio de vendorés). **Un ISO n'y tient pas.** |
| **GitHub Releases** | **2 GiO par fichier**, 1 000 assets par release, pas de limite de taille totale ni de bande passante | Un ISO **en ligne** (léger) passe. Un ISO **hors-ligne** ne passe pas. |
| Référence : Omarchy | ISO ~**6 à 7 GiO** (3.1.1 : 6,29 GiO ; 3.2.0 : 6,17 GiO) | Omarchy héberge sur `iso.omarchy.org`, avec miroir SourceForge et torrents communautaires, **plus son propre miroir des dépôts Arch** (`omarchy-mirror`, Cloudflare R2). |

**Conclusion opérationnelle** : « ISO hors-ligne » et « hébergement » sont **la même décision**. Un ISO offline engage une infrastructure hors GitHub. Un ISO en ligne ne l'engage pas.

---

## 3. Axe 2 — Greeter graphique et session authentifiée

### 3.1 Le paysage greetd packagé (index Arch, 2026-08-28)

| Paquet | Version | Mis à jour | Nature |
|---|---|---|---|
| `extra/greetd` | 0.10.3-2 | 2026-03-27 | le démon |
| `extra/greetd-agreety` | 0.10.3-2 | 2026-03-27 | greeter texte de référence |
| `extra/greetd-tuigreet` | 0.11.1-2 | **2026-08-23** | TUI, le plus vivant des greeters texte |
| `extra/greetd-regreet` | 0.5.0-1 | 2026-07-17 | GTK4/Rust (Relm4), Wayland uniquement — nécessite un compositeur pour s'afficher |
| `extra/greetd-gtkgreet` | 0.8-3 | **2025-11-02** | GTK, le « historique » ; le moins actif |
| `extra/nwg-hello` | 0.4.5-1 | 2026-05-08 | GTK3/Python, pensé pour sway/Hyprland/labwc |
| `extra/cosmic-greeter` | 1:1.7.0-1 | 2026-08-26 | l'alternative « bureau complet » (COSMIC) |

SDDM/GDM restent les display managers classiques, mais ils apportent leur propre pile (Qt/QML pour SDDM, GNOME pour GDM) et n'ont aucune affinité avec le monde Quickshell/DMS.

### 3.2 `dms-greeter` — la trouvaille de cet axe

- **Il est déjà dans les dépôts Arch officiels, par ricochet** : le paquet `extra/dms-shell 1.5.3-1` livre `usr/share/quickshell/dms/Modules/Greetd/assets/dms-greeter`, ainsi que tout le module QML (`GreeterContent.qml`, `GreeterSurface.qml`, `GreeterUserPicker.qml`, `GreetdSettings.qml`, `GreetdMemory.qml`…). ALARM aarch64 miroite `dms-shell 1.5.3-1` à l'identique (veille SP2 §4). **Aucun recours à l'AUR n'est nécessaire.**
- **`archinstall` le câble officiellement** : `GreeterType.GreetdDms = 'dms-greeter'`. La recette exacte lue dans `archinstall/lib/profile/profiles_handler.py` :
  - paquets installés : **`greetd` seul** (le binaire vient de DMS) ;
  - service activé : `greetd` ;
  - `/etc/greetd/config.toml` écrit avec `vt = 1`, `user = "greeter"`, `command = "/usr/share/quickshell/dms/Modules/Greetd/assets/dms-greeter --command niri -p /usr/share/quickshell/dms"` ;
  - `/etc/tmpfiles.d/dms-greeter.conf` : `d /var/cache/dms-greeter 0750 greeter greeter -` et `d /var/lib/greeter 0755 greeter greeter -`.
- **Le dépôt amont est très jeune** : [`AvengeMedia/dank-greeter`](https://github.com/AvengeMedia/dank-greeter) — créé le **2026-07-19**, dernier commit le **2026-08-21**, 18 ★, 4 forks, 28 commits, MIT, **aucun tag, aucune release**. AUR : `greetd-dms-greeter-bin` (préconstruit) et `greetd-dms-greeter-git`. Un binaire unique embarque l'UI Quickshell ; il tourne sous niri, Hyprland, sway, Scroll, Miracle WM, labwc, MangoWC.
- **Fonctions** : authentification PAM avec **empreinte digitale (`pam_fprintd`)** et **clés de sécurité (`pam_u2f`)** en option ; mémorise la dernière session et le dernier utilisateur ; **synchronise thème, fond d'écran et réglages depuis DMS**.
- **Contrainte de packaging documentée** : les paquets officiels livrent `/usr/lib/sysusers.d/dms-greeter.conf` (compte `greeter`, home `/var/lib/greeter`) et `/usr/lib/tmpfiles.d/dms-greeter.conf`. **Des ACL sont requises** pour que l'utilisateur `greeter` traverse le home de l'utilisateur et lise sa configuration (c'est ainsi que le greeter reprend le thème). `dms greeter install` / `dms greeter enable` automatisent permissions, service et configuration.

### 3.3 Le trousseau PAM — ce que la veille tranche

Trois constats emboîtés, tous datés :

1. **`greetd` en autologin saute la pile `auth` de PAM.** Aucun `pam_gnome_keyring`, `pam_systemd_loadkey` ou `pam_gdm` ne peut fonctionner dans ce mode : il n'y a pas de mot de passe à capter. *(Fil NixOS Discourse ; la solution de contournement qui y est décrite passe par un module tiers `pam_fde_boot_pw` qui rejoue la passphrase LUKS depuis le trousseau du noyau — c'est un contournement de niche, pas un chemin nominal.)*
2. **Le déverrouillage par PAM est mécanique une fois l'authentification réelle rétablie** : `auth optional pam_gnome_keyring.so` dans la section `auth` et `session optional pam_gnome_keyring.so auto_start` dans la section `session`, avec la contrainte classique que **le mot de passe du trousseau « login » doit être celui du compte**.
3. **Mais l'amont DMS ne le fait pas pour nous, et peut nous écraser.** Issue [`DankMaterialShell#2390`](https://github.com/AvengeMedia/DankMaterialShell/issues/2390) (ouverte 2026-05-11, fermée 2026-05-12) : le packaging COPR du greeter ne fournissait pas le module PAM gnome-keyring. Réponse du mainteneur, verbatim : « *We don't force a keyring in the package by default as not everyone uses the gnome-keyring. We leave this up to the users.* » Et un commentaire signale que les `pam.d` **générés sont réécrits à chaque synchronisation des configurations**, en demandant un interrupteur pour l'éviter.

> **Ce que cela impose au SP4** : Eschaton doit **posséder** la configuration PAM du greeter (fichier livré par un paquet `eschaton-*`, dans `backup=` ou hors du chemin réécrit), et **le critère de recette doit inclure une réécriture de config du greeter suivie d'un relogin** — sinon la dette ADR 0003 se rouvre en silence à la première synchronisation.

### 3.4 Verrouillage d'écran

DMS **a le sien** : il remplace explicitement swaylock, swayidle, hypridle et **hyprlock**, avec détection d'inactivité, auto-verrouillage/suspension paramétrables séparément sur secteur et sur batterie, et un front-end de réglages **pour dank-greeter**. Pilotable par IPC (`dms ipc call lock`).

Défauts ouverts relevés en 2026 (à surveiller, pas bloquants) : désynchronisation de l'état de saisie au déverrouillage sous niri ([#2138](https://github.com/AvengeMedia/DankMaterialShell/issues/2138)), crash du verrou à l'extinction d'un moniteur ([#1468](https://github.com/AvengeMedia/DankMaterialShell/issues/1468)), noms de disposition clavier incohérents entre barre et verrou ([#1849](https://github.com/AvengeMedia/DankMaterialShell/issues/1849)). Empreinte digitale sur le verrou : [#205](https://github.com/AvengeMedia/DankMaterialShell/issues/205).

**Conséquence** : « hyprlock » ne doit pas apparaître dans la spec SP4. Le verrou est une fonction de DMS déjà présente ; le travail SP4 est de le **configurer et de le vérifier**, pas de l'apporter.

---

## 4. Axe 3 — Signature du dépôt et chaîne de confiance

### 4.1 Le problème d'amorçage, nommé et résolu publiquement il y a quatre jours

Migration Omarchy **`migrations/1787589206.sh`** — horodatage **2026-08-24 16:33 UTC** — lue verbatim via l'API GitHub :

```bash
echo "Require signed packages from the Omarchy repository"

# The [omarchy] repo predates the Omarchy packaging key, so existing installs
# carry a SigLevel override that also accepts unsigned packages. Packages are
# signed now, so drop the override and let the repo inherit the global
# SigLevel = Required DatabaseOptional like every other repo. Machine-wide and
# self-detecting, so another user's rerun no-ops.
omarchy_sig_override='SigLevel = Optional TrustAll'

if [[ -f /etc/pacman.conf ]] &&
  sed -n '/^\[omarchy\]/,/^\[/p' /etc/pacman.conf | grep -qxF "$omarchy_sig_override"; then
  # Requiring signatures with an untrusted packaging key would fail every
  # omarchy transaction, including the one that could repair it.
  if omarchy-pkg-missing omarchy-keyring ||
    ! sudo pacman-key --list-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 &>/dev/null; then
    omarchy-update-keyring
  fi

  sudo sed -i "/^\[omarchy\]/,/^\[/{/^$omarchy_sig_override$/d}" /etc/pacman.conf
fi
```

Et le mécanisme de réparation, `bin/omarchy-update-keyring` :

```bash
if omarchy-pkg-missing omarchy-keyring || ! sudo pacman-key --list-keys 40DFB6…C571 &>/dev/null; then
  sudo pacman-key --recv-keys 40DFB6…C571 --keyserver keys.openpgp.org
  sudo pacman-key --lsign-key 40DFB6…C571
  sudo pacman -Sy            # commenté comme « generally not a good idea », assumé ici
  omarchy-pkg-add omarchy-keyring
fi
# puis, toujours : réinstallation d'archlinux-keyring (il peut changer sans bump de version)
```

**Ce que cela nous apprend, littéralement** :

1. La bascule `Optional TrustAll` → `Required DatabaseOptional` **ne peut pas être une simple modification de fichier de configuration** : il faut d'abord garantir que la clé est présente et localement signée, sinon la transaction qui répare devient elle-même impossible. C'est une migration **auto-détectante et idempotente**, pas un `sed`.
2. **Le paquet keyring est le véhicule de rotation**, pas le véhicule d'amorçage. L'amorçage se fait par `--recv-keys` depuis un serveur de clés (`keys.openpgp.org`) **ou** par une clé embarquée sur le média (voir §4.3).
3. `archlinux-keyring` doit être **réinstallé systématiquement**, parce que son contenu peut changer sans changement de version — remarque directement applicable au risque ALARM de la spec §8 ligne 2.

### 4.2 Le patron chez les autres dérivées

| Distro | Paquet keyring | Clé | Amorçage |
|---|---|---|---|
| **Omarchy** | `omarchy-keyring` | `40DFB630FF42BCFFB047046CF0134EE680CAC571` | `--recv-keys` depuis keys.openpgp.org + `--lsign-key`, ou clé embarquée dans l'ISO |
| **CachyOS** | `cachyos-keyring` | `F3B607488DB35A47` | paquet keyring téléchargé directement depuis le miroir, ou `--recv-keys` depuis keyserver.ubuntu.com + `--lsign-key` |
| **EndeavourOS** | `endeavouros-keyring` | — | même schéma ; la mise à jour du keyring est annoncée comme prioritaire aux utilisateurs |

C'est un patron **universel** : paquet `<distro>-keyring` + clé lsignée. Il n'y a pas de débat de conception à ouvrir, seulement une décision d'exécution (§4.4).

### 4.3 L'ISO comme véhicule d'amorçage

Lu dans `builder/build-iso.sh` d'Omarchy :

```
pacman-key --add /builder/omarchy.gpg
pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571
```

— la clé publique (`builder/omarchy.gpg`, 632 octets) est **versionnée dans le dépôt de l'ISO**, ajoutée et lsignée pendant la construction, et le paquet `omarchy-keyring` est installé **à la fois dans l'environnement live et dans le miroir hors-ligne**. C'est la réponse propre au problème « comment fait-on confiance à la première installation, hors ligne, sans serveur de clés ».

### 4.4 Où signer — et la position à ne pas prendre par défaut

**Outillage `pacman`** (`repo-add(8)`) :
- `-s`/`--sign` : `gpg --detach-sign` sur la base générée → `eschaton.db.sig` (utilise l'agent GPG si disponible) ;
- `-k`/`--key` ou `GPGKEY` : choix de la clé ;
- `--verify` : vérifie la signature de la base **avant** de la mettre à jour, et échoue sinon ;
- **si un `.sig` accompagne un paquet ajouté, la signature est embarquée dans la base** — c'est ce qui rend `SigLevel = Required DatabaseOptional` opérant même sans base signée.

**Ce que fait Omarchy, et qui mérite attention** : la signature a lieu dans un conteneur Docker (`build/sign.sh`) via `GPG_PRIVATE_KEY` et `GPG_PASSPHRASE`… **mais pas dans GitHub Actions**. Les seuls workflows publics de `omacom/omarchy-pkgs` sont `sync-aur.yml`, `sync-rebuilds.yml`, `sync-upstream.yml` et `test.yml` — synchronisation AUR, déclenchement de reconstructions, tests. Le cycle build → signature → publication est piloté par `bin/omarchy-release` **depuis une machine de release**, avec un pipeline à canaux `edge → rc → stable` et `bin/repo advance --from … --to …`. Les builds aarch64 se font en QEMU (`tonistiigi/binfmt`).

**Le risque CI, documenté** : les secrets d'un dépôt public sont accessibles à tout collaborateur ; les déclencheurs privilégiés (`pull_request_target`, `workflow_run`) exécutent dans le contexte du dépôt de base **avec accès aux secrets** ; le vol d'identifiants est le fil conducteur des attaques récentes sur GitHub Actions. Notre CI part avec deux bons réflexes (`permissions: contents: read` par défaut, élévation limitée au job `publish`) et une dette : **les actions ne sont pas épinglées par SHA** — dette déjà routée SP4 et qui, si la clé approche la CI, cesse d'être cosmétique.

### 4.5 Reproductibilité

Arch dispose d'une instance **rebuilderd** expérimentale sur sa propre infrastructure, avec une page de statut ; le paquet `rebuilderd` est passé de v0.25.0 à **v0.27.0** en `extra-testing` en 2026 ; l'outil `arch-repro-status` permet de vérifier ses propres paquets. **Aucun chiffre global fiable de taux de reproductibilité n'a été trouvé** dans cette passe. Pour Eschaton, la reproductibilité n'est pas un prérequis de la signature : c'est ce qui permettrait, plus tard, qu'un tiers **vérifie** que la signature correspond à la source. À noter comme horizon, pas comme livrable.

---

## 5. Axe 4 — Mises à jour atomiques sur base Arch : position honnête

### 5.1 Ce que fait l'état de l'art

| Approche | Mécanique | Ce qu'elle garantit | Coût |
|---|---|---|---|
| **SteamOS 3** | A/B rootfs, image en lecture seule ; `steamos-atomupd-client` → bundle **RAUC** → `casync extract` vers la partition inactive → bascule de l'entrée de boot | L'OS n'est jamais dans un état partiel ; rollback = repointer le slot ; `/home` unique partagé | Ce n'est plus une distribution à paquets. Le gestionnaire de paquets ne pilote plus le système. |
| **systemd-sysupdate + mkosi** | A/B au niveau fichier/répertoire/**partition** ; artefacts signés (rootfs, kernels, UKI) téléchargés dans le slot inactif, bascule des entrées de boot, rollback automatique si le nouveau slot ne boote pas | Mise à jour vérifiée cryptographiquement et atomique ; A/B/C/… possible | Remplace `pacman` pour le système. Nécessite de produire et d'héberger des images. |
| **ParticleOS** (systemd) | `mkosi` au-dessus d'une distro classique ; **arch, fedora, debian supportés** ; images signées par les clés de l'utilisateur | Contrôle complet : paquets, processus de mise à jour, mécanismes de sécurité | Public **développeurs**. Retours d'early adopters : la variante Arch fonctionne, mais la construction locale est lente (compression) et le démarrage des applications (Flatpak) souffre. |
| **Immuarch** (annonce forum Arch, **2026-01-28**) | btrfs + overlayfs avec tmpfs rw sur `/` et `/home` ; **GRUB** ; FDE ; installation en place après un Arch de base ; possibilité de construire son système comme image OCI et de l'importer depuis podman | Atomicité + boot sur la n-ième version antérieure, **en restant Arch** | AUR (`immuarch-core-git`, `immuarch-utils-git`), un seul auteur, dépend de **GRUB** — incompatible en l'état avec notre chaîne Limine. |
| **openSUSE `transactional-update`** | `pacman`-équivalent (zypper) exécuté **dans un snapshot** ; le nouvel état n'est activé qu'en cas de succès complet | « Soit tout est appliqué, soit rien n'est changé » ; la mise à jour **n'influence pas le système en cours d'exécution** | Un redémarrage pour appliquer. Pas d'A/B, pas d'images. |
| **Eschaton aujourd'hui** | `snap-pac` prend un snapshot avant/après chaque transaction pacman ; `limine-snapper-sync` amarre les snapshots au menu Limine ; restauration par méthode *replace* | Rollback **prouvé en conditions réelles le 2026-08-28** (spec §8 risque 8) | Aucun coût supplémentaire — c'est déjà là. |

### 5.2 La différence réelle, formulée sans complaisance

La documentation openSUSE la dit mieux que nous ne le ferions : les snapshots « fournissent un moyen très fiable de restaurer le système dans un état fonctionnel, mais cette approche n'atténue pas la plupart des problèmes qui cassent le système en premier lieu ». Les mises à jour traditionnelles s'exécutent **contre le système en cours d'exécution**, elles peuvent l'impacter et en être impactées ; ces variables dynamiques rendent l'échec plus probable, donc **le besoin de rollback plus fréquent qu'il ne devrait**.

Autrement dit : **la ligne de partage n'est pas « rollback ou pas », c'est « prévenir ou réparer ».** Nous savons réparer. Nous ne prévenons pas.

### 5.3 Les trous précis de notre modèle actuel — ce qui n'est pas couvert par le snapshot

1. **L'ESP n'est pas snapshotée.** Elle est en FAT32, hors btrfs. Kernels et initramfs y vivent. Ce qui rend le filet réel, c'est que `limine-snapper-sync` **recopie kernel + initramfs par snapshot** dans l'ESP — et c'est exactement le mécanisme qui s'arrête en silence au-delà de `LIMIT_USAGE_PERCENT` (85 %), risque déjà identifié (spec §8 ligne 8). **Notre atomicité s'arrête à la frontière du système de fichiers.**
2. **Une transaction pacman interrompue laisse le système vivant en état intermédiaire.** Le snapshot « avant » existe, mais la remise en état demande une action délibérée (et parfois un redémarrage). Pour un utilisateur grand public, « mon système est cassé, il faut choisir un snapshot » est déjà un échec produit, même si techniquement récupérable.
3. **Aucune vérification cryptographique de l'état du système** : ni UKI signé, ni `dm-verity`. La signature du dépôt (§4) couvre la *provenance* des paquets, pas l'*intégrité du système installé*.
4. **Rien ne teste que le nouvel état démarre** avant de le rendre par défaut.

### 5.4 Position recommandée

> **L'atomicité au sens A/B n'est pas nécessaire pour le grand public v1, et son coût est disproportionné.** Elle exige d'abandonner `pacman` comme moteur de mise à jour du système, de produire et d'héberger des images (avec les contraintes d'hébergement du §2.6), et elle contredit le principe directeur *thin installer, fat packages* qui fait la lisibilité d'Eschaton.
>
> **Le pas intermédiaire qui apporte l'essentiel du bénéfice pour une fraction du coût est l'application hors-ligne** : exécuter la transaction `pacman` **dans un snapshot en écriture** plutôt que dans le système vivant, puis basculer au redémarrage — le modèle `transactional-update`, transposé. Il conserve pacman, conserve nos paquets, conserve Limine et `limine-snapper-sync`, et transforme « je répare après » en « je n'ai jamais cassé ».
>
> **Ce que le snapshot-avant-transaction couvre déjà et qui suffit au grand public v1** : la panne de mise à jour, la régression de paquet, le retour en arrière depuis le menu de démarrage. C'est prouvé en conditions réelles depuis le 2026-08-28.
>
> **Ce qui manque vraiment et qui devrait figurer dans la spec SP4 à la place de « mises à jour atomiques »** : (a) une **vérification que le nouvel état démarre** avant de le rendre par défaut, (b) une **surveillance de la santé du filet** (occupation de l'ESP, présence des entrées de snapshot) exposée **dans le shell**, puisque c'est notre différenciateur. Le risque 8 de la spec Socle est aujourd'hui traité par de la documentation ; pour le grand public il doit devenir une **fonction visible**.

---

## 6. Axe 5 — Chiffrement (LUKS) et support matériel

### 6.1 LUKS + btrfs + Limine

- **Limine** : `extra/limine 12.6.1-1`, mis à jour le **2026-08-26** (l'article Wikipedia qui annonce 11.2.1 au 2026-04-04 est en retard — se fier à l'index Arch).
- La combinaison **LUKS2 + btrfs + subvolumes + Limine** est documentée et pratiquée (guides Arch communautaires, CachyOS). Ligne de commande type : `cryptdevice=UUID=…:root root=/dev/mapper/root rootflags=subvol=@ rw rootfstype=btrfs`.
- **`limine-snapper-sync` supporte le chiffrement, et sa recommandation valide notre layout** : le README recommande de stocker les fichiers de démarrage (kernel, initramfs/initrd, ou UKI) **en dehors d'une partition entièrement chiffrée**, pour un démarrage de snapshot chiffré plus rapide et une **invite de mot de passe graphique Plymouth**. Notre ESP FAT32 de 4 GiO montée sur `/boot` est déjà cette disposition.
- Le README confirme par ailleurs (et c'est utile de l'avoir de première main) : **Limine 8 minimum**, ESP FAT32 d'**au moins 4 GiO recommandée**, `TARGET_OS_NAME` explicite « améliore la fiabilité » face à l'auto-détection depuis `/etc/os-release`, `LIMIT_USAGE_PERCENT` à 85 par défaut (aucune nouvelle entrée au-delà), `MAX_SNAPSHOT_ENTRIES` à `auto` (suppression des anciennes **sans préavis**). Tout cela corrobore la spec §4.3 et §8 ligne 8.
- **Les hooks overlayfs** (`limine-mkinitcpio-hook`, que nous packageons déjà) servent précisément à simuler une couche inscriptible sur un snapshot en lecture seule — et le README les relie explicitement aux **problèmes de compatibilité des display managers sur systèmes chiffrés**. C'est-à-dire : le paquet dont nous héritons les comportements intrusifs (spec §8 ligne 7) est aussi celui qui rend le boot-sur-snapshot utilisable avec un greeter et du chiffrement. On ne peut pas s'en débarrasser au SP4 ; il faut le maîtriser.
- **Point de vigilance concret** : l'issue [`limine-snapper-sync#7`](https://gitlab.com/Zesko/limine-snapper-sync/-/issues/7) décrit une chaîne d'échecs avec `sd-btrfs-overlayfs` sur racine LUKS (binaires manquants dans l'initramfs : `/usr/bin/env`, `mktemp`, `mkdir`, `rmdir` ; puis `mount: /: fsconfig() failed: overlay: No changes allowed in reconfigure` **au démarrage sur snapshot**). Sans résolution visible dans la page consultée. **À rejouer soi-même : le chiffrement peut casser précisément le boot-sur-snapshot, c'est-à-dire le filet.**

### 6.2 TPM2 : état de l'art, et pourquoi ce n'est pas pour la v1

- Chemin standard : `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7`, avec `--tpm2-with-pin=yes` en option.
- **PCR 7 exige que le Secure Boot soit actif et en mode utilisateur**, sinon n'importe quel média de démarrage non autorisé peut déverrouiller le volume. Et l'état du PCR 7 **change si les certificats du firmware changent**, ce qui peut enfermer l'utilisateur dehors.
- Or : **les certificats Secure Boot Microsoft de 2011 expirent en juin 2026** — `Microsoft UEFI CA 2011` (celui qui signe les shims Linux, GRUB et les Option ROM) autour du **27 juin 2026**, `Windows Production PCA 2011` en octobre 2026. Le remplacement par les certificats 2023 se déploie par mises à jour de firmware, y compris via **fwupd/LVFS** côté Linux. Aucun « brick » massif attendu, mais **une vague de changements de firmware sur le parc pendant l'exercice 2026** — donc une vague de PCR 7 modifiés.
- **Secure Boot côté Limine** : possible si le binaire est signé et la clé enrôlée dans le firmware ; Limine contourne le chaînage EFI, **seul le binaire Limine a besoin d'être signé**. Guides CachyOS avec `sbctl` (le plus récent daté du 2026-07-02). Mais le média d'installation `archiso` ne supporte pas Secure Boot (§2.1) : il faut donc désactiver le Secure Boot pour installer, puis l'enrôler après.

> **Recommandation** : LUKS2 **oui** (passphrase), TPM2 auto-unlock **non par défaut en v1** — au mieux une option explicitement présentée comme avancée, avec une clé de secours obligatoire.

### 6.3 GPU : le plancher matériel, chiffré

C'est le constat le plus lourd de cet axe, et il est **récent et vérifiable** :

- Arch a **remplacé** `nvidia` → `nvidia-open`, `nvidia-dkms` → `nvidia-open-dkms`, `nvidia-lts` → `nvidia-lts-open`. **Index Arch au 2026-08-28 : aucun paquet `nvidia` ni `nvidia-dkms`.** Présents : `extra/nvidia-open 610.57.04-10` (2026-08-28), `extra/nvidia-open-dkms 610.57.04-1` (2026-08-06), `extra/nvidia-open-lts 1:610.57.04-9`, `extra/nvidia-utils 610.57.04-1`, `core/linux-firmware-nvidia 20260810-2`.
- **Annonce Arch du 2025-12-20** : le pilote 590 **n'accepte plus Maxwell (GTX 900) ni Pascal (GTX 10xx)**. Ces cartes doivent basculer sur `nvidia-580xx-dkms` **depuis l'AUR**. Turing (RTX 20xx, GTX 16xx) et plus récent : transition automatique.
- **`archinstall` 4.1 (2026-03-31) a retiré l'option « pilote Nvidia propriétaire »** — explicitement « parce que `nvidia-dkms` n'est plus dans les dépôts Arch ». Le code d'`archinstall` optimise même : si tous les kernels sélectionnés sont mainline, il installe `nvidia-open` plutôt que `nvidia-open-dkms` pour éviter dkms et les headers.
- **Wayland/explicit sync** : le protocole `linux-drm-syncobj-v1` est supporté par le pilote depuis la **555** ; prérequis `xorg-xwayland ≥ 24.1` et `wayland-protocols ≥ 1.34`. En 2026, le scintillement XWayland qui empoisonnait Nvidia+Wayland est décrit comme **largement disparu sur matériel moderne**. Le problème historique Hyprland+Nvidia n'est plus le problème de 2026.

> **Formulation honnête pour la spec SP4** : « Eschaton v1 supporte les GPU Nvidia **Turing (2018) et ultérieurs**, avec les modules noyau ouverts. Les cartes antérieures nécessitent un pilote hors dépôts officiels et **ne sont pas supportées**. » Toute autre formulation serait un mensonge vérifiable.

### 6.4 Firmware, Wi-Fi, et la largeur réaliste

- **Arch a scindé `linux-firmware`** en paquets par vendeur depuis `20250613.12fe085f-5` (juin 2025) : `linux-firmware` devient un paquet vide qui dépend d'un ensemble par défaut, et des sous-paquets existent (`linux-firmware-amdgpu`, `linux-firmware-intel`, `linux-firmware-nvidia` — ce dernier pesait à lui seul près de 100 Mio, d'où la scission). **Double conséquence pour le SP4** : un levier de réduction de taille pour un ISO/miroir hors-ligne, **et un risque d'omission** — un sous-paquet firmware manquant, c'est un Wi-Fi mort au premier démarrage, sur une machine sans réseau pour se réparer.
- **Wi-Fi** : le constat 2026 est stable — **Intel fonctionne, Broadcom est la zone rouge**. La combinaison « Ryzen + Wi-Fi Intel » est décrite comme la plus sûre hors matériel certifié.
- **fwupd/LVFS** : Dell, Lenovo, HP, Framework, System76, Star Labs, Tuxedo y participent à des degrés divers. Mais la certification « Linux » d'un constructeur porte sur **une configuration précise et des versions d'Ubuntu précises** — elle ne se transpose pas à Eschaton.

> **Liste de matériel « supporté » minimale viable proposée pour la v1** : UEFI x86_64 (Secure Boot désactivable), GPU **AMD** ou **Intel** intégrés (pilotes en arbre, aucun DKMS), ou **Nvidia Turing et plus** avec `nvidia-open`. Wi-Fi Intel. Aucun laptop « certifié ». Cette liste tient sur trois lignes et se **prouve** ; toute extension exige une machine physique et un protocole de test.

---

## 7. Conséquences pour la spec SP4

### 7.1 Ce que la veille **impose**

1. **Signer le dépôt avant toute distribution, et livrer `eschaton-keyring`.** Le patron est universel (Omarchy, CachyOS, EndeavourOS) : paquet keyring + clé lsignée. La bascule `Optional TrustAll` → `Required DatabaseOptional` **doit être une migration auto-détectante et auto-réparante**, pas une modification de configuration — nos installations de dogfooding portent déjà l'override, et exiger la signature avec une clé non fiable ferait échouer la transaction même qui pourrait réparer.
2. **Livrer la clé publique dans le média d'installation** (`archiso`) et l'installer dans le keyring cible, sinon la première installation dépend d'un serveur de clés joignable.
3. **Le greeter authentifié met fin à l'autologin, et c'est la seule façon de solder la dette ADR 0003.** L'autologin `greetd` saute la pile `auth` de PAM : aucune configuration ne peut y déverrouiller le trousseau. Les deux dettes (session non authentifiée, secrets en clair au repos) sont une seule dette, avec un seul livrable.
4. **Eschaton doit posséder la configuration PAM du greeter**, et la recette doit inclure un test « je resynchronise la configuration du greeter, je me reconnecte, le trousseau est toujours déverrouillé » — l'amont ne met pas gnome-keyring dans les `pam.d` générés, et ceux-ci sont réécrits à chaque synchronisation.
5. **Le plancher matériel Nvidia est Turing.** Il doit apparaître **en toutes lettres** dans la spec, pas dans une note de bas de page.
6. **L'ESP de 4 GiO doit être re-documentée comme décision de chiffrement** autant que de rétention : c'est la disposition que `limine-snapper-sync` recommande pour LUKS.
7. **Décider de l'hébergement en même temps que du périmètre de l'ISO.** Pages plafonne à 1 Go, Releases à 2 GiO par fichier ; l'ISO hors-ligne d'Omarchy pèse 6–7 GiO. Un ISO hors-ligne engage une infrastructure hors GitHub.
8. **Épingler les actions CI par SHA avant que la clé de signature n'approche la CI** (différé déjà routé SP4 — il change de nature).

### 7.2 Ce que la veille **interdit**

1. **Interdit d'écrire un installeur graphique maison avant d'avoir épuisé `archinstall`.** `archinstall` 4.4 couvre déjà Limine (+ `removable`, notre chemin exact), btrfs et subvolumes, Snapper, LUKS2, `custom_repositories` avec `sign_check`/`sign_option`, `packages`, `custom_commands`, et le greeter DMS. Le concurrent le plus proche n'a pas écrit d'installeur : il a écrit ~1 000 lignes de bash + `gum` **au-dessus** d'archinstall.
2. **Interdit de présenter « l'installeur graphique » comme un différenciateur.** Calamares est graphique depuis des années chez CachyOS et Manjaro. Le territoire vide est ailleurs (§7.5).
3. **Interdit de promettre un « support matériel large ».** Nvidia pré-Turing est hors dépôts officiels ; Broadcom est un champ de mines ; aucun laptop n'est certifié pour Eschaton.
4. **Interdit d'activer le déverrouillage TPM2 par défaut** : PCR 7 exige Secure Boot actif, et les certificats Secure Boot de 2011 expirent en juin/octobre 2026 — la vague de mises à jour de firmware associée invalidera des enrôlements.
5. **Interdit de faire des « mises à jour atomiques » un livrable v1** (§5.4).
6. **Interdit d'introduire `hyprlock`** : DMS a son propre verrou et remplace explicitement hyprlock/hypridle.
7. **Interdit d'adopter Calamares sans trancher le modèle d'installation** : il installe en déballant un squashfs, ce qui contredit *thin installer, fat packages*.

### 7.3 Ce que la veille **recommande**

1. **Réutiliser `archinstall` en pilotage JSON** (ou en mode bibliothèque), et concentrer l'effort graphique là où il différencie : la **collecte** (un écran Quickshell/DMS qui produit le JSON) et l'**onboarding au premier démarrage**. C'est l'architecture d'Omarchy, en remplaçant `gum` par DMS — et c'est le seul endroit où « installeur graphique » devient une phrase vraie et peu coûteuse.
2. **Adopter le mode OEM / provisionnement différé** (précédent Omarchy `Ctrl+C`) : l'installeur pose le système ; le premier démarrage crée l'utilisateur, définit le mot de passe **et le mot de passe du trousseau**, et configure le premier fournisseur IA. C'est la jonction naturelle avec l'ADR 0003 et avec le SP3.
3. **Commencer par un ISO en ligne** (≤ 2 GiO, hébergeable sur GitHub Releases) — c'est la requalification honnête de l'« ISO minimal » jamais livré du SP2. L'ISO hors-ligne n'arrive que si le besoin est prouvé.
4. **Sortir la clé de signature de GitHub Actions**, ou à défaut : environnement protégé, actions épinglées par SHA, `permissions` minimales, aucun déclencheur `pull_request_target`/`workflow_run`. Le canal `edge/rc/stable` d'Omarchy est un modèle à considérer si l'on veut publier sans exposer la clé à chaque push.
5. **Remplacer « mises à jour atomiques » par deux objectifs réels** : (a) l'application hors-ligne (transaction pacman dans un snapshot, bascule au redémarrage), (b) la **santé du filet exposée dans le shell** (occupation de l'ESP, présence des entrées de snapshot, dernier rollback possible).
6. **Rejouer soi-même le boot-sur-snapshot avec LUKS** avant d'écrire la spec : l'issue amont #7 suggère que c'est précisément là que ça casse.
7. **Traiter `dank-greeter` comme une dépendance jeune** : le binaire vient de `extra/dms-shell` (rassurant), mais le dépôt amont a cinq semaines et **aucun tag**. Notre point d'ancrage doit être le paquet Arch, pas le dépôt git.

### 7.4 Trois découpages candidats du sous-projet

Le SP4 tel qu'écrit contient au moins cinq chantiers hétérogènes (ISO, installeur, greeter/onboarding, signature, atomique, matériel) dont les dépendances et les bancs d'essai diffèrent. Trois découpages sont défendables.

**A — « Chaîne de confiance d'abord » (4 lots)**

| Lot | Contenu | Banc d'essai | Dépendances |
|---|---|---|---|
| **SP4a — Signature & keyring** | clé, `eschaton-keyring`, signature en build, `repo-add -s`, migration auto-réparante, décision « où vit la clé », actions épinglées SHA | VM existante, CI | aucune — **peut démarrer immédiatement** |
| **SP4b — ISO & installeur** | profil archiso, clé embarquée, pilotage archinstall par JSON, écran de collecte DMS | VM x86_64 puis vraie machine | SP4a (le média doit amorcer la confiance) |
| **SP4c — Greeter, session, onboarding** | greetd + dms-greeter, fin de l'autologin, PAM gnome-keyring, ACL du compte `greeter`, premier démarrage OEM, premier fournisseur IA | VM | SP4b utile mais pas bloquant |
| **SP4d — Chiffrement & matériel** | LUKS2, boot-sur-snapshot chiffré, liste de matériel supporté, firmware par vendeur | **vraie machine obligatoire** | SP4b |

*Avantage* : SP4a est court, bloquant, sans dépendance, et solde la dette la plus ancienne. *Inconvénient* : quatre cycles spec/plan.

**B — « Première vraie machine » (3 lots)** — *recommandé*

| Lot | Contenu | Pourquoi ce regroupement |
|---|---|---|
| **SP4a — Signature & keyring** | comme ci-dessus | Indépendant, bloquant, court. |
| **SP4b — Première vraie machine** | ISO + installeur + LUKS2 + liste de matériel + firmware | **Ces quatre-là se valident sur le même banc, en une seule séance** : on ne prouve pas l'installeur sans matériel, ni le chiffrement sans installeur, ni le matériel sans ISO. Les séparer, c'est multiplier les allers-retours physiques. |
| **SP4c — Première ouverture de session** | greeter + fin de l'autologin + PAM/trousseau + onboarding + premier fournisseur | Un seul récit utilisateur, une seule dette (ADR 0003), testable en VM. |

*Avantage* : chaque lot correspond à un moment vécu par l'utilisateur et à un banc d'essai unique. *Inconvénient* : SP4b est gros.

**C — « Minimal viable » (2 lots + report)**

| Lot | Contenu |
|---|---|
| **SP4** | Signature + ISO **en ligne** + installeur (archinstall piloté) + greeter/onboarding |
| **SP6 (nouveau, après le Gaming)** | Chiffrement, matériel large, application hors-ligne des mises à jour |

*Raisonnement* : le SP5 (Gaming) est ce qui **apporte** la première vraie machine x86_64. Faire le chiffrement et le matériel avant lui, c'est acheter du matériel deux fois. *Inconvénient* : livrer une distribution « grand public » sans chiffrement est difficile à assumer publiquement — mais parfaitement assumable en dogfooding.

> **Recommandation** : **B**, avec la précision que **SP4a doit être détaché et lancé en premier** — il est court, bloquant, sans dépendance matérielle, et c'est la dette que la spec Socle a explicitement placée « avant toute distribution à des tiers ».

### 7.5 Note sur le différenciateur (à rejouer, comme au SP2 et au SP3)

Rien dans cette passe ne restaure « installeur graphique » ou « IA intégrée » comme différenciateurs. Ce que cette passe **ajoute** au différenciateur reformulé par les veilles SP2 et SP3 (« le rollback et l'administration système comme fonctions natives et unifiées du shell, adossées à un assistant à catalogue borné ») :

- **le filet de sécurité peut s'arrêter en silence** (`LIMIT_USAGE_PERCENT`, nommage `TARGET_OS_NAME`, overlayfs + LUKS) et **personne, chez aucun concurrent, ne le rend visible dans son interface**. CachyOS active les snapshots par défaut ; Omarchy propose une réinitialisation d'usine par snapshot. Aucun n'affiche « ton filet est-il en état de te rattraper ? ».
- C'est, à ce jour, la formulation la mieux étayée par les faits de la présente veille.

---

## 8. Risques — table datée (2026-08-28)

| # | Risque | Gravité | Constat daté | Traitement proposé |
|---|---|---|---|---|
| 1 | **Le boot-sur-snapshot casse sous LUKS** (overlayfs) | **Élevée** — c'est le filet lui-même | `limine-snapper-sync#7` : binaires manquants dans l'initramfs, puis `overlay: No changes allowed in reconfigure` au démarrage sur snapshot, racine LUKS. Sans résolution visible. | **Spike obligatoire avant la spec SP4** : LUKS2 + btrfs + Limine + snapshot bootable, prouvé en VM x86_64. |
| 2 | **Plancher matériel Nvidia = Turing** | Élevée (produit) | Index Arch 2026-08-28 : `nvidia`/`nvidia-dkms` absents ; annonce Arch 2025-12-20 : 590 abandonne Maxwell et Pascal. | Écrire le plancher en toutes lettres dans la spec. Ne pas promettre au-delà. |
| 3 | **Clé de signature exposée en CI** | Élevée (sécurité) | Secrets accessibles aux collaborateurs ; `pull_request_target`/`workflow_run` s'exécutent avec les secrets du dépôt de base ; actions Eschaton non épinglées par SHA. Le pair le plus proche (Omarchy) **ne signe pas dans GitHub Actions**. | Décider explicitement : machine de release hors CI, ou CI durcie (SHA épinglés, environnement protégé, triggers restreints). |
| 4 | **La bascule `SigLevel` casse les installations existantes** | Moyenne, mais irréversible sur le terrain | Migration Omarchy du 2026-08-24, verbatim : « exiger des signatures avec une clé de packaging non fiable ferait échouer toute transaction omarchy, y compris celle qui pourrait la réparer ». | Migration auto-détectante et idempotente, testée sur une VM portant l'ancien `Optional TrustAll`. |
| 5 | **La config PAM du greeter est réécrite par l'amont** | Moyenne — rouvre la dette ADR 0003 en silence | `DankMaterialShell#2390` (2026-05-11/12) : gnome-keyring absent des `pam.d` générés par choix amont ; les `pam.d` sont réécrits à chaque synchronisation. | Fichier PAM possédé par un paquet Eschaton ; test de non-régression après resynchronisation. |
| 6 | **`dank-greeter` est un projet de cinq semaines** | Moyenne | Créé 2026-07-19, 18 ★, 28 commits, **aucun tag ni release**, dernier push 2026-08-21. Atténuation forte : le binaire est livré par `extra/dms-shell` et câblé par `archinstall`. | S'ancrer sur le paquet Arch, jamais sur le dépôt git. Surveiller l'apparition d'un paquet dédié en `extra`. |
| 7 | **L'ISO hors-ligne n'est hébergeable nulle part gratuitement** | Moyenne (produit) | Pages : 1 Go. Releases : 2 GiO/fichier. Omarchy : 6–7 GiO, hébergement propre + SourceForge + torrents + miroir Arch maison. | Commencer par un ISO en ligne. Traiter l'hébergement comme une décision de spec. |
| 8 | **`archiso` ne supporte pas le Secure Boot** | Moyenne | Aucun support dans le média officiel depuis 2016 ; seul archboot en a. | Documenter « désactiver le Secure Boot pour installer » ; enrôlement `sbctl` post-install en option. |
| 9 | **Expiration des certificats Secure Boot 2011** | Moyenne, temporaire | `Microsoft UEFI CA 2011` ~27 juin 2026 ; `Windows Production PCA 2011` en octobre 2026. Vague de mises à jour de firmware sur le parc, donc de PCR 7 modifiés. | Ne pas enrôler le TPM sur PCR 7 par défaut. Clé de secours obligatoire si option activée. |
| 10 | **Sous-paquet firmware manquant = machine sans réseau** | Moyenne | Arch a scindé `linux-firmware` par vendeur depuis juin 2025 ; `linux-firmware` est un méta-paquet. | Ne pas élaguer les firmwares dans l'ISO v1. Élaguer seulement quand un besoin de taille est prouvé. |
| 11 | **Calamares : dépôt GitHub archivé, cadence lente, hors dépôts Arch** | Faible (si on ne l'adopte pas) | GitHub archivé (2025-05-06) ; Codeberg, 3.4.2 le 2026-03-10, seule release 2026 ; AUR uniquement côté Arch. | Ne pas l'adopter. Si le sujet revient, ré-instruire la santé du projet à ce moment-là. |
| 12 | **Quickshell en 0.x, API privées de Qt** | Faible pour le bureau, **notable pour un média figé** | `extra/quickshell 0.3.1-1` (2026-08-21) ; reconstruction obligatoire à chaque version de Qt sous peine de crash ABI. | Si un jour une UI Quickshell entre dans l'ISO, la reconstruire à chaque regénération et la tester. |
| 13 | **Érosion continue du différenciateur** | Élevée (stratégie) | Omarchy a poussé sur `omarchy-iso` **le jour même de cette veille** (2026-08-28) et a basculé sa signature quatre jours plus tôt. | Rejouer cette veille à l'ouverture du SP4 (§10). C'est, comme au SP2 et au SP3, l'affirmation la plus volatile du projet. |

---

## 9. Ce qui n'a pas pu être vérifié dans cette passe

À reprendre à l'ouverture du SP4 :

- **`wiki.archlinux.org` et `aur.archlinux.org` ont refusé les requêtes automatisées** (protection Anubis, code 403). Les pages ArchWiki *greetd*, *GNOME/Keyring*, *Limine*, *pacman/Package signing* et les fiches AUR (`calamares`, `greetd-dms-greeter-*`, `nvidia-580xx-dkms`, `immuarch-core-git`) n'ont donc **pas** été lues de première main ; les éléments les concernant proviennent de sources secondaires ou de la documentation amont. **Les votes/popularité AUR de `greetd-dms-greeter-bin` restent inconnus.**
- **Le contenu exact du `pacman.conf` d'Omarchy** (fichiers `default/pacman/pacman-{stable,rc,edge}.conf`) n'a été lu qu'à travers des extraits de recherche de code — ces extraits montrent bien `SigLevel = Required DatabaseOptional` en réglage global.
- **Aucune mesure de taux de reproductibilité d'Arch** n'a pu être obtenue.
- **Le comportement réel de `pam_gnome_keyring` sous `greetd` avec un greeter authentifiant** (par opposition à l'autologin) n'a pas de source de première main confirmant un succès : le raisonnement s'appuie sur le fait que l'autologin est la cause de l'échec. **À prouver en VM, pas à supposer.**

---

## 10. Les affirmations les plus périssables (à rafraîchir à l'ouverture du SP4)

Classées par vitesse de péremption estimée.

| # | Affirmation | Pourquoi elle bouge | Comment la re-vérifier |
|---|---|---|---|
| 1 | « Omarchy exige désormais les signatures (`Required DatabaseOptional`) » | **Quatre jours d'âge** (2026-08-24). Une migration récente peut être amendée ou reculée. | Relire `migrations/` et `default/pacman/pacman-*.conf` sur la branche `quattro`. |
| 2 | « Le Configurator d'Omarchy est du bash + gum au-dessus d'archinstall » | Push sur `omarchy-iso` **le jour même de cette veille** ; 493 commits sur `quattro`. Rien n'empêche une bascule graphique. | Relire `configs/airootfs/root/configurator` et `builder/build-iso.sh`. |
| 3 | « `dank-greeter` : 18 ★, 28 commits, aucun tag » | Projet de cinq semaines, dans l'orbite d'un amont qui pousse 34 à 139 commits/semaine. Peut s'institutionnaliser (paquet `extra` dédié) ou stagner. | API GitHub + index Arch (`greetd-dms-greeter*`) + AUR. |
| 4 | « archinstall 4.4, avec Limine, `custom_repositories`, `GreeterType.GreetdDms` » | **Cinq versions majeures en trois mois** (4.0 → 4.4, mars→juin 2026). Les clés JSON peuvent bouger d'une version à l'autre. | Relire `examples/config-sample.json`, `docs/cli_parameters/`, `models/bootloader.py`, `default_profiles/profile.py`. |
| 5 | « `nvidia-open 610.57.04`, plancher Turing » | Le pilote sort toutes les quelques semaines (`nvidia-open` mis à jour le 2026-08-28, une version déjà en `extra-testing`). Le plancher peut remonter. | [Index Arch `nvidia`](https://archlinux.org/packages/?q=nvidia) + annonces `archlinux.org/news`. |
| 6 | « Les certificats Secure Boot 2011 expirent en juin/octobre 2026 » | **La date est passée ou imminente selon le moment de l'ouverture.** L'état du parc au moment du SP4 sera différent de l'état analysé ici. | Constater l'effet réel, pas la prévision. |
| 7 | « Le différenciateur = rollback + administration natifs dans le shell » | Déjà signalée comme la plus volatile par les veilles SP2 (§8) et SP3 (§8 ligne 10). Omarchy itère chaque semaine. | Rejouer la comparaison fonctionnelle du tableau SP2 §6. |
| 8 | « Calamares : 3.4.2, une seule release en 2026, dépôt GitHub archivé » | Cadence lente = un événement suffit à changer le tableau (nouvelle release, entrée dans `extra`, ou au contraire mise en sommeil). | Codeberg `Calamares/calamares/releases` + AUR. |
| 9 | « `extra/limine 12.6.1-1`, `extra/archiso 89-1`, `extra/greetd 0.10.3-2` » | Versions d'index, périssables par nature. **Note : Wikipedia annonçait Limine 11.2.1 — l'index Arch fait foi.** | Index Arch. |
| 10 | « Aucun précédent d'installeur QML/Quickshell » | Affirmation négative : la moins solide de toutes. Un projet peut apparaître en quelques semaines dans cet écosystème. | Recherche ciblée à refaire. |

---

## 11. Sources

**Amont Eschaton** — [spec Socle](../../../docs/superpowers/specs/2026-08-27-socle-design.md), [plan Socle](../../../docs/superpowers/plans/2026-08-27-socle.md), [bilan d'exécution SP1](../../../docs/superpowers/bilans/2026-08-28-socle-execution.md), [ADR 0003](../../../docs/decisions/0003-service-secrets-assistant.md), [spec Bureau](../../../docs/superpowers/specs/2026-08-28-bureau-design.md), [spec Assistant](../../../docs/superpowers/specs/2026-08-28-assistant-design.md), [veille SP2](../../../docs/veille/2026-08-28-sp2-bureau.md), [veille SP3](../../../docs/veille/2026-08-28-sp3-assistant.md), `installer/eschaton-install`, `repo/build-repo`, `.github/workflows/ci.yml`.

**ISO & installeurs** — [omacom/omarchy-iso](https://github.com/omacom/omarchy-iso) (README, `builder/build-iso.sh`, `configs/airootfs/root/configurator`, arborescence via l'API GitHub) ; [DeepWiki — Omarchy ISO, Installation System](https://deepwiki.com/omacom-io/omarchy-iso/3-installation-system) ; [omacom/omarchy-configurator](https://github.com/omacom/omarchy-configurator) ; [archlinux/archinstall](https://github.com/archlinux/archinstall) (`models/bootloader.py`, `models/device.py`, `default_profiles/profile.py`, `lib/profile/profiles_handler.py`, `examples/config-sample.json`, `docs/cli_parameters/config/config_options.csv`, releases 4.0→4.4) ; [OSTechNix — archinstall 4.0](https://ostechnix.com/archinstall-4-0-textual-tui-release/) ; [archinstall 4.1](https://www.linuxcompatible.org/story/archinstall-41-released/) ; [Calamares — Codeberg releases](https://codeberg.org/Calamares/calamares/releases) ; [calamares/calamares (archivé)](https://github.com/calamares/calamares) ; [Calamares — modules et branding QML](https://github.com/calamares/calamares/blob/calamares/src/modules/README.md) ; [CachyOS — changelog installeur GUI](https://wiki.cachyos.org/cachyos_basic/changelogs/gui_installer/) ; [CachyOS janvier 2026](https://www.linuxcompatible.org/story/cachyos-january-2026-released/) ; [ALCI](https://github.com/arch-linux-calamares-installer/alci-iso) ; [archiso — ArchWiki](https://wiki.archlinux.org/title/Archiso) ; [Archboot](https://archboot.com/) ; [limites GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits) ; [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases).

**Greeter & session** — [AvengeMedia/dank-greeter](https://github.com/AvengeMedia/dank-greeter) (API GitHub, README) ; [DankGreeter — installation](https://danklinux.com/docs/dankgreeter/installation) ; [`extra/dms-shell` — liste de fichiers](https://archlinux.org/packages/extra/x86_64/dms-shell/files/) ; [index Arch `greetd`](https://archlinux.org/packages/?q=greetd) ; [DankMaterialShell#2390](https://github.com/AvengeMedia/DankMaterialShell/issues/2390), [#2138](https://github.com/AvengeMedia/DankMaterialShell/issues/2138), [#1468](https://github.com/AvengeMedia/DankMaterialShell/issues/1468), [#205](https://github.com/AvengeMedia/DankMaterialShell/issues/205) ; [NixOS Discourse — greetd + gnome-keyring](https://discourse.nixos.org/t/automatically-unlocking-the-gnome-keyring-using-luks-key-with-greetd-and-hyprland/54260) ; [greetd (sourcehut)](https://sr.ht/~kennylevinsen/greetd/).

**Signature** — `basecamp/omarchy` : `migrations/1787589206.sh`, `bin/omarchy-update-keyring`, `default/pacman/pacman-{stable,rc,edge}.conf` (lus via l'API GitHub le 2026-08-28) ; [omarchy#2712](https://github.com/basecamp/omarchy/issues/2712) ; [omacom/omarchy-pkgs](https://github.com/omacom/omarchy-pkgs) (README, `build/sign.sh`, `.github/workflows/`) ; [repo-add(8)](https://man.archlinux.org/man/repo-add.8) ; [CachyOS — dépôts optimisés](https://wiki.cachyos.org/features/optimized_repos/) ; [EndeavourOS — keyring](https://forum.endeavouros.com/t/endeavouros-keyring-updated-users-should-update-soon/41117) ; [Wiz — durcissement GitHub Actions](https://www.wiz.io/blog/github-actions-security-guide) ; [Reproducible Builds — rapports 2026](https://reproducible-builds.org/reports/2026-05/).

**Atomique** — [systemd-sysupdate(8)](https://man.archlinux.org/man/systemd-sysupdate.8.en) ; [mkosi(1)](https://man.archlinux.org/man/mkosi.1.en) ; [systemd/particleos](https://github.com/systemd/particleos) et [FOSDEM 2026](https://fosdem.org/2026/schedule/event/DVVAV9-particle-os-from-trad-distro-to-immutable-image/) ; [Collabora — SteamOS 3.6 atomic updates](https://www.collabora.com/news-and-blog/news-and-events/steamos-3-6-how-the-steam-deck-atomic-updates-are-improving.html) ; [openSUSE/transactional-update](https://github.com/openSUSE/transactional-update) ; [Immuarch — forum Arch, 2026-01-28](https://bbs.archlinux.org/viewtopic.php?id=311910).

**Chiffrement & matériel** — [limine-snapper-sync](https://gitlab.com/Zesko/limine-snapper-sync) (README, [issue #7](https://gitlab.com/Zesko/limine-snapper-sync/-/issues/7)) ; [index Arch `limine`](https://archlinux.org/packages/?q=limine) ; [systemd-cryptenroll — ArchWiki](https://wiki.archlinux.org/title/Systemd-cryptenroll) ; [Secure Boot Limine sur CachyOS (2026-07-02)](https://retr0680.github.io/limine_secure_boot/) ; [Microsoft — expiration des certificats Secure Boot juin 2026](https://techcommunity.microsoft.com/blog/windows-itpro-blog/act-now-secure-boot-certificates-expire-in-june-2026/4426856) ; [index Arch `nvidia`](https://archlinux.org/packages/?q=nvidia) ; [Phoronix — Arch passe aux modules ouverts](https://www.phoronix.com/news/Arch-LInux-NVIDIA-Open-Default) ; [TechPowerUp — abandon Pascal](https://www.techpowerup.com/344385/arch-linux-drops-support-for-nvidia-pascal-and-older-gpus) ; [Hyprland Wiki — Nvidia](https://wiki.hypr.land/Nvidia/) ; [core/linux-firmware](https://archlinux.org/packages/core/any/linux-firmware/) ; [fwupd](https://en.wikipedia.org/wiki/Fwupd).
