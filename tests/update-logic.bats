#!/usr/bin/env bats

@test "les verdicts et messages du panneau sont exécutés sous Node" {
  run node --test "$BATS_TEST_DIRNAME/update-logic.cjs"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}
