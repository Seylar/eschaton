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

### 5.3 Variante démon — nécessaire dès que la session dure

Le `vmrun.py` ci-dessus ouvre et referme le pty à chaque **exécution du
script**. Tant qu'on enchaîne les commandes d'un seul appel, c'est sans
conséquence ; mais un agent qui appelle le script une fois par commande retombe
exactement dans le SIGHUP décrit plus haut. La Task 9 a donc scindé le motif en
deux :

- un **démon** lancé une fois pour toute la session, qui garde le pty ouvert,
  écrit tout ce qui arrive dans `console.log` et poste sur la ligne les fichiers
  déposés dans `inbox/` ;
- un **client** sans état (`run` / `send` / `raw` / `wait` / `tail`) qui écrit
  dans `inbox/` et relit `console.log`.

Le journal cumulatif est un bénéfice à lui seul : les sorties longues
(`pacstrap`) restent relisibles après coup, et les barres de progression de
pacman — qui saturent n'importe quel `tail` — se filtrent hors bande
(`grep -Ev '\[#|\[-|B/s'`).

Deux points de cycle de vie du pty, tous deux vérifiés :

> **Un `reboot` de l'invité NE change PAS le pty.** QEMU ne redémarre que la
> machine virtuelle, pas son processus : le démon continue de fonctionner à
> travers les redémarrages, y compris d'archboot vers Eschaton. Seul un
> `utmctl stop` / `start` renumérote le pty — il faut alors le redétecter et
> relancer le démon.

> **Après un redémarrage, la console est sur une invite de connexion, pas sur un
> shell.** Envoyer des commandes à ce moment revient à les taper comme nom
> d'utilisateur : elles échouent en silence et le pilotage semble « muet ».
> Toujours vérifier ce qu'affiche la console (`tail`) avant de reprendre, et
> attendre un motif franc (`eschaton login:`, `[root@archboot`) plutôt qu'un
> délai fixe.

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

## 7. L'environnement live en pratique

*(Écrit pour préparer la Task 9 ; vérifié par elle. La procédure d'installation
elle-même est au §8.)*

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
live : le système Eschaton installé démarre bien avec ses 4 cœurs (vérifié,
§8.6).

> Mesuré depuis : le mono-cœur **ne coûte presque rien**. Le `pacstrap` complet
> prend 1 min 30 s, pas les 30 à 60 minutes qu'on craignait — voir §8.1.

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

---

## 8. Installation réelle d'Eschaton (procédure vérifiée)

Déroulée trois fois de bout en bout le 2026-08-28, entièrement par la console
série, sans jamais ouvrir l'interface de UTM. C'est la procédure qui valide la
définition de terminé §7.1 de la spec.

### 8.1 Durées réelles

Le plan tablait sur un `pacstrap` de 30 à 60 minutes à cause du CPU unique du
live env (§7). **La réalité est vingt fois plus rapide** — le mono-cœur ne pèse
presque rien : l'essentiel du temps part en téléchargement, et le reste est
dominé par les entrées/sorties.

| Étape | Durée |
|---|---|
| Démarrage de la VM → invite archboot | ~30 s |
| `pacman -Sy` + 4 outils d'installation | ~15 s |
| `eschaton-install` complet (231 paquets, 276 Mio téléchargés, 1,5 Gio installés) | **1 min 30 s** |
| `reboot` → invite de connexion Eschaton | ~18 s |
| **Total, VM éteinte → session ouverte** | **≈ 4 min** |

