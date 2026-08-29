#!/usr/bin/env bats
#
# Garde d'invariant : AUCUNE auto-approbation dans le chemin de mise à jour.
#
# Ce fichier ne teste pas une fonction, il tient un invariant du dépôt. Le
# 2026-08-30, la mise à jour d'Eschaton était auto-approuvée sans que personne
# ne l'ait décidé : `lib.sh` traduisait `--yes` en `--noconfirm`, et le widget
# comme l'assistant passaient `--yes`. Rien ne l'avait signalé pendant deux
# vagues de revue.
#
# La garde tient sur deux jambes, volontairement redondantes :
#
#   1. À L'EXÉCUTION — `eschaton-update` REFUSE ces options. Aucun appelant, y
#      compris un appelant futur que personne n'aurait pensé à relire, ne peut
#      donc auto-approuver. C'est la jambe qui rend la faute impossible, pas
#      seulement visible.
#   2. À LA LECTURE — aucun appel de `pacman` ni d'`eschaton-update` du chemin
#      de mise à jour ne porte une telle option, et la liste des fichiers du
#      chemin est vérifiée COMPLÈTE : on ne peut pas échapper à la garde en
#      ajoutant un fichier.
#
# Une option d'auto-approbation reste licite ailleurs (`tools/build-pkg`,
# `installer/`, les conteneurs de la CI) : ces chemins construisent ou
# amorcent un système, ils ne mettent pas à jour celui de l'utilisateur.

setup() {
  RACINE="$BATS_TEST_DIRNAME/.."
  LIB="$RACINE/packages/eschaton-base/lib.sh"
  # Les options qui répondent à la place de l'utilisateur. `--overwrite` en
  # fait partie : il tranche un conflit de fichiers (archétype linux-firmware)
  # que seul un humain devrait trancher.
  INTERDITES='--noconfirm|--yes|--ask|--overwrite'
  # Le chemin de mise à jour, déclaré. Le test de complétude ci-dessous vérifie
  # que cette liste n'a pas pris de retard sur le dépôt.
  CHEMIN=(
    "packages/eschaton-base/PKGBUILD"
    "packages/eschaton-base/eschaton-update"
    "packages/eschaton-base/lib.sh"
    "packages/eschaton-dms-plugin-assistant/ToolExecutor.qml"
    "packages/eschaton-dms-plugin-update/EschatonUpdateWidget.qml"
  )
}

# Les lignes de commentaire ne sont pas des appels : `#` pour le shell et les
# PKGBUILD, `//` pour QML. Le reste est du code, et le code, lui, s'applique.
sans_commentaires() { grep -v -E '^[[:space:]]*(#|//)'; }

# `eschaton-update` sourcé depuis le dépôt : le script cherche `lib.sh` à son
# emplacement installé, qui n'existe pas sur une machine de développement.
# On réécrit CETTE ligne dans une copie plutôt que d'ouvrir dans le script
# livré une variable d'environnement — un point d'entrée dont un chemin
# privilégié n'a pas besoin.
prepare_banc() {
  BANC="$BATS_TEST_TMPDIR/banc"
  mkdir -p "$BANC/bin"
  sed "s#^source /usr/lib/eschaton/lib.sh\$#source $LIB#" \
    "$RACINE/packages/eschaton-base/eschaton-update" > "$BANC/eschaton-update"
  chmod +x "$BANC/eschaton-update"
  grep -q "^source $LIB\$" "$BANC/eschaton-update"   # la réécriture a bien pris

  # Doublures : toute exécution réelle laisse une trace, dont l'absence est
  # elle-même l'assertion.
  for outil in pacman sudo; do
    printf '#!/bin/sh\necho "$0 $*" >> "%s/appels.txt"\nexit 0\n' "$BANC" > "$BANC/bin/$outil"
    chmod +x "$BANC/bin/$outil"
  done
  # `df --output` est une extension GNU : la doublure rend le test identique
  # sur la CI et sur une machine de développement.
  printf '#!/bin/sh\nprintf "Avail\\n99999999\\n"\n' > "$BANC/bin/df"
  chmod +x "$BANC/bin/df"
  : > "$BANC/appels.txt"
}

