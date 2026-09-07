#!/usr/bin/env bats
@test "Codex : protocole abonnement, streaming, annulation et outils fermés" {
  run node --test "$BATS_TEST_DIRNAME/codex-protocol.cjs"
  [ "$status" -eq 0 ]
}
