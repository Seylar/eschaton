#!/usr/bin/env bats
#
# Garde-fous du profil archiso (SP4b-1, Task 1).
#
# Ce fichier ne construit rien : construire l'ISO coûte des dizaines de minutes
# et un conteneur x86_64. Il verrouille en revanche les invariants qu'une
# modification distraite du profil ferait sauter en silence — et dont la panne
# n'apparaîtrait qu'au démarrage du média, voire plus tard.
#
# Les assertions travaillent par `grep` et jamais en sourçant profiledef.sh :
# ce fichier appelle `date --date=@…` (GNU) et déclare un tableau associatif,
# deux choses que le bash 3.2 de macOS ne sait pas faire.

setup() {
  PROFIL="$BATS_TEST_DIRNAME/../iso/eschaton"
  AIROOTFS="$PROFIL/airootfs"
}

paquets() { grep -vE '^[[:space:]]*(#|$)' "$PROFIL/packages.x86_64"; }

@test "le profil embarque iwd et surtout PAS wpa_supplicant" {
  # `releng` embarque les deux. La veille T2 documente une régression de
  # wpa_supplicant 2.11 : sa présence sur le média est un défaut, pas un extra.
  run paquets
  [[ "$output" == *"iwd"* ]]
  ! grep -qx 'wpa_supplicant' <(paquets)
}

@test "les dépendances directes d'eschaton-install sont embarquées" {
  # Exactement les paquets que la procédure vérifiée installait à la main dans
  # un live env tiers (tools/vm-dev.md §8.2). En manquer un rend le média
  # inutilisable pour ce qu'il est censé faire.
  for p in arch-install-scripts gptfdisk btrfs-progs dosfstools; do
    grep -qx "$p" <(paquets) || { echo "paquet manquant : $p"; return 1; }
  done
}

@test "les outils de secours exigés par la spec §3.3 sont embarqués" {
  for p in snapper btrfs-progs limine; do
    grep -qx "$p" <(paquets) || { echo "outil de secours manquant : $p"; return 1; }
  done
}

@test "le média est UEFI seulement, et rien ne traîne du chemin BIOS" {
  grep -q "^bootmodes=('uefi.systemd-boot')" "$PROFIL/profiledef.sh"
  ! grep -q 'bios.syslinux' "$PROFIL/profiledef.sh"
  # `syslinux` n'a plus de raison d'être ni dans la liste ni dans le profil.
  ! grep -qx 'syslinux' <(paquets)
  [ ! -d "$PROFIL/syslinux" ]
}

@test "les crochets PXE de mkinitcpio sont retirés en même temps que leur paquet" {
  # Garder un crochet archiso_pxe_* sans `mkinitcpio-nfs-utils` fait échouer la
  # génération de l'initramfs — donc toute la construction, mais tardivement.
  ! grep -q 'archiso_pxe' "$AIROOTFS/etc/mkinitcpio.conf.d/archiso.conf"
  ! grep -qx 'mkinitcpio-nfs-utils' <(paquets)
  # …et le crochet `archiso` lui-même reste là, sans quoi le média ne démarre pas.
  grep -qE '^HOOKS=\(.* archiso .*\)' "$AIROOTFS/etc/mkinitcpio.conf.d/archiso.conf"
}

@test "le crochet memdisk n'est pas là sans le paquet qui fournit memdiskfind" {
  # Constat du 2026-08-29 : `memdisk` appelle `memdiskfind`, livré par
  # `syslinux`. Retiré avec le chemin BIOS, il faisait échouer mkinitcpio — SANS
  # faire échouer la construction, qui produisait une image à l'initramfs amputé.
  # C'est le couplage qu'on verrouille, pas seulement l'absence de `memdisk`.
  if grep -qE '^HOOKS=\(.* memdisk .*\)' "$AIROOTFS/etc/mkinitcpio.conf.d/archiso.conf"; then
    grep -qx 'syslinux' <(paquets) || {
      echo "crochet memdisk présent sans le paquet syslinux (memdiskfind)"; return 1; }
  fi
  # Et la garde qui a attrapé le cas reste dans le script de construction.
  grep -q 'errors were encountered during the build' "$BATS_TEST_DIRNAME/../iso/build-iso"
}

@test "le dépôt [eschaton] est préconfiguré des DEUX côtés (construction et live)" {
  grep -q '^\[eschaton\]' "$PROFIL/pacman.conf"
  grep -q '^\[eschaton\]' "$AIROOTFS/etc/pacman.conf"
  # Une seule URL de dépôt dans tout le profil, et c'est celle du Socle §5.3.
  grep -q 'Server = https://seylar.github.io/eschaton/\$arch' "$PROFIL/pacman.conf"
  grep -q 'Server = https://seylar.github.io/eschaton/\$arch' "$AIROOTFS/etc/pacman.d/eschaton-mirror"
  grep -q 'Include = /etc/pacman.d/eschaton-mirror' "$AIROOTFS/etc/pacman.conf"
}