@test "eschaton-update refuse chaque option d'auto-approbation, sans toucher à pacman" {
  prepare_banc
  for interdite in --noconfirm --yes --ask --ask=4 --overwrite '--overwrite=/usr/lib/*'; do
    run env PATH="$BANC/bin:$PATH" "$BANC/eschaton-update" "$interdite"
    [ "$status" -ne 0 ] || {
      echo "eschaton-update a accepté : $interdite"
      return 1
    }
    [[ "$output" == *"option interdite dans le chemin de mise à jour"* ]] || {
      echo "message d'erreur inattendu pour $interdite : $output"
      return 1
    }
  done
  # Aucune transaction n'a été lancée, pas même partiellement.
  [ ! -s "$BANC/appels.txt" ] || {
    echo "pacman/sudo appelés malgré une option interdite : $(cat "$BANC/appels.txt")"
    return 1
  }
}

@test "eschaton-update s'arrête sans terminal plutôt que de laisser pacman répondre par défaut" {
  prepare_banc
  # Sans terminal sur l'entrée standard, pacman lit EOF et applique SES
  # réponses par défaut : une auto-approbation qui ne s'écrit nulle part.
  run env PATH="$BANC/bin:$PATH" "$BANC/eschaton-update" < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"pas de terminal sur l'entrée standard"* ]]
  [ ! -s "$BANC/appels.txt" ] || {
    echo "pacman/sudo appelés sans terminal : $(cat "$BANC/appels.txt")"
    return 1
  }
}

@test "aucun appel de pacman du chemin de mise à jour ne porte d'option d'auto-approbation" {
  for fichier in "${CHEMIN[@]}"; do
    [ -f "$RACINE/$fichier" ] || {
      echo "fichier déclaré absent : $fichier"
      return 1
    }
    suspectes=$(grep -n -E -- "pacman" "$RACINE/$fichier" \
      | grep -E -- "$INTERDITES" \
      | grep -v -E '^[0-9]+:[[:space:]]*(#|//)' || true)
    [ -z "$suspectes" ] || {
      echo "appel pacman auto-approuvé dans $fichier :"
      echo "$suspectes"
      return 1
    }
  done
}

@test "aucun appel d'eschaton-update ne porte d'option d'auto-approbation" {
  # Portée volontairement plus large que la liste : tout `packages/`. Un
  # appelant oublié serait attrapé ici avant même le test de complétude.
  #
  # L'examen porte sur un CONTEXTE, pas sur une ligne : un tableau de commande
  # QML met chaque argument sur sa propre ligne, et une garde ligne-à-ligne ne
  # verrait jamais le `--yes` qui suit le chemin du programme. L'ancrage sur
  # `/usr/bin/eschaton-update` vise l'invocation, non les mentions du nom dans
  # les messages ou les commentaires.
  suspectes=$(grep -rn --exclude-dir=pkg --exclude='*.pkg.tar.*' -B1 -A6 \
    -e '/usr/bin/eschaton-update' "$RACINE/packages" \
    | grep -E -- "$INTERDITES" \
    | grep -v -E '[-:][[:space:]]*(#|//)' || true)
  [ -z "$suspectes" ] || {
    echo "appel d'eschaton-update auto-approuvé :"
    echo "$suspectes"
    return 1
  }
}

@test "la liste du chemin de mise à jour est complète" {
  # Le point faible d'une garde textuelle est le fichier qu'on oublie d'y
  # inscrire. On recalcule donc la liste depuis le dépôt et on la compare.
  reel=$(cd "$RACINE" && grep -rl --exclude-dir=pkg --exclude='*.pkg.tar.*' \
    -e 'eschaton-update' packages | sort)
  declare_=$(printf '%s\n' "${CHEMIN[@]}" | sort)
  [ "$reel" = "$declare_" ] || {
    echo "la liste CHEMIN a divergé du dépôt."
    echo "— dans le dépôt :"; echo "$reel"
    echo "— déclarés ici  :"; echo "$declare_"
    echo "Ajoute le fichier manquant à CHEMIN (et vérifie qu'il n'auto-approuve rien)."
    return 1
  }
}

@test "lib.sh ne traduit plus rien vers une option d'auto-approbation" {
  source "$LIB"
  # La traduction supprimée le 2026-08-30 rendait `--noconfirm` sur stdout.
  for interdite in --yes --noconfirm --ask --overwrite; do
    if sortie=$(pacman_update_args "$interdite" 2>/dev/null); then
      echo "pacman_update_args a accepté $interdite"
      return 1
    fi
    [ -z "$sortie" ] || {
      echo "pacman_update_args a produit « $sortie » pour $interdite"
      return 1
    }
  done
  # Et il ne fabrique pas non plus l'option à partir d'un argument anodin.
  sortie=$(pacman_update_args --needed --sysupgrade)
  [[ "$sortie" != *"--noconfirm"* ]]
}
