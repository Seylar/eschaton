# L'ISO d'Eschaton (SP4b-1)

Média d'installation **x86_64, UEFI, en ligne**. Il embarque de quoi partitionner,
`pacstrap` et se dépanner ; il **ne contient aucun paquet du système cible**, qu'il
télécharge depuis les dépôts Arch et depuis `[eschaton]` pendant l'installation.

- **Autorité** : [spec SP4b-1](../docs/superpowers/specs/2026-08-29-iso-design.md) §3.
- **Provenance et licence du profil** : [`PROVENANCE.md`](PROVENANCE.md) — dérivé de
  `configs/releng` d'archiso, **GPL-3.0-or-later**, alors que le reste du dépôt est MIT.
- **Garde-fous** : `tests/iso-profil.bats`, exécuté par le job `lint` de la CI à
  chaque PR. Il ne construit rien : il verrouille les invariants du profil.

```
iso/
├── build-iso            script de construction (mesure + somme de contrôle)
├── eschaton/            LE profil archiso — il n'y en a qu'un
│   ├── profiledef.sh    identité de l'image, modes d'amorçage, compression
│   ├── packages.x86_64  ce que porte l'environnement live
│   ├── pacman.conf      dépôts utilisés POUR CONSTRUIRE
│   ├── efiboot/         entrées systemd-boot
│   └── airootfs/        ce qui est déposé dans l'environnement live
├── variants/t2/         le DELTA du variant T2 — jamais une copie du profil
│   ├── packages.x86_64  paquets ajoutés/retirés (« -nom » retire)
│   ├── arch-mact2.conf  dépôt tiers, POUR LA CONSTRUCTION SEULEMENT
│   └── motd             ce qui ne marchera pas sur ce matériel
├── work/                artefact de construction (ignoré par git)
└── out/                 l'image et sa somme (ignoré par git)
```

**Deux images, un seul profil** (spec §3.1) :

| | ISO nominal | Variant T2 |
|---|---|---|
| Commande | `iso/build-iso` | `iso/build-iso --variant t2` |
| Cible | x86_64 ordinaire — **le produit** | MacBook Pro 2019 de l'auteur — **le banc** |
| Noyau | `linux` (Arch) | `linux-t2` (dépôt tiers `arch-mact2`, non signé) |
| Image | `eschaton-<version>-x86_64.iso` | `eschaton-t2-<version>-x86_64.iso` |
| Publication | GitHub Release au tag | **jamais, nulle part** (§Variant T2) |

## Construire

`mkarchiso` **n'a besoin ni de `losetup` ni de périphériques loop** : depuis
archiso 89 il assemble l'ESP avec `mtools` (`mmd`/`mcopy`), l'image racine avec
`mksquashfs` et l'ISO avec `xorriso` — aucun de ces outils ne monte quoi que ce
soit. Ce qui reste nécessaire, c'est **root** et la capacité de **monter
`/proc`, `/sys`, `/dev` dans le `pacstrap`**. (`mkarchiso` sait aussi travailler
sans root via `unshare --map-auto`, mais il lui faut alors des plages
`/etc/subuid` / `/etc/subgid` : hors périmètre de notre outillage.)

**`--privileged` n'est pas nécessaire.** `--cap-add SYS_ADMIN --security-opt
apparmor=unconfined` suffisent : c'est ce que fait
[`.github/workflows/iso.yml`](../.github/workflows/iso.yml), vérifié le
2026-08-29 sur un conteneur d'action GitHub, là où `--privileged` accorderait
bien davantage. Les commandes ci-dessous emploient donc les options réduites.

> Réserve d'honnêteté : la **mesure locale** du 2026-08-29 (tableau plus bas) a
> été faite avec `--privileged`. Les options réduites sont prouvées en CI, pas
> re-mesurées sur Docker Desktop. Si la construction locale s'arrêtait sur un
> `mount: … permission denied`, c'est là qu'il faudrait regarder d'abord.

Conséquence pratique, vérifiée : **la construction locale marche sur un Mac
Apple Silicon**, dans un conteneur x86_64 émulé.

```bash
docker run --rm --cap-add SYS_ADMIN --security-opt apparmor=unconfined \
  --platform linux/amd64 \
  -v "$PWD":/eschaton -w /eschaton archlinux:base-devel iso/build-iso
