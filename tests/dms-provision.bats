#!/usr/bin/env bats

setup() {
  source "$BATS_TEST_DIRNAME/../packages/eschaton-desktop-config/eschaton-dms-provision"
  settings="$BATS_TEST_TMPDIR/settings.json"
  printf '%s\n' \
    '{"barConfigs":[{"rightWidgets":["systemTray","controlCenterButton"]}]}' \
    > "$settings"
}

@test "le provisioning ajoute les deux widgets sans déplacer ceux de DMS" {
  add_eschaton_widgets "$settings"
  run jq -c '.barConfigs[0].rightWidgets' "$settings"
  [ "$status" -eq 0 ]
  [ "$output" = '["systemTray","controlCenterButton","eschatonUpdate","eschatonRollback"]' ]
}

@test "le provisioning des widgets est idempotent" {
  add_eschaton_widgets "$settings"
  add_eschaton_widgets "$settings"
  run jq '[.barConfigs[0].rightWidgets[] | select(. == "eschatonUpdate")] | length' "$settings"
  [ "$output" = "1" ]
  run jq '[.barConfigs[0].rightWidgets[] | select(. == "eschatonRollback")] | length' "$settings"
  [ "$output" = "1" ]
}

@test "le wallpaper Eschaton ne remplace qu'un repli DMS vide" {
  wallpaper="$BATS_TEST_TMPDIR/default.png"
  : > "$wallpaper"

  run wallpaper_needs_seed "" "$wallpaper"
  [ "$status" -eq 0 ]
  run wallpaper_needs_seed "/home/seylar/mon-fond.png" "$wallpaper"
  [ "$status" -eq 1 ]
  run wallpaper_needs_seed "" "$BATS_TEST_TMPDIR/absent.png"
  [ "$status" -eq 1 ]
}

@test "la readiness attend une position de barre valide, pas seulement l'IPC plugins" {
  count="$BATS_TEST_TMPDIR/bar-attempts"
  fake_dms="$BATS_TEST_TMPDIR/dms"
  cat > "$fake_dms" <<'EOF'
#!/usr/bin/env bash
count_file="${BATS_TEST_TMPDIR}/bar-attempts"
attempt=0
[[ ! -f "$count_file" ]] || read -r attempt < "$count_file"
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$count_file"
if ((attempt == 1)); then
  printf '%s\n' 'Target not found.'
else
  printf '%s\n' top
fi
EOF
  chmod +x "$fake_dms"

  run wait_for_bar_position "$fake_dms" 3 0
  [ "$status" -eq 0 ]
  [ "$output" = top ]
  [ "$(< "$count")" = 2 ]
}

@test "le provisioning n'accepte qu'un plugin chargé de façon stable" {
  count="$BATS_TEST_TMPDIR/plugin-status-attempts"
  fake_dms="$BATS_TEST_TMPDIR/dms-plugin"
  cat > "$fake_dms" <<'EOF'
#!/usr/bin/env bash
count_file="${BATS_TEST_TMPDIR}/plugin-status-attempts"
if [[ $4 == enable ]]; then
  exit 0
fi
attempt=0
[[ ! -f "$count_file" ]] || read -r attempt < "$count_file"
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$count_file"
if ((attempt == 1)); then
  printf '%s\n' disabled
else
  printf '%s\n' loaded
fi
EOF
  chmod +x "$fake_dms"

  run ensure_plugin_loaded "$fake_dms" eschatonUpdate 4 0
  [ "$status" -eq 0 ]
  [ "$(< "$count")" = 3 ]
}

@test "la vague v2 active aussi le daemon assistant sans l'ajouter à la barre" {
  provision="$BATS_TEST_DIRNAME/../packages/eschaton-desktop-config/eschaton-dms-provision"
  run grep -F 'for plugin in eschatonUpdate eschatonRollback eschatonAssistant' "$provision"
  [ "$status" -eq 0 ]

  run grep -F '.eschaton-plugins-provisioned-v2' "$provision"
  [ "$status" -eq 0 ]

  add_eschaton_widgets "$settings"
  run jq -e '[.barConfigs[0].rightWidgets[] | select(. == "eschatonAssistant")] | length == 0' "$settings"
  [ "$status" -eq 0 ]
}

@test "la barre mémoire doit contenir les deux widgets Eschaton" {
  fake_dms="$BATS_TEST_TMPDIR/dms-settings"
  cat > "$fake_dms" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${DMS_BAR_CONFIGS}"
EOF
  chmod +x "$fake_dms"

  export DMS_BAR_CONFIGS='[{"rightWidgets":["systemTray","eschatonUpdate","eschatonRollback"]}]'
  run dms_bar_has_eschaton_widgets "$fake_dms"
  [ "$status" -eq 0 ]

  export DMS_BAR_CONFIGS='[{"rightWidgets":["systemTray"]}]'
  run dms_bar_has_eschaton_widgets "$fake_dms"
  [ "$status" -eq 1 ]
}

@test "la recomposition DMS est demandée sans bloquer le oneshot" {
  calls="$BATS_TEST_TMPDIR/systemctl-calls"
  fake_systemctl="$BATS_TEST_TMPDIR/systemctl"
  cat > "$fake_systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${BATS_TEST_TMPDIR}/systemctl-calls"
EOF
  chmod +x "$fake_systemctl"

  run request_dms_recompose "$fake_systemctl"
  [ "$status" -eq 0 ]
  [ "$(< "$calls")" = "--user --no-block restart dms.service" ]
}

