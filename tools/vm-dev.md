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
| `…-latest-aarch64.iso` | 2300 Mo | serveur DHCP local requis | oui, mais seulement si la VM a ≥ 3200 Mo de RAM |
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
curl -fsSLO https://raw.githubusercontent.com/Seylar/eschaton/main/installer/eschaton-install
curl -fsSLO https://raw.githubusercontent.com/Seylar/eschaton/main/installer/lib.sh
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

**Codes de sortie** (durcissement du 2026-08-28, avant que le Bureau n'en
dépende) : `run` rend **le code de retour de la commande dans la VM**, `wait`
rend 0 si le motif est vu ; `124` = délai dépassé, `125` = dialogue série cassé
(marqueur de fin vu, rc illisible), `2` = usage. Une commande qui échoue dans la
VM fait donc échouer le client — enchaîner sous `set -e` devient sûr.

**Fin de ligne** : quand le pty raccroche (`utmctl stop`, arrêt de la VM), le
démon le journalise et **s'arrête de lui-même** après `VM_SERIAL_EOF_GRACE`
secondes (10 par défaut). Avant ce correctif il tournait à **100 % de CPU
indéfiniment et sans un mot** (mesuré : 4,98 s de CPU en 5 s). Voir le message
`[vm-serial] EOF confirmé …` dans `console.log` : il faut alors redétecter le
pty (`utmctl attach`) et relancer le démon.

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

### 9.10 Reste à prouver : le rollback à travers un changement de kernel

**À exécuter à la première mise à jour de kernel ALARM.** C'est le seul morceau
du filet que la Task 10 n'a pas pu exercer : les snapshots 1 à 7 partagent tous
le même `Image_sha256_f65ff2e7…`, donc l'appel à
`limine-snapper-sync --restore-kernels` a bien réussi mais **n'a eu aucun
fichier à remettre en place**. Or c'est précisément le cas pour lequel cet appel
existe.

Le contrat de la commande a été vérifié **statiquement** le 2026-08-28, sur les
sources du tag 1.31.0 que `packages/vendor/limine-snapper-sync/PKGBUILD`
construit (`#tag=${pkgver}`) — le détail et les références de lignes sont en
commentaire dans `packages/eschaton-base/eschaton-rollback`, à l'appel. Résumé :
l'argument est lu, exigé entier et présent dans `snapshots.json`, et il
sélectionne bien les kernels recopiés depuis `limine_history/` vers `/boot` ;
sans argument la commande s'arrête sur une erreur explicite. La preuve
dynamique, elle, reste due.

Le protocole, quand un nouveau kernel arrivera :

```bash
uname -r                                  # noter la version AVANT
sudo eschaton-update                      # snapshots pre/post encadrent la MAJ
sudo reboot && uname -r                   # nouvelle version, nouveau Image_sha256_
eschaton-rollback                         # revenir au snapshot « pre »
sudo reboot
```

Ce qu'il faut alors constater, et qui n'a **pas** encore été vu :

- `uname -r` rend de nouveau l'ancienne version ;
- `/boot/Image` a repris l'empreinte de l'ancien kernel (deux
  `Image_sha256_…` distincts existent désormais dans `limine_history/`) ;
- `ls /usr/lib/modules/$(uname -r)` existe — c'est le test qui compte : kernel
  et modules de nouveau d'accord, ce qui est tout l'objet de l'appel ;
- aucune unité en échec.

---

## 10. Smoke test x86_64 émulé — VM `eschaton-x86-smoke` (spec §7.3)

Déroulé le 2026-08-28. C'est le critère n° 3 de la spec §7 : **le même
`eschaton-install`, sans une ligne de modification, produit un système x86_64
qui démarre.** Il est passé — et il a répondu à la réserve que la Task 9 avait
laissée ouverte sur `limine-entry-tool` (§8.6), qui ne s'exerce que sur x86_64.

**Résultat : aucun défaut trouvé.** Contrairement aux Tasks 9 et 10, ce test n'a
produit aucun correctif au dépôt. Tout ce qui suit décrit donc l'outillage
(la VM) et les constats, pas des réparations.

### 10.1 Ce que le x86_64 change, en une table