```

L'arborescence de travail de `mkarchiso` pèse plusieurs gigaoctets et l'écrire à
travers le montage lié (virtiofs sous Docker Desktop) est lent. La garder dans le
conteneur et ne faire traverser que l'image :

```bash
docker run --rm --cap-add SYS_ADMIN --security-opt apparmor=unconfined \
  --platform linux/amd64 \
  -e ESCHATON_ISO_WORK=/tmp/iso-work -e ESCHATON_ISO_OUT=/out \
  -v "$PWD":/eschaton -v /chemin/vers/sortie:/out \
  -w /eschaton archlinux:base-devel iso/build-iso
```

En CI, c'est [`.github/workflows/iso.yml`](../.github/workflows/iso.yml) :
déclenchement manuel ou sur un tag `v*`, publication en **GitHub Release** (Pages
plafonne à 1 Go par site, Releases à 2 Gio par fichier).

| Variable | Défaut | Rôle |
|---|---|---|
| `ESCHATON_ISO_WORK` | `iso/work` | arborescence de travail de mkarchiso |
| `ESCHATON_ISO_OUT` | `iso/out` | où atterrissent l'image et sa somme |
| `ESCHATON_ISO_VERSION` | la date du jour | estampille l'image (la CI y met le tag) |

### Ce que `build-iso` vérifie, et pourquoi il le vérifie

`mkarchiso` **peut rendre 0 sur une image inutilisable**. Constaté le 2026-08-29 :
le crochet mkinitcpio `memdisk` réclamait `memdiskfind` (paquet `syslinux`, que
nous avions retiré avec le chemin BIOS). mkinitcpio a rendu
`ERROR: binary not found` puis `errors were encountered during the build` — et la
construction a continué jusqu'à produire une ISO, parce que pacman traite l'échec
d'un crochet post-transaction comme un avertissement et que mkarchiso ne le
regarde pas. C'est exactement la panne muette contre laquelle le Socle s'était
déjà armé côté installeur.

`build-iso` relit donc la sortie de mkarchiso et cherche **deux** motifs :

| Motif | Origine | Portée |
|---|---|---|
| `errors were encountered during the build` | mkinitcpio | la panne du 2026-08-29 |
| `error: command failed to execute correctly` | pacman | **n'importe quel** crochet en échec |

Le second est le marqueur générique : sans lui, la garde n'attraperait que la
panne déjà vue, et le prochain crochet en échec — qui ne passera pas forcément
par mkinitcpio — sortirait de nouveau en silence.

Il contrôle ensuite que l'image contient le noyau, l'initramfs, le squashfs, le
binaire EFI et l'entrée d'amorçage — **et que chacun pèse un minimum**, parce
qu'un fichier vide ou tronqué passait le contrôle de présence au vert. L'image
entière a de même un **plancher** en plus de son plafond : une image tronquée
sort plus petite, pas plus grosse. Ce que ces seuils n'attrapent pas, et il faut
le dire : un binaire manquant *à l'intérieur* d'un initramfs par ailleurs bien
formé — ce cas-là reste du ressort de la relecture du journal.

## Mesure

| | |
|---|---|
| Image | `eschaton-2026.08.29-x86_64.iso` |
| Taille | **1 257 252 864 octets (1,17 Gio)** |
| Budget (GitHub Releases, spec §3.4) | 2 147 483 648 octets (2 Gio) |
| Marge | **849 Mio** |
| Paquets dans l'environnement live | **178** (contre 130 déclarés par `releng`, ~500 installés) |
| Durée de construction | **4 min 55 s** en conteneur x86_64 **émulé** sur Apple M1 Pro |

`build-iso` **échoue** au-delà de 2 Gio : au-delà, GitHub Releases refuse le
fichier et l'image n'est pas publiable. Autant l'apprendre à la construction.

## La place du trousseau (SP4a)

Le dépôt `[eschaton]` n'est pas signé aujourd'hui. Le profil est écrit pour que
son arrivée ne demande **aucune réorganisation** — seulement des modifications
mécaniques, listées ici pour qu'on n'en oublie aucune :

1. Déposer la clé publique en `iso/keyring/eschaton.gpg`. `build-iso` la détecte
   seul : il fait `pacman-key --add` puis `--lsign-key` avec l'empreinte lue dans
   la clé même, **avant** le `pacstrap`. Rien à écrire dans le script.
   (C'est le motif d'Omarchy relevé par la veille §4.3 : la clé est versionnée
   dans le dépôt de construction, jamais téléchargée pendant le build.)
2. Ajouter `eschaton-keyring` à `eschaton/packages.x86_64`, à l'emplacement déjà
   réservé en fin de fichier.
3. Remplacer `SigLevel = Optional TrustAll` par
   `SigLevel = Required DatabaseOptional` dans **les deux** `pacman.conf` —
   `eschaton/pacman.conf` (construction) et `eschaton/airootfs/etc/pacman.conf`
   (environnement live). Les deux portent le repère `SP4a`, et
   `tests/iso-profil.bats` protège ce repère.
4. Reconsidérer le groupe de concurrence de `iso.yml` : l'ISO dépendra alors d'un
   paquet publié par `ci.yml`, et les deux workflows cesseront d'être indépendants.

## Ce qui est un choix de média de développement

Trois décisions servent le dogfooding d'aujourd'hui plus que le produit de
demain. Elles sont sans danger tant que l'ISO reste un livrable d'ingénierie
(spec §2), et **à repeser avant toute distribution grand public** :

1. **Console série sur l'entrée d'amorçage par défaut** (`console=ttyS0,115200`)
   **et auto-connexion root sur la série.** C'est ce qui rend le média pilotable
   en VM sans repatcher l'image à l'octet — le poste le plus coûteux du smoke
   test x86_64 du Socle (`tools/vm-dev.md` §10.3). Portée de sécurité nulle
   aujourd'hui : root a déjà un mot de passe vide et une auto-connexion sur tty1,
   comme sur l'ISO Arch. Une entrée de repli **sans** console série est offerte
   dans le menu.
2. **`KEYMAP=fr` par défaut.** Cohérent avec le système qu'installe
   `eschaton-install`, et surtout : le mot de passe saisi à l'installation doit
   correspondre à celui du système installé. `loadkeys us` est rappelé dans le
   `/etc/motd`.
3. **Root sans mot de passe**, comme `releng`. C'est la norme des médias
   d'installation, mais ce n'en est pas moins une décision.

## Réserves connues (spec §5)

- **Secure Boot non supporté.** `archiso` ne le supporte pas et n'a rien supporté
  depuis 2016 ; le média officiel d'Arch non plus. Un ISO Eschaton ne démarre
  donc **pas** sur une machine dont le Secure Boot est actif — il faut le
  désactiver dans le firmware. Le seul environnement live Arch qui le supporte
  est `archboot` : piste pour le SP4b-2, pas pour maintenant.
- **Amorçage UEFI uniquement.** Le chemin BIOS hérité est retiré volontairement :
  `eschaton-install` exige `/sys/firmware/efi`, un live BIOS ne pourrait rien
  installer. Sur une machine BIOS, ce média ne démarre pas du tout — ce qui vaut
  mieux qu'un live qui démarre pour rien.
- **Installation en ligne.** Le média a besoin du réseau pendant toute
  l'installation. L'ISO hors-ligne engagerait une infrastructure d'hébergement
  hors GitHub (veille §2.6) : c'est un projet en soi, pas un paramètre.
- **Dépôt `[eschaton]` non signé** (`SigLevel = Optional TrustAll`) tant que le
  SP4a n'est pas livré. Voir plus haut.
- **`sshd` livré mais arrêté, et root n'y entre que par clé.** `releng` active
  l'unité ; nous non. `releng` livre aussi
  `airootfs/etc/ssh/sshd_config.d/10-archiso.conf` (`PasswordAuthentication yes`,
  `PermitRootLogin yes`) ; nous ne le reprenons pas, donc le défaut d'OpenSSH
  — `PermitRootLogin prohibit-password` — s'applique. **`passwd` puis
  `systemctl start sshd` ne permet donc pas d'entrer** : il faut déposer une clé
  publique dans `/root/.ssh/authorized_keys` avant de démarrer le service.
  La marche à suivre est dans `/etc/motd` du média.
- **Le média s'identifie « Arch Linux ».** `eschaton-branding` n'est pas dans
  `packages.x86_64` — mais l'y ajouter ne suffirait pas, et c'est le vrai sujet :
  le paquet installe son `os-release` en `/usr/share/eschaton/os-release`, pas en
  `/usr/lib/os-release`. C'est pour cette raison qu'`eschaton-install` fait
  explicitement `rm -f /etc/os-release && cp /usr/share/eschaton/os-release
  /etc/os-release` sur le système cible. Donner son identité au média demande de
  trancher trois choses qui n'ont pas de réponse évidente : *où* la poser
  (`airootfs/usr/lib/os-release` ? un vrai fichier `/etc/os-release`, sachant que
  la copie de l'`airootfs` par mkarchiso écrirait **à travers** le lien
  symbolique que livre `filesystem` — le piège même que documente l'installeur) ;
  si le média doit porter le **même** `os-release` que le système installé ; et
  que faire du `/usr/lib/motd.d/10-eschaton` du paquet, qui s'ajouterait au
  `/etc/motd` du profil. S'y ajoute une conséquence de CI : l'ISO dépendrait
  alors d'un paquet publié par `ci.yml`, ce que le commentaire de `iso.yml`
  range déjà parmi les points « à réévaluer au SP4a ». À trancher, pas à bricoler.
- **`eschaton-install` n'a AUCUNE confirmation avant d'effacer.**
  `sgdisk --zap-all` part dès que les gardes passent. Or ces gardes vérifient la
  *nature* de la cible — que c'est bien un disque entier, qu'il n'est pas occupé,
  que les noms de partition s'en dérivent — **jamais laquelle**. `--disk /dev/sda`
  tapé pour `/dev/sdb` franchit tout et détruit le mauvais disque. Depuis que la
  garde `--disk` tient ses promesses, elle est aussi la *seule* protection qui
  reste, et elle ne couvre pas ce cas-là.
  Ce n'est pas corrigé ici, volontairement : une confirmation qui vaut quelque
  chose doit **montrer ce qu'il y a sur le disque** (modèle, taille, partitions,
  étiquettes) avant de demander, sans quoi elle n'ajoute qu'une frappe et
  entraîne à répondre oui. Le rendu de ce `lsblk`, le descripteur d'où lire la
  réponse (le média démarre sur une console série `ttyS0`, cf. plus haut) et le
  comportement sur EOF — qui doit refuser, jamais consentir — ne se vérifient pas
  depuis un poste macOS, sans ISO ni VM. Poser à l'aveugle une invite sur la
  seule opération irrattrapable irait contre la règle même qui a motivé les
  corrections précédentes.
  À noter pour qui l'implémentera : **il n'y a pas d'usage scripté à préserver
  aujourd'hui.** Le chemin réel est déjà interactif — `arch-chroot /mnt passwd`
  attend une saisie au terminal. Un futur `--yes` devra donc trancher d'abord ce
  qu'il fait du mot de passe, pas seulement de l'effacement.
- **Le variant T2 n'est prouvé que jusqu'à la construction** : il n'a jamais
  démarré sur du matériel. Voir la section suivante.

---

# Le variant T2 (Task 4)

> **Le Mac T2 est une cible *tolérée et cloisonnée*, jamais une cible
> *supportée*** — [ADR 0004](../docs/decisions/0004-perimetre-materiel-mac-t2.md).
> Ce variant est un outil de dogfooding pour l'auteur, sur sa machine. Il n'est
> ni publié, ni annoncé, ni garanti.

## Pourquoi il existe

La puce T2 **est le contrôleur NVMe** du MacBook Pro 2019. Un noyau Arch standard
ne voit donc **aucun disque** : l'ISO nominal démarre sur cette machine et
s'arrête avant de pouvoir partitionner quoi que ce soit. Ce n'est pas un défaut
de configuration, c'est du matériel — et c'est la seule raison d'être de ce
variant. `linux-t2` porte les correctifs T2 et le pilote `apple-bce`, qui expose
le clavier, le trackpad, l'audio et la webcam.

## Ce qu'il change, exactement

Il n'y a **qu'un seul profil archiso** dans ce dépôt. `--variant t2` applique un
delta à la copie de travail, jamais au profil versionné :

| Ce qui change | Où | Pourquoi |
|---|---|---|
| `linux` → `linux-t2` | `variants/t2/packages.x86_64` | la T2 est le contrôleur NVMe |
| `+ apple-bcm-firmware` | idem | Wi-Fi ; **pas d'Ethernet** sur cette machine |
| `+ t2fanrd` | idem | sans démon, les ventilateurs restent au régime du SMC |
| `[arch-mact2]` | `pacman.conf` **de construction** | le noyau n'est nulle part ailleurs |
| `linux.preset` → `linux-t2.preset` | copie de travail | mkinitcpio cherche le nom du **paquet** |
| `vmlinuz-linux` → `vmlinuz-linux-t2` | entrées d'amorçage | le fichier a un autre nom |
| `+ intel_iommu=on iommu=pt pcie_ports=compat pm_async=off` | idem | recette t2linux (veille §2.1) |
| une entrée `nomodeset` de plus | idem | échappatoire écran noir (voir §Points ouverts) |
| le motd dit ce qui ne marchera pas | copie de travail | l'auteur doit le lire avant, pas après |

**`apple-bce` n'est pas dans la liste, et ce n'est pas un oubli.** Le plan
(Task 4.1) et la spec §3.3 le nomment comme un paquet ; l'index réel du dépôt,
relevé le 2026-08-30, publie 37 paquets et **aucun de ce nom**. Le pilote est
compilé *dans* `linux-t2`. C'est le plan qu'il faut corriger, pas la liste.

## Le dépôt tiers ne sort pas de la construction

`arch-mact2` est servi par un miroir tiers, publié par un mainteneur unique, et
**n'est pas signé** (`SigLevel = Never`). Il est ajouté au `pacman.conf` de
construction et **jamais** à celui de l'environnement live ni du système
installé (ADR 0004 §4.2) — sans quoi l'exigence de signature que le SP4a doit
fermer sur `[eschaton]` serait vidée de son sens.

`build-iso` le vérifie **deux fois** : sur le profil avant de construire, et sur
l'arborescence que `pacstrap` a réellement produite. Le contrôle porte sur les
*configurations pacman*, pas sur le mot lui-même — le motd nomme le dépôt en
toutes lettres, et c'est voulu. (Ce raffinement n'est pas théorique : la première
construction s'est arrêtée sur ce faux positif exact, cf. `tools/vm-dev.md` §20.)

## La garde d'épinglage du noyau

Elle vit dans le paquet **`packages/eschaton-t2/`**, qui ne s'installe **qu'à la
main**, sur la machine concernée : rien ne le tire, ni `eschaton-base` ni
l'installeur. Trois crochets alpm y branchent un script unique :

| Crochet | Moment | Effet |
|---|---|---|
| `90-…-noyau` | PreTransaction, `AbortOnFail` | **refuse** `linux`, `linux-lts`, `linux-zen`, `linux-hardened`, `linux-rt` |
| `91-…-retrait` | PreTransaction, `AbortOnFail` | **refuse** le retrait de `linux-t2` |
| `92-…-alignement` | PostTransaction | **constate** : arbre de modules, `apple-bce`, `/boot` |

Le script tranche sur le **nom exact** du paquet, jamais sur ce qu'il fournit :
`linux-t2` déclare `provides = linux`, et l'on ne veut pas dépendre de la façon
dont pacman associe une cible à un fournisseur.

**Ce que la garde ne fait pas, et il faut le dire.** La veille §2.3 souhaitait
« un crochet qui bloque un `-Syu` si `linux-t2` n'est pas disponible pour la
version cible ». Ce n'est **pas** implémenté : pacman n'expose à un crochet ni la
version amont ni la notion de « version cible », et un crochet qui interrogerait
le réseau mentirait sur ce qu'il mesure. Le filet reste le **snapshot
pré-mise-à-jour et le rollback** — ce que l'ADR 0004 §4.4 appelle précisément le
test de résistance le plus sévère de notre fonctionnalité phare.

*Note de terrain (2026-08-30)* : `linux-t2` est en **7.1.8.arch1-3** alors que la
veille relevait un amont en 7.1.5 début août. Le retard structurel décrit par la
veille §2.2 est réel dans son mécanisme (mainteneur unique, dépôt tiers), mais il
**n'était pas observable ce jour-là**. Il reste à mesurer dans la durée.

## L'interdiction de publier — trois verrous

Le variant embarque `apple-bcm-firmware`, c'est-à-dire du **firmware Broadcom
extrait de macOS Big Sur et redistribué**. Zone grise juridique (spec §3.3) :
`archiso-t2` l'assume en tant que projet communautaire, Eschaton ne l'a pas
tranché — et tant que ce n'est pas tranché, la réponse est non.

1. **`build-iso` refuse de construire le variant sous CI** (`GITHUB_ACTIONS` ou
   `CI`). On ne publie pas par accident un fichier qui n'a jamais été produit. Le
   refus est placé avant les contrôles de root et d'architecture, donc
   atteignable — et **testable** — depuis un poste macOS.
2. **`iso.yml` refuse tout artefact T2** avant la publication, et le job de
   Release **n'emploie plus de joker** `iso-out/*.iso` : il énumère et refuse
   l'ambiguïté. Ce second verrou n'est pas redondant — le premier empêche l'image
   d'être *produite* en CI, celui-ci empêche une image produite *ailleurs* d'être
   publiée.
3. **L'image se nomme `eschaton-t2-…`** et `build-iso` dépose un
   `NE-PAS-PUBLIER.txt` à côté d'elle, pour qui la retrouverait dans six mois.

`tests/iso-variant-t2.bats` exerce les trois.

## Marche à suivre sur la vraie machine (Task 5 — non exécutée)

> Rien de ce qui suit n'a été fait : cette section est un mode opératoire, pas un
> compte rendu. Elle exige la machine physique de l'auteur.

1. **Depuis macOS, avant tout le reste** — noter le modèle exact
   (`Menu Pomme > Réglages > Général > Informations`, identifiant `MacBookProXX,Y`) :
   il détermine la présence du GPU AMD dédié.
2. **Redémarrer en Recovery** (`Cmd+R` maintenu à l'allumage) →
   *Utilitaire de sécurité au démarrage* (**Startup Security Utility** si macOS
   est en anglais) :
   - Sécurité au démarrage → **Aucune sécurité** ;
   - Démarrage externe → **Autoriser le démarrage depuis un support externe**.

   Ce réglage vit dans la T2 et **survit à l'effacement du disque** : le faire
   **avant** d'effacer, sinon la clé USB ne démarrera plus.
3. **Écrire l'image** sur une clé (`dd`, ou l'outil habituel), démarrer avec
   `Alt/Option` maintenu et choisir le média EFI.
4. **Vérifier d'abord que le disque est visible** : `lsblk -o NAME,SIZE,MODEL,TYPE`.
   S'il ne l'est pas, ne pas insister — l'image n'est pas la bonne.
5. **Installer** : `eschaton-install --disk /dev/… --user … --hostname …`.
   ⚠️ L'installeur **efface le disque entier sans confirmation** (voir les
   réserves plus haut) et exige une ESP de 4 Gio, là où celle d'Apple fait
   300 Mo : c'est l'effacement complet, ou rien.
6. **Après le premier démarrage**, installer la garde à la main :
   ajouter le dépôt `arch-mact2` (sa politique est à l'utilisateur, elle n'est
   pas livrée par Eschaton), puis `pacman -S eschaton-t2`.
7. **Prouver le rollback** sur cette machine : cassage volontaire, restauration,
   redémarrage vérifié. C'est le point le plus précieux de toute la tâche.

## Ce qui ne marchera pas, ou mal

Liste tenue de la veille §3, à ne pas édulcorer :

| | |
|---|---|
| **Touch ID** | **Jamais.** Le capteur répond à la Secure Enclave, qui ne rend à l'OS ni image ni verdict exploitable. Ce n'est pas « pas encore » : aucune version de `fprintd`/PAM n'y accédera. |
| **Micro interne** | Volume faible — caractéristique matérielle, pas un défaut logiciel. |
| **Veille / suspend** | Fragile ; régressions connues sur les noyaux récents. |
| **Touch Bar** | Fonctionne, mais **ne se réveille pas après une veille** (6.12.31+/7.0.5). |
| **GPU AMD (15″/16″)** | Bascule hybride à gérer ; la Radeon Pro 5600M rend un écran noir sans `nomodeset`. |
| **Trackpad** | Ni force-touch ni rejet de paume. |
| **Bluetooth** | Perturbé quand le Wi-Fi 2,4 GHz est actif simultanément. |
| **Chiffrement** | Celui de la T2 est transparent pour Linux : au repos, ce sera **LUKS** ou rien. |

## Points ouverts — l'auteur seul peut les trancher

Ils sont **paramétrés, pas figés** : y répondre ne demande pas de repenser le
variant.

1. **Taille d'écran** (ADR 0004 §6.1) — 13″ (iGPU seul) ou 15″/16″ (Radeon
   dédiée). La réponse est l'option `--gpu` :

   | Valeur | Effet |
   |---|---|
   | `indetermine` (défaut) | aucun paramètre GPU supposé |
   | `igpu` | 13″ : rien à ajouter, il n'y a pas de bascule |
   | `amd` | 15″/16″ : `apple_gmux.force_igd=y` |

   Et **même sans réponse, l'image est utilisable** : elle offre au menu une
   entrée `nomodeset` qui couvre le cas de l'écran noir. La question ne bloque
   donc pas la construction — elle affine le défaut.
2. **Sort de macOS** (ADR 0004 §6.2) — **sans effet sur l'image** : c'est une
   décision qui se joue à l'étape 5 ci-dessus, dans les arguments d'installation.
   La recommandation de la veille §8 reste l'effacement complet (l'ESP d'Apple
   fait 300 Mo contre les 4 Gio exigés, et une mise à jour macOS casse le boot).
3. **Ratification du périmètre** (ADR 0004 §6.3) — l'ADR est encore *proposé*.

Un quatrième point s'y ajoute, découvert en écrivant ce variant :

4. **L'architecture du paquet `eschaton-t2`.** L'ADR §4.1 l'annonce
   « forcément non-`any` puisqu'il dépend de `linux-t2` ». Il est livré en
   **`arch=(any)`**, et le PKGBUILD dit pourquoi : l'architecture décrit ce qu'un
   paquet *contient* — ici deux fichiers texte et un script shell — pas ce dont
   il dépend. Ce n'est pas cosmétique : `repo/build-repo` construit **tous** les
   PKGBUILD dans les **deux** jobs d'architecture et refuse un dépôt incomplet,
   donc un `arch=(x86_64)` ferait échouer le job aarch64. À ratifier.
