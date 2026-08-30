# Profil archiso — provenance et licence

Le profil `iso/eschaton/` est **dérivé de `configs/releng/`** d'[archiso], le
profil dont l'ISO officielle d'Arch Linux est construite. C'est la méthode que
l'outil documente (« copier un profil, éditer `packages.x86_64`, déposer dans
`airootfs/` ») et celle que la spec §3.2 retient.

| | |
|---|---|
| Amont | https://gitlab.archlinux.org/archlinux/archiso |
| Version copiée | `extra/archiso 89-1` (`any`) |
| Date de la copie | 2026-08-29 |
| Inventaire re-mesuré le | 2026-08-30, contre l'archive du tag `v89` du dépôt amont |
| Licence amont | **GPL-3.0-or-later** |

## Conséquence de licence, à ne pas contourner en silence

Le dépôt Eschaton est sous **MIT** (`LICENSE` à la racine). `archiso` est sous
**GPL-3.0-or-later**. Les fichiers de `iso/eschaton/` qui reprennent du contenu
de `releng` **restent couverts par la licence d'archiso**, pas par le MIT du
reste du dépôt. C'est le même principe que `packages/vendor/` : ce sont les
fichiers de leurs auteurs, pas les nôtres.

### Inventaire exact

Ce document ne vaut que par sa précision : un inventaire approximatif ne protège
personne. Il a donc été **mesuré**, pas estimé — profil comparé fichier par
fichier à `configs/releng` de l'archive du tag `v89` d'archiso, le 2026-08-30.
La reprise est plus large que ce qui figurait ici (« deux fichiers »).

**Trois fichiers sont BYTE-IDENTIQUES à `releng`** — dont deux qu'aucune ligne
de ce dépôt ne nommait :

- `airootfs/etc/shadow`
- `airootfs/etc/locale.conf`
- `airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf`

**Six autres le sont une fois les commentaires retirés** : seul le commentaire
(traduit ou étoffé) diffère, pas une directive.

- `airootfs/etc/pacman.d/hooks/uncomment-mirrors.hook`
- `airootfs/etc/pacman.d/hooks/zzzz99-remove-custom-hooks-from-airootfs.hook`
- `airootfs/etc/mkinitcpio.d/linux.preset`
- `airootfs/etc/systemd/journald.conf.d/volatile-storage.conf`
- `airootfs/etc/systemd/logind.conf.d/do-not-suspend.conf`
- `airootfs/etc/systemd/system/systemd-networkd-wait-online.service.d/wait-for-only-one-interface.conf`

**Deux unités ne diffèrent que par leur `Description=`**, traduite :
`airootfs/etc/systemd/system/etc-pacman.d-gnupg.mount` et
`airootfs/etc/systemd/system/pacman-init.service`.

**Les 14 liens symboliques du profil viennent tous de `releng`**, au même chemin ;
13 pointent vers exactement la même cible. Le quatorzième,
`multi-user.target.wants/pacman-init.service`, vise
`/etc/systemd/system/pacman-init.service` là où `releng` écrit
`../pacman-init.service` — même fichier, chemin absolu au lieu de relatif.

Les autres (`profiledef.sh`, `pacman.conf`, `packages.x86_64`, les deux
`.network`, `loader.conf`, `passwd`, `motd`, `hostname`, `archiso.conf`) sont
**réécrits**, mais leur structure et plusieurs de leurs valeurs viennent de
`releng` : on les traite comme dérivés.

L'effet juridique est le même qu'avec l'ancien décompte — tout `iso/eschaton/`
est traité comme dérivé de `releng`. Ce qui change, c'est l'exactitude.

**À trancher avant la première publication grand public** : soit le dépôt
mentionne explicitement cette double licence, soit `iso/` reçoit son propre
fichier de licence. La question ne se pose pas tant que l'ISO reste un livrable
d'ingénierie ; elle se poserait dès la première mise en ligne étiquetée.

## Ce qui a été retiré de `releng`

Le profil est une **réduction**, jamais une extension. Le détail et le motif de
chaque retrait sont dans les fichiers concernés (`packages.x86_64`,
`profiledef.sh`, `airootfs/etc/mkinitcpio.conf.d/archiso.conf`). En résumé :

| Retiré | Motif |
|---|---|
| `bios.syslinux` et l'arborescence `syslinux/` | `eschaton-install` exige un amorçage UEFI ; un live BIOS ne pourrait rien installer |
| Crochet mkinitcpio `memdisk` | il appelle `memdiskfind`, du paquet `syslinux` retiré ci-dessus |
| Crochets mkinitcpio `archiso_pxe_*` et `mkinitcpio-nfs-utils` | Eschaton ne démarre pas par le réseau |
| `wpa_supplicant` | **régression 2.11** constatée par la veille ; `iwd` seul |
| ~100 paquets de sauvetage, PXE, cloud-init, intégrations invité, systèmes de fichiers tiers | l'ISO est *en ligne* (spec §3.4) : il partitionne, `pacstrap`, et se dépanne — il ne répare pas les systèmes des autres |
| `grub/`, entrées memtest86+, `edk2-shell` | sans objet une fois le chemin BIOS et GRUB écartés |
| Activation de `sshd.service` | décision, pas défaut de configuration (veille §1, ligne 9) |
| `airootfs/etc/ssh/sshd_config.d/10-archiso.conf` (`PasswordAuthentication yes`, `PermitRootLogin yes`) | second durcissement, par abstention : le défaut d'OpenSSH (`prohibit-password`) s'applique, root n'entre que par clé. **Conséquence sur la marche à suivre**, voir [`README.md`](README.md) et le `motd` |
| `MulticastDNS=yes` dans les deux `.network` | relevé le 2026-08-30 en comparant à `releng` ; divergence qui n'était consignée nulle part. Sans objet pour un média d'installation, mais elle est désormais écrite ici |
| `/root/.zlogin`, `.automated_script.sh`, `choose-mirror`, `livecd-sound` | mécaniques de l'ISO Arch dont nous n'avons pas l'usage |
| Shell de root en `/usr/bin/zsh` (`airootfs/etc/passwd`) | `zsh` n'est pas dans `packages.x86_64` ; root est en `/usr/bin/bash` |

## Ce qui a été ajouté

| Ajouté | Motif |
|---|---|
| Dépôt `[eschaton]` dans les deux `pacman.conf` | spec §3.3 — « le dépôt préconfiguré » |
| `console=ttyS0,115200` sur l'entrée par défaut **et** auto-connexion série | rend le média pilotable en VM sans repatcher l'image à l'octet (`tools/vm-dev.md` §10.3) |
| `snapper`, `limine`, `efibootmgr` | outils de secours exigés par la spec §3.3 |
| `KEYMAP=fr` | cohérence avec le système que `eschaton-install` installe |
| Masquage de `systemd-gpt-auto-generator` | déjà fait par `releng` ; on le conserve et on le teste, car il empêche systemd de monter tout seul l'ESP de la machine qu'on s'apprête à effacer |

## Ce qui a été ramené à la valeur amont

| Fichier | Écart, et pourquoi il n'existe plus |
|---|---|
| `airootfs/etc/systemd/networkd.conf.d/ipv6-privacy-extensions.conf` | portait `IPv6PrivacyExtensions=kernel` là où `releng` écrit `yes`, sans motif consigné. `kernel` laisse en place le réglage du noyau (désactivé par défaut) : le fichier n'activait donc RIEN, dans un fichier dont le nom promet l'inverse. Revenu à `yes` le 2026-08-30, avec le motif écrit dans le fichier |

[archiso]: https://gitlab.archlinux.org/archlinux/archiso
