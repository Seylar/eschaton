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

keyring_pkgs_for() { # $1 = aarch64|x86_64
  # Le trousseau doit être installé EXPLICITEMENT : `base` ne tire que
  # `archlinux-keyring` (les clés Arch x86_64), y compris sur Arch Linux ARM.
  # Sans `archlinuxarm-keyring`, le système installé ne possède pas les clés qui
  # signent les paquets ALARM : `/usr/share/pacman/keyrings/` ne contient
  # qu'`archlinux.gpg`, la clé « Arch Linux ARM Build System » reste en confiance
  # « inconnue », et la PREMIÈRE mise à jour échoue sur
  # « signature de … est de confiance inconnue » (constat Task 9).
  # Le piège est silencieux : le pacstrap initial réussit, lui, car il vérifie
  # avec le trousseau de l'environnement live. Et la panne est sans issue une
  # fois installée — récupérer le trousseau demanderait de valider la signature
  # du paquet trousseau lui-même.
  case "$1" in
    aarch64) echo "archlinuxarm-keyring" ;;
    x86_64)  echo "archlinux-keyring" ;;
    *) echo "architecture non gérée : $1" >&2; return 1 ;;
  esac
}

microcode_for_cpu() { # x86_64 uniquement : détection du vendeur
  if grep -q GenuineIntel /proc/cpuinfo 2>/dev/null; then echo intel-ucode
  elif grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null; then echo amd-ucode
  fi
}
