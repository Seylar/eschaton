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

@test "le dry-run contient le déroulé complet dans l'ordre" {
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --hostname eschaton --user seylar
  [ "$status" -eq 0 ]
  [[ "$output" == *"sgdisk --zap-all /dev/vda"* ]]
  [[ "$output" == *"-n1:0:+2G"*  ]]              # ESP 2 Gio
  [[ "$output" == *"mkfs.btrfs"* ]]
  for sv in @ @home @log @pkg @snapshots; do [[ "$output" == *"subvolume create /mnt/$sv"* ]]; done
  [[ "$output" == *"pacstrap"* && "$output" == *"eschaton-base"* ]]
  [[ "$output" == *"genfstab"* ]]
  [[ "$output" == *"limine"* ]]
  [[ "$output" == *"cp /usr/share/eschaton/os-release /etc/os-release"* ]]
  [[ "$output" == *"Include = /etc/pacman.d/eschaton.conf"* ]]   # le système cible connaît [eschaton]
}