| | aarch64 `eschaton-dev` (§1-§9) | x86_64 `eschaton-x86-smoke` |
|---|---|---|
| Backend | QEMU + HVF (`hypervisor:true`) | QEMU **TCG**, `hypervisor:false` — émulation |
| Machine | `virt` | `q35` |
| ISO | archboot 462 Mio | Arch officielle 1,5 Gio |
| CPU dans le live env | **1** (`nr_cpus=1` imposé par archboot) | **4**, aucune bride |
| `sgdisk` dans le live env | absent, à installer | **présent** |
| Console série du live env | gratuite (`console=ttyAMA0` dans l'ISO) | **à ajouter soi-même** (§10.3) |
| Console série du système installé | gratuite (sur `virt`, la console noyau par défaut *est* l'UART) | **à ajouter soi-même** (§10.3) |
| Menu du bootloader sur la série | oui (Limine passe par la console UEFI) | **non** (Limine écrit sur la console VGA) |
| `limine-update` (limine-entry-tool) | s'arrête sur « The system is not x86_64 » | **s'exécute** (§10.6) |
| Microcode | sans objet | `intel-ucode` seul, détecté (§10.5) |

### 10.2 ISO et création de la VM

**ISO Arch officielle**, somme vérifiée contre celle publiée par archlinux.org
elle-même (page `/download/`), pas seulement contre le `sha256sums.txt` du
miroir :

| | |
|---|---|
| Fichier | `archlinux-2026.08.01-x86_64.iso` |
| Taille | 1 597 014 016 octets (1,49 Gio) |
| SHA-256 | `4e82dced1c4fd3e498b22a853f8db2a4d262d32b97e7e07d97390d9e425ffe5e` |
| Téléchargement | 43 s (~35 Mo/s) depuis `geo.mirror.pkgbuild.com` |

```bash
curl -fL -C - --retry 3 -o ~/Downloads/archlinux-2026.08.01-x86_64.iso \
  https://geo.mirror.pkgbuild.com/iso/2026.08.01/archlinux-2026.08.01-x86_64.iso
shasum -a 256 ~/Downloads/archlinux-2026.08.01-x86_64.iso   # = la valeur ci-dessus
```

**Création — tout se pose à la création, il n'y a pas d'équivalent du §3.3.**

```applescript
tell application "UTM"
	set isoPath to POSIX file "/Users/<vous>/Downloads/archlinux-2026.08.01-x86_64-serial.iso"
	set vm to make new virtual machine with properties {backend:qemu, configuration:{name:"eschaton-x86-smoke", architecture:"x86_64", machine:"q35", memory:4096, cpu cores:4, hypervisor:false, uefi:true, drives:{{removable:false, interface:VirtIO, guest size:40960}, {removable:true, interface:IDE, source:isoPath}}, network interfaces:{{mode:shared, hardware:"virtio-net-pci"}}, displays:{{hardware:"virtio-vga"}}, «class SrPt»:{{interface:ptty}}}}
	return id of vm
end tell
```

> **`isoPath` désigne la copie PATCHÉE de l'ISO (§10.3 a), pas l'originale — et
> la VM en dépend durablement.** UTM ne recopie pas l'image dans le bundle : il
> range le `source:` sous forme de *security-scoped bookmark* vers ce chemin
> exact (§3.2). Le fichier
> `~/Downloads/archlinux-2026.08.01-x86_64-serial.iso` doit donc **rester en
> place** aussi longtemps que la VM existe : un nettoyage du dossier
> `Downloads` casse le lecteur CD **en silence** — le `config.plist` n'affiche
> aucun chemin, et la panne ne se voit qu'au démarrage suivant, quand l'UEFI ne
> trouve plus de média amorçable. Contrairement à la VM aarch64, on ne peut pas
> s'en affranchir par l'astuce du §3.3 (copier l'ISO dans le bundle et poser
> `ImageName`) : cette astuce passe par le `config.plist`, que UTM ignore quand
> il tourne. Pour rendre la VM autonome, il faut la recréer (§10.4).

Quatre écarts avec la recette aarch64 du §3.1, tous nécessaires :

1. **`hypervisor:false`** — HVF n'accélère que l'architecture de l'hôte. Sur
   Apple Silicon, un invité x86_64 est *émulé* (TCG).
2. **Le disque est le PREMIER de la liste `drives`.** L'ordre de la liste donne
   le `bootindex` : disque en tête ⇒ `bootindex=0` dès la création, et la
   chirurgie du `config.plist` du §3.3 devient inutile. L'UEFI tente le disque,
   retombe sur le CD tant qu'il n'est pas amorçable.
3. **CD sur `IDE`, surtout pas `USB`.** Avec le lecteur en USB (le choix du
   §3.1), le firmware n'arrive pas à lire l'ISO en émulation et abandonne :
   ```
   ../systemd/src/boot/boot.c:2999@call_image_start: Error opening root path: Time out
   BdsDxe: failed to start Boot0001 "UEFI QEMU QEMU USB HARDDRIVE …": Time out
   ```
   Le menu de systemd-boot s'affiche, le compte à rebours va à son terme, puis
   le chargement du kernel expire et l'UEFI tombe dans son shell interne. Sur
   `q35`, `IDE` est câblé sur le contrôleur AHCI — l'ISO apparaît alors en
   `Boot0001 … /Sata(0,65535,0)` et se lit sans peine.
4. **`hardware:"virtio-net-pci"`** — UTM pose `e1000` par défaut sur x86_64.
   Émulé, il est nettement plus lent, et `pacstrap` est dominé par le réseau.

> **Le `config.plist` n'est PAS la source de vérité quand UTM tourne.** Éditer
> le fichier puis lancer la VM ne change rien : `utmctl start` démarre depuis la
> configuration **en mémoire** de UTM. La recette du §3.3 ne fonctionne que
> parce qu'elle quitte UTM d'abord. Ici on ne le peut pas (cela arrêterait
> `eschaton-dev`) — d'où le choix de tout poser à la création.

> **`update configuration … with {displays:{}}` fait planter UTM 4.7.5**
> (`EXC_BREAKPOINT` au démarrage suivant, piège Swift sur une liste vide), et le
> plantage emporte **toutes les VM en cours**. Ne pas vider la liste des écrans ;
> pour changer de configuration, supprimer et recréer la VM (§10.4).

> **`update configuration` ne réordonne pas les lecteurs.** Il les apparie par
> `id` et conserve leurs positions ; l'ordre de démarrage est figé à la
> création. Il *perd* en revanche la source du CD (`ImageName` retombe à
> `None`). Le §3.2 disait déjà de s'en méfier : c'est confirmé.

**Suite : l'installation elle-même.** Elle suit la procédure du §8.2 sans rien
changer à l'installeur ; ses ajustements x86_64 sont au **§10.3 c**, après la
console série du §10.3 — qui en est le préalable, puisque sans elle rien n'est
pilotable.

### 10.3 Le vrai piège : il n'y a pas de console série sur x86

C'est le point qui coûte le plus cher si on l'ignore, et il n'a **aucun
équivalent côté aarch64**, où tout arrive gratuitement sur `ttyAMA0`.

Sur `q35`, la console par défaut du noyau est `tty0` (l'écran). Sans
`console=ttyS0` sur la ligne de commande, **rien** ne sort sur le port série :
ni les messages d'amorçage, ni le getty. Et cela vaut **deux fois** — pour l'ISO
et pour le système installé.

**a) Côté ISO** — l'entrée systemd-boot de l'ISO officielle porte seulement
`options archisobasedir=arch archisosearchuuid=…`. On travaille donc sur une
**copie** de l'ISO (l'originale reste intacte et vérifiable) dont on modifie
l'entrée, pour obtenir :

```
options  archisobasedir=arch archisosearchuuid=… console=tty0 console=ttyS0,115200
```

`console=ttyS0` **en dernier** : le dernier `console=` de la ligne devient
`/dev/console`, celui que `systemd-getty-generator` instancie et sur lequel
arrivent les messages d'amorçage.

Trois contraintes commandent la méthode :

1. Le fichier `loader/entries/01-archiso-linux.conf` existe en **deux
   exemplaires** — un dans l'arbre ISO9660, un dans l'image FAT de l'ESP
   (partition `0xEF` de l'hybride). Selon la façon dont le firmware amorce le
   média, c'est l'un ou l'autre qui fait foi : **patcher les deux**.
2. **macOS ne sait pas monter cette ESP en écriture.** `mount -t msdos` (sans
   `-r`) rend `Permission denied`, et `hdiutil attach` sans `-nomount` rend
   « aucun système de fichiers montable ». L'édition se fait donc **directement
   dans l'image**, à l'octet.
3. La **taille du fichier doit être conservée** : elle est inscrite dans les
   métadonnées ISO9660 et dans l'entrée de répertoire FAT, qu'on ne touche pas.
   La place se prend sur la ligne `title` et sur `sort-key` — superflue, car
   `loader.conf` désigne l'entrée par défaut par son **nom de fichier**.

**Cloner puis patcher** (`cp -c` = clone APFS : instantané, sans coût disque) :

```bash
cd ~/Downloads
cp -c archlinux-2026.08.01-x86_64.iso archlinux-2026.08.01-x86_64-serial.iso
python3 patch-iso-serial.py archlinux-2026.08.01-x86_64-serial.iso
```

> Honnêteté sur l'ordre réellement suivi : lors du smoke test, la copie a
> d'abord été patchée **dans le bundle de la VM**
> (`…/eschaton-x86-smoke.utm/Data/archlinux.iso`, tentative de suivre le §3.3),
> puis clonée vers `~/Downloads/…-serial.iso`. Le résultat est identique — le
> script ne dépend que du contenu du fichier — mais l'ordre ci-dessus est le
> chemin direct, et c'est lui qu'il faut rejouer.

Le script, tel qu'exécuté :

```python
#!/usr/bin/env python3
"""Ajoute une console serie a l'entree systemd-boot de l'ISO Arch (copie)."""
import sys

path = sys.argv[1]

OLD = (
    b"title    Arch Linux install medium (x86_64, UEFI)\n"
    b"sort-key 01\n"
    b"linux    /arch/boot/x86_64/vmlinuz-linux\n"
    b"initrd   /arch/boot/x86_64/initramfs-linux.img\n"
    b"options  archisobasedir=arch archisosearchuuid=2026-08-01-14-10-23-00\n"
)

NEW = (
    b"title    Arch Linux (serie)\n"
    b"linux    /arch/boot/x86_64/vmlinuz-linux\n"
    b"initrd   /arch/boot/x86_64/initramfs-linux.img\n"
    b"options  archisobasedir=arch archisosearchuuid=2026-08-01-14-10-23-00"
    b" console=tty0 console=ttyS0,115200\n"
)

NEW += b"\n" * (len(OLD) - len(NEW))   # meme taille exacte, comble par des lignes vides
assert len(NEW) == len(OLD), f"taille {len(NEW)} != {len(OLD)}"

with open(path, "r+b") as f:
    data = f.read()
    hits = []
    off = data.find(OLD)
    while off != -1:
        hits.append(off)
        off = data.find(OLD, off + 1)
    if not hits:
        sys.exit("motif introuvable — l'ISO n'est pas celle attendue")
    for off in hits:
        f.seek(off)
        f.write(NEW)
    print(f"{len(hits)} exemplaire(s) patche(s) aux offsets " +
          ", ".join(hex(o) for o in hits))
    print(f"taille inchangee : {len(OLD)} octets")
```

```console
$ python3 patch-iso-serial.py archlinux-2026.08.01-x86_64-serial.iso
2 exemplaire(s) patche(s) aux offsets 0x4ef3f000, 0x4f54e400
taille inchangee : 220 octets
```

> **Les offsets ne se recopient pas d'une release à l'autre** — ceux ci-dessus
> valent pour l'ISO 2026.08.01. Le script les **retrouve seul** en cherchant le
> motif ; c'est bien ainsi qu'il faut le rejouer. Il refuse de travailler
> (« motif introuvable ») si l'entrée amont a changé — auquel cas il faut relire
> le fichier réel (commandes de vérification ci-dessous) et réajuster `OLD` et
> `NEW`, en gardant `len(NEW) == len(OLD)`.

**Vérifier le patch avant de démarrer** — remonter les deux systèmes de fichiers
de l'image et relire le fichier dans chacun :

```bash
hdiutil attach -nomount -readonly ~/Downloads/archlinux-2026.08.01-x86_64-serial.iso
#   /dev/disk20          FDisk_partition_scheme
#   /dev/disk20s2        0xEF
mkdir -p /tmp/iso /tmp/esp
mount -t cd9660 -r /dev/disk20   /tmp/iso    # l'arbre ISO9660
mount -t msdos  -r /dev/disk20s2 /tmp/esp    # l'image FAT de l'ESP
cat /tmp/iso/loader/entries/01-archiso-linux.conf
cat /tmp/esp/loader/entries/01-archiso-linux.conf
umount /tmp/iso /tmp/esp && hdiutil detach /dev/disk20
```

Les deux doivent rendre exactement :

```
title    Arch Linux (serie)
linux    /arch/boot/x86_64/vmlinuz-linux
initrd   /arch/boot/x86_64/initramfs-linux.img
options  archisobasedir=arch archisosearchuuid=2026-08-01-14-10-23-00 console=tty0 console=ttyS0,115200
```

> **Détacher l'image avant de démarrer la VM.** Une image encore attachée à
> l'hôte reste accessible, mais autant ne pas la laisser montée pendant que QEMU
> la lit. Le numéro de `disk` change à chaque `hdiutil attach` : relire la sortie
> plutôt que recopier `disk20`.

**b) Côté système installé** — `eschaton-install` écrit
`cmdline: root=LABEL=eschaton rootflags=subvol=@ rw quiet`, sans `console=`. Et
c'est très bien ainsi : une console série est un besoin de VM de développement,
pas de matériel réel. **C'est donc une étape de la procédure de smoke test, à
faire depuis le live env juste après l'installation et avant le premier
redémarrage** — sans quoi le système démarre parfaitement et on n'en voit
strictement rien :

```bash
# encore dans le live env, /mnt/boot toujours monté
sed -i 's|rw quiet|rw console=tty0 console=ttyS0,115200|' /mnt/boot/limine.conf
umount -R /mnt && reboot
```

> **Ne pas compter sur SSH pour remplacer la série.** `sshd` est bien activé et
> actif, l'invité obtient bien un bail DHCP — mais **l'hôte ne peut pas ouvrir
> de connexion TCP vers l'invité** à travers le `vmnet-shared` de UTM :
> `No route to host`, y compris vers la VM aarch64 (vérifié sur les deux). C'est
> la même limite d'hôte que l'ICMP du §6. Le trafic ne va que dans le sens
> invité → extérieur.

> **Le silence sur la série n'est pas une panne.** OVMF n'écrit rien quand le
> démarrage réussit (ses lignes `BdsDxe: failed to…` ne sortent qu'en cas
> d'échec), et **Limine, sur x86, dessine son menu sur la console VGA, pas sur
> la console UEFI** — à l'inverse d'aarch64 (§9.5) où il n'y a pas de VGA. Entre
> la fin du firmware et le premier message du noyau, il est donc normal de ne
> rien voir.

**c) Le déroulé d'installation** — c'est **celui du §8.2**, à l'installeur près
de rien : mêmes `curl`, même comparaison d'empreintes, même
`./eschaton-install --disk /dev/vda --user seylar`, mêmes deux invites `passwd`.
Le pilotage par `tools/vm-serial` (§5.3, §9.2) est identique. Quatre ajustements
x86_64, tous des **simplifications** :

| §8.2 (aarch64 / archboot) | x86_64 / ISO Arch officielle |
|---|---|
| attendre `Hit ENTER … or CTRL-C for bash prompt`, envoyer **`Ctrl-C`** (`raw 03`) | **pas de danse `Ctrl-C`** : l'ISO rend une invite `archiso login:` — envoyer `root`, sans mot de passe |
| `pacman -Sy --noconfirm arch-install-scripts gptfdisk btrfs-progs dosfstools` | **inutile** : `pacstrap`, `arch-chroot`, `genfstab`, `sgdisk`, `mkfs.btrfs`, `mkfs.vfat` sont **tous déjà là** (inventaire du live : table du §10.1) |
| `stty cols 200 rows 60` | identique — toujours nécessaire |
| `umount -R /mnt && reboot` | **précédé du `sed` de l'étape (b)** ci-dessus, sinon le système démarre invisible |

```bash
# console série obtenue (§10.3 a), au prompt `archiso login:`
tools/vm-serial send "root"                     # aucun mot de passe sur l'ISO Arch
tools/vm-serial run "stty cols 200 rows 60"

# identique au §8.2 à partir d'ici
tools/vm-serial run "cd /root && curl -fsSLO https://raw.githubusercontent.com/Seylar/eschaton/main/installer/eschaton-install \
  && curl -fsSLO https://raw.githubusercontent.com/Seylar/eschaton/main/installer/lib.sh \
  && chmod +x eschaton-install && sha256sum eschaton-install lib.sh"
#   à comparer au dépôt : raw.githubusercontent met en cache

tools/vm-serial send 'cd /root && ./eschaton-install --disk /dev/vda --user seylar; echo INSTALL_RC=$?'
#   ~8 min plus tard : « New password: » puis « Retype new password: »
#   -> `send "eschaton"` deux fois ; attendre `INSTALL_RC=0`

tools/vm-serial run "sed -i 's|rw quiet|rw console=tty0 console=ttyS0,115200|' /mnt/boot/limine.conf"
tools/vm-serial send "umount -R /mnt && reboot"
```

> **Lancer l'installeur par `send`, pas par `run`.** Les deux invites `passwd`
> sont interactives : `run` attend un marqueur de fin qui n'arrivera jamais et
> se désynchronise. D'où le `echo INSTALL_RC=$?` — et, quand on guette ce
> marqueur, chercher `INSTALL_RC=[0-9]` et non `INSTALL_RC=`, sinon on tombe sur
> l'écho de la commande qu'on vient de taper.

### 10.4 Rattraper un système installé qu'on ne voit pas

Si l'étape (b) du §10.3 a été oubliée, le disque est amorçable et l'UEFI ne
retombe plus sur l'ISO : on ne peut plus entrer nulle part. La sortie est de
**recréer la VM avec le CD en premier** — l'ordre étant figé à la création
(§10.2), c'est le seul levier — en réinjectant le disque déjà installé :

```bash
VM="$HOME/Library/Containers/com.utmapp.UTM/Data/Documents/eschaton-x86-smoke.utm"
/Applications/UTM.app/Contents/MacOS/utmctl stop eschaton-x86-smoke --force
cp -c "$VM/Data/"*.qcow2 /tmp/eschaton-x86-installed.qcow2      # clone APFS, instantané
osascript -e 'tell application "UTM" to delete virtual machine named "eschaton-x86-smoke"'
osascript ~/create-x86-cd-first.applescript                      # CD en 1er dans `drives`
rm -f "$VM/Data/"*.qcow2 && cp -c /tmp/eschaton-x86-installed.qcow2 "$VM/Data/<nouvel-id>.qcow2"
```

Le live env démarre alors, `mount /dev/vda1 /mnt/esp` donne accès à `limine.conf`,
et on recrée ensuite la VM dans l'ordre nominal (disque d'abord).

