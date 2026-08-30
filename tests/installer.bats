#!/usr/bin/env bats
setup() { source "$BATS_TEST_DIRNAME/../installer/lib.sh"; }

@test "kernel_pkgs_for aarch64" {
  run kernel_pkgs_for aarch64
  [ "$output" = "linux-aarch64" ]
}

@test "kernel_pkgs_for x86_64 inclut kernel et microcodes candidats" {
  run kernel_pkgs_for x86_64
  [ "$output" = "linux intel-ucode amd-ucode" ]
}

@test "keyring_pkgs_for donne le trousseau de l'architecture" {
  run keyring_pkgs_for aarch64
  [ "$output" = "archlinuxarm-keyring" ]
  run keyring_pkgs_for x86_64
  [ "$output" = "archlinux-keyring" ]
}

@test "le dry-run contient le déroulé complet dans l'ordre" {
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --hostname eschaton --user seylar
  [ "$status" -eq 0 ]
  [[ "$output" == *"sgdisk --zap-all /dev/vda"* ]]
  [[ "$output" == *"-n1:0:+4G"*  ]]              # ESP 4 Gio
  [[ "$output" == *"mkfs.btrfs"* ]]
  for sv in @ @home @log @pkg @snapshots; do [[ "$output" == *"subvolume create /mnt/$sv"* ]]; done
  [[ "$output" == *"pacstrap"* && "$output" == *"eschaton-base"* ]]
  [[ "$output" == *"genfstab"* ]]
  [[ "$output" == *"limine"* ]]
  [[ "$output" == *"cp /usr/share/eschaton/os-release /etc/os-release"* ]]
  [[ "$output" == *"Include = /etc/pacman.d/eschaton.conf"* ]]   # le système cible connaît [eschaton]
}

# Les deux assertions ci-dessous verrouillent des pannes SILENCIEUSES
# constatées à la Task 9 : le système démarrait, mais amputé.

@test "le trousseau de l'architecture est installé par pacstrap" {
  # Sans lui, la première mise à jour échoue sur « confiance inconnue ».
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar
  [[ "$output" == *"pacstrap"*"keyring"* ]]
  [[ "$output" == *"pacman-key --init && pacman-key --populate"* ]]
}

@test "os-release est délié avant d'être écrit" {
  # Sinon le cp suit le lien et écrase /usr/lib/os-release (paquet filesystem).
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar
  [[ "$output" == *"rm -f /etc/os-release && cp /usr/share/eschaton/os-release /etc/os-release"* ]]
}

@test "limine.conf imbrique le kernel sous l'entrée OS (exigence limine-snapper-sync)" {
  # Une entrée plate démarre, mais n'obtient JAMAIS d'entrée de snapshot.
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar
  [[ "$output" == *"/Eschaton"* ]]
  [[ "$output" == *"//linux"* ]]        # sous-entrée de kernel (linux / linux-aarch64)
  [[ "$output" == *"//Snapshots"* ]]    # ancre des entrées de snapshot
  # Sans default_entry, le sous-menu n'est pas amorçable et Limine reste dessus.
  [[ "$output" == *"default_entry: Eschaton/linux"* ]]
}

# --- différés d'installeur routés au SP4 (bilan du Socle §18) -----------------

@test "une option de valeur en DERNIER token rend un message utile, pas « unbound variable »" {
  # Sous `set -u`, consommer $2 quand il n'existe pas fait échouer bash avec un
  # message qui n'apprend rien à celui qui installe.
  for opt in --disk --user --hostname; do
    run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run "$opt"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$opt attend un argument"* ]]
    [[ "$output" != *"unbound variable"* ]]
  done
}

@test "valider_utilisateur n'accepte qu'un nom de compte conforme à useradd" {
  run valider_utilisateur seylar;     [ "$status" -eq 0 ]
  run valider_utilisateur _service;   [ "$status" -eq 0 ]
  run valider_utilisateur a-b_c9;     [ "$status" -eq 0 ]

  run valider_utilisateur "";                    [ "$status" -eq 1 ]
  run valider_utilisateur "Seylar";              [ "$status" -eq 1 ]   # majuscule
  run valider_utilisateur "9vies";               [ "$status" -eq 1 ]   # chiffre en tête
  run valider_utilisateur "-rf";                 [ "$status" -eq 1 ]   # ressemble à une option
  run valider_utilisateur "a b";                 [ "$status" -eq 1 ]
  # Le nom finit dans une commande privilégiée : l'injection doit être refusée.
  run valider_utilisateur 'x; rm -rf /';         [ "$status" -eq 1 ]
  run valider_utilisateur 'x$(id)';              [ "$status" -eq 1 ]
  run valider_utilisateur "$(printf 'a%.0s' {1..33})"; [ "$status" -eq 1 ]  # 33 signes
}