Prévoir large reste raisonnable (le débit du miroir n'est pas garanti), mais un
timeout de 10 minutes suffit très largement, et un pilotage qui abandonne au
bout de 2 minutes se trompe de diagnostic.

### 8.2 Déroulé

```bash
# 1. Depuis le Mac : démarrer, récupérer le pty, lancer le démon de console
UTMCTL=/Applications/UTM.app/Contents/MacOS/utmctl
$UTMCTL start eschaton-dev
$UTMCTL attach eschaton-dev          # affiche « PTTY: /dev/ttysNNN »
```

Attendre `Hit ENTER for login routine or CTRL-C for bash prompt.`, envoyer
**`Ctrl-C`** (octet `0x03`) → `[root@archboot /] #`. Puis, dans la VM :

```bash
stty cols 200 rows 60                # sinon les lignes longues sont repliées
pacman -Sy --noconfirm arch-install-scripts gptfdisk btrfs-progs dosfstools

cd /root
curl -fsSLO https://raw.githubusercontent.com/Seylar/eschaton/socle/installer/eschaton-install
curl -fsSLO https://raw.githubusercontent.com/Seylar/eschaton/socle/installer/lib.sh
chmod +x eschaton-install
sha256sum eschaton-install lib.sh    # à comparer au dépôt : raw.githubusercontent met en cache

./eschaton-install --disk /dev/vda --user seylar
#   → deux invites `passwd` : saisir le mot de passe, puis le confirmer
umount -R /mnt && reboot
```

Le `pacman -Sy` du live passe **sans `--disable-sandbox`** : le bac à sable
Landlock ne pose problème que dans les conteneurs Docker de la CI, pas ici.

Rien à faire au redémarrage : le disque porte `bootindex=0` (§3.3) et Limine
démarre tout seul (`default_entry`, §8.4).

> **Mot de passe de la VM de dev : `eschaton`** (compte `seylar`, également
> demandé par `sudo`). C'est une VM locale jetable — **à changer** dès que cette
> image sert à autre chose qu'au développement.

### 8.3 Réinstaller par-dessus

Une fois le disque amorçable, l'UEFI ne retombe plus sur l'ISO. Inutile de
toucher à la configuration de UTM : il suffit de rendre le disque non amorçable
depuis Eschaton, puis de redémarrer.

```bash
sudo rm -rf /boot/EFI && sudo reboot   # → l'UEFI retombe sur archboot
```

Le `sgdisk --zap-all` que l'installeur exécute en première étape efface ensuite
le reste. (Ne pas essayer de zapper la table des partitions depuis le système
qui tourne dessus : l'arrêt propre n'a plus de disque où écrire.)

### 8.4 Écarts trouvés et corrigés

Quatre défauts, **tous silencieux** : le système démarrait et se disait en bon
état dans chaque cas. Aucun n'était visible en `--dry-run`, aucun n'aurait été
trouvé sans installation réelle. Corrigés dans le dépôt (installeur, PKGBUILD),
puis revalidés par une réinstallation complète.

| # | Symptôme | Cause | Correctif |
|---|---|---|---|
| 1 | 1re mise à jour : « signature … de confiance inconnue » | `base` ne tire qu'`archlinux-keyring` ; les clés ALARM n'ont jamais été signées dans la cible | `keyring_pkgs_for()` + `pacman-key --populate` dans le chroot |
| 2 | Identité perdue à la 1re mise à jour de `filesystem` | `/etc/os-release` est un lien : le `cp` écrasait `/usr/lib/os-release` | `rm -f` avant le `cp` |
| 3 | **Aucune entrée de snapshot, jamais** | `limine.conf` plat : limine-snapper-sync exige `//<kernel>` sous `/<OS>` | structure imbriquée + ancre `//Snapshots` |
| 4 | Le veilleur de snapshots meurt à 54 ms | `inotify-tools` n'est qu'un *optdepend* de limine-snapper-sync | dépendance de `eschaton-base` |

Le correctif n°3 en a appelé un cinquième, trouvé au redémarrage suivant :
une entrée de premier niveau qui contient des sous-entrées **n'est plus
amorçable**, c'est un sous-menu. Limine restait donc sur son menu à l'expiration
du `timeout`, et la VM ne démarrait plus du tout. D'où
`default_entry: Eschaton/<kernel>` — désigné par son **chemin** et non par un
index, puisque limine-snapper-sync insère des entrées qui décaleraient toute
numérotation. Vérifié : la ligne survit aux réécritures de l'outil.

> La leçon générale : sur ce socle, **une panne se signale rarement**. Un
> système qui démarre, dont aucune unité n'est en échec et dont
> `eschaton-update` rend 0, peut être privé de tout son filet de sécurité. Les
> vérifications qui comptent sont celles qui exercent la mécanique — installer
> un paquet, créer un snapshot — pas celles qui lisent un état.

### 8.5 Pièges de vérification

- **`findmnt` n'accepte qu'une seule cible.** `findmnt -no TARGET,OPTIONS / /home
  …` rend une sortie **vide** et `rc=1` — ce qui ressemble beaucoup à « les
  montages sont absents ». Boucler sur les points de montage, ou utiliser
  `findmnt -nrt btrfs -o TARGET,SOURCE`.
- **Ne jamais utiliser `ping`** (§6, critère 2) : l'ICMP ne traverse pas le NAT
  `vmnet-shared`. `curl -fsI https://archlinux.org` est le test qui fait foi.
- **`hostname` n'existe pas** sur une base Arch moderne (`inetutils` n'est pas
  dans `base`) : utiliser `hostnamectl`.
