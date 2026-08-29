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
| Licence amont | **GPL-3.0-or-later** |

## Conséquence de licence, à ne pas contourner en silence

Le dépôt Eschaton est sous **MIT** (`LICENSE` à la racine). `archiso` est sous
**GPL-3.0-or-later**. Les fichiers de `iso/eschaton/` qui reprennent du contenu
de `releng` **restent couverts par la licence d'archiso**, pas par le MIT du
reste du dépôt. C'est le même principe que `packages/vendor/` : ce sont les
fichiers de leurs auteurs, pas les nôtres.

Deux fichiers sont repris **mot pour mot** et sont donc pleinement concernés :

- `airootfs/etc/pacman.d/hooks/uncomment-mirrors.hook`
- `airootfs/etc/pacman.d/hooks/zzzz99-remove-custom-hooks-from-airootfs.hook`

Les autres (`profiledef.sh`, `pacman.conf`, unités systemd, `.network`,
`linux.preset`) sont **réécrits**, mais leur structure et plusieurs de leurs
valeurs viennent de `releng` : on les traite comme dérivés.

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
| `/root/.zlogin`, `.automated_script.sh`, `choose-mirror`, `livecd-sound` | mécaniques de l'ISO Arch dont nous n'avons pas l'usage |

## Ce qui a été ajouté

| Ajouté | Motif |
|---|---|
| Dépôt `[eschaton]` dans les deux `pacman.conf` | spec §3.3 — « le dépôt préconfiguré » |
| `console=ttyS0,115200` sur l'entrée par défaut **et** auto-connexion série | rend le média pilotable en VM sans repatcher l'image à l'octet (`tools/vm-dev.md` §10.3) |
| `snapper`, `limine`, `efibootmgr` | outils de secours exigés par la spec §3.3 |
| `KEYMAP=fr` | cohérence avec le système que `eschaton-install` installe |
| Masquage de `systemd-gpt-auto-generator` | déjà fait par `releng` ; on le conserve et on le teste, car il empêche systemd de monter tout seul l'ESP de la machine qu'on s'apprête à effacer |

[archiso]: https://gitlab.archlinux.org/archlinux/archiso
