#!/usr/bin/env bats

setup() {
  assistant_dir="$BATS_TEST_DIRNAME/../packages/eschaton-dms-plugin-assistant"
  desktop_config_dir="$BATS_TEST_DIRNAME/../packages/eschaton-desktop-config"
  desktop_dir="$BATS_TEST_DIRNAME/../packages/eschaton-desktop"
  catalog="$assistant_dir/tool-catalog.json"
  manifest="$assistant_dir/plugin.json"
  providers="$assistant_dir/providers.json"
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
  run grep -R -E "Quickshell\\.Networking|/(ba)?sh|[\"']-c[\"']" \
    "$assistant_dir/AssistantCore.qml" "$assistant_dir/providers"
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

@test "les fournisseurs par défaut sont une configuration datée sans secret" {
  run jq -e '
    .schema_version == 1 and .updated == "2026-08-28" and
    ([.providers[].id] == ["ramalama-local", "openai", "anthropic"]) and
    ([.providers[].format] == ["openai", "openai", "anthropic"]) and
    ([.providers[].requires_key] == [false, true, true]) and
    (all(.providers[];
      (keys | sort) == ["base_url", "format", "id", "model", "name", "requires_key"]))
  ' "$providers"
  [ "$status" -eq 0 ]

  run grep -E 'api[_-]?key|secret|token' "$providers"
  [ "$status" -eq 1 ]
}

@test "le trousseau utilise des attributs stables et stdin, jamais argv" {
  bridge="$assistant_dir/KeyringBridge.qml"
  run grep -F '"application", "org.eschaton.Assistant"' "$bridge"
  [ "$status" -eq 0 ]
  run grep -F '"provider", String(providerId)' "$bridge"
  [ "$status" -eq 0 ]
  run grep -F 'write(root._pendingSecret + "\n")' "$bridge"
  [ "$status" -eq 0 ]
  run grep -E 'command.*_pendingSecret|command.*apiKeyInput' "$bridge"
  [ "$status" -eq 1 ]
  run grep -F 'interval: 60000' "$bridge"
  [ "$status" -eq 0 ]
  run grep -F 'Qt.callLater(function()' "$bridge"
  [ "$status" -eq 0 ]
}

@test "Secret Service appartient au bureau et le risque autologin est visible" {
  run bash -c '
    source "$1/PKGBUILD"
    [[ " ${depends[*]} " == *" gnome-keyring "* ]]
  ' _ "$desktop_dir"
  [ "$status" -eq 0 ]

  run grep -F "les clés seraient stockées en clair sur le disque" \
    "$assistant_dir/EschatonAssistantSettings.qml"
  [ "$status" -eq 0 ]
}

@test "local-only est imposé par le core et la surcharge utilisateur reste en lecture seule" {
  run grep -F 'ProviderPolicy.validateEndpoint(baseUrl, localOnly)' "$assistant_dir/AssistantCore.qml"
  [ "$status" -eq 0 ]
  run grep -F '/eschaton/assistant/providers.json' "$assistant_dir/ProviderCatalog.qml"
  [ "$status" -eq 0 ]
  run grep -E 'FileView|write\(|save\(' "$assistant_dir/ProviderCatalog.qml"
  [ "$status" -eq 1 ]
}

@test "Anthropic passe sa clé par environnement et traduit les outils natifs" {
  adapter="$assistant_dir/providers/AnthropicAdapter.js"
  run grep -F 'x-api-key: {{ESCHATON_ASSISTANT_API_KEY}}' "$adapter"
  [ "$status" -eq 0 ]
  run grep -F 'input_schema: fn.parameters' "$adapter"
  [ "$status" -eq 0 ]
  run grep -F 'reason === "tool_use" ? "tool_calls"' "$adapter"
  [ "$status" -eq 0 ]
}

@test "le transport ignore curlrc et borne les appels d'outils" {
  run grep -F '"--disable"' "$assistant_dir/providers/OpenAIAdapter.js"
  [ "$status" -eq 0 ]

  run grep -F 'maxToolCallsPerRound: 8' "$assistant_dir/AssistantCore.qml"
  [ "$status" -eq 0 ]

  run grep -F 'maxToolPayloadChars: 65536' "$assistant_dir/AssistantCore.qml"
  [ "$status" -eq 0 ]
}

@test "le manifeste expose un daemon DMS honnête sur ses permissions" {
  run jq -e '
    .id == "eschatonAssistant" and
    .type == "daemon" and
    .component == "./EschatonAssistantDaemon.qml" and
    .requires_dms == ">=1.5.0" and
    (.permissions | index("process") != null) and
    (._permissions_notice | contains("non appliquées par DMS"))
  ' "$manifest"
  [ "$status" -eq 0 ]
}

@test "le paquet runtime exclut les harnais et garde les dépendances bi-arch" {
  run bash -c '
    source "$1/PKGBUILD"
    [[ ${arch[*]} == any ]]
    [[ ${depends[*]} == "dms-shell curl libsecret jq pacman-contrib" ]]
    [[ ${optdepends[*]} == ramalama:* ]]
    [[ " ${source[*]} " != *" CoreHarness.qml "* ]]
    [[ " ${source[*]} " != *" ParserHarness.qml "* ]]
    [[ " ${source[*]} " != *" tests/fixtures "* ]]
    [[ " ${source[*]} " == *" providers.json "* ]]
    [[ " ${source[*]} " == *" AnthropicAdapter.js "* ]]
  ' _ "$assistant_dir"
  [ "$status" -eq 0 ]
}

@test "SUPER+A vise uniquement le daemon assistant" {
  defaults="$BATS_TEST_DIRNAME/../packages/eschaton-desktop-config/eschaton-defaults.lua"
  run grep -F 'hl.bind("SUPER + A", hl.dsp.exec_cmd("dms ipc call plugins toggle eschatonAssistant")' "$defaults"
  [ "$status" -eq 0 ]
}

@test "le contrôle de shadowing détecte l'id même dans un dossier autrement nommé" {
  config="$BATS_TEST_TMPDIR/config"
  plugin="$config/DankMaterialShell/plugins/personnalisation/plugin.json"
  fake_dms="$BATS_TEST_TMPDIR/dms"
  calls="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$(dirname "$plugin")"
  printf '%s\n' '{"id":"eschatonAssistant"}' > "$plugin"
  cat > "$fake_dms" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${ASSISTANT_SHADOW_CALLS}"
EOF
  chmod +x "$fake_dms"

  ASSISTANT_SHADOW_CALLS="$calls" \
    XDG_CONFIG_HOME="$config" \
    ESCHATON_DMS_BIN="$fake_dms" \
    run "$desktop_config_dir/eschaton-assistant-shadowing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remplace le plugin système"* ]]
  [[ "$(< "$calls")" == notify\ Assistant\ Eschaton\ remplacé* ]]
}