- **`fatal library error, lookup self`** pendant le `pacstrap` : c'est snap-pac
  qui tente un snapshot post-transaction dans le chroot. Sans conséquence, le
  système installé prend ses snapshots normalement.
- **`sd-vconsole: "/etc/vconsole.conf" not found`** pendant le `pacstrap` :
  l'initramfs est généré avant que l'installeur n'écrive le fichier. Sans
  conséquence pratique (systemd applique la disposition au démarrage), et corrigé
  de lui-même à la première régénération de l'initramfs.

### 8.6 État vérifié du système installé

Tout ce qui suit a été lu sur la console de la VM, sur l'installation finale :

```
ID=eschaton                              /etc/os-release (fichier, plus un lien)
curl -fsI https://archlinux.org          → NET_OK      (enp0s1, 192.168.64.x)
lsblk -no SIZE,FSTYPE /dev/vda1          → 4G vfat     (ESP, spec §4.3)
5 subvolumes  @ @home @log @pkg @snapshots  montés, compress=zstd:1,noatime
swapon --show                            → /dev/zram0 seul, 1,9 Gio, aucune partition
NetworkManager sshd fstrim.timer limine-snapper-sync snapper-cleanup.timer → enabled
limine-snapper-sync.service              → active (le veilleur tourne)
systemctl --failed                       → vide
TARGET_OS_NAME="Eschaton"                = nom de l'entrée /Eschaton (invariant §4.2)
grep -c '^/' /boot/limine.conf           → 1  (aucun doublon d'entrée)
nproc                                    → 4  (le live env est le seul bridé à 1)
motd « Bienvenue sur Eschaton »          affiché à l'ouverture de session
eschaton-update                          → rc=0, les 5 dépôts se synchronisent
pacman -S tree                           → snapshots snapper 1 (pre) / 2 (post)
                                           puis entrées de démarrage générées
                                           automatiquement sous //Snapshots
```

La réserve de la Task 7 sur un éventuel doublon d'entrée « Eschaton » **ne se
pose pas sur aarch64** : `limine-update` (limine-entry-tool) s'y arrête sur
« The system is not x86_64 » et ne génère donc jamais rien. `limine.conf` y a une
seule source, l'installeur. La réserve reste entière côté x86_64, où l'outil
fonctionne — c'est à la Task 11 de la lever.

---

## 9. Test de casse et rollback (spec §7.2)

Déroulé le 2026-08-28 sur l'installation du §8, **sans jamais la réinstaller**,
entièrement par la console série. C'est le test qui valide la définition de
terminé §7.2 : sabotage réel, restauration par snapshot, et démarrage sur un
snapshot depuis Limine.

