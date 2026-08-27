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
