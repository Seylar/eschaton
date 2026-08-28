#!/usr/bin/env bats

setup() {
  export VM_SERIAL_WORK="$BATS_TEST_TMPDIR"
  tool="$BATS_TEST_DIRNAME/../tools/vm-serial"
}

assert_usage_without_traceback() {
  [ "$status" -eq 2 ]
  [[ "$output" != *Traceback* ]]
}

@test "run refuse un délai non numérique proprement" {
  run "$tool" run --timeout demain true
  assert_usage_without_traceback
}

@test "raw refuse un hexadécimal invalide proprement" {
  run "$tool" raw xyz
  assert_usage_without_traceback
}

@test "tail refuse un nombre de lignes négatif proprement" {
  run "$tool" tail -2
  assert_usage_without_traceback
}

@test "wait refuse une expression régulière invalide proprement" {
  run "$tool" wait '[' 1
  assert_usage_without_traceback
}
