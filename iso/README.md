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
├── eschaton/            le profil archiso
│   ├── profiledef.sh    identité de l'image, modes d'amorçage, compression
│   ├── packages.x86_64  ce que porte l'environnement live
│   ├── pacman.conf      dépôts utilisés POUR CONSTRUIRE
│   ├── efiboot/         entrées systemd-boot
│   └── airootfs/        ce qui est déposé dans l'environnement live
├── work/                artefact de construction (ignoré par git)
└── out/                 l'image et sa somme (ignoré par git)
```

## Construire

`mkarchiso` **n'a besoin ni de `losetup` ni de périphériques loop** : depuis
archiso 89 il assemble l'ESP avec `mtools` (`mmd`/`mcopy`), l'image racine avec
`mksquashfs` et l'ISO avec `xorriso` — aucun de ces outils ne monte quoi que ce
soit. Ce qui reste nécessaire, c'est de pouvoir **monter `/proc`, `/sys`, `/dev`
dans le `pacstrap`** : d'où root et `--privileged`. (`mkarchiso` sait aussi
travailler sans root via `unshare --map-auto`, mais il lui faut alors des plages
`/etc/subuid` / `/etc/subgid` : hors périmètre de notre outillage.)

Conséquence pratique, vérifiée : **la construction locale marche sur un Mac
Apple Silicon**, dans un conteneur x86_64 émulé.

```bash
docker run --rm --privileged --platform linux/amd64 \
  -v "$PWD":/eschaton -w /eschaton archlinux:base-devel iso/build-iso
```

L'arborescence de travail de `mkarchiso` pèse plusieurs gigaoctets et l'écrire à
travers le montage lié (virtiofs sous Docker Desktop) est lent. La garder dans le
conteneur et ne faire traverser que l'image :

```bash
docker run --rm --privileged --platform linux/amd64 \
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
déjà armé côté installeur. `build-iso` relit donc la sortie de mkarchiso, puis
contrôle que l'image contient bien le noyau, l'initramfs, le squashfs, le binaire
EFI et l'entrée d'amorçage, avant de mesurer et de signer.

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
- **`sshd` livré mais arrêté.** `releng` l'active ; nous non. `passwd` puis
  `systemctl start sshd` pour l'ouvrir.
- **Rien n'est prouvé pour le variant T2** (Task 4 du plan) : il dépend d'arbitrages
  utilisateur non tranchés (ADR 0004 §6).