@test "valider_hote n'accepte qu'une étiquette RFC 1123" {
  run valider_hote eschaton;      [ "$status" -eq 0 ]
  run valider_hote mac-de-seylar; [ "$status" -eq 0 ]
  run valider_hote a;             [ "$status" -eq 0 ]

  run valider_hote "";                     [ "$status" -eq 1 ]
  run valider_hote "-eschaton";            [ "$status" -eq 1 ]   # tiret en tête
  run valider_hote "eschaton-";            [ "$status" -eq 1 ]   # tiret en queue
  run valider_hote "esch aton";            [ "$status" -eq 1 ]
  run valider_hote "eschaton.local";       [ "$status" -eq 1 ]   # /etc/hostname n'est pas un FQDN
  run valider_hote 'x'"'"'; rm -rf /; #';  [ "$status" -eq 1 ]   # apostrophe : ancienne interpolation
  run valider_hote "$(printf 'a%.0s' {1..64})"; [ "$status" -eq 1 ]  # 64 signes
}

@test "l'installeur refuse un utilisateur ou un hôte invalide AVANT d'écrire quoi que ce soit" {
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user 'x; rm -rf /'
  [ "$status" -eq 1 ]
  [[ "$output" == *"nom d'utilisateur invalide"* ]]
  [[ "$output" != *"sgdisk"* ]]      # rien n'a été planifié, même en dry-run

  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar --hostname "-x"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nom d'hôte invalide"* ]]
  [[ "$output" != *"sgdisk"* ]]
}

@test "le partitionnement attend l'apparition des noeuds de partition" {
  # Le noyau relit la table de façon asynchrone : sans attente, le mkfs qui suit
  # échoue par intermittence sur du matériel réel.
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar
  [[ "$output" == *"udevadm settle"* ]]
  [[ "$output" == *"attendre_bloc /dev/vda1"* ]]
  [[ "$output" == *"attendre_bloc /dev/vda2"* ]]
  # …et l'attente précède bien le formatage.
  attente="$(printf '%s\n' "$output" | grep -n 'attendre_bloc /dev/vda1' | head -1 | cut -d: -f1)"
  format="$(printf '%s\n' "$output" | grep -n 'mkfs.vfat' | head -1 | cut -d: -f1)"
  [ "$attente" -lt "$format" ]
}

@test "attendre_bloc abandonne sur un délai borné plutôt que d'attendre indéfiniment" {
  run attendre_bloc /dev/eschaton-inexistant 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"n'est pas apparu"* ]]

  # Le délai est respecté : 1 s demandée, on tolère largement, mais pas l'infini.
  debut="$SECONDS"
  run attendre_bloc /dev/eschaton-inexistant 1
  [ "$status" -eq 1 ]
  [ "$((SECONDS - debut))" -lt 5 ]
}

# --- la garde --disk : elle doit tenir ce qu'elle promet ----------------------
#
# `[[ -b ]]` ne distingue PAS un disque entier d'une partition, d'un volume LVM
# ou d'un lien /dev/disk/by-id/… — le test suit les liens. Et le
# `sgdisk --zap-all` s'exécutait AVANT que les noms de partition dérivés ne
# soient confrontés au réel : pour ces trois cas, l'installeur détruisait
# d'abord et abandonnait ensuite.
#
# Ces tests ont besoin d'un vrai périphérique bloc (le `[[ -b ]]` doit passer)
# et d'un `lsblk` sous contrôle (macOS n'en a pas, et on ne veut pas dépendre du
# matériel de la machine de test). D'où le stub de PATH.

