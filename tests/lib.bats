#!/usr/bin/env bats
setup() { source "$BATS_TEST_DIRNAME/../packages/eschaton-base/lib.sh"; }

@test "check_free_space_kb accepte quand l'espace suffit" {
  run check_free_space_kb 2000000 1000000
  [ "$status" -eq 0 ]
}

@test "check_free_space_kb refuse quand l'espace manque" {
  run check_free_space_kb 500000 1000000
  [ "$status" -eq 1 ]
}

@test "running_kernel_missing_modules détecte un kernel remplacé" {
  dir="$BATS_TEST_TMPDIR/modules"; mkdir -p "$dir/6.10.1-arch1"
  run running_kernel_missing_modules "$dir" "6.9.0-arch1"
  [ "$status" -eq 0 ]
}

@test "running_kernel_missing_modules silencieux si le kernel courant est présent" {
  dir="$BATS_TEST_TMPDIR/modules"; mkdir -p "$dir/6.10.1-arch1"
  run running_kernel_missing_modules "$dir" "6.10.1-arch1"
  [ "$status" -eq 1 ]
}

@test "pacman_update_args transmet les options anodines sans les modifier" {
  run pacman_update_args --needed --color=never
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "--needed" ]
  [ "${lines[1]}" = "--color=never" ]
}

@test "pacman_update_args n'écrit rien quand il n'a rien reçu" {
  run pacman_update_args
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Le remplacement du 2026-08-30 : `--yes` était traduit en `--noconfirm`, donc
# la mise à jour s'auto-approuvait. Il est maintenant refusé, comme toute
# option qui répondrait à la place de l'utilisateur. La garde d'invariant du
# dépôt vit dans tests/update-sans-auto-approbation.bats.
@test "pacman_update_args refuse toute option d'auto-approbation" {
  # Appel direct plutôt que `run` : `run` fusionne stderr dans $output, or on
  # veut précisément vérifier que la SORTIE STANDARD reste vide.
  for interdite in --yes --noconfirm --ask --ask=4 --overwrite '--overwrite=/usr/lib/*'; do
    if sortie=$(pacman_update_args --needed "$interdite" 2>/dev/null); then
      echo "option acceptée à tort : $interdite"
      return 1
    fi
    # L'appelant ne doit pas avoir à trier un résultat partiel avant de
    # constater l'échec.
    if [ -n "$sortie" ]; then
      echo "sortie standard non vide pour $interdite : $sortie"
      return 1
    fi
  done
}

# Les quatre suivantes couvrent le remplacement de sous-volume d'eschaton-rollback
# (Task 10) : `snapper rollback` refuse la disposition Arch d'Eschaton, la
# restauration se fait donc en manipulant les noms de sous-volumes à la main.

@test "device_of_source sépare le disque du sous-volume" {
  run device_of_source "/dev/vda2[/@]"
  [ "$output" = "/dev/vda2" ]
  run device_of_source "/dev/vda2"
  [ "$output" = "/dev/vda2" ]
}

@test "subvol_of_source lit le sous-volume, et refuse une source qui n'en a pas" {
  run subvol_of_source "/dev/vda2[/@]"
  [ "$status" -eq 0 ]
  [ "$output" = "@" ]
  run subvol_of_source "/dev/vda2[/@snapshots]"
  [ "$output" = "@snapshots" ]
  # Une partition montée à sa racine n'a pas de sous-volume à remplacer :
  # eschaton-rollback doit s'arrêter là plutôt que de renommer au hasard.
  run subvol_of_source "/dev/vda2"
  [ "$status" -eq 1 ]
}

@test "snapshot_subvol_path compose le chemin vu depuis subvolid=5" {
  run snapshot_subvol_path "@snapshots" 3
  [ "$output" = "@snapshots/3/snapshot" ]
}

@test "booted_on_snapshot distingue le système normal d'un démarrage sur snapshot" {
  # Menu Limine → entrée « Snapshots » : la racine est SOUS @snapshots. Y lancer
  # le remplacement de sous-volume abîmerait le magasin au lieu de restaurer @.
  run booted_on_snapshot "@snapshots/3/snapshot" "@snapshots"
  [ "$status" -eq 0 ]
  run booted_on_snapshot "@" "@snapshots"
  [ "$status" -eq 1 ]
  # Un sous-volume dont le nom commence pareil n'est pas dedans pour autant.
  run booted_on_snapshot "@snapshots-old" "@snapshots"
  [ "$status" -eq 1 ]
}

@test "valid_snapshot_number refuse 0, le vide et le non-numérique" {
  run valid_snapshot_number 3;      [ "$status" -eq 0 ]
  run valid_snapshot_number 007;    [ "$status" -eq 0 ]
  # 0 est le pseudo-snapshot « current » de snapper : aucun sous-volume derrière.
  run valid_snapshot_number 0;      [ "$status" -eq 1 ]
  run valid_snapshot_number "";     [ "$status" -eq 1 ]
  run valid_snapshot_number "3; rm -rf /"; [ "$status" -eq 1 ]
}

@test "noninteractive_rollback_number n'accepte que --yes suivi d'un snapshot" {
  run noninteractive_rollback_number --yes 42
  [ "$status" -eq 0 ]
  [ "$output" = "42" ]

  run noninteractive_rollback_number --yes 0
  [ "$status" -eq 1 ]
  run noninteractive_rollback_number --force 42
  [ "$status" -eq 1 ]
  run noninteractive_rollback_number --yes 42 extra
  [ "$status" -eq 1 ]
}