Il a trouvé **quatre défauts**, dont un bloquant : `eschaton-rollback` ne
fonctionnait pas du tout. Rien dans l'état du système ne le laissait présager —
aucune unité en échec, aucun avertissement, `eschaton-update` rendait 0. Il a
fallu casser pour de vrai.

### 9.1 Durées réelles

| Étape | Durée |
|---|---|
| Ouverture de session série (login + mot de passe) | ~5 s |
| `snapper create` d'un snapshot manuel | < 1 s |
| Remplacement du sous-volume par `eschaton-rollback` | ~2 s |
| `reboot` → invite de connexion | **~19 s** (mesuré trois fois) |
| `eschaton-update` d'un seul petit paquet, hooks snapper compris | ~25 s |

Le cycle complet « je casse, je restaure, je vérifie » tient en **moins de deux
minutes**. Trois redémarrages ont été nécessaires en tout.

### 9.2 Pilotage : `tools/vm-serial`

Le motif démon/client du §5.3 vit maintenant dans le dépôt
(`tools/vm-serial`). Une session type :

```bash
UTMCTL=/Applications/UTM.app/Contents/MacOS/utmctl
$UTMCTL attach eschaton-dev                     # → PTTY: /dev/ttysNNN
W=/tmp/eschaton-console && mkdir -p "$W"
nohup tools/vm-serial daemon /dev/ttysNNN "$W" &

export VM_SERIAL_WORK=$W
tools/vm-serial send "seylar"                   # invite de connexion
tools/vm-serial send "eschaton"                 # « Mot de passe : »
tools/vm-serial run "stty cols 200 rows 60"     # sinon les lignes se replient
```

> **`sudo` redemande le mot de passe, et ce n'est pas scriptable en une
> commande.** Le motif qui marche : `send "sudo -v"` puis `send "eschaton"` une
> fois, ensuite `run "sudo -n …"` tant que l'horodatage est valide. **Le cache
> est perdu à chaque redémarrage** — le refaire après chaque `reboot`. Sans
> `-n`, un cache expiré transforme la commande suivante en invite de mot de
> passe silencieuse et le pilotage se désynchronise.

### 9.3 Étape 1 — le sabotage

```console
$ sudo snapper --config root create --description 'avant-sabotage'
3 │ single │ │ ven. 28 août 2026 01:41:52 │ root │ │ avant-sabotage │

$ findmnt -no OPTIONS / | tr ',' '\n' | grep subvol
subvolid=256
subvol=/@

$ sudo rm /usr/bin/ls
$ ls / || echo SABOTAGE_EFFECTIF
-bash: /usr/bin/ls: Aucun fichier ou dossier de ce nom
SABOTAGE_EFFECTIF

$ sudo pacman -Qkk coreutils
avertissement : coreutils: /usr/bin/ls (Aucun fichier ou dossier de ce nom)
coreutils : 444 fichiers au total, 1 fichier modifié
```

Le veilleur avait déjà généré l'entrée de démarrage du snapshot 3 sans qu'on lui
demande quoi que ce soit (`comment: 3 snapshots` dans `limine.conf`).

### 9.4 Étape 2 — le rollback, et le défaut qu'il a révélé

**`snapper rollback` ne fonctionne pas sur la disposition d'Eschaton.** La spec
§6 le nommait ; la réalité le refuse :

```console
Numéro du snapshot vers lequel revenir (vide pour annuler) : 3
Impossible de détecter le contexte car le sous-volume par défaut est inconnu.
Cela peut arriver si le système n'a pas été configuré pour le retour à l'état initial.
Le contexte peut être spécifié manuellement à l'aide de l'option --ambit.

$ LANG=C sudo snapper --config root rollback 3 2>&1; echo rc=$?
Cannot detect ambit since default subvolume is unknown.
This can happen if the system was not set up for rollback.
The ambit can be specified manually using the --ambit option.
rc=1
```

La cause tient en deux lignes :

```console
$ sudo btrfs subvolume get-default /
ID 5 (FS_TREE)
$ cat /proc/cmdline
root=LABEL=eschaton rootflags=subvol=@ rw quiet
```

