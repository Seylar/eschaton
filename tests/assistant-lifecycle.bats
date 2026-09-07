#!/usr/bin/env bats

@test "la logique de cycle de vie QML passe les scénarios exécutés sous Node" {
  run node --test "$BATS_TEST_DIRNAME/assistant-lifecycle.cjs"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}
