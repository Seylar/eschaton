# VM de développement `eschaton-dev` (aarch64, UTM)

Procédure de création de la VM de développement sur Mac Apple Silicon, et
résultat du spike qui valide l'environnement live aarch64 (spec §4.1, risque n°1).

## Décision

**archboot aarch64 est validé** — chemin nominal retenu. Les 4 critères du spike
passent sur un Mac Apple Silicon (M1 Pro, macOS 26.5.1), dans une VM UTM
virtualisée (QEMU + HVF).

Le repli prévu par la spec (image Arch Linux ARM préfabriquée + mode
« convergence » de `eschaton-install`) **n'est pas nécessaire** : Task 7 n'a pas
à développer le mode convergence.

Spike réalisé le 2026-08-27.

---

## 1. Prérequis hôte : UTM

```bash
ls /Applications/UTM.app 2>/dev/null || brew install --cask utm
```

Version utilisée : **UTM 4.7.5** (cask Homebrew). Le cask installe aussi le CLI
`/Applications/UTM.app/Contents/MacOS/utmctl`, qui n'est pas dans le `PATH`.

> **Ne jamais cocher « Apple Virtualization ».** La FAQ archboot est explicite :
> le backend Apple Virtualization de UTM ne fonctionne pas avec le kernel
> aarch64 d'archboot. La VM décrite ici utilise le backend **QEMU avec
> accélération HVF** (le mode « Virtualize » par défaut de UTM) — vérifiable sur
> la ligne de commande QEMU générée, qui porte `-accel hvf`.

## 2. ISO archboot

L'URL du plan initial (`pkgbuild.com/~tpowa/archboot/iso/aarch64/latest/`) est
**morte (HTTP 404)**. La source qui fait foi est `https://archboot.com/`, dont le
tableau des releases pointe le miroir officiel `release.archboot.com`.

| | |
|---|---|
| Fichier | `archboot-2026.08.27-02.28-7.2.0-2-aarch64-ARCH-aarch64.iso` |
| URL | `https://release.archboot.com/aarch64/latest/iso/archboot-2026.08.27-02.28-7.2.0-2-aarch64-ARCH-aarch64.iso` |
| Taille | 484 597 760 octets (462 MiB) |
| BLAKE2b | `5cacbd877b5983bef2f9621d65f04d68ba664f9e2acf76eec95c64c16939b44a02eb5d212c82637c51ece3344db405c8e1682112a8ad86e5fc535097e04e3286` |
| Sommes de contrôle | `https://release.archboot.com/aarch64/latest/b2sum.txt` |

```bash
cd ~/Downloads
curl -L -C - --retry 3 -O \
  https://release.archboot.com/aarch64/latest/iso/archboot-2026.08.27-02.28-7.2.0-2-aarch64-ARCH-aarch64.iso
curl -sSL https://release.archboot.com/aarch64/latest/b2sum.txt | grep 'ARCH-aarch64.iso)'
b2sum archboot-2026.08.27-02.28-7.2.0-2-aarch64-ARCH-aarch64.iso
```

Le b2sum a été vérifié et correspond à l'amont.

**Choisir la variante « standard »**, pas les variantes `-latest` ni `-local` :

| Variante | RAM pour booter | Réseau | Cache de paquets |
|---|---|---|---|
| `…-aarch64.iso` (retenue) | 750 Mo | DHCP au boot | non |
| `…-latest-aarch64.iso` | 2300 Mo | serveur DHCP local requis | ≥ 3200 Mo de RAM |
| `…-local-aarch64.iso` | 3200 Mo | hors-ligne | oui |

## 3. Création de la VM (scriptée, sans GUI)

UTM expose un dictionnaire AppleScript
(`/Applications/UTM.app/Contents/Resources/UTM.sdef`) qui permet de créer la VM
sans toucher à l'interface. `utmctl` ne sait pas créer de VM (pas de
sous-commande `create`) mais sait lister, démarrer, arrêter et supprimer.

### 3.1 Créer la VM