@test "un settings absent puis partiellement écrit devient prêt dans la même session" {
  rm "$settings"
  settings_ticks=0
  sleep() {
    settings_ticks=$((settings_ticks + 1))
    if ((settings_ticks == 1)); then
      printf '{"barConfigs":' > "$settings"
    else
      printf '{"theme":"personnel"}' > "$settings"
    fi
  }
  wait_for_settings "$settings" 3 0
  [ "$settings_ticks" -eq 2 ]
  [ "$(jq -r .theme "$settings")" = personnel ]
}

@test "l'attente settings est bornée et ne remplace jamais un fichier invalide" {
  printf 'incomplet' > "$settings"
  settings_ticks=0
  sleep() { settings_ticks=$((settings_ticks + 1)); }
  if wait_for_settings "$settings" 3 0; then
    return 1
  fi
  [ "$settings_ticks" -eq 3 ]
  [ "$(cat "$settings")" = incomplet ]
}

prepare_delayed_session() {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export DMS_TEST_SETTINGS="$XDG_CONFIG_HOME/DankMaterialShell/settings.json"
  export DMS_TEST_TICKS="$BATS_TEST_TMPDIR/ticks"
  export DMS_TEST_CALLS="$BATS_TEST_TMPDIR/calls"
  export DMS_TEST_APPEARS_AT=65
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/sleep" <<'SH'
#!/usr/bin/env bash
n=0
[[ ! -f "$DMS_TEST_TICKS" ]] || read -r n < "$DMS_TEST_TICKS"
n=$((n + 1))
printf '%s\n' "$n" > "$DMS_TEST_TICKS"
if ((n == DMS_TEST_APPEARS_AT)); then
  mkdir -p "$(dirname "$DMS_TEST_SETTINGS")"
  printf '%s\n' '{"theme":"personnel","barConfigs":[{"rightWidgets":["systemTray"]}]}' > "$DMS_TEST_SETTINGS"
fi
SH
  cat > "$BATS_TEST_TMPDIR/bin/dms" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DMS_TEST_CALLS"
case "$*" in
  'ipc call plugins list') echo 'plugins' ;;
  'ipc call bar getPosition index 0') echo top ;;
  'ipc call bar setPosition index 0 top') : ;;
  'ipc call wallpaper get') echo /home/user/personal.png ;;
  'ipc call plugins status '*) echo loaded ;;
  'ipc call settings get barConfigs') echo '[{"rightWidgets":["systemTray"]}]' ;;
  *) exit 1 ;;
esac
SH
  cat > "$BATS_TEST_TMPDIR/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DMS_TEST_CALLS"
exit "${DMS_TEST_RESTART_RC:-0}"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export ESCHATON_DMS_BIN="$BATS_TEST_TMPDIR/bin/dms"
  export ESCHATON_SYSTEMCTL_BIN="$BATS_TEST_TMPDIR/bin/systemctl"
  provision_script="$BATS_TEST_DIRNAME/../packages/eschaton-desktop-config/eschaton-dms-provision"
  provision_stamp="$XDG_CONFIG_HOME/DankMaterialShell/.eschaton-plugins-provisioned-v2"
}

@test "première session lente : le programme attend 65 ticks, compose et ne rejoue pas le succès" {
  prepare_delayed_session
  run bash "$provision_script"
  [ "$status" -eq 0 ]
  [ -f "$provision_stamp" ]
  [ "$(jq -r .theme "$DMS_TEST_SETTINGS")" = personnel ]
  [ "$(jq -c '.barConfigs[0].rightWidgets' "$DMS_TEST_SETTINGS")" = '["systemTray","eschatonUpdate","eschatonRollback"]' ]
  grep -qx -- '--user --no-block restart dms.service' "$DMS_TEST_CALLS"
  calls_before=$(cat "$DMS_TEST_CALLS")
  run bash "$provision_script"
  [ "$status" -eq 0 ]
  [ "$(cat "$DMS_TEST_CALLS")" = "$calls_before" ]
}

@test "DMS absent : le programme échoue après 90 ticks sans marqueur ni IPC" {
  prepare_delayed_session
  export DMS_TEST_APPEARS_AT=999
  run bash "$provision_script"
  [ "$status" -eq 1 ]
  [[ "$output" == *'après 90 s'* ]]
  [ "$(cat "$DMS_TEST_TICKS")" -eq 90 ]
  [ ! -e "$provision_stamp" ]
  [ ! -e "$DMS_TEST_CALLS" ]
}

@test "une recomposition refusée laisse le provisioning rejouable" {
  prepare_delayed_session
  export DMS_TEST_RESTART_RC=1
  run bash "$provision_script"
  [ "$status" -eq 1 ]
  [ ! -e "$provision_stamp" ]
  export DMS_TEST_RESTART_RC=0
  run bash "$provision_script"
  [ "$status" -eq 0 ]
  [ -f "$provision_stamp" ]
  [ "$(jq '[.barConfigs[0].rightWidgets[] | select(. == "eschatonUpdate")] | length' "$DMS_TEST_SETTINGS")" -eq 1 ]
}