> **Supprimer `Data/efi_vars.fd` remet la NVRAM à zéro** (UTM la recrée depuis
> son gabarit au démarrage suivant, 328 704 octets). Utile : cela efface les
> entrées de démarrage inscrites par l'invité. À savoir — le fichier que QEMU
> régénère lui-même après un `rm` à chaud n'a pas la même taille (458 752) ;
> seule la recréation de la VM redonne le gabarit d'origine.

### 10.5 Durées réelles — l'émulation coûte ~3×, pas ~15×

La spec §8 (risque 5) parle d'« émulation x86_64 très lente ». Mesuré, c'est
**beaucoup moins dramatique que prévu** : le facteur est de l'ordre de **3 sur
le cycle complet** et de **6 sur `pacstrap`**, pas les 10 à 20 redoutés. La VM
émulée voit d'ailleurs ses **4 cœurs**, là où le live env aarch64 est bridé à un
seul (§7).

| Étape | x86_64 émulé | aarch64 virtualisé (§8.1) |
|---|---|---|
| Téléchargement de l'ISO | 43 s (1,5 Gio) | — |
| Démarrage de la VM → invite du live env | **≈ 2 min** | ~30 s |
| `eschaton-install` complet | **8 min 46 s** | 1 min 30 s |
| — volume | 234 paquets, 402 Mio téléchargés, 1 220 Mio installés | 231 paquets, 276 Mio, 1,5 Gio |
| Redémarrage → invite de connexion Eschaton | **≈ 55 s** | ~18 s |
| **Total, VM éteinte → session ouverte** | **≈ 12 min** | ≈ 4 min |
| `eschaton-update` (dont kernel, 147 Mio) | 2 min 31 s | ~25 s (petit paquet) |
| Redémarrage après mise à jour du kernel | 60 s | ~19 s |

Décomposition d'un démarrage d'Eschaton, par `systemd-analyze` :

```
Startup finished in 2.205s (firmware) + 3.407s (loader) + 3.060s (kernel)
                  + 9.487s (initrd) + 20.785s (userspace) = 38.946s
```

> **`systemd-analyze` ment sur le poste « firmware » en émulation.** Au
> redémarrage suivant il a annoncé `7min 22s (firmware)` pour un cycle qui a
> duré **60 s au chronomètre**. La valeur vient de variables EFI dont la base de
> temps n'est pas fiable sous TCG. Seule la mesure au mur fait foi.

### 10.6 `limine-entry-tool` sur x86_64 : la réserve de la Task 9 est levée

C'est ce que ce smoke test devait attraper. Rappel du §8.6 : sur aarch64
`limine-update` s'arrête sur « The system is not x86_64 » et ne génère jamais
rien ; **sur x86_64 il s'exécute**, et rien ne garantissait *a priori* qu'il
s'entende avec le `limine.conf` écrit par `eschaton-install`.

**Il s'entend — et c'est `TARGET_OS_NAME` qui le fait.** L'invariant du §4.2
étape 6, posé par `eschaton-base` dans `/etc/default/limine`, est lu par
`limine-entry-tool` exactement comme par `limine-snapper-sync` : l'outil
retrouve l'entrée `/Eschaton`, y retrouve la sous-entrée de kernel, et **réécrit
son corps sur place**. C'est l'harmonisation qu'espérait la Task 7bis, vérifiée.

Ce qu'il fait, au premier changement de kernel (`linux` 7.1.9 → 7.1.10) :

```
(3/4) Record kernels marked for removal in Limine
(4/4) Removing linux initcpios...
(3/5) Clean Limine boot entries of removed kernels
(4/5) Updating linux initcpios...
Copied: /tmp/limine-mkinitcpio.…/initramfs -> /boot/<machine-id>/linux/initramfs
Copied: /usr/lib/modules/7.1.10-arch1-1/vmlinuz -> /boot/<machine-id>/linux/vmlinuz
Updated: /boot/limine.conf
```

`limine.conf` après réécriture — une seule entrée de premier niveau, la nôtre :

```
timeout: 3
default_entry: Eschaton/linux

/Eschaton
    //linux
  ### This kernel entry is auto-generated by limine-entry-tool
  comment: Kernel version: 7.1.10-arch1-1
  protocol: linux
  module_path: boot():/<machine-id>/linux/initramfs#<blake2b>
  path: boot():/<machine-id>/linux/vmlinuz#<blake2b>
  cmdline: root=LABEL=eschaton rootflags=subvol=@ rw console=tty0 console=ttyS0,115200

    //Snapshots
     ### Auto-generated by limine-snapper-sync
     comment: 2 snapshots
     ///2 │ 2026-08-28 06:02:55
     …
```

Point par point, la réserve :

| Question de la Task 9 | Réponse mesurée |
|---|---|
| Ajoute-t-il une entrée en double à côté des nôtres ? | **Non.** `grep -c '^/[^/]' /boot/limine.conf` → `1`, avant comme après. |
| Écrase-t-il `default_entry` ? | **Non.** `default_entry: Eschaton/linux` intact. |
| Écrase-t-il notre `cmdline` ? | **Non.** Recopié verbatim — y compris l'ajout `console=` du §10.3. |
| Casse-t-il l'ancre `//Snapshots` ? | **Non.** Préservée, et `limine-snapper-sync` y a écrit ses 2 entrées. |
| `TARGET_OS_NAME` harmonise-t-il les deux outils ? | **Oui** — c'est la clé de tout ce qui précède. |

**Ce qu'il change tout de même**, et qu'il faut connaître :