`snapper rollback` suppose la disposition openSUSE — le système tourne sur le
sous-volume **par défaut** de btrfs, et restaurer consiste à en désigner un
autre. Eschaton suit la disposition Arch : la racine est épinglée par
`rootflags=subvol=@` et le sous-volume par défaut est resté `FS_TREE`. Forcer
`--ambit classic` n'aurait rien sauvé : la commande aurait changé le sous-volume
par défaut, **dont le démarrage ne tient aucun compte**. On aurait obtenu un
rollback qui rend 0 et ne restaure rien — la panne muette du §8.4, encore.

Le README de `limine-snapper-sync` le dit d'ailleurs noir sur blanc : la méthode
`opensuse` « requires an OpenSUSE-style layout », et la recommandation pour les
installations Arch est `replace` ou `rsync`.

`eschaton-rollback` applique donc désormais **`replace`** : le sous-volume `@`
est renommé de côté, puis recréé comme instantané inscriptible du snapshot
choisi. Le **nom** `@` ne bouge pas — ni la ligne de commande du kernel, ni
`fstab`, ni `limine.conf` n'ont à être réécrits.

```console
==> Restauration du snapshot 3 dans le sous-volume « @ » de /dev/vda2.
    L'état actuel n'est pas détruit : il est mis de côté sous « @.avant-rollback-20260828-014936 ».
Confirmer ? [oui/N] oui
Create snapshot of '/run/eschaton-rollback.dPvCcp/@snapshots/3/snapshot' in '/run/eschaton-rollback.dPvCcp/@'
Saved: /boot/d30aa44e2b314902a0b5f864dac156f3/limine_history/snapshots.json
Updated: /boot/limine.conf
==> Rollback appliqué. Redémarre pour démarrer sur l'état restauré (sudo reboot).
```

**Avant / après**, sur le même disque et le même nom de sous-volume :

```console
# avant le rollback
/dev/vda2[/@]  …,subvolid=256,subvol=/@

# après le rollback, AVANT redémarrage — le renommage est visible à chaud
/dev/vda2[/@.avant-rollback-20260828-014936]  …,subvolid=256,subvol=/@.avant-rollback-20260828-014936

# après redémarrage
/dev/vda2[/@]  …,subvolid=266,subvol=/@
```

Le **numéro** de sous-volume change (256 → 266), le **nom** non. C'est la
signature de la méthode `replace`.

```console
$ ls / && echo ROLLBACK_OK
bin  boot  dev  etc  home  lib  mnt  opt  proc  root  run  sbin  srv  sys  tmp  usr  var
ROLLBACK_OK

$ sudo pacman -Qkk coreutils
coreutils : 444 fichiers au total, 0 fichier modifié
$ systemctl --failed --no-legend
(vide)
```

> **Renommer un sous-volume monté est licite en btrfs.** Seul son nom dans
> l'arbre racine change ; le système qui tourne dessus continue sans rien
> remarquer — `findmnt` reflète le nouveau nom à chaud, comme ci-dessus.

### 9.5 Étape 3 — démarrer sur un snapshot, sans toucher au menu

**Le menu Limine s'affiche sur la console série** — contrairement à ce qu'on
croyait. Le menu et son compte à rebours arrivent bien sur `ttyAMA0`, à chaque
démarrage :

```
Limine 12.6.1 (aarch64, UEFI)
[-] Eschaton
 |--> linux-aarch64
 `[+] Snapshots
ARROWS Select  ENTER Boot  E Edit  S Firmware Setup  B Blank Entry
Booting automatically in 3...
```

La navigation au clavier est donc possible. Elle reste néanmoins **le mauvais
outil pour un test scripté** : trois secondes de `timeout`, des touches à
envoyer à l'aveugle, aucun moyen de vérifier ce qui est sélectionné avant de
valider. La méthode déterministe consiste à **piloter `default_entry`**.

```bash
# 1. lire le nom exact de l'entrée de snapshot générée par limine-snapper-sync
entry=$(grep -m1 -E "^ +///" /boot/limine.conf | sed "s|^ *///||")
#    → 3 │ 2026-08-28 01:41:52          (le séparateur est U+2502, pas un pipe)

