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
