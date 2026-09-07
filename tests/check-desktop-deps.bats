#!/usr/bin/env bats

setup() {
  tool="$BATS_TEST_DIRNAME/../tools/check-desktop-deps"
}

@test "une option sans valeur rend une erreur d'usage contrôlée" {
  run "$tool" --pkgbuild
  [ "$status" -eq 2 ]
  [[ "$output" == *"attend un chemin"* ]]
}

@test "un PKGBUILD additionnel sans valeur rend aussi une erreur d'usage" {
  run "$tool" --also-pkgbuild
  [ "$status" -eq 2 ]
  [[ "$output" == *"--also-pkgbuild attend un chemin"* ]]
}

@test "une panne de l'API Arch est une erreur d'outillage, pas un paquet absent" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
url=${!#}
case "$url" in
  */core/|*/extra/) printf '%s\n' 'href="foo-1.0-1-aarch64.pkg.tar.xz"' ;;
  *) exit 7 ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  cat > "$BATS_TEST_TMPDIR/PKGBUILD" <<'EOF'
pkgname=test-desktop
depends=(foo)
EOF

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run "$tool" \
    --pkgbuild "$BATS_TEST_TMPDIR/PKGBUILD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"API Arch injoignable"* ]]
  [[ "$output" != *"ABSENT"* ]]
}