```applescript
-- ~/create-eschaton-dev.applescript
tell application "UTM"
	set isoPath to POSIX file "/Users/<vous>/Downloads/archboot-2026.08.27-02.28-7.2.0-2-aarch64-ARCH-aarch64.iso"
	set vm to make new virtual machine with properties {backend:qemu, configuration:{name:"eschaton-dev", architecture:"aarch64", machine:"virt", memory:4096, cpu cores:4, hypervisor:true, uefi:true, drives:{{removable:true, interface:USB, source:isoPath}, {removable:false, interface:VirtIO, guest size:65536}}, network interfaces:{{mode:shared}}, «class SrPt»:{{interface:ptty}}}}
	return id of vm
end tell
```

```bash
osascript ~/create-eschaton-dev.applescript
```

### 3.2 Deux pièges d'AppleScript/UTM (rencontrés et contournés)

1. **`serial ports` doit s'écrire `«class SrPt»`.** AppleScript normalise la clé
   `serial ports` en `serial port` (singulier), ce qui entre en collision avec la
   classe du même nom et fait échouer toute la coercition avec « Impossible de
   convertir … en type qemu configuration ». Le code brut `«class SrPt»`
   contourne le problème (caractères `«` `»`, à saisir tels quels).
2. **`update configuration` remplace les listes en entier.** Un appel qui ne
   passe que le lecteur CD **supprime le disque de 64 Gio** (et son `.qcow2`).
   Ne pas l'utiliser pour des mises à jour partielles — préférer l'édition du
   `config.plist`, UTM quitté (§3.3).

À noter : le `config.plist` de la VM ainsi créée n'affiche **aucun chemin d'ISO**
sur le lecteur CD. Ce n'est pas un bug — UTM range le `source:` sous forme de
*security-scoped bookmark* dans ses préférences
(`~/Library/Containers/com.utmapp.UTM/Data/Library/Preferences/com.utmapp.UTM.plist`),
avec le chemin absolu vers `~/Downloads`. L'ISO est bien montée. L'étape §3.3
sert à rendre la VM autonome de ce chemin externe.

### 3.3 Finaliser : écran, ISO autonome, ordre de démarrage

Trois retouches, **UTM quitté** (sinon il réécrit le plist depuis sa copie
mémoire) :

- **l'écran** : la création par AppleScript n'en pose aucun, la VM serait
  headless ;
- **l'ISO dans le bundle** : `cp -c` = clone APFS, instantané et sans coût
  disque ; le `ImageName` prime sur le bookmark, la VM ne dépend donc plus de
  `~/Downloads` ;
- **l'ordre des lecteurs** : le premier de la liste reçoit `bootindex=0`. En
  plaçant **le disque avant le CD**, l'UEFI tente d'abord `/dev/vda` et retombe
  sur l'ISO tant que le disque n'est pas amorçable. Aucune manipulation ne sera
  donc nécessaire après l'installation pour démarrer sur Eschaton (§7).

```bash
VM="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/eschaton-dev.utm"

osascript -e 'tell application "UTM" to quit'
cp -c ~/Downloads/archboot-2026.08.27-02.28-7.2.0-2-aarch64-ARCH-aarch64.iso "$VM/Data/archboot.iso"

plutil -insert Display.0 -json \
  '{"Hardware":"virtio-gpu-pci","DynamicResolution":true,"NativeResolution":false,"UpscalingFilter":"Nearest","DownscalingFilter":"Linear"}' \
  "$VM/config.plist"

python3 - "$VM/config.plist" <<'PY'
import plistlib, sys
p = sys.argv[1]
cfg = plistlib.load(open(p, "rb"))
for d in cfg["Drive"]:
    if d.get("ImageType") == "CD":
        d["ImageName"] = "archboot.iso"
# disque en premier -> bootindex=0 ; CD ensuite -> bootindex=1
cfg["Drive"].sort(key=lambda d: 0 if d.get("ImageType") == "Disk" else 1)
plistlib.dump(cfg, open(p, "wb"))
for i, d in enumerate(cfg["Drive"]):
    print(f"Drive.{i}  {d.get('ImageType')}  {d.get('ImageName')}")
PY

plutil -lint "$VM/config.plist"
open -a UTM
```

État attendu — et état réel de la VM du spike :

```
Drive.0  Disk  1F2D3648-….qcow2   (VirtIO, 64 Gio, bootindex=0)
Drive.1  CD    archboot.iso       (USB, bootindex=1)
```

### 3.4 Démarrer / arrêter

