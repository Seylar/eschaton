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

# ————————— Pré-vol : « cette transaction demande-t-elle une décision ? » —————
#
# `checkupdates` répond à « y a-t-il des mises à jour ? », jamais à « faut-il
# une décision humaine ? ». La seconde question est celle qui conditionne le
# zéro-terminal.
#
# Le pré-vol emprunte le VRAI chemin (`pacman -Syu`, entrée standard sur
# /dev/null), pas `--print`. Mesuré le 2026-08-30 : un `--print` est
# structurellement AVEUGLE à l'interactivité. Son `cb_question` répond
# lui-même, sans rien afficher — source amont `src/pacman/callback.c` :
#
#     if(config->print) {
#             switch(question->type) {
#                     case ALPM_QUESTION_INSTALL_IGNOREPKG:
#                     case ALPM_QUESTION_REPLACE_PKG:
#                             question->any.answer = 1;      /* OUI, en silence */
#                             break;
#                     default:
#                             question->any.answer = 0;
#                             break;
#             }
#             return;
#     }
#
# Sur le vrai chemin, en revanche, EOF fait répondre NON à tout (§ `question()`
# de util.c) : le pré-vol s'arrête au sommaire sans avoir rien téléchargé ni
# installé, et il aura AFFICHÉ chaque question rencontrée.
#
# Viser les marqueurs plutôt que d'énumérer les messages : toute question de
# pacman passe par `question()` ou `select_question()`, qui impriment l'un de
# ces quatre motifs. Une invite ajoutée en amont demain sera donc attrapée sans
# que personne n'ait à mettre cette liste à jour.
#
# Suppose une locale déterministe côté appelant (`LC_ALL=C.UTF-8`) : ces textes
# sont traduits.
update_marqueurs_invite() {
  printf '%s\n' '\[Y/n\]|\[y/N\]|Enter a number|Enter a selection'
}

# La question du sommaire — la seule à laquelle l'humain a déjà répondu, devant
# la modale polkit. C'est elle qu'on cherche à isoler des autres.
update_marqueur_sommaire() {
  printf '%s\n' 'Proceed with installation'
}

# Verdict du pré-vol, en un mot :
#
#   rien      il n'y a rien à mettre à jour ;
#   propre    une seule question a été posée, et c'est le sommaire — la
#             transaction peut recevoir l'unique réponse déjà authentifiée ;
#   decision  une question A PRÉCÉDÉ le sommaire (remplacement, conflit, choix
#             de fournisseur…). Eschaton s'arrête : y répondre serait répondre
#             à la place de l'utilisateur ;
#   erreur    la transaction ne se résout pas.
#
# On échoue fermé : tout ce qui n'est pas franchement propre est traité comme
# une décision humaine.
verdict_prevol() { # $1=fichier de sortie du pré-vol $2=code de retour de pacman
  local invites invites_du_sommaire
  # ON COMPTE LES INVITES, PAS LES LIGNES — corrigé le 2026-08-30 (revue de
  # sécurité I2). `grep -cE` compte des LIGNES : deux invites qui partagent une
  # ligne n'en valaient qu'une, le verdict tombait sur « propre », et le
  # `printf 'y'` de la transaction allait approuver LA PREMIÈRE question — un
  # remplacement de paquet — au lieu du sommaire. Ce n'est pas théorique :
  # pacman écrit bien deux messages sur une même ligne, on l'a mesuré (le cas
  # « … [Y/n]  there is nothing to do » ci-dessous, vm-dev.md §31.3).
  # `grep -oE | wc -l` compte les OCCURRENCES. Le `|| true` protège du
  # `pipefail` de l'appelant quand il n'y en a aucune.
  invites=$({ grep -oE "$(update_marqueurs_invite)" "$1" || true; } | wc -l | tr -d ' ')
  # Et l'unique invite doit être CELLE DU SOMMAIRE. On ne se contente pas de
  # constater que le sommaire est quelque part dans le fichier : on exige que
  # l'invite comptée soit portée par une ligne de sommaire. Sans cela, une
  # question isolée sur une ligne et un sommaire sans invite lisible ailleurs
  # passeraient ensemble pour un pré-vol propre.
  invites_du_sommaire=$({ grep -F "$(update_marqueur_sommaire)" "$1" || true; } \
    | { grep -oE "$(update_marqueurs_invite)" || true; } | wc -l | tr -d ' ')
  # Les questions AVANT « rien à faire », et l'ordre n'est pas cosmétique.
  # Mesuré le 2026-08-30 sur un vrai remplacement de paquet : après notre refus
  # du remplacement, pacman n'avait plus rien à faire et écrivait
  # « there is nothing to do » — sur la même ligne que la question. Tester
  # « rien à faire » d'abord transformait donc une décision humaine en succès
  # silencieux, ce qui est précisément le mensonge qu'on veut interdire.
  if ((invites == 1)) && ((invites_du_sommaire == 1)); then
    printf 'propre\n'
  elif ((invites >= 1)); then
    printf 'decision\n'
  elif grep -qF 'nothing to do' "$1"; then
    printf 'rien\n'
  elif (($2 != 0)); then
    printf 'erreur\n'
  else
    printf 'rien\n'
  fi
}

# Un verrou pacman sans processus pacman est un verrou orphelin.
#
# Mesuré le 2026-08-30 : un `pacman` tué par SIGTERM pendant « Retrieving
# packages… » ne retire PAS `/var/lib/pacman/db.lck` — l'annulation laissait
# donc derrière elle exactement l'orphelin que la définition de terminé
# interdit. pacman lui-même dit à l'utilisateur de supprimer ce fichier « si tu
# es sûr qu'aucun gestionnaire de paquets ne tourne » : la condition est
# précisément celle-ci, et on la vérifie au lieu de la supposer.
verrou_pacman_orphelin() { # $1=chemin du verrou $2=nombre de pacman vivants
  [[ -e $1 ]] || return 1
  (($2 == 0))
}

# Un service en échec après une transaction réussie n'est PAS un succès.
#
# Archétype `dovecot >= 2.4` (nouvelle Arch du 2025-10-31) : `pacman` réussit,
# et c'est le service qui ne redémarre plus, faute de migration de sa
# configuration. Un updater qui ne lit que le code de retour annonce un succès
# franc. On compare donc la liste des unités en échec avant et après, et on ne
# retient QUE les nouvelles — celles qui étaient déjà cassées avant ne sont pas
# le fait de cette mise à jour.
unites_nouvellement_en_echec() { # $1=liste avant $2=liste après (une unité par ligne)
  comm -13 <(printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | sort -u) \
           <(printf '%s\n' "$2" | sed '/^[[:space:]]*$/d' | sort -u)
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
