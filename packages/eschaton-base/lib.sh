#!/usr/bin/env bash
# Fonctions pures du socle Eschaton. Sourcé par eschaton-update/-rollback.

check_free_space_kb() { # $1=dispo_kb $2=minimum_kb
  [[ "$1" -ge "$2" ]]
}

running_kernel_missing_modules() { # $1=/usr/lib/modules $2=$(uname -r)
  [[ ! -d "$1/$2" ]]
}

# `--yes` est l'interface stable d'Eschaton (CLI et plugin DMS), alors que
# pacman nomme cette option `--noconfirm`. Transmettre `--yes` tel quel fait
# échouer pacman avant même la résolution des paquets.
pacman_update_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --yes) printf '%s\n' --noconfirm ;;
      *) printf '%s\n' "$arg" ;;
    esac
  done
}

# `findmnt -no SOURCE` rend « /dev/vda2[/@] » pour un montage de sous-volume
# btrfs, et « /dev/vda2 » tout court sinon. Les deux moitiés se lisent séparément.

device_of_source() { # $1=source findmnt -> « /dev/vda2 »
  printf '%s\n' "${1%%\[*}"
}

subvol_of_source() { # $1=source findmnt -> « @ » ; rc=1 si pas de sous-volume
  local s=$1
  [[ $s == *'['*']' ]] || return 1
  s=${s##*\[}
  s=${s%\]}
  s=${s#/}
  [[ -n $s ]] || return 1
  printf '%s\n' "$s"
}

# Chemin d'un snapshot snapper vu depuis la racine du système de fichiers btrfs
# (subvolid=5) : le sous-volume des snapshots, le numéro, puis « snapshot ».
snapshot_subvol_path() { # $1=sous-volume des snapshots $2=numéro
  printf '%s/%s/snapshot\n' "$1" "$2"
}

# Le 0 de `snapper list` est le pseudo-snapshot « current » : il ne désigne
# aucun sous-volume et n'est donc pas une cible de restauration.
valid_snapshot_number() { # $1=saisie de l'utilisateur
  [[ $1 =~ ^[0-9]+$ ]] || return 1
  ((10#$1 > 0))
}

# Vrai quand la racine vit SOUS le sous-volume des snapshots, c'est-à-dire quand
# on a démarré sur une entrée « Snapshots » du menu Limine. Le remplacement de
# sous-volume n'a alors aucun sens : il abîmerait le magasin de snapshots au lieu
# de restaurer `@`. C'est `limine-snapper-restore` qu'il faut, pas celui-ci.
booted_on_snapshot() { # $1=sous-volume racine $2=sous-volume des snapshots
  [[ $1 == "$2"/* ]]
}