```bash
UTMCTL=/Applications/UTM.app/Contents/MacOS/utmctl
$UTMCTL list
$UTMCTL start eschaton-dev
$UTMCTL status eschaton-dev
$UTMCTL stop eschaton-dev
```

## 4. Réglages de la VM

| Réglage | Valeur |
|---|---|
| Nom | `eschaton-dev` |
| Backend | QEMU (**pas** Apple Virtualization), `hypervisor:true` → `-accel hvf` |
| Architecture / machine | `aarch64` / `virt` |
| RAM | 4096 Mio |
| Cœurs configurés | 4 (mais l'environnement live n'en voit qu'un — §7) |
| Disque | 64 Gio, VirtIO, qcow2 → `/dev/vda` dans l'invité, `bootindex=0` |
| ISO | lecteur CD amovible sur USB, `bootindex=1` → `/dev/sr0` |
| Réseau | `Shared` → `-netdev vmnet-shared`, DHCP, invité en `192.168.64.2/24` |
| Série | `ptty` → `-chardev pty -serial chardev:term0` |
| Écran | `virtio-gpu-pci` |
| Démarrage | UEFI (edk2-aarch64), `fw_platform_size` = 64 |

## 5. Piloter la VM depuis le terminal (console série)

C'est le point qui rend la VM **entièrement scriptable, sans aucune interaction
graphique** : archboot active un getty série sur `ttyS0`, `ttyAMA0` et `ttyUSB0`,
et sa ligne de commande kernel contient `console=ttyAMA0,115200`. Le port série
`ptty` de UTM expose donc un shell root sur un pty de l'hôte.

Récupérer le chemin du pty :

```bash
/Applications/UTM.app/Contents/MacOS/utmctl attach eschaton-dev
#   WARNING: attach command is not implemented yet!
#   PTTY: /dev/ttys000
```

`utmctl attach` **n'est pas implémenté** en UTM 4.7.5 : il se contente d'afficher
le chemin. Même information par AppleScript :

```bash
osascript -e 'tell application "UTM" to return address of serial port 1 of virtual machine named "eschaton-dev"'
```

Session interactive humaine (`screen` et `cu` sont fournis par macOS) :

```bash
screen /dev/ttys000        # quitter : Ctrl-A puis k
```

### 5.1 Obtenir le shell root : `Ctrl-C`

Une fois booté, archboot affiche sur la console série :

```
Welcome to Archboot - Arch Linux AARCH64
…
Hit ENTER for login routine or CTRL-C for bash prompt.
```

Envoyer **`Ctrl-C` (octet `0x03`)** donne immédiatement `[root@archboot /] #`.

**Il n'est pas nécessaire de passer par l'assistant « Basic Setup ».** Vérifié :
sans l'assistant, le DHCP est déjà obtenu (`enp0s1` en `192.168.64.2/24`) et
`/etc/pacman.d/mirrorlist` contient déjà
`Server = http://mirror.archlinuxarm.org/$arch/$repo` — `pacman -Sy` fonctionne
directement. C'est le chemin à privilégier pour Task 9.

Pour mémoire, si l'on appuie sur `ENTER` au lieu de `Ctrl-C`, l'assistant se
déroule ainsi (`Entrée` à chaque étape sauf mention) : Locale `en_US` → Network
Interface `enp0s1` → Profile Name → *Use DHCP?* `Yes` → Proxy (vide) → Summary
`Yes` → Package Mirror (une flèche bas puis `Entrée`) → Launcher Menu (`Tab` puis
`Entrée`) → Exit Menu `1 Exit Program`.

### 5.2 Pilotage scripté

Ouvrir le pty **une seule fois** pour toute la session.

```python
#!/usr/bin/env python3
# usage: vmrun.py "<commande>" ["<commande>" ...]
import os, re, select, sys, termios, time
DEV, B, E = "/dev/ttys000", "__B__", "__E__"
ANSI = re.compile(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][0-9A-B]|\x1b.")
fd = os.open(DEV, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd); a[0] = a[1] = a[3] = 0
a[6][termios.VMIN] = a[6][termios.VTIME] = 0
termios.tcsetattr(fd, termios.TCSANOW, a)
for cmd in sys.argv[1:]:
    while select.select([fd], [], [], 0.2)[0]: os.read(fd, 65536)
    os.write(fd, f"echo {B}; {cmd}; echo {E}$?\n".encode())
    buf, deadline = bytearray(), time.time() + 120
    while time.time() < deadline:
        if select.select([fd], [], [], 0.3)[0]:
            buf += os.read(fd, 65536)
            if buf.count(E.encode()) >= 2 and b"\n" in buf.rsplit(E.encode(), 1)[1]: break
    txt = ANSI.sub("", buf.decode("utf-8", "replace")).replace("\r", "")
    out, cap, rc = [], False, None
    for ln in txt.split("\n"):          # la ligne tapée est ré-affichée par le
        if not cap:                     # tty : ne capturer qu'après le marqueur
            cap = ln.strip() == B       # SEUL sur sa ligne
            continue
        if ln.startswith(E):
            rc = ln[len(E):].strip(); break
        out.append(ln)
    print(f"$ {cmd}\n" + "\n".join(out).strip() + f"\n[rc={rc}]")
os.close(fd)
```

```console
$ python3 vmrun.py "uname -m" "nproc" "lsblk -o NAME,SIZE -n /dev/vda"
$ uname -m
aarch64
[rc=0]
$ nproc
1
[rc=0]
$ lsblk -o NAME,SIZE -n /dev/vda
vda   64G
[rc=0]
```

Deux règles apprises à la dure :

> **Ne pas rouvrir le pty à chaque commande.** Enchaîner `open()`/`close()` finit
> par raccrocher la ligne (SIGHUP) et la console devient muette pendant plusieurs
> dizaines de secondes. Un `Ctrl-C` (octet `0x03`) la réveille.

> **Préfixer par `timeout N` toute commande qui peut bloquer** (réseau en
> particulier). Une commande bloquée ne rend jamais son marqueur de fin : les
> commandes suivantes s'empilent dans le tampon du tty et le pilotage se
> désynchronise silencieusement.

## 6. Résultat des 4 critères du spike

Vérifiés une première fois via l'assistant, puis **re-vérifiés intégralement sur
un démarrage neuf** avec la configuration finale de la VM et le chemin `Ctrl-C`
(sans assistant). Résultats identiques.

### Critère 1 — boot UEFI jusqu'à un shell root : **OK**

```
Linux archboot 7.2.0-2-aarch64-ARCH #1 SMP PREEMPT_DYNAMIC Mon Aug 24 19:44:47 UTC 2026 aarch64 GNU/Linux
UEFI: yes
/sys/firmware/efi/fw_platform_size = 64
```

Bannière : `archboot.com | aarch64 | 7.2.0-2-aarch64-ARCH`, puis
`Welcome to Archboot - Arch Linux AARCH64`, puis `[root@archboot /] #`.

### Critère 2 — le réseau sort : **OK**, mais **`ping` ne fonctionne pas**

DHCP obtenu sans intervention, résolution DNS et trafic TCP/HTTP(S)
opérationnels :

```
enp0s1  UP  192.168.64.2/24   (+ IPv6)
default via 192.168.64.1 dev enp0s1 proto dhcp
getent hosts mirror.archlinuxarm.org  → 50.116.36.110
curl https://archlinux.org/           → http=200 ip=209.126.35.79
curl http://mirror.archlinuxarm.org/aarch64/core/core.db → http=302 (redirection normale)
```

En revanche `ping -c1 archlinux.org` **ne rend jamais la main** (tué par
`timeout`, rc=124) : le nom est bien résolu
(`PING archlinux.org (209.126.35.79)`) mais l'ICMP ne traverse pas le NAT
`vmnet-shared` de UTM. C'est une limite de l'hôte, pas d'archboot.

> **Pour Task 9** : ne jamais tester la connectivité avec `ping` dans cette VM —
> le script se bloquerait. Utiliser `curl`, `getent hosts` ou `pacman -Sy`.

### Critère 3 — pacman fonctionne : **OK**

```
/etc/pacman.d/mirrorlist : Server = http://mirror.archlinuxarm.org/$arch/$repo   (par défaut)

# pacman -Sy
:: Synchronizing package databases...
 core downloading...
 extra downloading...
 alarm downloading...
 aur downloading...
                                                        → rc=0

# pacman -Sl core | wc -l  → 311
```

### Critère 4 — outils d'installation présents ou installables : **OK**

| Outil | État |
|---|---|
| `pacstrap` | `/usr/bin/pacstrap` (arch-install-scripts 31-2) |
| `arch-chroot` | `/usr/bin/arch-chroot` |
| `genfstab` | `/usr/bin/genfstab` |
| `mkfs.btrfs` / `btrfs` | `/usr/bin/…` (btrfs-progs 7.1-1) |
| `mkfs.fat` | `/usr/bin/mkfs.fat` |
| `sgdisk` | **absent de l'ISO**, installé par `pacman -S --noconfirm gptfdisk` → GPT fdisk 1.0.10 |

Versions du live : `pacman 7.1.0.r9.g54d9411-2`, `btrfs-progs 7.1-1`,
`arch-install-scripts 31-2`, `gptfdisk 1.0.10-2`.

Le disque cible est adressable :

```
# sgdisk -p /dev/vda
Disk /dev/vda: 134217728 sectors, 64.0 GiB
```

---

## 7. Ce que Task 9 doit savoir

**Base = Arch Linux ARM, pas Arch vanille.** L'archboot aarch64 est bâti sur
Arch Linux ARM : `pacman.conf` déclare `[core] [extra] [alarm] [aur]` et les
miroirs sont ceux d'`archlinuxarm.org`. Conforme à la spec §4.2 (« miroirs
ALARM » pour la branche aarch64). Le dépôt `[aur]` d'ALARM ne compte que
12 paquets — ce n'est pas l'AUR.