# 2. sauvegarder la valeur d'origine HORS de l'ESP (limine-snapper-sync y écrit)
cp /boot/limine.conf ~/limine.conf.avant-t10

# 3. viser l'entrée de snapshot, par son chemin complet
sudo sed -i "s|^default_entry:.*|default_entry: Eschaton/Snapshots/$entry/linux-aarch64|" /boot/limine.conf
sudo reboot
```

Limine suit le chemin sans broncher — espaces et caractère semi-graphique
compris — déplie le sous-menu et démarre l'entrée :

```
`[-] Snapshots
 |[-] 3 ? 2026-08-28 01:41:52
 | `--> linux-aarch64
linux: Loading kernel `boot():/…/limine_history/Image_sha256_f65ff2e7…`...
[FAILED] Failed to listen on GnuPG network …ent daemon for /etc/pacman.d/gnupg.
      (5 autres sockets GnuPG, même cause)
eschaton login:
```

Le système démarre **sur le snapshot**, en lecture seule :

```console
$ findmnt -no SOURCE,OPTIONS /
/dev/vda2[/@snapshots/3/snapshot] rw,noatime,…,subvolid=265,subvol=/@snapshots/3/snapshot

$ cat /proc/cmdline
root=LABEL=eschaton rootflags=subvol=/@snapshots/3/snapshot rw quiet

$ sudo btrfs property get -ts /
ro=true