@test "la place du trousseau SP4a est réservée et repérable" {
  # Tant que SP4a n'est pas livré, le dépôt est en Optional TrustAll. Le jour où
  # il l'est, ce sont ces DEUX lignes qui changent — et le repère « SP4a » est ce
  # qui permet de les retrouver toutes les deux. Ce test protège le repère.
  grep -q '^SigLevel = Optional TrustAll' "$PROFIL/pacman.conf"
  grep -q '^SigLevel = Optional TrustAll' "$AIROOTFS/etc/pacman.conf"
  grep -q 'SP4a' "$PROFIL/pacman.conf"
  grep -q 'SP4a' "$AIROOTFS/etc/pacman.conf"
  # Et le script de construction sait déjà importer la clé quand elle arrivera.
  grep -q 'pacman-key --lsign-key' "$BATS_TEST_DIRNAME/../iso/build-iso"
}

@test "le profil ne contient AUCUNE copie de l'installeur" {
  # Source unique de vérité : installer/. `iso/build-iso` l'y dépose au moment
  # de construire, dans une copie de travail. Une copie versionnée ici
  # divergerait sans que rien ne le signale.
  [ ! -e "$AIROOTFS/usr/local/bin/eschaton-install" ]
  [ ! -e "$AIROOTFS/usr/local/bin/lib.sh" ]
  grep -q 'install -Dm755 .*installer/eschaton-install' "$BATS_TEST_DIRNAME/../iso/build-iso"
  grep -q 'install -Dm644 .*installer/lib.sh' "$BATS_TEST_DIRNAME/../iso/build-iso"
  # …et le profil déclare les permissions des deux fichiers qu'il recevra.
  grep -q '"/usr/local/bin/eschaton-install"\]="0:0:755"' "$PROFIL/profiledef.sh"
}

@test "install_dir tient dans les 8 caractères que mkarchiso autorise" {
  valeur="$(sed -n 's/^install_dir="\([a-z0-9]*\)".*/\1/p' "$PROFIL/profiledef.sh")"
  [ -n "$valeur" ]
  [ "${#valeur}" -le 8 ]
}

@test "l'entrée d'amorçage par défaut existe et porte la console série" {
  # `[[:space:]][[:space:]]*` et non `\+` : le sed de macOS ne connaît pas `\+`
  # en expression rationnelle basique, et ces tests tournent aussi sur le Mac.
  defaut="$(sed -n 's/^default[[:space:]][[:space:]]*//p' "$PROFIL/efiboot/loader/loader.conf")"
  [ -f "$PROFIL/efiboot/loader/entries/$defaut" ]
  # La console série est ce qui rend le média pilotable en VM sans repatcher
  # l'image à l'octet (tools/vm-dev.md §10.3).
  grep -q 'console=ttyS0,115200' "$PROFIL/efiboot/loader/entries/$defaut"
  # …et l'auto-connexion série va avec, sinon la console s'arrête sur un login.
  grep -q 'autologin root' "$AIROOTFS/etc/systemd/system/serial-getty@.service.d/autologin.conf"
  # Une entrée de repli sans console série reste offerte.
  ! grep -q 'console=ttyS0' "$PROFIL/efiboot/loader/entries/02-eschaton-sans-serie.conf"
}

@test "sshd est livré mais pas activé" {
  # Décision (veille §1, ligne 9) : un média qui ouvre un port en écoute dès le
  # démarrage est un choix, pas un défaut de configuration. `releng` l'active.
  grep -qx 'openssh' <(paquets)
  [ ! -e "$AIROOTFS/etc/systemd/system/multi-user.target.wants/sshd.service" ]
  [ ! -e "$AIROOTFS/etc/systemd/system/sockets.target.wants/sshd.socket" ]
}

@test "le générateur GPT automatique de systemd est masqué" {
  # Sans ce masquage, systemd peut monter tout seul des partitions trouvées sur
  # les disques — y compris l'ESP de la machine qu'on s'apprête à effacer.
  lien="$AIROOTFS/etc/systemd/system-generators/systemd-gpt-auto-generator"
  [ -L "$lien" ]
  [ "$(readlink "$lien")" = "/dev/null" ]
}

@test "les crochets pacman de construction portent le marqueur qui les fait disparaître" {
  # Sans « remove from airootfs », le crochet zzzz99 ne les retire pas de l'image
  # et ils s'exécutent pendant le `pacstrap` que l'installeur lance vers /mnt.
  for h in "$AIROOTFS"/etc/pacman.d/hooks/*.hook; do
    head -1 "$h" | grep -q 'remove from airootfs' || { echo "marqueur absent : $h"; return 1; }
  done
}