**Un seul CPU dans l'environnement live, par conception.** Malgré les 4 cœurs
configurés côté UTM, l'invité n'en voit qu'un :

```
/proc/cmdline : BOOT_IMAGE=/boot/Image-aarch64.gz nr_cpus=1 console=ttyAMA0,115200 console=tty0 …
nproc → 1 ;  dmesg : "smp: Brought up 1 node, 1 CPU"
```

La cause est dans le GRUB d'archboot lui-même
(`/boot/grub/archboot-main-grub.cfg`) :

```
# kexec on aarch64 only allowed with nr_cpus=1!
_aarch64_options="nr_cpus=1"
```

C'est **volontaire et sans entrée de menu alternative** : archboot pilote son
environnement par `kexec`, qui n'est autorisé qu'à un CPU sur aarch64. Un
`pacstrap` dans cette VM sera donc mono-cœur. La restriction ne concerne que le
live : le système Eschaton installé démarrera avec ses 4 cœurs.

**Disposition disque vue par l'invité :**

```
sr0     462.1M rom          ISO archboot
zram0       6G disk  /      racine du live (en RAM)
vda        64G disk         disque cible de l'installation
```

RAM disponible dans le live : 3907 Mio au total, ~3247 Mio libres.

**Paquets Eschaton disponibles dans les dépôts ALARM :**