$ touch /ecriture-test
touch: impossible de faire un touch '/ecriture-test': Système de fichiers accessible en lecture seulement
```

> **Piège de vérification : `findmnt` affiche `rw` sur un snapshot en lecture
> seule.** La ligne de commande du kernel demande `rw`, le noyau l'inscrit dans
> les options de montage — mais le sous-volume porte le drapeau `ro` de btrfs et
> toute écriture échoue. Ne pas conclure « la racine est inscriptible » depuis
> `findmnt` : la preuve, c'est `btrfs property get -ts /` ou une tentative
> d'écriture.

Les **six unités socket GnuPG en échec** sont la conséquence attendue de la
racine en lecture seule (elles créent des sockets sous `/etc/pacman.d/gnupg`).
Aucune ne gêne le travail de récupération.

**L'ESP reste inscriptible depuis le snapshot** — c'est ce qui rend la
récupération possible :

```console
$ findmnt -no SOURCE,OPTIONS /boot
/dev/vda1 rw,relatime,fmask=0022,…
$ sudo sed -i "s|^default_entry:.*|default_entry: Eschaton/linux-aarch64|" /boot/limine.conf
$ sha256sum /boot/limine.conf ~/limine.conf.avant-t10
c36d72750db81b683115bb0acce6a487832039787f6962be7738d743935e6aae  /boot/limine.conf
c36d72750db81b683115bb0acce6a487832039787f6962be7738d743935e6aae  /home/seylar/limine.conf.avant-t10
```

Retour nominal au redémarrage suivant :

```console
$ findmnt -no SOURCE,OPTIONS /
/dev/vda2[/@] rw,noatime,…,subvolid=266,subvol=/@
$ cat /proc/cmdline
root=LABEL=eschaton rootflags=subvol=@ rw quiet
$ ls /usr/bin/ls && echo NOMINAL_OK
/usr/bin/ls
NOMINAL_OK
$ systemctl --failed --no-legend
(vide)
```

> **`default_entry` survit aux réécritures de limine-snapper-sync.** L'outil a
> réécrit `limine.conf` deux fois pendant le test (une fois pendant le rollback,
> une fois au redémarrage suivant) sans jamais toucher à la ligne, y compris
> quand elle pointait sur une entrée de snapshot. Le service se déclenche sur
> événement — création ou suppression de snapshot —, pas en continu : entre deux
> transactions pacman, la fenêtre est grande ouverte.

> **La restauration « depuis le snapshot » est l'affaire de l'amont.** Une fois
> démarré sur un snapshot, `limine-snapper-restore` (paquet limine-snapper-sync)
> rend l'état permanent — c'est le second chemin de la spec §6.
> `limine-snapper-sync --restore` ne prend **aucun numéro** : il restaure le
> snapshot sur lequel on a démarré, et rien d'autre. D'où deux outils bien
> distincts : `eschaton-rollback` depuis le système qui marche,
> `limine-snapper-restore` depuis le snapshot quand il ne marche plus.

### 9.6 Rétention (constat, sans rien forcer)

```console
$ grep -E 'NUMBER|TIMELINE' /etc/snapper/configs/root
TIMELINE_CREATE="no"
NUMBER_CLEANUP="yes"
NUMBER_MIN_AGE="1800"
NUMBER_LIMIT="10"
NUMBER_LIMIT_IMPORTANT="5"
```

Après le test : **deux paires pre/post automatiques** (1-2, 4-5) et un snapshot
manuel (3). On est loin des 10 paires de `NUMBER_LIMIT` — `snapper-cleanup` n'a
donc encore rien eu à tailler, et le comportement de la borne reste à observer
sur une VM plus ancienne. L'ESP tient largement : `255 Mo utilisés sur 4,0 Go`
(7 %) avec 5 snapshots, parce que limine-snapper-sync déduplique les kernels par
empreinte (`Image_sha256_…`) — les 5 entrées partagent le même fichier de 44 Mo.

### 9.7 Les trois autres défauts

Les deux premiers découverts en **exécutant** ce que le socle affiche, pas en le
lisant ; le troisième en relisant le correctif.

| # | Symptôme | Cause | Correctif |
|---|---|---|---|
| 1 | `eschaton-rollback` refuse tout : « Cannot detect ambit… » | `snapper rollback` exige la disposition openSUSE | méthode `replace` dans `eschaton-rollback` |
| 2 | `avertissement : les permissions pour /etc/sudoers.d/ sont différentes` à chaque transaction | `install -D` crée le parent en 755, `sudo` le livre en 750 | `install -d -m750` dans le PKGBUILD |
| 3 | Le nettoyage indiqué en fin de rollback échoue | `btrfs subvolume delete` n'est pas récursif | `--recursive` dans le message |
| 4 | `eschaton-rollback` lancé depuis un snapshot démarré abîmerait le magasin | la racine est alors `@snapshots/<N>/snapshot` | garde + renvoi vers `limine-snapper-restore` |

Le n°2 mérite un mot : ce n'est qu'un avertissement, mais il rend
`pacman -Qkk eschaton-base` bruyant **pour toujours** (« 1 fichier modifié »).
Un contrôle d'intégrité qui crie en permanence est un contrôle qu'on cesse de
lire — c'est ainsi qu'une vraie altération passe inaperçue.

Le n°3 se lit bien :

```console
$ sudo btrfs subvolume delete /mnt/@.avant-rollback-20260828-014936
Delete subvolume 256 (no-commit): '/mnt/@.avant-rollback-20260828-014936'
ERROR: Could not destroy subvolume/snapshot: Directory not empty