un_peripherique_bloc() { # imprime un chemin de périphérique bloc réel, quel qu'il soit
  local c
  for c in /dev/loop0 /dev/sda /dev/vda /dev/nvme0n1 /dev/xvda /dev/disk0; do
    [[ -b "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  for c in /dev/*; do [[ -b "$c" ]] && { printf '%s\n' "$c"; return 0; }; done
  return 1
}

# Prépare $STUB (en tête de PATH) avec un `lsblk` qui répond $1, et des doublures
# INERTES pour tout ce qui écrit sur le disque : chacune laisse une trace dans
# $TEMOIN au lieu d'agir. Deux effets : le test peut exercer le chemin réel
# (sans --dry-run) sans rien risquer, et l'assertion « $TEMOIN n'existe pas »
# prouve qu'aucune écriture n'a été TENTÉE.
stub_outils() { # $1 = type rendu par lsblk
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  TEMOIN="$BATS_TEST_TMPDIR/ecriture-tentee"
  printf '#!/bin/sh\necho %s\n' "$1" > "$STUB/lsblk"
  local outil
  for outil in sgdisk wipefs mkfs.vfat mkfs.btrfs mount pacstrap; do
    printf '#!/bin/sh\ntouch %s\nexit 0\n' "$TEMOIN" > "$STUB/$outil"
  done
  for outil in blockdev udevadm; do printf '#!/bin/sh\nexit 0\n' > "$STUB/$outil"; done
  chmod +x "$STUB"/*
  PATH="$STUB:$PATH"
}

@test "valider_disque accepte un disque ENTIER et rend son chemin canonique" {
  bloc="$(un_peripherique_bloc)" || skip "aucun périphérique bloc sur cette machine"
  stub_outils disk
  run valider_disque "$bloc"
  [ "$status" -eq 0 ]
  [ "$output" = "$(readlink -f "$bloc")" ]
}

@test "valider_disque refuse une PARTITION que [[ -b ]] laissait passer" {
  bloc="$(un_peripherique_bloc)" || skip "aucun périphérique bloc sur cette machine"
  stub_outils part
  run valider_disque "$bloc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"part"* ]]
  [[ "$output" == *"disque ENTIER"* ]]
}

@test "valider_disque refuse un volume LVM" {
  bloc="$(un_peripherique_bloc)" || skip "aucun périphérique bloc sur cette machine"
  stub_outils lvm
  run valider_disque "$bloc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lvm"* ]]
}

@test "valider_disque résout un lien de type /dev/disk/by-id/… avant de juger" {
  # Le cas le plus grave : c'est la façon canonique et prudente de désigner un
  # disque. `-b` suit le lien, donc la garde passait ; puis udev nomme la
  # partition « …-part1 » et non « …1 », donc le nom dérivé n'existait pas —
  # après l'effacement. Résoudre le lien AVANT est ce qui répare les deux.
  bloc="$(un_peripherique_bloc)" || skip "aucun périphérique bloc sur cette machine"
  lien="$BATS_TEST_TMPDIR/nvme-ESCHATON_TEST_0001"
  ln -s "$bloc" "$lien"
  stub_outils disk
  run valider_disque "$lien"
  [ "$status" -eq 0 ]
  [ "$output" = "$(readlink -f "$bloc")" ]
  [ "$output" != "$lien" ]
}

@test "valider_disque refuse plutôt que de deviner quand lsblk manque" {
  bloc="$(un_peripherique_bloc)" || skip "aucun périphérique bloc sur cette machine"
  STUB="$BATS_TEST_TMPDIR/vide"; mkdir -p "$STUB"
  # PATH réduit au stub vide : plus aucun lsblk n'est atteignable.
  PATH="$STUB" run valider_disque "$bloc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"lsblk introuvable"* ]]
}

@test "RIEN de destructeur ne s'exécute avant que la cible ne soit validée" {
  # La preuve du correctif : `sgdisk` est remplacé par un stub qui laisse une
  # trace. Si la garde travaille dans le bon ordre, la trace n'apparaît jamais.
  bloc="$(un_peripherique_bloc)" || skip "aucun périphérique bloc sur cette machine"
  stub_outils part
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --disk "$bloc" --user seylar
  [ "$status" -eq 1 ]
  [[ "$output" == *"disque ENTIER"* ]]
  [ ! -e "$TEMOIN" ]     # aucune écriture n'a même été TENTÉE
}

@test "les noms de partition dérivés sont validés, et le sont AVANT le zap" {
  run nom_partition /dev/sda 1;      [ "$output" = "/dev/sda1" ]
  run nom_partition /dev/nvme0n1 2;  [ "$output" = "/dev/nvme0n1p2" ]
  run nom_partition /dev/mmcblk0 1;  [ "$output" = "/dev/mmcblk0p1" ]

  run valider_noms_partitions /dev/sda /dev/sda1 /dev/sda2;  [ "$status" -eq 0 ]
  # Une dérivation qui ne retomberait pas sur le disque est refusée…
  run valider_noms_partitions /dev/sda /dev/sdb1 /dev/sda2;  [ "$status" -eq 1 ]
  # …de même qu'un nom vide, ou deux partitions homonymes.
  run valider_noms_partitions /dev/sda "" /dev/sda2;         [ "$status" -eq 1 ]
  run valider_noms_partitions /dev/sda /dev/sda1 /dev/sda1;  [ "$status" -eq 1 ]

  # …et dans le déroulé, la validation précède bien le premier appel destructeur.
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar
  [ "$status" -eq 0 ]
  garde="$(printf '%s\n' "$output" | grep -n 'blockdev --rereadpt' | head -1 | cut -d: -f1)"
  zap="$(printf '%s\n' "$output" | grep -n 'sgdisk --zap-all' | head -1 | cut -d: -f1)"
  [ "$garde" -lt "$zap" ]
}

@test "la relecture de la table est VÉRIFIÉE, pas seulement espérée" {
  # `attendre_bloc` ne constate qu'une PRÉSENCE : sur un disque occupé dont le
  # noyau refuse de relire la table, les anciens nœuds sont toujours là et
  # mkfs formaterait l'ancienne géométrie. `blockdev --rereadpt` rend EBUSY
  # dans ce cas — c'est le `partprobe` prescrit par le plan Task 2.3.
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar
  [ "$status" -eq 0 ]
  [[ "$output" == *"blockdev --rereadpt /dev/vda"* ]]
  # Une fois avant le zap, une fois après le partitionnement.
  [ "$(printf '%s\n' "$output" | grep -c 'blockdev --rereadpt')" -eq 2 ]
  relecture="$(printf '%s\n' "$output" | grep -n 'blockdev --rereadpt' | tail -1 | cut -d: -f1)"
  format="$(printf '%s\n' "$output" | grep -n 'mkfs.vfat' | head -1 | cut -d: -f1)"
  [ "$relecture" -lt "$format" ]
}

# --- ergonomie des options : le silence n'est pas un service ------------------

@test "une option de valeur RÉPÉTÉE est refusée au lieu d'être écrasée" {
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run \
      --disk /dev/vda --disk /dev/vdb --user seylar
  [ "$status" -eq 1 ]
  [[ "$output" == *"--disk indiqué plusieurs fois"* ]]
  [[ "$output" == *"/dev/vda"* && "$output" == *"/dev/vdb"* ]]
  [[ "$output" != *"sgdisk"* ]]

  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run \
      --disk /dev/vda --user seylar --user autre
  [ "$status" -eq 1 ]
  [[ "$output" == *"--user indiqué plusieurs fois"* ]]

  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run \
      --disk /dev/vda --user seylar --hostname a --hostname b
  [ "$status" -eq 1 ]
  [[ "$output" == *"--hostname indiqué plusieurs fois"* ]]
}

@test "la forme --option=valeur est acceptée, pas rejetée en « option inconnue »" {
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run \
      --disk=/dev/vda --user=seylar --hostname=mabecane
  [ "$status" -eq 0 ]
  [[ "$output" == *"sgdisk --zap-all /dev/vda"* ]]
  [[ "$output" == *"useradd -m -G wheel seylar"* ]]
  [[ "$output" == *"écrire « mabecane » dans /mnt/etc/hostname"* ]]

  # …et une valeur collée vide reste une valeur manquante.
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk= --user seylar
  [ "$status" -eq 1 ]
  [[ "$output" == *"--disk attend un argument"* ]]

  # `--dry-run=quelque-chose` n'a pas de sens : on le dit.
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run=1 --disk /dev/vda --user seylar
  [ "$status" -eq 1 ]
  [[ "$output" == *"n'attend pas de valeur"* ]]
}

@test "valider_utilisateur refuse les comptes système, root en tête" {
  # `useradd root` échouerait — mais à l'étape 4, APRÈS l'effacement du disque
  # et le pacstrap : l'installation s'arrêterait sur une machine à moitié faite.
  for compte in root bin daemon ftp http nobody dbus systemd-network; do
    run valider_utilisateur "$compte"
    [ "$status" -eq 1 ]
  done
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user root
  [ "$status" -eq 1 ]
  [[ "$output" == *"compte SYSTÈME"* ]]
  [[ "$output" != *"sgdisk"* ]]
}

@test "aucune valeur fournie par l'utilisateur n'est interpolée dans une chaîne shell" {
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar --hostname mabecane
  # hostname : write_file, plus de `bash -c "echo '…' > …"`
  [[ "$output" == *"écrire « mabecane » dans /mnt/etc/hostname"* ]]
  [[ "$output" != *"echo 'mabecane'"* ]]
  # utilisateur : arch-chroot appelé directement, plus de `bash -c`
  [[ "$output" == *"arch-chroot /mnt useradd -m -G wheel seylar"* ]]
  [[ "$output" != *'bash -c useradd'* ]]
}
