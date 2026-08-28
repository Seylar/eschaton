#!/usr/bin/env bats

setup() {
  assistant_dir="$BATS_TEST_DIRNAME/../packages/eschaton-dms-plugin-assistant"
  catalog="$assistant_dir/tool-catalog.json"
}

@test "le catalogue assistant contient exactement les trois outils v1" {
  run jq -r '[.tools[].function.name] | join(",")' "$catalog"
  [ "$status" -eq 0 ]
  [ "$output" = "system_status,trigger_update,propose_rollback" ]
}

@test "chaque outil porte un schéma strict sans propriétés libres" {
  run jq -e '
    .version == 1 and
    (.tools | length == 3) and
    all(.tools[];
      .type == "function" and
      .function.strict == true and
      .function.parameters.type == "object" and
      .function.parameters.additionalProperties == false)
  ' "$catalog"
  [ "$status" -eq 0 ]
}

@test "snapshot_id est le seul argument privilégié et reste positif" {
  run jq -e '
    .tools[]
    | select(.function.name == "propose_rollback")
    | .function.parameters
    | (.required == ["snapshot_id"]) and
      (.properties | keys == ["snapshot_id"]) and
      (.properties.snapshot_id.type == "integer") and
      (.properties.snapshot_id.minimum == 1)
  ' "$catalog"
  [ "$status" -eq 0 ]
}

@test "le transport n'introduit ni shell ni Quickshell.Networking" {
  run grep -R -E "Quickshell\\.Networking|/(ba)?sh|[\"']-c[\"']" "$assistant_dir"
  [ "$status" -eq 1 ]
}

@test "la clé API est développée par curl depuis l'environnement" {
  run grep -F 'Authorization: Bearer {{ESCHATON_ASSISTANT_API_KEY}}' \
    "$assistant_dir/providers/OpenAIAdapter.js"
  [ "$status" -eq 0 ]

  run grep -F 'Authorization: Bearer " + apiKey' \
    "$assistant_dir/providers/OpenAIAdapter.js"
  [ "$status" -eq 1 ]
}

@test "le transport ignore curlrc et borne les appels d'outils" {
  run grep -F '"--disable"' "$assistant_dir/providers/OpenAIAdapter.js"
  [ "$status" -eq 0 ]

  run grep -F 'maxToolCallsPerRound: 8' "$assistant_dir/AssistantCore.qml"
  [ "$status" -eq 0 ]

  run grep -F 'maxToolPayloadChars: 65536' "$assistant_dir/AssistantCore.qml"
  [ "$status" -eq 0 ]
}
