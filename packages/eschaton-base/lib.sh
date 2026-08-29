#!/usr/bin/env bash
# Fonctions pures du socle Eschaton. Sourcé par eschaton-update/-rollback.

check_free_space_kb() { # $1=dispo_kb $2=minimum_kb
  [[ "$1" -ge "$2" ]]
}

running_kernel_missing_modules() { # $1=/usr/lib/modules $2=$(uname -r)
  [[ ! -d "$1/$2" ]]
}

# ————— Interdiction d'auto-approbation dans le chemin de mise à jour —————
#
# Jusqu'au 2026-08-30, cette fonction traduisait `--yes` — l'interface stable
# d'Eschaton — en `--noconfirm`. Autrement dit, la mise à jour d'Eschaton
# répondait « oui » à la place de l'utilisateur : aux remplacements de paquets,
# aux retraits de conflits, aux imports de clés. C'est l'anti-modèle que le
# projet bannit partout ailleurs, et il était actif ici, y compris par l'outil
# `trigger_update` de l'assistant. La traduction est supprimée.
#
# Les options sont désormais REFUSÉES, pas ignorées. Une option silencieusement
# ignorée laisse croire à l'appelant qu'elle a pris effet, et le prochain
# lecteur la remet ; un refus rend la faute visible au premier appel.
pacman_auto_approve_arg() { # $1=argument ; rc=0 si l'option répond à la place de l'humain
  case "$1" in
    # Répond à toutes les questions.
    --noconfirm|--yes) return 0 ;;
    # `--ask` préremplit les réponses par un masque de bits : même effet, moins
    # lisible encore.
    --ask|--ask=*) return 0 ;;
    # `--overwrite` fait passer outre un conflit de fichiers — exactement la
    # décision humaine de l'archétype `linux-firmware` (spec §4). La porte de
    # secours de ce cas est `pacman` dans un terminal, jamais une option
    # d'`eschaton-update` : l'ajouter « par robustesse » écraserait des fichiers
    # que personne n'a examinés.
    --overwrite|--overwrite=*) return 0 ;;
    *) return 1 ;;
  esac
}

# Rend les arguments destinés à pacman, inchangés, ou échoue si l'un d'eux
# supprime une question. Rien n'est écrit sur la sortie standard en cas
# d'échec : l'appelant n'a jamais à filtrer un résultat partiel.
pacman_update_args() {
  local arg
  for arg in "$@"; do
    if pacman_auto_approve_arg "$arg"; then
      printf 'eschaton-update : option interdite dans le chemin de mise à jour : %s\n' "$arg" >&2
      printf "  Une mise à jour ne répond jamais à la place de l'utilisateur.\n" >&2
      return 1
    fi
  done
  (($# == 0)) || printf '%s\n' "$@"
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

# Interface non interactive volontairement minuscule : pkexec authentifie le
# PROGRAMME, pas ses arguments. N'accepter que la forme exacte `--yes N`
# empêche qu'un appel privilégié soit détourné vers une autre opération.
noninteractive_rollback_number() {
  (($# == 2)) || return 1
  [[ $1 == --yes ]] || return 1
  valid_snapshot_number "$2" || return 1
  printf '%s\n' "$2"
}

# Vrai quand la racine vit SOUS le sous-volume des snapshots, c'est-à-dire quand
# on a démarré sur une entrée « Snapshots » du menu Limine. Le remplacement de
# sous-volume n'a alors aucun sens : il abîmerait le magasin de snapshots au lieu
# de restaurer `@`. C'est `limine-snapper-restore` qu'il faut, pas celui-ci.
booted_on_snapshot() { # $1=sous-volume racine $2=sous-volume des snapshots
  [[ $1 == "$2"/* ]]
}