| Paquet | État |
|---|---|
| `snapper` | `extra/snapper 0.13.1-3` |
| `snap-pac` | `extra/snap-pac 3.0.1-3` |
| `limine` | `extra/limine 12.6.1-1` |
| `mkinitcpio` | `core/mkinitcpio 41.1-1` |
| `btrfs-progs` | `core/btrfs-progs 7.1-1` |
| `limine-snapper-sync` | **absent** de `core`/`extra`/`alarm`/`aur` |

L'absence de `limine-snapper-sync` **confirme le risque n°3 de la spec** (« absent
des dépôts Arch officiels ») et vaut aussi côté ALARM : il devra être packagé
dans le dépôt `[eschaton]`, comme prévu.

**L'environnement live est éphémère.** La racine est un zram : tout ce qui est
installé dans le live (`gptfdisk`, dépôt `[eschaton]` ajouté au `pacman.conf`…)
disparaît au redémarrage de la VM et doit être refait à chaque session. Seul
`/dev/vda` persiste.

**Démarrer sur Eschaton après l'installation** : rien à faire. Le disque porte
`bootindex=0` (§3.3), l'UEFI le tente en premier et ne retombe sur l'ISO que
tant qu'il n'est pas amorçable.

> Ne pas chercher à « éjecter » l'ISO en retirant `Drive.*.ImageName` du
> `config.plist` : UTM retombe alors sur le *bookmark* de `~/Downloads` et
> remonte la même ISO. L'éjection réelle passe par l'interface graphique de UTM
> (lecteur → *Eject*) — inutile ici grâce à l'ordre de démarrage.
