#!/usr/bin/env bats

setup() {
  # Sourcer le lanceur ne démarre pas Hyprland : sa logique est protégée par
  # un main guard précisément pour rendre cet amorçage testable sans session.
  source "$BATS_TEST_DIRNAME/../packages/eschaton-desktop-config/eschaton-session"
  hypr_dir="$BATS_TEST_TMPDIR/hypr"
  binds_user="$hypr_dir/dms/binds-user.lua"
  hook_stamp="$hypr_dir/.eschaton-hook"
  defaults=/usr/share/eschaton/hypr/eschaton-defaults.lua
  hook="dofile(\"$defaults\")"
  dms_config_dir="$BATS_TEST_TMPDIR/DankMaterialShell"
  dms_settings="$dms_config_dir/settings.json"
}

@test "le seed DMS crée un objet vide mais ne remplace jamais les réglages" {
  ensure_dms_settings_seed
  [ "$(cat "$dms_settings")" = "{}" ]

  printf '%s\n' '{"theme":"custom"}' > "$dms_settings"
  ensure_dms_settings_seed
  [ "$(cat "$dms_settings")" = '{"theme":"custom"}' ]
}

@test "le hook Eschaton est ajouté et marqué une seule fois" {
  ensure_eschaton_hook
  [ -e "$hook_stamp" ]
  [ "$(grep -cF "$hook" "$binds_user")" -eq 1 ]

  ensure_eschaton_hook
  [ "$(grep -cF "$hook" "$binds_user")" -eq 1 ]
}

@test "un hook préexistant est marqué sans être dupliqué" {
  mkdir -p "$(dirname "$binds_user")"
  printf '%s\n' "$hook" > "$binds_user"

  ensure_eschaton_hook
  [ -e "$hook_stamp" ]
  [ "$(grep -cF "$hook" "$binds_user")" -eq 1 ]
}

@test "retirer volontairement le hook après amorçage est respecté" {
  ensure_eschaton_hook
  printf '%s\n' '-- configuration utilisateur' > "$binds_user"

  ensure_eschaton_hook
  ! grep -qF "$hook" "$binds_user"
}
