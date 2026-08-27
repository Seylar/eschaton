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
