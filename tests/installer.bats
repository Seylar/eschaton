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

@test "aucune valeur fournie par l'utilisateur n'est interpolée dans une chaîne shell" {
  run "$BATS_TEST_DIRNAME/../installer/eschaton-install" --dry-run --disk /dev/vda --user seylar --hostname mabecane
  # hostname : write_file, plus de `bash -c "echo '…' > …"`
  [[ "$output" == *"écrire « mabecane » dans /mnt/etc/hostname"* ]]
  [[ "$output" != *"echo 'mabecane'"* ]]
  # utilisateur : arch-chroot appelé directement, plus de `bash -c`
  [[ "$output" == *"arch-chroot /mnt useradd -m -G wheel seylar"* ]]
  [[ "$output" != *'bash -c useradd'* ]]
}
