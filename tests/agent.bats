#!/usr/bin/env bats
@test "Agent : transactions, conflits, reprise durable et indépendance du panneau" {
  run node --test "$BATS_TEST_DIRNAME/agent.cjs"
  [ "$status" -eq 0 ]
}
