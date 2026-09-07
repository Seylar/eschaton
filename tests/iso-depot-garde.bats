#!/usr/bin/env bats

setup() {
  # Fonction de production extraite : le constructeur entier exige root/Arch.
  eval "$(sed -n '/^fuite_depot_tiers() {/,/^}/p' "$BATS_TEST_DIRNAME/../iso/build-iso")"
  arbre="$BATS_TEST_TMPDIR/airootfs"
  mkdir -p "$arbre/etc/pacman.d"
  printf '[core]\n' > "$arbre/etc/pacman.conf"
}

@test "le contrôle distingue absence et déclaration effective du dépôt tiers" {
  run fuite_depot_tiers "$arbre"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  printf '[arch-mact2]\n' > "$arbre/fragment"
  run fuite_depot_tiers "$arbre"
  [ "$status" -eq 0 ]; [[ "$output" == *fragment* ]]
  rm "$arbre/fragment"
  printf 'Include = /etc/pacman.d/arch-mact2.conf\n' >> "$arbre/etc/pacman.conf"
  run fuite_depot_tiers "$arbre"
  [ "$status" -eq 0 ]; [[ "$output" == *arch-mact2.conf* ]]
}

@test "une erreur grep n'est jamais absorbée, même après un résultat" {
  grep() { echo 'fragment:[arch-mact2]'; return 2; }
  run fuite_depot_tiers "$arbre"
  [ "$status" -eq 2 ]
  # Même composition que les deux appels de build-iso, avec pipefail.
  run bash -o pipefail -c 'eval "$1"; eval "$2"; fuites=$(fuite_depot_tiers "$3" | sort -u)' \
    bash "$(declare -f fuite_depot_tiers)" "$(declare -f grep)" "$arbre"
  [ "$status" -eq 2 ]
}

@test "une arborescence absente ou un fichier réellement illisible sont refusés" {
  run fuite_depot_tiers "$arbre/absent"
  [ "$status" -ne 0 ]
  ((EUID != 0)) || skip 'root peut lire même sans bits de permission'
  printf 'contenu\n' > "$arbre/illisible"
  chmod 000 "$arbre/illisible"
  run fuite_depot_tiers "$arbre"
  chmod 600 "$arbre/illisible"
  [ "$status" -ne 0 ]
}

@test "une erreur du second contrôle pacman remonte aussi" {
  grep() {
    if [[ "$1" == -rE ]]; then return 1; fi
    return 2
  }
  run fuite_depot_tiers "$arbre"
  [ "$status" -eq 2 ]
}
