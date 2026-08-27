#!/usr/bin/env bash
# Fonctions d'eschaton-install. DRY_RUN=1 => run_cmd imprime au lieu d'exécuter.

run_cmd() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then echo "DRY: $*"; else "$@"; fi
}

detect_arch() {
  # macOS dit « arm64 » là où Linux dit « aarch64 » : les tests bats tournent
  # sur le Mac, le script sur le live env — un seul dialecte en sortie.
  local m; m="$(uname -m)"
  [[ "$m" == "arm64" ]] && m="aarch64"
  echo "$m"
}

kernel_pkgs_for() { # $1 = aarch64|x86_64
  case "$1" in
    aarch64) echo "linux-aarch64" ;;
    x86_64)  echo "linux intel-ucode amd-ucode" ;;
    *) echo "architecture non gérée : $1" >&2; return 1 ;;
  esac
}

microcode_for_cpu() { # x86_64 uniquement : détection du vendeur
  if grep -q GenuineIntel /proc/cpuinfo 2>/dev/null; then echo intel-ucode
  elif grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null; then echo amd-ucode
  fi
}
