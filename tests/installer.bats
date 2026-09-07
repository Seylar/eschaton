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

@test "l'installeur vérifie que les actions polkit contraignent bien les binaires" {
  # REVUE DE SÉCURITÉ I6. Deux façons de perdre la contrainte, aucune visible :
  # l'action absente — `pkexec` retombe alors sur l'action générique, qui
  # autorise l'authentification depuis une session distante ou inactive — ou
  # l'action MASQUÉE par un fichier de même nom dans /etc/polkit-1/actions, qui
  # prime sur /usr/share, silencieusement. L'installeur contrôle les deux avant
  # de dire « terminé ».
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar
  [ "$status" -eq 0 ]
  for action in org.eschaton.update org.eschaton.rollback; do
    [[ "$output" == *"/mnt/usr/share/polkit-1/actions/$action.policy"* ]] || {
      echo "l'installeur ne vérifie pas la présence de $action"
      return 1
    }
    [[ "$output" == *"/mnt/etc/polkit-1/actions/$action.policy"* ]] || {
      echo "l'installeur ne vérifie pas le masquage de $action par /etc"
      return 1
    }
  done
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

@test "la répétition à blanc applique la garde COMPLÈTE quand le disque est là" {
  # Le cœur du correctif : dès que le périphérique existe ici, la répétition ne
  # se contente plus de la forme du nom, elle passe par `valider_disque` — donc
  # par lsblk et par la canonisation. Elle rend alors exactement le verdict du
  # chemin réel, ce qui est toute sa raison d'être.
  bloc="$(un_peripherique_bloc)" || skip "aucun périphérique bloc sur cette machine"
  stub_outils part
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk "$bloc" --user seylar
  [ "$status" -eq 1 ]
  [[ "$output" == *"disque ENTIER"* ]]
  [[ "$output" != *"sgdisk"* ]]

  # …et un disque entier reste accepté, canonisé, avec les bons noms dérivés.
  stub_outils disk
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk "$bloc" --user seylar
  [ "$status" -eq 0 ]
  canon="$(readlink -f "$bloc")"
  [[ "$output" == *"sgdisk --zap-all $canon"* ]]
  [[ "$output" != *"absent de cette machine"* ]]
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

# --- la répétition à blanc doit refuser ce que le chemin réel refuse ----------

@test "la répétition à blanc refuse les trois entrées que le chemin réel refuse" {
  # Sondes mesurées avant correctif, avec `valider_disque` sautée en --dry-run :
  #   --disk /dev/sda1               → status 0 et « DRY: sgdisk --zap-all /dev/sda1 »
  #   --disk /dev/disk/by-id/nvme-…  → « DRY: attendre_bloc …_1234561 » (« p1 » en réalité)
  #   --disk /dev/disk/by-id/ata-…   → « DRY: attendre_bloc …_XYZ1 » (udev écrit « -part1 »)
  # Le chemin réel refuse les trois. `valider_noms_partitions` ne rattrapait
  # rien : son test `"$p" == "$disque"[0-9p]*` est satisfait par
  # « /dev/sda1 » → « /dev/sda1p1 ». Un mode dont la raison d'être est de DIRE À
  # L'AVANCE ce qui va se passer ne peut pas valider ce que le vrai chemin refuse.
  for cible in /dev/sda1 \
               /dev/disk/by-id/nvme-ESCHATON_TEST_123456 \
               /dev/disk/by-id/ata-ESCHATON_TEST_XYZ; do
    run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk "$cible" --user seylar
    [ "$status" -eq 1 ] || { echo "accepté en dry-run : $cible"; return 1; }
    [[ "$output" != *"sgdisk"* ]]        # aucun effacement n'a été annoncé
    [[ "$output" != *"attendre_bloc"* ]] # aucun nom de partition inventé
  done
}

@test "valider_forme_disque juge le nom quand le périphérique est absent" {
  # Répétition depuis un autre poste : il n'y a rien à interroger. Ce qui reste
  # jugeable, c'est la FORME du nom — et c'est justement ce qui sépare les trois
  # entrées ci-dessus d'un vrai nom de disque.
  run valider_forme_disque /dev/sda1
  [ "$status" -eq 1 ]; [[ "$output" == *"PARTITION"* ]]
  run valider_forme_disque /dev/nvme0n1p2;  [ "$status" -eq 1 ]
  run valider_forme_disque /dev/mmcblk0p1;  [ "$status" -eq 1 ]
  run valider_forme_disque /dev/vdb3;       [ "$status" -eq 1 ]

  run valider_forme_disque /dev/disk/by-id/nvme-ESCHATON_TEST_123456
  [ "$status" -eq 1 ]; [[ "$output" == *"nœud noyau"* ]]
  run valider_forme_disque /dev/disk/by-id/ata-ESCHATON_TEST_XYZ; [ "$status" -eq 1 ]
  run valider_forme_disque /dev/mapper/vg-lv;                     [ "$status" -eq 1 ]
  run valider_forme_disque sda;                                   [ "$status" -eq 1 ]
  run valider_forme_disque /dev;                                  [ "$status" -eq 1 ]
  run valider_forme_disque "";                                    [ "$status" -eq 1 ]

  # …et les noms de disque ENTIER passent, sans quoi la répétition ne servirait plus.
  run valider_forme_disque /dev/sda;     [ "$status" -eq 0 ]
  run valider_forme_disque /dev/vda;     [ "$status" -eq 0 ]
  run valider_forme_disque /dev/nvme0n1; [ "$status" -eq 0 ]
  run valider_forme_disque /dev/mmcblk0; [ "$status" -eq 0 ]
}

@test "la répétition à blanc DIT quand elle n'a pu juger que la forme du nom" {
  # Le commentaire de l'installeur affirmait que « la dérivation des noms est
  # vérifiée » en répétition à blanc. Elle ne l'était pas. Le mode annonce
  # désormais ce qu'il a réellement pu contrôler — et ce qu'il n'a pas pu.
  [ ! -b /dev/vda ] || skip "/dev/vda existe ici : la garde complète s'applique"
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar
  [ "$status" -eq 0 ]
  [[ "$output" == *"absent de cette machine"* ]]
  [[ "$output" == *"FORME"* ]]
}

# --- ce que la relecture promet doit être vrai AU MOMENT où elle le promet ----

@test "« Rien n'a été écrit » ne se dit qu'avant le partitionnement" {
  # Le message était UNIQUE pour DEUX appels : celui d'avant le zap, où il est
  # vrai, et celui d'après `sgdisk --zap-all` et les deux `sgdisk -n`, où il est
  # faux. Un utilisateur dont la table vient d'être effacée lisait « Rien n'a
  # été écrit » — et pouvait renoncer à toute tentative de récupération.
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  printf '#!/bin/sh\nexit 1\n' > "$STUB/blockdev"; chmod +x "$STUB/blockdev"
  PATH="$STUB:$PATH"; DRY_RUN=0

  run relire_table /dev/eschaton-test "avant le partitionnement" intact
  [ "$status" -eq 1 ]
  [[ "$output" == *"Rien n'a été écrit"* ]]
  [[ "$output" != *"A DÉJÀ ÉTÉ MODIFIÉ"* ]]

  run relire_table /dev/eschaton-test "après le partitionnement" table-reecrite
  [ "$status" -eq 1 ]
  [[ "$output" != *"Rien n'a été écrit"* ]]
  [[ "$output" == *"A DÉJÀ ÉTÉ MODIFIÉ"* ]]
  # …et il ne suffit pas de retirer la fausse promesse : il faut dire quoi faire.
  [[ "$output" == *"testdisk"* ]]

  # Un état non renseigné retombe sur le pire cas, jamais sur le rassurant.
  run relire_table /dev/eschaton-test "moment non précisé"
  [ "$status" -eq 1 ]
  [[ "$output" != *"Rien n'a été écrit"* ]]
}

@test "chaque appel de relire_table annonce l'état RÉEL du disque à ce moment" {
  # Le chemin réel exige un Linux (/sys/firmware/efi, un vrai disque) : il ne
  # peut pas tourner ici. On verrouille donc le CÂBLAGE, qui est précisément ce
  # qui était faux — un message unique pour deux moments opposés.
  src="$BATS_TEST_DIRNAME/../installer/eschaton-install"
  grep -q 'relire_table "$DISK" "avant le partitionnement" intact' "$src"
  grep -q 'relire_table "$DISK" "après le partitionnement" table-reecrite' "$src"
  # Les motifs sont ancrés en début de ligne : les COMMENTAIRES du script citent
  # eux aussi `sgdisk --zap-all`, et un `grep` lâche les prendrait pour le code.
  avant="$(grep -n '^relire_table .* intact'         "$src" | head -1 | cut -d: -f1)"
  zap="$(  grep -n '^run_cmd sgdisk --zap-all'       "$src" | head -1 | cut -d: -f1)"
  apres="$(grep -n '^relire_table .* table-reecrite' "$src" | head -1 | cut -d: -f1)"
  [ -n "$avant" ] && [ -n "$zap" ] && [ -n "$apres" ]
  [ "$avant" -lt "$zap" ]
  [ "$zap" -lt "$apres" ]
}

@test "le message de relecture nomme le vrai périmètre de BLKRRPART" {
  # L'ancienne énumération (« montée, prise par LVM, membre d'un RAID ») oubliait
  # le swap actif, cas très courant sur une machine déjà installée. Et elle
  # laissait croire que la garde couvre le disque : BLKRRPART ne rend EBUSY que
  # si une PARTITION est ouverte — un disque entier utilisé cru (PV LVM, LUKS,
  # membre btrfs/ZFS sans table) franchit cette garde comme il franchit
  # `valider_disque`.
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  printf '#!/bin/sh\nexit 1\n' > "$STUB/blockdev"; chmod +x "$STUB/blockdev"
  PATH="$STUB:$PATH"; DRY_RUN=0

  run relire_table /dev/eschaton-test "avant le partitionnement" intact
  [ "$status" -eq 1 ]
  [[ "$output" == *"swap"* ]]
  [[ "$output" == *"PARTITIONS"* ]]   # le sujet est la partition, pas le disque
}

@test "blockdev absent est nommé pour ce qu'il est, pas pris pour un disque occupé" {
  # `blockdev` manquant rend 127, que la suite prenait pour un EBUSY : le message
  # « une partition est OCCUPÉE » envoyait chercher un montage inexistant.
  STUB="$BATS_TEST_TMPDIR/vide"; mkdir -p "$STUB"
  DRY_RUN=0
  PATH="$STUB" run relire_table /dev/eschaton-test "avant le partitionnement" intact
  [ "$status" -eq 1 ]
  [[ "$output" == *"blockdev introuvable"* ]]
  [[ "$output" == *"util-linux"* ]]
  [[ "$output" != *"OCCUPÉE"* ]]
  # …et l'état du disque reste dit, puisque c'est ce que l'utilisateur cherche.
  [[ "$output" == *"Rien n'a été écrit"* ]]
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