- **Il devient propriétaire des fichiers du kernel.** L'entrée pointait sur
  `/boot/vmlinuz-linux` + `/boot/initramfs-linux.img` (écrits par l'installeur) ;
  après la première transaction elle pointe sur
  `/boot/<machine-id>/linux/{vmlinuz,initramfs}`. Les deux fichiers d'origine
  sont **supprimés** par son crochet de pré-transaction — pas d'orphelins, mais
  l'arborescence n'est plus celle que l'installeur a posée. Sans conséquence :
  il maintient désormais les siens, et le système démarre (vérifié : 7.1.10 au
  redémarrage, modules concordants).
- **Il installe un second Limine et l'inscrit en NVRAM.** `/boot/EFI/limine/`
  contient `limine_x64.efi` — **binaire identique** (même md5) à celui que
  l'installeur pose en `/boot/EFI/BOOT/BOOTX64.EFI` — plus un `.bak`. Pendant le
  `pacstrap` il crée aussi, via `efibootmgr`, une entrée UEFI
  `Boot0004* Limine … \EFI\limine\limine_x64.efi` **prioritaire** sur le chemin
  de repli de l'installeur. Le premier démarrage passe donc par *son* binaire —
  sans différence observable, les deux étant le même fichier. La variable EFI
  `LimineLastBootedEntry` valait alors `Eschaton/linux` : c'est bien notre
  entrée qui a démarré.
- **L'entrée NVRAM n'est pas recréée** aux transactions suivantes : après une
  remise à zéro de la NVRAM (§10.4), le système démarre par
  `\EFI\BOOT\BOOTX64.EFI` et y reste, même après une mise à jour de kernel.
- **Coût en place sur l'ESP** : ~31 Mio pour le doublon kernel + initramfs. Sur
  les 4 Gio du §4.3, l'ESP reste à **108 Mio (3 %)** avec 2 snapshots — très
  loin du seuil `LIMIT_USAGE_PERCENT` (85 %) du risque n° 8.

**Conclusion : aucun conflit réel, aucun correctif à porter au dépôt.**

### 10.7 Checklist §7.3 — sorties réelles

Toutes lues sur la console série de la VM, après le premier démarrage.

```console
$ grep '^ID=eschaton$' /etc/os-release && echo SMOKE_X86_OK
ID=eschaton
SMOKE_X86_OK

$ uname -m; uname -r; nproc
x86_64
7.1.9-arch1-2                      (puis 7.1.10-arch1-1 après eschaton-update)
4

$ pacman -Q linux intel-ucode amd-ucode
linux 7.1.9.arch1-2
intel-ucode 20260812-1
erreur : le paquet « amd-ucode » n'a pas été trouvé      ← détection du vendeur : OK

$ systemctl --failed --no-legend
(vide — 0 ligne)

$ for u in NetworkManager sshd fstrim.timer limine-snapper-sync snapper-cleanup.timer …
NetworkManager.service           enabled   active
sshd.service                     enabled   active
fstrim.timer                     enabled   active
limine-snapper-sync.service      enabled   active
snapper-cleanup.timer            enabled   active

$ grep -c '^/[^/]' /boot/limine.conf ; grep '^default_entry' /boot/limine.conf
1
default_entry: Eschaton/linux

$ grep TARGET /etc/default/limine
TARGET_OS_NAME="Eschaton"

$ timeout 60 curl -fsI https://archlinux.org >/dev/null && echo NET_OK
NET_OK                                            (enp0s1, 192.168.64.x, jamais `ping`)

$ eschaton-update --noconfirm
Paquets (1) linux-7.1.10.arch1-1
(1/4) Performing snapper pre snapshots…    ==> root: 1
(2/4) Waiting for limine-snapper-sync to finish...
(5/5) Performing snapper post snapshots…   ==> root: 2
==> Le kernel a été mis à jour : redémarre pour l'utiliser (sudo reboot).
UPDATE_RC=0

$ uname -r ; ls -d /usr/lib/modules/$(uname -r)      # après redémarrage
7.1.10-arch1-1
/usr/lib/modules/7.1.10-arch1-1                   ← kernel et modules d'accord

$ findmnt -nrt btrfs -o TARGET,SOURCE
/                     /dev/vda2[/@]
/home                 /dev/vda2[/@home]
/.snapshots           /dev/vda2[/@snapshots]
/var/cache/pacman/pkg /dev/vda2[/@pkg]
/var/log              /dev/vda2[/@log]

$ swapon --show
/dev/zram0 partition 1,9G   0B  100                ← zram seul, aucune partition

$ lsblk -no SIZE,FSTYPE /dev/vda1
   4G vfat                                          ← ESP 4 Gio (spec §4.3)

$ pacman -Q eschaton-base eschaton-branding limine limine-snapper-sync limine-mkinitcpio-hook
eschaton-base 0.1.0-11        eschaton-branding 0.1.0-1        limine 12.6.1-1
limine-snapper-sync 1.31.0-1  limine-mkinitcpio-hook 1.37.1-1

$ sudo pacman -Qkk eschaton-base
eschaton-base : 26 fichiers au total, 0 fichier modifié     ← correctif Task 10 n°2 tenu
```

Bannière de connexion série : `Eschaton 7.1.9-arch1-2 (ttyS0)`, puis
`Eschaton 7.1.10-arch1-1 (ttyS0)` après la mise à jour — l'identité vient bien
de `/etc/os-release`. Le motd s'affiche à l'ouverture de session :
`Bienvenue sur Eschaton — https://eschaton (rolling)`.

### 10.8 Pièges propres à ce smoke test

- **Ne pas supprimer `~/Downloads/archlinux-2026.08.01-x86_64-serial.iso`.** La
  VM ne contient pas l'ISO : elle la référence par *bookmark* vers ce chemin
  (§10.2). Un nettoyage du dossier `Downloads` casse le lecteur CD **sans aucun
  message** — le `config.plist` n'affiche pas le chemin, et la panne n'apparaît
  qu'au démarrage suivant, sous la forme d'un UEFI qui ne trouve plus de média.
  Le fichier fait 1,5 Gio mais c'est un clone APFS de l'ISO d'origine : il ne
  coûte que les 220 octets réécrits. Garder **les deux** ISO — l'originale reste
  la pièce vérifiable (SHA-256 amont), la patchée est celle qui démarre.
- **Ne pas confondre les deux VM sur le réseau.** Les deux s'appellent
  `eschaton` et vivent en `192.168.64.x`. Le bail se lit dans
  `/var/db/dhcpd_leases` sur le Mac ; **identifier par l'adresse MAC**, pas par
  le nom. (Le live env archiso s'y annonce avec un identifiant DUID, le système
  installé avec sa MAC : ce ne sont pas les mêmes baux.)
- **Le `pacstrap` demande les invites `passwd` au bout de ~8 min.** Un pilotage
  qui abandonne avant se trompe de diagnostic — même leçon qu'au §8.1, avec un
  facteur 6.
- **Le pty change à chaque `utmctl stop`/`start`** (§5.3) : le redétecter et
  relancer le démon. Un `reboot` de l'invité, lui, ne le change pas.
- **`fatal library error, lookup self`** et **`sd-vconsole: "/etc/vconsole.conf"
  not found`** pendant le `pacstrap` : identiques à aarch64 (§8.5), sans
  conséquence.
- **`x86/CPU: Model not found in latest microcode list`** au démarrage : le
  processeur émulé (« Intel Core Processor (Skylake) », synthétique) n'a pas de
  blob dans `intel-ucode`. Le chargeur précoce a bien tourné — c'est lui qui
  émet le message — et le crochet `microcode` de mkinitcpio a bien intégré le
  blob à l'initramfs. Rien à corriger : c'est une propriété du CPU émulé.
- **Le compte `seylar` a le mot de passe `eschaton`**, comme la VM aarch64
  (§8.2). VM jetable, à ne pas exposer.

### 10.9 Ce que ce test rend possible, et qu'il n'a pas fait

La VM est restée sur un état où le §9.10 devient exécutable : **deux kernels
distincts** (7.1.9 et 7.1.10) existent maintenant dans `limine_history/`, avec
un snapshot `pre` antérieur au changement. Le rollback *à travers* un changement
de kernel — le seul morceau du filet que la Task 10 n'a pas pu exercer faute de
mise à jour de kernel ALARM — peut donc s'éprouver ici, sur x86_64, sans
attendre. Hors périmètre du §7.3, mais l'occasion est ouverte.

---

## 11. Définition de terminé — dossier de preuves (spec §7)

Cette section **ne rejoue rien** : elle compile le dossier. Pour chacun des
quatre critères de la spec §7, elle dit où vit la preuve — la section de ce
document qui la porte, le rapport de tâche qui la détaille, le commit qui l'a
fixée dans le dépôt. Un seul critère se re-vérifie en direct, le **§7.4** : la CI
et le dépôt publié sont les seuls dont l'état peut changer sans que personne ne
touche à rien.

Consolidé le **2026-08-28**, à la clôture du Socle (`v0.1.0`).

| Critère §7 | Statut | Sections | Rapport de tâche | Commit qui le fixe |
|---|---|---|---|---|
| **7.1** Installation reproductible (VM UTM aarch64) | **Prouvé** le 2026-08-28 | §8, §8.6 | `task-9-report.md` | `43af004` |
| **7.2** Casse réelle → restauration par snapshot | **Prouvé** le 2026-08-28 | §9, §9.4, §9.5, §9.8, §9.9 | `task-10-report.md` | `ed27687` |
| **7.3** Cible x86_64 prouvée (VM émulée) | **Prouvé** le 2026-08-28 | §10, §10.6, §10.7 | `task-11-report.md` | `035fe92` |
| **7.4** CI verte, dépôt publié et installable | **Re-vérifié en direct** le 2026-08-28 | §11.4 | `task-8-report.md` | `fa34322` |

Les rapports de tâche nommés dans cette table sont des **archives de session,
non versionnées** : elles vivent sous `.superpowers/`, gitignoré, donc absentes
d'un clone du dépôt. Ce ne sont pas les preuves. **Les preuves durables sont les
sections de ce document et les commits cités** — eux seuls survivent au clone.

Aucun des quatre n'est un constat sur le papier : chacun renvoie à des sorties
console lues sur une VM, ou à une exécution de CI horodatée.

### 11.1 §7.1 — Installation reproductible

> *« depuis le Mac, la procédure documentée/scriptée (`tools/`) produit une VM
> UTM aarch64 qui boote Eschaton — `os-release` l'affirme, le réseau fonctionne,
> un utilisateur existe, `eschaton-update` s'exécute sans erreur. »*

**Preuve** : §8 de ce document — procédure déroulée **trois fois de bout en
bout** le 2026-08-28, entièrement par la console série, sans jamais ouvrir
l'interface de UTM. Les quatre exigences, point par point, dans le relevé du
§8.6 : `ID=eschaton` lu dans `/etc/os-release` (fichier, plus un lien) ;
`curl -fsI https://archlinux.org` → `NET_OK` sur `enp0s1` ; compte `seylar` avec
session ouverte et `sudo` ; `eschaton-update` → `rc=0`, cinq dépôts synchronisés.
Le §8.1 chiffre la reproductibilité (≈ 4 min, VM éteinte → session ouverte), le
§8.3 dit comment réinstaller par-dessus.

**Rapport** : `task-9-report.md` (statut `DONE_WITH_CONCERNS`).

**Commits** : `43af004` valide le critère ; il n'a été atteignable qu'après les
correctifs que l'installation réelle a exigés — cinq défauts, quatre commits :
`10cfd13` (trousseau de l'architecture + `os-release` délié, défauts 1 et 2),
`2100c58` (`limine.conf` imbriqué, sans quoi **aucune** entrée de snapshot
n'était jamais générée), `0508d19` (`inotify-tools`, le veilleur mourait à
54 ms), `a277065` (`default_entry`, sans lequel la VM ne démarrait plus du tout
— défaut appelé par le correctif précédent).

**Réserve** : les cinq défauts trouvés étaient **tous silencieux** (§8.4) — le
système démarrait et se disait en bon état dans chaque cas. La leçon vaut pour
la suite du projet : sur ce socle, une panne se signale rarement.

### 11.2 §7.2 — Test de casse réel

> *« sabotage volontaire du système […] → restauration par snapshot → système
> fonctionnel. Exécuté pour de vrai, pas sur le papier. »*

**Preuve** : §9 de ce document, déroulé le 2026-08-28 **sur l'installation du §8,
sans jamais la réinstaller**. Sabotage réel (`rm /usr/bin/ls`, §9.3), restauration
par `eschaton-rollback` (§9.4 : `ROLLBACK_OK`, `pacman -Qkk coreutils` de nouveau
à 0 fichier modifié, `systemctl --failed` vide), et **démarrage sur un snapshot
depuis Limine** (§9.5) — le troisième scénario de la spec §6, celui du système
qui ne démarre plus. Le §9.8 vérifie le correctif **par le chemin complet** —
paquet publié → `eschaton-update` → empreintes identiques au dépôt — et non par
un fichier posé à la main. Le §9.9 montre la VM rendue propre à la fin.

**Rapport** : `task-10-report.md` (verdict : §7.2 validé).

**Commits** : `ed27687` valide le critère. Le test a trouvé **quatre défauts,
dont un bloquant** — `eschaton-rollback` ne fonctionnait pas du tout :
`b71153c` (méthode `replace` : `snapper rollback` exige la disposition openSUSE),
`398763a` (`--recursive` sur le nettoyage indiqué), `b7f8137` (refus de
s'exécuter depuis un snapshot démarré), `78e4d73` (`/etc/sudoers.d` n'est plus
revendiqué en 755). La spec §6 a été amendée en conséquence (`f801713`), et le
contrat de `--restore-kernels` vérifié statiquement (`806fcea`).

**Réserve ouverte, consignée §9.10** : le rollback **à travers un changement de
kernel** n'a pas été exercé dynamiquement — les sept snapshots de la VM
partagent la même empreinte de kernel, faute de mise à jour ALARM pendant le
test. Le contrat de `limine-snapper-sync --restore-kernels` est vérifié sur ses
sources (tag 1.31.0) ; la preuve dynamique reste due, et le §10.9 note que la VM
x86_64 la rend exécutable dès maintenant (deux kernels distincts en
`limine_history/`).

### 11.3 §7.3 — Cible x86_64 prouvée

> *« le même `eschaton-install` déroulé dans une VM x86_64 émulée (lente — smoke
> test uniquement) produit un système qui boote. »*

**Preuve** : §10 de ce document, déroulé le 2026-08-28 sur la VM
`eschaton-x86-smoke`. Le même installeur, **sans une ligne de modification** —
empreintes de `eschaton-install` et `lib.sh` relevées dans la VM et identiques au
dépôt. Checklist et sorties réelles au §10.7 : `SMOKE_X86_OK`, `uname -m` →
`x86_64`, détection du vendeur de microcode (`intel-ucode` posé, `amd-ucode`
absent), cinq subvolumes, ESP 4 Gio, zram seul, `systemctl --failed` vide,
`eschaton-update` → `rc=0` avec mise à jour de kernel puis redémarrage sur
`7.1.10-arch1-1` avec modules concordants. Le §10.5 mesure le coût réel de
l'émulation (≈ 3×, pas 15×) et le §10.8 liste les pièges propres à ce test.

**Rapport** : `task-11-report.md` (statut : §7.3 validé, aucun défaut trouvé,
aucun correctif au dépôt).

**Commits** : `035fe92` valide le critère ; `c9a8a40` documente la fabrication de
l'ISO patchée (console série) et rend le test rejouable.

**Ce que ce test a aussi levé** : la réserve que la Task 9 avait laissée ouverte
sur `limine-entry-tool` (§8.6), qui ne s'exerce que sur x86_64 — voir §10.6.
`TARGET_OS_NAME` harmonise l'outil avec `limine-snapper-sync` et avec le
`limine.conf` de l'installeur : pas d'entrée en double, `default_entry` et
`cmdline` intacts, ancre `//Snapshots` préservée. **Constat neuf porté au registre
des risques** (spec §8) : `limine-entry-tool` installe sur x86_64 son propre
exemplaire de Limine (`/boot/EFI/limine/`) plus une entrée NVRAM prioritaire, à
côté de celui posé par l'installeur — bénin tant que les binaires sont
identiques, dette surveillée si les chemins de mise à jour divergent.

### 11.4 §7.4 — CI verte, dépôt publié et installable

> *« lint des scripts shell (shellcheck), lint des PKGBUILDs (namcap), build des
> paquets, dépôt publié et installable. »*

Le seul critère re-vérifié **en direct** à la clôture. La CI tourne sur `socle`
(et sur `main`) : tant que la branche n'était pas fusionnée, c'était `socle` qui faisait
foi.

```console
$ gh run list --branch socle --limit 1
completed  success  fix: contrat de --restore-kernels vérifié statiquement …
           ci  socle  push  33134865064  4m51s  2026-08-28T02:05:50Z
```

Les quatre jobs du run, tous `success` — c'est leur découpage qui couvre les
quatre exigences du critère :

| Job | Couvre | Résultat |
|---|---|---|
| `lint` | `shellcheck` sur les 9 scripts du dépôt, `bats tests/` | `success` |
| `build-x86_64` | `repo/build-repo` en conteneur Arch natif — build des 4 paquets + `namcap` (informatif, spec §7.4) | `success` |
| `build-aarch64` | idem sur runner `ubuntu-24.04-arm`, image ALARM | `success` |
| `publish` | index `repo-add` des deux architectures assemblé et déployé sur GitHub Pages | `success` |

**Dépôt publié et installable**, vérifié le 2026-08-28 depuis le Mac :

```console
$ curl -fsI https://seylar.github.io/eschaton/x86_64/eschaton.db
HTTP/2 200
last-modified: Fri, 28 Aug 2026 02:10:35 GMT

$ curl -fsI https://seylar.github.io/eschaton/aarch64/eschaton.db
HTTP/2 200
last-modified: Fri, 28 Aug 2026 02:10:35 GMT
```

(Extraits : `curl -fsI` rend l'en-tête complet ; `-I` et non `-i`, on ne
télécharge pas l'index pour savoir qu'il est là.)

L'horodatage est celui du run ci-dessus : c'est bien lui qui a publié l'index
servi. Et « installable » n'est pas une lecture d'en-tête HTTP — c'est le chemin
qu'ont emprunté les deux tests d'installation : §9.8 (aarch64 :
`eschaton-update` installe `eschaton-base-0.1.0-10` depuis ce dépôt, empreintes
identiques aux fichiers du dépôt git) et §10.7 (x86_64 : `eschaton-base 0.1.0-11`,
`pacman -Qkk` à 0 fichier modifié).

**Rapport** : `task-8-report.md` (statut `DONE_WITH_CONCERNS`) ; **commit** :
`fa34322` (CI GitHub : lint, build des deux architectures, dépôt publié), avec
`687a104` (`build-repo` refuse aussi un dépôt vide — un index valide et vide
aurait fait disparaître tous les paquets d'un `pacman -Syu`).

**Réserve, héritée de la Task 8** : le Gradle Plugin Portal est instable depuis
le runner ARM — c'est la seule source connue d'échec intermittent de la CI, sur
les deux paquets vendorés. Elle n'a pas rejoué depuis.

> **Run de clôture** : le run déclenché par le commit qui porte cette section
> (`1395680`) est allé à son terme — run **`33142693443`**, ses quatre jobs
> verts (`lint`, `build-x86_64`, `build-aarch64`, `publish`).

### 11.5 Ce que « Socle terminé » ne dit pas

Le §7 est atteint ; il ne prétend pas que tout est prouvé. Restent dus, tracés
et non bloquants pour `v0.1.0` :

- le **rollback à travers un changement de kernel** (§9.10) — protocole écrit,
  exécutable sur la VM x86_64 (§10.9) ;
- la **signature du dépôt** — dette v0 assumée, prérequis bloquant du
  sous-projet 4 (spec §5.3 et risque n° 4) ;
- le **double Limine sur x86_64** (§10.6) — surveillance, spec §8 ;
- la **vérification elle-même**, qui reste une checklist manuelle en v0 : son
  automatisation sous QEMU est un chantier ultérieur, nommé par la spec §7.

---

## 12. Spike rendu bureau — Quickshell/DMS sous virtio-gpu (SP2, Task 1)

Déroulé le 2026-08-28 sur la VM `eschaton-dev` (Socle 0.1.0-11), entièrement par
la console série. Répond au risque n° 1 de la [spec Bureau](../docs/superpowers/specs/2026-08-28-bureau-design.md)
et à son critère §6.1.

### 12.1 Décision : **rendu OK, par repli logiciel côté compositeur seulement**

| | |
|---|---|
| Hyprland 0.56.1 | démarre et tient, **à condition de `LIBGL_ALWAYS_SOFTWARE=1`** |
| Quickshell 0.3.1 / DMS 1.5.3 | rend **sans aucune variable d'environnement** — Qt prend l'OpenGL de Mesa, qui retombe seul en logiciel |
| Qualité | barre, Control Center, lanceur, fond d'écran, icônes SVG, texte antialiasé, traduction `fr` — **aucun artefact** |
| Coût | 0 % de CPU au repos ; ~620 Mio de RSS pour le bureau (Hyprland 256 + `qs` 363) |

Le repli du risque n° 1 de la spec est donc **partiellement nécessaire, et son
nom est faux** (§12.6). Les tâches 7–9 peuvent tabler sur un bureau qui rend.

### 12.2 Le fait qui explique tout : pas de virgl

UTM n'expose **aucune accélération 3D** sur son `virtio-gpu-pci`. C'est visible
dès le `dmesg` de l'invité, avant toute installation :

```
[drm] pci: virtio-gpu-pci detected at 0000:00:02.0
[drm] features: -virgl +edid -resource_blob -host_visible
[drm] number of cap sets: 0
[drm] Initialized virtio_gpu 0.1.0 for 0000:00:02.0 on minor 0
```

`-virgl` + `cap sets: 0` = le noyau donne un KMS complet (modes, EDID, tampons
« dumb ») mais **aucun contexte GL**. Mesa a bien `/usr/lib/dri/virtio_gpu_dri.so`,
il ne peut simplement pas créer d'écran DRI dessus. Tout le reste en découle.

### 12.3 La séquence qui marche (et les deux échecs qui la précèdent)

**Échec 1 — depuis la console série, pas de siège.** Une session série n'a pas
de VT, donc pas de *seat* logind :

```console
$ loginctl show-session … -p Type -p Seat -p VTNr
VTNr=0
Seat=
Type=tty

$ Hyprland -c ~/.config/hypr/hyprland.lua
…
terminate called after throwing an instance of 'std::runtime_error'
  what():  CBackend::create() failed!            → rc 134 (core dumped)
```

**Le contournement est `seatd`** — déjà installé (dépendance d'`aquamarine`,
elle-même dépendance d'`hyprland`), lancé à la main, **sans rien modifier dans
`/etc`** :

```console
$ sudo seatd -g wheel -l info &
[INFO] [seatd/seat.c:48] Created VT-bound seat seat0
[INFO] [seatd/seatd.c:194] seatd started
$ ls -l /run/seatd.sock
srwxrwx--- 1 root wheel 0 /run/seatd.sock          (seylar est dans wheel)
```

**Échec 2 — siège obtenu, mais EGL refuse.** `LIBSEAT_BACKEND=seatd Hyprland …`
va bien plus loin (connecteur trouvé, allocateurs GBM et dumb créés) puis meurt
sur EGL :

```console
DEBUG from aquamarine ]: drm: Description Red Hat, Inc. QEMU Monitor  (Virtual-1)
DEBUG from aquamarine ]: drm: gpu /dev/dri/card0 becomes primary drm
DEBUG from aquamarine ]: DRM Dumb: created a dumb allocator
DEBUG from aquamarine ]: Created a GBM allocator with drm fd 25
ERR   from aquamarine ]: [EGL] Command eglInitialize errored out with
                         EGL_NOT_INITIALIZED (0x12289): DRI2: failed to create screen
ERR   from aquamarine ]: [EGL] … DRI2: failed to load driver
ERR   from aquamarine ]: CDRMRenderer: fail, eglInitialize failed
ERR   from aquamarine ]: drm: onReady: no renderer for gl formats
                                                 → rc 134 (core dumped)
```

**La séquence complète qui marche :**

```bash
sudo seatd -g wheel -l info &                     # une fois par démarrage
LIBSEAT_BACKEND=seatd LIBGL_ALWAYS_SOFTWARE=1 \
  Hyprland -c ~/.config/hypr/hyprland.lua &       # le compositeur
export WAYLAND_DISPLAY=wayland-1 \
       HYPRLAND_INSTANCE_SIGNATURE=$(basename $(ls -td /run/user/1000/hypr/*/ | head -1)) \
       XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=Hyprland
dms run &                                          # le shell — aucune variable GL
```

```console
$ hyprctl monitors
Monitor Virtual-1 (ID 0):
	1280x800@74.99400 at 0x0
	description: Red Hat Inc. QEMU Monitor
	currentFormat: XRGB8888
	directScanoutBlockedBy: user settings,software renders/cursors,missing candidate

$ hyprctl layers
	Layer level 0 (background):
		Layer …: xywh: 0 0 1280 800, a: 1, namespace: quickshell, pid: 2866
	Layer level 2 (top):
		Layer …: xywh: 0 0 1280 64,  a: 1, namespace: dms:bar,   pid: 2866
```

Les deux surfaces layer-shell **portent un tampon** (`a: 1`) : Quickshell a bien
peint, le compositeur affiche.

> **Le repli n'est nécessaire que pour le compositeur.** Vérifié dans
> `/proc/<pid>/environ` : `Hyprland` porte `LIBGL_ALWAYS_SOFTWARE=1`, `qs` ne
> porte que le `QSG_USE_SIMPLE_ANIMATION_DRIVER=1` que DMS se met tout seul.
> Les deux ont chargé `libgallium-26.2.1`. La raison est connue : sur une
> plateforme GBM, Mesa **ne retombe pas** seul en logiciel ; sur la plateforme
> Wayland d'un client, si.

> **Bruit résiduel, non fatal.** Même en mode logiciel, aquamarine réessaie son
> `CDRMRenderer` à chaque commit et échoue : `Can't create renderer, no matching
> devices found` / `drm: initMgpu: no renderer` / `Failed to update renderer
> state for Virtual-1 on applyCommit`. Le rendu, lui, passe par le renderer
> OpenGL propre à Hyprland. Ne pas lire ces lignes comme une panne.

### 12.4 Vie et stabilité (critères §6.1 de la spec Bureau)

```console
$ ps -eo pid,etime,%cpu,rss,comm | grep -E 'Hyprland|qs$|seatd'
   2605       15:56  0.0    3748 seatd
   2767       12:36  3.6  256104 Hyprland
   4996       05:06  1.3  363516 qs

$ top -bn2 -d 2                       → Hyprland 0,0 %  qs 0,0 %  (2e échantillon)
                                        %Cpu(s): 99,8 id
$ systemctl --failed --no-legend      → (vide)
$ coredumpctl list --since '…09:30'   → No coredumps found.
```

Relevé à nouveau à la clôture du spike : `seatd 20:29`, `Hyprland 17:09`,
`qs 09:39`, toujours aucun coredump et aucune unité en échec. Le critère
« stable ≥ 5 min » est tenu trois fois plutôt qu'une. Les seuls coredumps du
journal sont les **deux échecs de démarrage** du §12.3, à 09:22 et 09:28.

Puis la session a **encaissé une suspension/reprise de l'hôte** sans rien
perdre — voir l'encadré ci-dessous — et se relevait à `Hyprland 22:30`, les deux
surfaces layer-shell toujours pourvues d'un tampon, l'IPC toujours répondante et
une nouvelle capture 1280×800 produite après la reprise.

> **Piège d'exploitation : UTM dit `stopped` pour une VM seulement suspendue.**
> Constaté ici : `utmctl status` a rendu `stopped` alors que l'invité n'avait
> jamais redémarré. `utmctl start` l'a **reprise**, pas rebootée — même pty,
> même shell, même répertoire courant, mêmes PID, `who -b` inchangé
> (`démarrage système 2026-08-28 06:21`, `uptime` continu). Corollaires :
> - la règle du §5.3 (« seul un `utmctl stop`/`start` renumérote le pty ») ne
>   vaut pas pour ce cas-là — le pty était identique après la reprise ;
> - la console reste **muette** après la reprise tant qu'on ne lui envoie rien :
>   il n'y a ni bannière ni invite de connexion à attendre. Un `wait "…login:"`
>   expire pour de bon (rc 124). Envoyer un `raw 0a` et lire le `tail` est la
>   façon de savoir où l'on est ;
> - le démon série, lui, voit un EOF franc au moment de la suspension. C'est
>   exactement le cas que le durcissement de `tools/vm-serial` traite : il l'a
>   journalisé et s'est arrêté seul en 10 s au lieu de tourner à vide.

> **Le processus s'appelle `qs`, pas `quickshell`.** `pgrep -a quickshell` ne
> rend rien alors que le shell tourne — c'est `qs -p /usr/share/quickshell/dms`.
> Piège de vérification pour les tâches 7–9.

L'IPC répond (la commande du brief, `dms ipc call mpris getall`, n'existe pas —
la bonne est `mpris list`) :

```console
$ dms ipc call control-center status   → hidden
$ dms ipc call control-center open     → CONTROL_CENTER_OPEN_SUCCESS
$ dms ipc call spotlight open          → SPOTLIGHT_OPEN_SUCCESS
$ dms ipc                              → 30+ cibles : audio, bar, control-center,
                                         dock, launcher, lock, night, systemupdater,
                                         theme, tray, wallpaper, widget, …
```

> **DMS a déjà une cible IPC `systemupdater`** (`close, open, toggle,
> updatestatus`). À examiner avant d'écrire `eschaton-dms-plugin-update` : le
> plugin doit s'y brancher ou assumer de la doubler.

### 12.5 Preuve visuelle et méthode de capture

**La méthode retenue est la capture *dans l'invité*, pas depuis le Mac.** Elle
ne demande aucune permission de l'hôte, produit exactement ce que le
compositeur affiche, et se vérifie par empreinte :

```bash
# dans la VM (session Wayland exportée, cf. §12.3)
dms screenshot output -o Virtual-1 -d ~ --filename spike.png \
    --no-clipboard --no-notify
sha256sum ~/spike.png

# depuis le Mac — la ligne série suffit, l'image passe en base64
tools/vm-serial run --timeout 300 "base64 -w 200 /home/seylar/spike.png" > b64.raw
sed -e '1d' -e '$d' b64.raw | tr -d '\n ' | base64 -d > spike.png
shasum -a 256 spike.png        # doit égaler le sha256sum de l'invité
```

Vérifié : 79 110 octets, `PNG image data, 1280 x 800`, empreinte identique des
deux côtés (`dfcf2db8a16c…`). Une capture de ~80 Kio passe en quelques secondes.

Ce que montrent les captures : barre supérieure (grille d'applications, pastille
d'espace de travail, horloge, météo, tray, CPU/RAM, notifications, batterie,
réseau, volume) ; Control Center complet (avatar, uptime, verrouillage/extinction/
réglages, curseurs volume et luminosité, tuiles Ethernet « Connecté » / Bluetooth
« Aucun adaptateur », bascules Mode nuit / Mode sombre) ; lanceur avec champ de
recherche, liste d'applications avec icônes SVG, onglets *Tous / Applis /
Fichiers / **Plugins*** ; fond d'écran DMS. Coins arrondis, translucidité,
antialiasing et localisation `fr` corrects.

**La capture de la fenêtre UTM depuis le Mac** est possible mais **exige une
permission que l'agent ne peut pas s'accorder** :

```bash
osascript -e 'tell application "UTM" to activate' \
          -e 'tell application "System Events" to tell process "UTM" to \
              perform action "AXRaise" of window "eschaton-dev"'
osascript -e 'tell application "System Events" to tell process "UTM" to \
              get {position, size} of window "eschaton-dev"'
#   → 140, 53, 1280, 840      (840 = 800 + la barre de titre)
screencapture -x -R140,53,1280,840 utm-window.png
#   → could not create image from rect
```

Le nom de la fenêtre est le nom de la VM (`window "eschaton-dev"` — attention,
`window 1` échoue, UTM en ouvre plusieurs). `screencapture` échoue tant que
**Réglages Système → Confidentialité et sécurité → Enregistrement de l'écran**
n'autorise pas le terminal ; c'est un réglage de sécurité à accorder à la main.
En pratique, la méthode de l'invité rend celle-ci inutile.

### 12.6 Ce que le spike corrige dans la spec Bureau

1. **`QSG_RHI_BACKEND=software` (risque n° 1) n'existe pas.** Qt 6.11 le refuse :

   ```console
   WARN: Unknown key "software" for QSG_RHI_BACKEND, falling back to default backend.
   ```

   La variable ne nomme que des back-ends RHI (`vulkan`, `metal`, `d3d11`,
   `d3d12`, `opengl`, `null`) : aucun n'est un rendu logiciel. Le vrai repli
   logiciel de Qt Quick est **`QT_QUICK_BACKEND=software`**
   — testé, il démarre et rend barre et Control Center, **mais perd l'image du
   fond d'écran** (le rendu logiciel ne fait pas les effets). C'est un repli
   dégradé, pas l'égal du chemin nominal.

   Chemin nominal mesuré (`QSG_INFO=1`, sans aucune variable) :

   ```console
   qt.scenegraph.general: Creating QRhi with backend OpenGL for window …
     Prefer software device: 0
   ```

2. **`dms setup` possède `hyprland.lua`, pas seulement `~/.config/hypr/dms/`**
   (risque n° 4 et règle de propriété §4.2). Mesuré en plantant des marqueurs
   puis en relançant `dms setup` avec les mêmes réponses :

   | Fichier | Sort |
   |---|---|
   | `~/.config/hypr/hyprland.lua` | **régénéré** — la ligne ajoutée a disparu ; l'ancien est sauvé sous `~/.config/hypr/.dms-backups/<horodatage>/hyprland.lua`, et l'outil annonce « Successfully merged existing monitor sections » |
   | `~/.config/hypr/dms/binds.lua` | **« Updated »** — réécrit sans condition |
   | les six autres `dms/*.lua` | **« Skipping … (already exists) »** — le marqueur survit |
   | `~/.config/hypr/eschaton.lua` (fichier étranger, hors `dms/`) | **intact** |

   Conséquence pour la Task 3 : le `hyprland.lua` « de 3 lignes » posé par
   `/etc/skel` **ne survit pas** à un `dms setup` ultérieur. Soit Eschaton ne
   fait jamais tourner `dms setup` complet après le premier démarrage (et déploie
   l'arbre `dms/` par les sous-commandes `dms setup binds|colors|layout|…`), soit
   il assume que l'utilisateur qui le lance perd son point d'entrée — sauvegarde
   à l'appui.

3. **`start-hyprland` est le lanceur amont, et il sait passer `-c`.** Hyprland
   avertit à chaque démarrage direct (« Hyprland is being launched without
   start-hyprland. This is highly advised against »), et l'entrée de session
   packagée (`/usr/share/wayland-sessions/hyprland.desktop`) lance
   `/usr/bin/start-hyprland`. L'invariant §4.1 s'écrit donc
   **`start-hyprland -- -c <chemin du lua>`** (« Any arguments after -- are
   passed to Hyprland »). Au passage, l'invariant est confirmé côté Hyprland :
   `[cfg] Config is lua, loading lua mgr`.

4. **`dms doctor` ne reconnaît pas Eschaton** : `Operating System ····· Eschaton
   (not supported by dms setup)`. Conséquence directe de l'`ID=eschaton`
   d'`eschaton-branding`. Le déploiement des configs a fonctionné quand même,
   mais l'amont ne le garantit pas.

### 12.7 Ce que `dms setup` crée exactement (interface des Tasks 2 et 3)

`dms setup` est **interactif** et demande, dans l'ordre : outil d'élévation
(`sudo` / `run0` — court-circuitable par `DMS_PRIVESC=`), compositeur
(Niri / Hyprland / Mango / None), terminal (Ghostty / Kitty / Alacritty / None),
gestion de session systemd (oui / non), puis confirmation. Il **ajoute d'office
l'utilisateur au groupe `input`** (« for Caps Lock OSD support »), et **déploie
une configuration Ghostty même quand on répond « None »** au terminal.

Sur un `$HOME` vierge, il crée exactement :

```
~/.config/hypr/hyprland.lua          2990 o, 90 l.  point d'entrée, généré par DMS
~/.config/hypr/dms/binds.lua         9762 o, 171 l. réécrit à chaque setup
~/.config/hypr/dms/binds-user.lua      85 o         surcharges utilisateur (préservé)
~/.config/hypr/dms/colors.lua         614 o         « Auto-generated … do not edit »
~/.config/hypr/dms/cursor.lua          71 o
~/.config/hypr/dms/layout.lua         170 o         « Auto-generated by DMS »
~/.config/hypr/dms/outputs.lua        215 o         hl.monitor({ output = "", mode = "preferred", … })
~/.config/hypr/dms/windowrules.lua     66 o
~/.config/ghostty/config                            (même si terminal = None)
~/.config/ghostty/themes/dankcolors
~/.config/hypr/.dms-backups/<horodatage>/           (créé seulement au 2e passage)
```

`hyprland.lua` n'est **pas** un fichier de 3 lignes : c'est la configuration DMS
complète (entrées, général, décoration, animations, règles de fenêtres), encadrée
par des marqueurs `-- DMS_STARTUP_BEGIN` / `-- DMS_STARTUP_END` autour du bloc
d'amorçage, et terminée par les `require` :

```lua
hl.config({ autogenerated = false })
-- DMS_STARTUP_BEGIN
hl.on("hyprland.start", function()
	hl.exec_cmd("dbus-update-activation-environment --systemd --all")
	hl.exec_cmd("systemctl --user start hyprland-session.target")
end)
-- DMS_STARTUP_END
…
require("dms.colors") ; require("dms.outputs") ; require("dms.layout")
require("dms.cursor") ; require("dms.binds")   ; require("dms.binds-user")
require("dms.windowrules")
```

La racine des `require` est `~/.config/hypr/` (`dms.colors` → `dms/colors.lua`).

Côté systemd, `dms-shell` fournit `/usr/lib/systemd/user/dms.service` :
`Type=dbus`, `BusName=org.freedesktop.Notifications`,
`ExecStart=/usr/bin/dms run --session`, `WantedBy=graphical-session.target`,
`Requisite=graphical-session.target`. Il est **désactivé** par défaut
(`dms doctor` : `dms.service ·········· Disabled`) — c'est à
`eschaton-desktop-config` de le mettre au préset. `dms-shell-hyprland` est un
méta-paquet **sans aucun fichier**.

### 12.8 Inventaire réellement installé (Task 3 : depends à figer)

Installation : `pacman -S --noconfirm hyprland dms-shell-hyprland pipewire
wireplumber xdg-desktop-portal-hyprland ttf-jetbrains-mono-nerd noto-fonts`
→ **112 paquets, 230,47 Mio téléchargés, 1 165,86 Mio installés, en moins de
45 s** (snapshots snapper pre/post compris).

```
hyprland 0.56.1-3                 dms-shell 1.5.3-1
dms-shell-hyprland 1.5.3-1        quickshell 0.3.1-1
dgop 0.2.3-1                      pipewire 1:1.6.8-1
wireplumber 0.5.15-1              xdg-desktop-portal-hyprland 1.4.1-1
xdg-desktop-portal 1.22.1-2       ttf-jetbrains-mono-nerd 3.5.1-2
noto-fonts 1:2026.08.01-1         mesa 1:26.2.1-1
qt6-base 6.11.2-2                 qt6-declarative 6.11.2-1
qt6-wayland 6.11.2-1              qt6-svg 6.11.2-1
seatd 0.9.3-1                     aquamarine 0.14.0-2
wayland 1.26.0-1                  libinput 1.31.3-1
hyprlang 0.6.8-5                  hyprutils 0.14.1-1
hyprgraphics 0.5.1-4              hyprcursor 0.1.13-7
xorg-xwayland 24.1.13-1           llvm-libs 22.1.8-2
```

Tout vient de `extra` d'ALARM, en binaires natifs aarch64 — la veille est
confirmée, aucun vendoring. `hyprland` est bien en **0.56.1** côté ALARM (Arch
est en 0.56.2) : le risque n° 7 de la spec est réel mais sans effet ici.
`seatd` arrive par `aquamarine` (dépendance d'`hyprland`), il n'a pas à être
ajouté aux `depends` d'`eschaton-desktop`. `hyprlang` est encore là malgré la
config Lua.

> **Amendement du 2026-08-28 (Task 3) : cet inventaire est INCOMPLET côté audio.**
> Le paquet `pipewire` ne livre aucun greffon SPA audio — son
> `/usr/lib/spa-0.2/` ne contient que `control`, `support`, `v4l2`,
> `videoconvert` et `videotestsrc`. `libspa-alsa.so` et les codecs bluez5 sont
> dans **`pipewire-audio`**, que ni `pipewire` ni `wireplumber` ne tirent
> (relevé dans les index des deux dépôts, `pacman -Fl`). La pile du spike était
> donc **dépourvue de tout back-end de périphérique audio** : « Aucun appareil de
> sortie » n'est pas seulement le `-audio none` de QEMU (§12.9, §13.3), c'est
> aussi — et de façon certaine, elle, puisqu'elle vaut sur toute machine — le jeu
> de paquets. `eschaton-desktop` ajoute `pipewire-pulse`, qui tire
> `pipewire-audio` en dépendance dure et fournit en plus le serveur d'API
> PulseAudio des applications ordinaires (le Control Center de DMS, lui, parle le
> protocole PipeWire natif par Quickshell). Reste à vérifier sur matériel réel
> (Task 7) : la VM ne peut pas trancher, elle n'a pas de carte son.

### 12.9 Ce que le spike n'a pas prouvé

- **Cinq « Quickshell Features » manquent au build `extra` — dont `Polkit`.**
  C'est l'inconnue la plus lourde léguée à la Task 2. `dms doctor` sur
  `quickshell 0.3.1-1` (`Quickshell 0.3.1 (revision , distributed by Arch
  Linux)`) rend :

  ```
    Quickshell Features
      ○ Polkit ··············· Not available
      ○ IdleMonitor ·········· Not available
      ○ IdleInhibitor ········ Not available
      ○ ShortcutInhibitor ···· Not available
      ○ BackgroundBlur ······· Not available
    …
    → Consider using quickshell-git for full feature support
  ```

  Celle qui compte est **`Polkit`** : la spec Bureau §3 fait passer la
  restauration d'`eschaton-dms-plugin-rollback` « derrière polkit », et le
  conseil de l'amont — `quickshell-git` — est précisément ce que le risque n° 2
  interdit (politique « `extra/dms-shell` uniquement, jamais `-git` »). Les deux
  contraintes se croisent ici, et le spike ne les départage pas.

  **Attention, deux mesures qui ne se contredisent pas** : le *module Quickshell*
  `Polkit` est absent du build `extra`, alors que le *service DMS* du même nom
  démarre sans erreur (`INFO qml: [PolkitService:25] Initialized successfully`).
  Ce sont deux objets distincts. À trancher en Task 2, avant d'écrire le
  plugin : **lequel des deux un plugin DMS utilise réellement pour élever un
  privilège**, et si c'est le module Quickshell, quelle surface le remplace
  (helper dédié, `pkexec`, ou service D-Bus maison — les trois options que la
  spec §3 laisse ouvertes au risque n° 5). Les quatre autres features absentes
  ne touchent aucun livrable v1 : `IdleMonitor`/`IdleInhibitor` et
  `ShortcutInhibitor` relèvent du verrouillage et des raccourcis globaux (non-buts
  v1, différés SP4), `BackgroundBlur` est cosmétique — et de toute façon
  indisponible sans GL matériel (§12.2).

  > **Réserve levée le 2026-08-28 (Task 2) : la ligne `Polkit ····· Not
  > available` de `dms doctor` est un FAUX NÉGATIF.** Le greffon
  > `Quickshell_Services_PolkitPlugin` est bien lié dans le `/usr/bin/qs` du
  > paquet `extra`, l'agent d'authentification de DMS s'enregistre auprès de
  > `polkitd`, affiche sa modale, et une élévation aboutit :
  >
  > ```console
  > $ pkcheck --action-id org.freedesktop.policykit.exec --process $$ --allow-user-interaction
  > polkit\56result=auth_admin          → rc=0 après saisie du mot de passe
  > $ pkcheck --action-id org.freedesktop.policykit.exec --process $$
  > Authorization requires authentication and -u wasn't passed.   → rc=2
  > ```
  >
  > Mesuré deux fois : dans la session du spike, puis dans la vraie session
  > greetd du §13. Mauvais mot de passe → la modale reste ouverte, `pkcheck` ne
  > rend jamais la main (rc=124 par `timeout`). Détail et captures dans le
  > rapport de la Task 2. **Aucun agent polkit externe n'est à empaqueter.**
- **Le chemin de session réel.** Le spike démarre le compositeur depuis la
  console série avec `seatd` lancé à la main. Le produit passera par
  `greetd` + auto-login sur une VT, donc par le *seat* de logind : la question
  du siège disparaît, mais `LIBGL_ALWAYS_SOFTWARE=1` devra être posé dans
  l'entrée de session (Task 3). Rien ici ne dit *où* le poser.
- **Le rendu sur le vrai balayage écran.** Toutes les preuves passent par
  `wlr-screencopy` (`dms screenshot`), pas par une photo du framebuffer. Le
  scan-out direct est de toute façon désactivé (`directScanoutBlockedBy:
  software renders/cursors`).
- **PipeWire.** `ERROR quickshell.service.pipewire.loop: Failed to connect
  pipewire context. Errno: 112` — les unités utilisateur de PipeWire ne sont pas
  démarrées. Le Control Center affiche « Aucun appareil de sortie ». À traiter
  par le préset d'`eschaton-desktop-config`, pas un problème de rendu.
  *(Réserve levée le 2026-08-28, Task 2 : c'était l'absence de session logind,
  pas une affaire de préset — voir §13.3. Sous greetd, `pipewire.service` et
  `wireplumber.service` sont `running` sans rien ajouter.)*
- **La fluidité au sens strict.** Aucun compteur d'images mesuré : le constat est
  « 0 % de CPU au repos, ouverture du Control Center et du lanceur immédiates,
  aucun artefact sur les captures ».
- **Le matériel réel.** Sur une machine avec un GPU, `LIBGL_ALWAYS_SOFTWARE=1`
  serait une régression. Ce n'est pas un réglage à mettre dans le paquet — c'est
  un réglage de la **VM**.
- **La VM n'est pas nettoyée** (choix assumé du brief) : la pile est installée à
  la main, `seatd` tourne hors systemd, `~/.config/hypr` contient l'arbre de
  `dms setup` et un `eschaton.lua` de test. La Task 7 réinstallera par paquets
  par-dessus.

## 13. Session graphique par greetd (SP2, Task 2)

Déroulé le 2026-08-28, toujours par la console série, avec le paquet
`eschaton-desktop-config` 0.1.0-1 installé par `pacman -U`. La VM démarre
désormais **sur le bureau** : `greetd` est `enabled` (le préset livré par le
paquet a été appliqué par `systemctl preset greetd.service`, qui crée
`/etc/systemd/system/display-manager.service → greetd.service`).

### 13.1 Le réglage de banc d'essai à poser dans le greetd de LA VM

`LIBGL_ALWAYS_SOFTWARE=1` reste indispensable au compositeur sous ce
virtio-gpu sans virgl (§12.2), et reste **hors des paquets** : sur une machine
dotée d'un GPU ce serait une régression. La VM le porte dans son propre
`/etc/eschaton/greetd.toml` — un fichier `backup=`, donc modifiable sans que
pacman le reprenne :

```toml
[initial_session]
command = "env LIBGL_ALWAYS_SOFTWARE=1 /usr/bin/eschaton-session"
user = "seylar"
```

(Le fichier livré par le paquet dit `command = "/usr/bin/eschaton-session"` ;
seul le préfixe `env …` est propre à la VM. greetd n'a pas de section
d'environnement : `env` est le moyen d'en poser un.) Après édition :

```bash
sudo rm -f /run/greetd.run && sudo systemctl restart greetd
```

### 13.2 Piège : l'auto-login ne rejoue pas sur un simple `restart`

greetd retient dans `/run/greetd.run` qu'il a déjà déroulé son
`[initial_session]`. Un `systemctl restart greetd` **retombe donc sur
`[default_session]`** — chez nous `agreety`, le greeter texte, qui attend un
identifiant sur le VT 1 et ne peut pas être piloté depuis la console série. Le
journal le dit franchement :

```console
$ journalctl -u greetd | tail -3
greetd[18587]: pam_unix(greetd:session): session opened for user greeter(uid=965)
```

Supprimer `/run/greetd.run` avant le `restart` (ou redémarrer la VM) rejoue
l'auto-login :

```console
$ sudo rm -f /run/greetd.run && sudo systemctl restart greetd && sleep 18
$ ps -eo user,pid,comm | grep -E 'Hyprland|qs'
seylar     19382 Hyprland
seylar     19410 qs
```

### 13.3 Ce que la session greetd corrige par rapport au spike

- **Plus de `seatd` à la main.** greetd ouvre une session logind sur `seat0` /
  `tty1` ; `libseat` prend son back-end logind tout seul. Le contournement du
  §12.3 n'a plus lieu d'être.
- **PipeWire démarre.** La réserve du §12.9 tombe : dans une vraie session
  utilisateur, `pipewire.service` et `wireplumber.service` sont `running` sans
  qu'aucun préset d'Eschaton n'ait à s'en mêler. Le Control Center affiche
  toujours « Aucun appareil de sortie » — attribué ici au matériel de la VM
  (`-audio none` côté QEMU). *(Amendé le 2026-08-28, Task 3 : ce n'est pas la
  seule cause, ni même la cause suffisante — la pile installée n'avait aucun
  back-end de périphérique audio, `pipewire-audio` n'étant tiré ni par
  `pipewire` ni par `wireplumber`. Voir l'amendement du §12.8.)*
- **`dms.service` est supervisé.** `hyprland-session.target` (livré par
  `eschaton-desktop-config`, absent du paquet `hyprland`) tire
  `graphical-session.target`, qui tire `dms.service`.

```console
$ systemctl --user is-active hyprland-session.target graphical-session.target dms.service
active
active
active
```

> **Lecture trompeuse.** `systemctl --user list-unit-files dms.service` affiche
> encore `disabled` : cet état ne regarde que les liens de `/etc/systemd/user/`
> et de `~/.config/systemd/user/`, pas le `.wants` livré sous `/usr/lib`. La
> preuve utile est
> `systemctl --user show graphical-session.target -p Wants` → `dms.service`.

### 13.4 Injecter des frappes dans la session (utile aux tâches 7–9)

Aucun dispatcher `hyprctl` ne tape du texte, et `sendshortcut` ne vise que des
fenêtres — pas les surfaces layer-shell de DMS, qui portent justement les
modales. Le moyen qui marche est **`wtype`** (`extra`, 0.4-2, protocole
virtual-keyboard) :

```bash
export WAYLAND_DISPLAY=wayland-1
wtype 'eschaton'; wtype -k Return
```

C'est un outil de banc d'essai, installé à la main dans la VM ; il n'entre dans
les `depends` d'aucun paquet Eschaton.

### 13.5 Pousser un fichier de l'hôte vers la VM par la console série

Le §12.5 documente le sens invité → hôte. Le sens inverse tient au même
procédé, en morceaux (la ligne canonique de l'invité plafonne à 4096 caractères ;
480 passent sans risque) :

```bash
b64=$(base64 < paquet.pkg.tar.xz | tr -d '\n')
# pour chaque morceau de 480 caractères :
tools/vm-serial send "printf %s '<morceau>' >> /tmp/paquet.b64"
tools/vm-serial run "base64 -d /tmp/paquet.b64 > /tmp/paquet.pkg.tar.xz; sha256sum /tmp/paquet.pkg.tar.xz"
```

8 Kio (24 morceaux) passent en une vingtaine de secondes, empreinte vérifiée
des deux côtés.