$ sudo btrfs subvolume delete --recursive /mnt/@.avant-rollback-20260828-014936
Delete subvolume 261 (no-commit): '…/var/lib/portables'
Delete subvolume 262 (no-commit): '…/var/lib/machines'
Delete subvolume 256 (no-commit): '…/@.avant-rollback-20260828-014936'
```

systemd crée `var/lib/machines` et `var/lib/portables` comme sous-volumes
imbriqués. Corollaire à connaître : **la racine restaurée ne les a plus comme
sous-volumes**, seulement comme répertoires ordinaires — `btrfs subvolume
snapshot` ne descend pas dans les sous-volumes imbriqués. Sans conséquence
pratique (systemd les recrée au besoin), et `snapper rollback` se comporte
pareil.

Un quatrième défaut a été trouvé **en relisant le correctif**, pas en
l'exécutant — et son scénario est précisément celui de la spec §6 : le système
ne démarre plus, on démarre une entrée « Snapshots », et on lance là le premier
outil de restauration qui vient. La racine étant alors `@snapshots/<N>/snapshot`,
`eschaton-rollback` aurait renommé **ce** sous-volume et créé un snapshot neuf à
sa place : magasin de snapshots abîmé, et `@` — le seul à réparer — intact.
L'outil détecte désormais le cas et renvoie vers `limine-snapper-restore`.

### 9.8 Vérification de bout en bout du correctif

Le correctif a été livré **par le dépôt**, pas posé à la main dans la VM : après
CI verte, `eschaton-update` l'a installé et les empreintes concordent avec les
fichiers du dépôt.

```console
$ eschaton-update --noconfirm
Paquets (1) eschaton-base-0.1.0-7
(1/2) Performing snapper pre snapshots…   ==> root: 4
(2/2) Waiting for limine-snapper-sync to finish...
(2/2) Performing snapper post snapshots…  ==> root: 5

$ sha256sum /usr/bin/eschaton-rollback
3bce78f0253f86acd6c81defcf30b3d570ec6ed4594b3ecd042f98b9c510a362   # = celui du dépôt
```

Le filet fonctionne toujours après le rollback : la transaction a produit ses
deux snapshots, et `limine.conf` porte les cinq entrées correspondantes.

Même chemin pour la version portant les quatre correctifs — et c'est la
disparition de l'avertissement qui signe le n°2 :

```console
$ eschaton-update --noconfirm
Paquets (1) eschaton-base-0.1.0-10
(1/2) Performing snapper pre snapshots…   ==> root: 6
(2/2) Performing snapper post snapshots…  ==> root: 7
        (plus aucun avertissement sur /etc/sudoers.d)

$ pacman -Q eschaton-base
eschaton-base 0.1.0-10
$ sudo pacman -Qkk eschaton-base
eschaton-base : 26 fichiers au total, 0 fichier modifié
$ stat -c "%a %n" /etc/sudoers.d
750 /etc/sudoers.d
$ sha256sum /usr/bin/eschaton-rollback /usr/lib/eschaton/lib.sh
60f43921ce32247f19a384ab97cda4acf3658db30220216df85b2c91c18d0d88  /usr/bin/eschaton-rollback
9719cdb16d60ee69fa6f881f9aba9d3d7c837b502238b73d20c980176e93055a  /usr/lib/eschaton/lib.sh
```

Empreintes identiques aux fichiers du dépôt.

### 9.9 État de la VM à la fin du test

Elle reste l'installation de référence de la Task 9 : jamais réinstallée, et
rendue propre.

```console
$ findmnt -no SOURCE,OPTIONS /
/dev/vda2[/@] rw,noatime,…,subvolid=266,subvol=/@
$ sudo btrfs subvolume list / | grep -v "snapshots/"
ID 257 … @home     ID 258 … @log     ID 259 … @pkg
ID 260 … @snapshots                  ID 266 … @
$ grep -n "^default_entry" /boot/limine.conf
2:default_entry: Eschaton/linux-aarch64
$ df -h /boot | tail -1
/dev/vda1          4,0G    255M  3,8G   7% /boot
$ systemctl --failed --no-legend
(vide)
```

Aucun sous-volume `@.avant-rollback-*` résiduel, 7 snapshots et leurs 7 entrées
de démarrage, `default_entry` sur l'entrée nominale.

> **Le seul écart avec l'installation d'origine** : la racine est le
> sous-volume 266 et non plus 256, et `/var/lib/machines` comme
> `/var/lib/portables` y sont des répertoires ordinaires. C'est la trace normale
> d'un rollback par `replace`, pas un dommage.
