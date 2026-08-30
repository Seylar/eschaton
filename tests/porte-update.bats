#!/usr/bin/env bats
#
# La porte privilégiée de la mise à jour : `org.eschaton.update` +
# `eschaton-update-helper`.
#
# `pkexec` authentifie le PROGRAMME, pas ses arguments. Tout ce qui suit
# découle de cette phrase : l'argv de la porte est un ensemble fermé, il n'est
# jamais interpolé dans la commande privilégiée, et la validation est refaite
# du côté de l'exécution — la porte ne fait pas confiance à son appelant pour
# avoir vérifié quoi que ce soit (motif de la revue T5).

setup() {
  RACINE="$BATS_TEST_DIRNAME/.."
  PORTE="$RACINE/packages/eschaton-base/eschaton-update-helper"
  # L'action vit auprès du binaire qu'elle épingle depuis le 2026-08-30 (revue
  # de sécurité C1) : voir tests/actions-avec-binaires.bats pour la garde qui
  # interdit qu'ils se séparent de nouveau.
  POLICY="$RACINE/packages/eschaton-base/org.eschaton.update.policy"
}

# Doublures de `systemd-run` et `systemctl` : toute exécution laisse une trace,
# dont l'ABSENCE est l'assertion des tests de refus.
prepare_banc() {
  BANC="$BATS_TEST_TMPDIR/banc"
  mkdir -p "$BANC/bin"
  for outil in systemd-run systemctl pacman; do
    printf '#!/bin/sh\necho "$0 $*" >> "%s/appels.txt"\nexit 0\n' "$BANC" > "$BANC/bin/$outil"
    chmod +x "$BANC/bin/$outil"
  done
  : > "$BANC/appels.txt"
}

@test "la porte n'accepte que --apply et --cancel, et rien d'autre" {
  prepare_banc
  # Un seul mot, parmi deux. Tout le reste — y compris une forme voisine, une
  # option supplémentaire, ou un argument qui ressemble à une commande — est
  # refusé AVANT le moindre effet.
  refus=(
    ""                       # aucun argument
    "--apply --cancel"       # deux arguments
    "--apply 42"
    "--Apply"
    "--apply=1"
    "-a"
    "--status"
    "--transaction"
    "; systemctl stop sshd"
    "--apply; reboot"
    "/usr/bin/pacman"
  )
  for forme in "${refus[@]}"; do
    # shellcheck disable=SC2086 — le découpage est justement ce qu'on teste.
    run env PATH="$BANC/bin:$PATH" bash "$PORTE" $forme
    [ "$status" -eq 2 ] || {
      echo "forme « $forme » : rc=$status attendu 2 — sortie : $output"
      return 1
    }
    [[ "$output" == *"usage: eschaton-update-helper --apply|--cancel"* ]] || {
      echo "forme « $forme » : pas de message d'usage — $output"
      return 1
    }
  done
  [ ! -s "$BANC/appels.txt" ] || {
    echo "la porte a agi malgré un argv refusé : $(cat "$BANC/appels.txt")"
    return 1
  }
}

@test "la porte refuse d'agir sans être root, même avec un argv valide" {
  if [ "$EUID" -eq 0 ]; then
    skip "test écrit pour un appelant non privilégié"
  fi
  prepare_banc
  for forme in --apply --cancel; do
    run env PATH="$BANC/bin:$PATH" bash "$PORTE" "$forme"
    [ "$status" -eq 1 ]
    [[ "$output" == *"doit être lancé comme root (par pkexec)"* ]]
  done
  # La validation est refaite du côté de l'EXÉCUTION : rien n'a été tenté.
  [ ! -s "$BANC/appels.txt" ] || {
    echo "la porte a agi sans privilège : $(cat "$BANC/appels.txt")"
    return 1
  }
}

@test "la commande privilégiée est constante : aucun argument n'y est interpolé" {
  # Tout ce que la porte EXÉCUTE vit dans son `case "$action"`. Aucune
  # expansion d'argument n'y est permise — ni "$1", ni "$@", ni "$*" : le nom
  # de l'unité et la ligne de commande sont des constantes du fichier.
  bloc=$(awk '/^case "\$action" in$/,/^esac$/' "$PORTE")
  [ -n "$bloc" ] || {
    echo "le bloc d'exécution de la porte est introuvable — test à réécrire"
    return 1
  }
  suspectes=$(printf '%s\n' "$bloc" | grep -E '\$[1-9@*]|\$\{[1-9@*]' || true)
  [ -z "$suspectes" ] || {
    echo "argument interpolé dans la commande privilégiée :"
    echo "$suspectes"
    return 1
  }

  # Et les commandes privilégiées sont désignées par leur chemin absolu :
  # un programme lancé par pkexec ne doit pas dépendre du PATH qu'on lui donne.
  run grep -F 'readonly SYSTEMCTL=/usr/bin/systemctl' "$PORTE"
  [ "$status" -eq 0 ]
  run grep -F 'readonly SYSTEMD_RUN=/usr/bin/systemd-run' "$PORTE"
  [ "$status" -eq 0 ]
  nues=$(printf '%s\n' "$bloc" | grep -E '(^|[^"/A-Za-z_-])(systemctl|systemd-run)[[:space:]]' \
    | grep -v -E '^[[:space:]]*#' || true)
  [ -z "$nues" ] || {
    echo "commande privilégiée appelée sans chemin absolu :"
    echo "$nues"
    return 1
  }
  # Et la charge de l'unité est bien le mode transaction, pas pacman en direct :
  # la porte délègue, elle ne porte pas la transaction.
  run grep -F '/usr/bin/eschaton-update --transaction' "$PORTE"
  [ "$status" -eq 0 ]
  run grep -E '^[[:space:]]*(exec[[:space:]]+)?(sudo[[:space:]]+)?pacman' "$PORTE"
  [ "$status" -eq 1 ]
}

@test "l'unité de transaction ferme l'entrée standard, donc pacman ne peut rien approuver" {
  # `StandardInput=null` n'est pas un détail de confort : sur EOF, `question()`
  # de pacman rend « non » (src/pacman/util.c, relu le 2026-08-30). C'est ce
  # qui garantit qu'une transaction non surveillée échoue au lieu d'approuver.
  run grep -F -- '--property=StandardInput=null' "$PORTE"
  [ "$status" -eq 0 ]
}

@test "l'action polkit exige une authentification, sans mémorisation" {
  # On lit le bloc <defaults> lui-même, pas la prose du fichier : l'en-tête
  # explique justement pourquoi `auth_admin_keep` est proscrit, et le citer ne
  # doit pas faire échouer la garde.
  defauts=$(awk '/<defaults>/,/<\/defaults>/' "$POLICY")
  [[ "$defauts" == *"<allow_active>auth_admin</allow_active>"* ]] || {
    echo "allow_active attendu à auth_admin : $defauts"
    return 1
  }
  # `auth_admin_keep` couvrirait un appel privilégié ultérieur que personne
  # n'aurait vu passer : une mise à jour = une authentification.
  [[ "$defauts" != *"_keep"* ]] || {
    echo "autorisation mémorisée dans les défauts : $defauts"
    return 1
  }
  [[ "$defauts" == *"<allow_any>no</allow_any>"* ]]
  [[ "$defauts" == *"<allow_inactive>no</allow_inactive>"* ]]
  run grep -F '<action id="org.eschaton.update">' "$POLICY"
  [ "$status" -eq 0 ]
  # L'annotation épingle le programme — le seul mécanisme qui le fasse.
  run grep -F 'org.freedesktop.policykit.exec.path">/usr/bin/eschaton-update-helper<' "$POLICY"
  [ "$status" -eq 0 ]
}

@test "aucune règle polkit permissive n'est livrée par le dépôt" {
  # Une règle `rules.d` rendant YES supprimerait l'authentification sans que le
  # fichier de politique le montre. Elle a déjà été retirée du rollback le
  # 2026-08-28 ; elle ne revient pas par l'update.
  # On regarde ce qui est LIVRÉ, pas ce qui est écrit : les en-têtes des deux
  # politiques expliquent longuement pourquoi aucune règle n'existe, et les
  # citer ne doit pas déclencher la garde.
  reglees=$(find "$RACINE/packages" -name '*.rules' -not -path '*/pkg/*' -not -path '*/src/*' || true)
  [ -z "$reglees" ] || {
    echo "fichier de règles polkit dans le dépôt : $reglees"
    return 1
  }
  installees=$(grep -rn --exclude-dir=pkg --include=PKGBUILD 'polkit-1/rules\.d' "$RACINE/packages" || true)
  [ -z "$installees" ] || {
    echo "un PKGBUILD installe une règle polkit : $installees"
    return 1
  }
  # Et aucun fichier de politique ne rend YES sans authentification.
  for politique in $(find "$RACINE/packages" -name '*.policy' -not -path '*/pkg/*' -not -path '*/src/*'); do
    defauts=$(awk '/<defaults>/,/<\/defaults>/' "$politique")
    [[ "$defauts" != *">yes<"* ]] || {
      echo "autorisation implicite sans authentification dans $politique : $defauts"
      return 1
    }
  done
}

@test "le paquet livre la politique et le binaire de la porte" {
  run grep -F 'install -Dm755 eschaton-update-helper "$pkgdir/usr/bin/eschaton-update-helper"' \
    "$RACINE/packages/eschaton-base/PKGBUILD"
  [ "$status" -eq 0 ]
  run grep -F 'eschaton-update-helper' "$RACINE/packages/eschaton-base/PKGBUILD"
  [ "$status" -eq 0 ]
  # LE MÊME paquet, et c'est tout l'objet du correctif C1 : le binaire arrivait
  # sur les machines sans l'action qui le contraint, parce qu'elle était livrée
  # par un greffon que l'installeur ne pacstrape pas.
  run grep -F 'usr/share/polkit-1/actions/org.eschaton.update.policy' \
    "$RACINE/packages/eschaton-base/PKGBUILD"
  [ "$status" -eq 0 ]
  # Autant de sommes que de sources : un oubli ici casse silencieusement
  # makepkg.
  for pkgbuild in "$RACINE/packages/eschaton-base/PKGBUILD" \
                  "$RACINE/packages/eschaton-dms-plugin-update/PKGBUILD"; do
    sources=$(awk '/^source=\(/,/\)$/' "$pkgbuild" | tr ' ' '\n' \
      | grep -cE '^[A-Za-z0-9]' || true)
    sommes=$(awk '/^sha256sums=\(/,/\)$/' "$pkgbuild" | tr ' ' '\n' \
      | grep -c 'SKIP' || true)
    [ "$sources" -eq "$sommes" ] || {
      echo "$pkgbuild : $sources sources pour $sommes sommes"
      return 1
    }
  done
}

@test "le pré-vol distingue le sommaire seul d'une question qui le précède" {
  source "$RACINE/packages/eschaton-base/lib.sh"
  sortie="$BATS_TEST_TMPDIR/prevol.txt"

  # Pré-vol PROPRE : une seule question, et c'est le sommaire. La transaction
  # peut recevoir l'unique réponse déjà authentifiée devant la modale.
  # (Sortie réelle d'un `pacman -Syu` refusé au sommaire, vm-dev.md §31.)
  cat > "$sortie" <<'FIN'
:: Synchronizing package databases...
:: Starting full system upgrade...
resolving dependencies...
looking for conflicting packages...

Packages (1) qt6-base-6.11.2-3

Total Download Size:   14.11 MiB
:: Proceed with installation? [Y/n]
FIN
  run verdict_prevol "$sortie" 1
  [ "$output" = "propre" ]

  # Chaque famille de question qui PRÉCÈDE le sommaire fait basculer en
  # « decision » — y compris quand le sommaire finit par s'afficher aussi.
  declare -A avant_sommaire=(
    [remplacement]=':: Replace varnish with extra/vinyl-cache? [Y/n]'
    [conflit]=':: foo and bar are in conflict. Remove bar? [y/N]'
    [fournisseur]='Enter a number (default=1):'
    [ignore]=':: linux-firmware: local version is newer. Upgrade anyway? [y/N]'
    [selection]='Enter a selection (default=all):'
  )
  for cas in "${!avant_sommaire[@]}"; do
    printf '%s\n:: Proceed with installation? [Y/n]\n' "${avant_sommaire[$cas]}" > "$sortie"
    run verdict_prevol "$sortie" 1
    [ "$output" = "decision" ] || {
      echo "question « $cas » non détectée : verdict=$output"
      return 1
    }
    # Et même seule, sans que le sommaire soit jamais atteint (cas du conflit,
    # qui fait échouer la résolution).
    printf '%s\n' "${avant_sommaire[$cas]}" > "$sortie"
    run verdict_prevol "$sortie" 1
    [ "$output" = "decision" ] || {
      echo "question « $cas » seule non détectée : verdict=$output"
      return 1
    }
  done

  # Rien à faire : ni question, ni échec.
  printf ':: Starting full system upgrade...\n there is nothing to do\n' > "$sortie"
  run verdict_prevol "$sortie" 0
  [ "$output" = "rien" ]

  # RÉGRESSION, mesurée en VM le 2026-08-30 : après notre refus du
  # remplacement, pacman n'avait plus rien à faire et l'écrivait SUR LA MÊME
  # LIGNE que la question. Tester « rien à faire » en premier transformait une
  # décision humaine en succès silencieux. La ligne ci-dessous est la sortie
  # réelle, copiée telle quelle.
  printf ':: Replace eschaton-prevol-ancien with eschatonprevol/eschaton-prevol-nouveau? [Y/n]  there is nothing to do\n' > "$sortie"
  run verdict_prevol "$sortie" 0
  [ "$output" = "decision" ] || {
    echo "un remplacement refusé a été pris pour « rien à faire » : verdict=$output"
    return 1
  }

  # Résolution impossible, sans aucune question : ce n'est pas une décision
  # humaine, c'est une erreur — et l'interface ne doit pas les confondre.
  printf 'error: failed to prepare transaction (could not satisfy dependencies)\n' > "$sortie"
  run verdict_prevol "$sortie" 1
  [ "$output" = "erreur" ]
}

@test "deux invites sur UNE ligne ne passent pas pour un pré-vol propre" {
  source "$RACINE/packages/eschaton-base/lib.sh"
  sortie="$BATS_TEST_TMPDIR/prevol.txt"

  # REVUE DE SÉCURITÉ I2. Le verdict comptait des LIGNES (`grep -cE`), pas des
  # invites. Deux questions partageant une ligne n'en valaient donc qu'une, le
  # verdict tombait sur « propre », et le `printf 'y'` de la transaction allait
  # approuver LA PREMIÈRE — un remplacement de paquet — au lieu du sommaire.
  # Que pacman écrive deux messages sur une même ligne n'est pas une hypothèse :
  # c'est mesuré (vm-dev.md §31.3, le cas « … [Y/n]  there is nothing to do »).
  printf ':: Replace varnish with extra/vinyl-cache? [Y/n] :: Proceed with installation? [Y/n]\n' \
    > "$sortie"
  run verdict_prevol "$sortie" 1
  [ "$output" = "decision" ] || {
    echo "deux invites sur une ligne ont été prises pour un pré-vol propre : $output"
    return 1
  }

  # Et l'unique invite doit être CELLE DU SOMMAIRE : une question isolée, avec
  # un sommaire mentionné ailleurs sans invite lisible, n'est pas « propre ».
  printf ':: Replace varnish with extra/vinyl-cache? [Y/n]\nProceed with installation\n' \
    > "$sortie"
  run verdict_prevol "$sortie" 1
  [ "$output" = "decision" ] || {
    echo "une invite hors sommaire a été prise pour le sommaire : $output"
    return 1
  }

  # Contre-épreuve : le vrai sommaire, seul, reste « propre ». Une garde qui
  # refuserait tout ne prouverait rien.
  printf 'Total Download Size:   14.11 MiB\n:: Proceed with installation? [Y/n]\n' > "$sortie"
  run verdict_prevol "$sortie" 1
  [ "$output" = "propre" ]
}

@test "un verdict de pré-vol inattendu arrête la transaction (fail-closed)" {
  MAJ="$RACINE/packages/eschaton-base/eschaton-update"
  # REVUE DE SÉCURITÉ M3. Le `case` du verdict n'avait ni branche `propre`
  # explicite ni `*)` : un mot inattendu — valeur ajoutée à `verdict_prevol` et
  # oubliée ici, sortie tronquée — ne correspondait à AUCUNE branche, et le
  # script POURSUIVAIT jusqu'à la transaction. Le seul chemin qui installe doit
  # être celui qui a été explicitement autorisé, jamais celui qui reste.
  bloc=$(awk '/^case "\$verdict" in$/,/^esac$/' "$MAJ")
  [ -n "$bloc" ] || {
    echo "le case du verdict est introuvable — test à réécrire"
    return 1
  }
  [[ "$bloc" == *"propre)"* ]] || {
    echo "le verdict « propre » n'est pas une branche explicite : $bloc"
    return 1
  }
  [[ "$bloc" == *"*)"* ]] || {
    echo "le case du verdict n'a pas de branche par défaut : $bloc"
    return 1
  }
  # La branche par défaut s'ARRÊTE : elle ne se contente pas de journaliser.
  defaut=$(printf '%s\n' "$bloc" | awk '/^  \*\)$/,/;;/')
  [[ "$defaut" == *"exit 1"* ]] || {
    echo "la branche par défaut ne s'arrête pas : $defaut"
    return 1
  }
  [[ "$defaut" == *"ecrire_etat verdict-inconnu"* ]] || {
    echo "la branche par défaut ne publie pas d'état lisible par l'interface : $defaut"
    return 1
  }
}

@test "le pré-vol emprunte le vrai chemin, jamais --print" {
  MAJ="$RACINE/packages/eschaton-base/eschaton-update"
  # `--print` est structurellement aveugle : son `cb_question` répond OUI aux
  # remplacements sans rien afficher (src/pacman/callback.c). Le pré-vol l'a
  # utilisé jusqu'au 2026-08-30 et laissait donc passer exactement le cas
  # qu'il devait attraper. Il ne doit jamais revenir.
  # (Les commentaires en parlent, justement pour l'interdire ; c'est le CODE
  # qui ne doit plus le contenir.)
  suspectes=$(grep -n -F -- '--print' "$MAJ" | grep -v -E '^[0-9]+:[[:space:]]*#' || true)
  [ -z "$suspectes" ] || {
    echo "--print est revenu dans le code : $suspectes"
    return 1
  }
  run grep -F -- 'pacman -Syu "$@" < /dev/null' "$MAJ"
  [ "$status" -eq 0 ]
}

@test "un verrou pacman sans pacman est reconnu comme orphelin, et pas autrement" {
  source "$RACINE/packages/eschaton-base/lib.sh"
  verrou="$BATS_TEST_TMPDIR/db.lck"

  # Pas de verrou : rien à faire, quoi qu'il tourne.
  run verrou_pacman_orphelin "$verrou" 0
  [ "$status" -ne 0 ]

  : > "$verrou"
  # Verrou présent et aucun pacman vivant : orphelin.
  run verrou_pacman_orphelin "$verrou" 0
  [ "$status" -eq 0 ]
  # Verrou présent mais un pacman tourne ailleurs : on n'y touche PAS. Le lui
  # voler casserait une transaction légitime lancée dans un terminal.
  run verrou_pacman_orphelin "$verrou" 1
  [ "$status" -ne 0 ]
  run verrou_pacman_orphelin "$verrou" 3
  [ "$status" -ne 0 ]
}

@test "l'annulation nettoie le verrou laissé par un pacman tué" {
  MAJ="$RACINE/packages/eschaton-base/eschaton-update"
  # Mesuré le 2026-08-30 : un pacman tué pendant « Retrieving packages… »
  # laisse /var/lib/pacman/db.lck. Sans ce nettoyage, l'annulation laissait
  # l'orphelin que la définition de terminé interdit.
  section=$(awk '/if "\$annulee"; then/,/^fi$/' "$MAJ")
  [[ "$section" == *"liberer_verrou_orphelin"* ]] || {
    echo "la branche d'annulation ne libère pas le verrou"
    return 1
  }
  # Et le nettoyage est conditionnel : jamais un `rm` inconditionnel.
  run grep -E '^\s*rm -f "\$VERROU_PACMAN"' "$MAJ"
  [ "$status" -eq 0 ]
  bloc=$(awk '/^liberer_verrou_orphelin\(\)/,/^}/' "$MAJ")
  [[ "$bloc" == *"verrou_pacman_orphelin"* ]]
  [[ "$bloc" == *"pgrep -c -x pacman"* ]]
}

@test "la transaction fait un pré-vol avant d'agir, en locale déterministe" {
  source "$RACINE/packages/eschaton-base/lib.sh"
  MAJ="$RACINE/packages/eschaton-base/eschaton-update"

  # Le pré-vol n'a pas d'entrée standard : tout y est refusé, donc rien n'y est
  # téléchargé ni installé.
  run grep -F -- 'pacman -Syu "$@" < /dev/null' "$MAJ"
  [ "$status" -eq 0 ]
  # …et il précède la transaction dans le fichier.
  ligne_prevol=$(grep -n -F -- 'pacman -Syu "$@" < /dev/null' "$MAJ" | head -1 | cut -d: -f1)
  ligne_transaction=$(grep -n -F -- 'pacman -Su "$@"' "$MAJ" | head -1 | cut -d: -f1)
  [ -n "$ligne_prevol" ] && [ -n "$ligne_transaction" ]
  [ "$ligne_prevol" -lt "$ligne_transaction" ] || {
    echo "le pré-vol (ligne $ligne_prevol) ne précède pas la transaction (ligne $ligne_transaction)"
    return 1
  }
  # La transaction se joue sur les bases que le pré-vol vient de synchroniser :
  # dans toute la section `--transaction`, le seul `-Sy` est celui du pré-vol.
  # Un second rouvrirait la fenêtre entre ce qui a été vérifié et ce qui est
  # installé. (Le mode terminal, lui, fait bien un `-Syu` : un humain est là.)
  section=$(awk '/mode --transaction \(unité systemd\)/,0' "$MAJ")
  rafraichissements=$(printf '%s\n' "$section" \
    | grep -v -E '^[[:space:]]*#' \
    | grep -E 'pacman -Sy' \
    | grep -v -F '< /dev/null' || true)
  [ -z "$rafraichissements" ] || {
    echo "second rafraîchissement dans la transaction : $rafraichissements"
    return 1
  }

  # La locale est forcée sur les DEUX phases : `question()` compare la réponse
  # à la traduction locale de « Y ». En français elle vaut « O », et un « y »
  # y signifie NON.
  [ "$(grep -c 'LC_ALL="\$LOCALE_TRANSACTION"' "$MAJ")" -eq 2 ]
  run grep -F 'readonly LOCALE_TRANSACTION=C.UTF-8' "$MAJ"
  [ "$status" -eq 0 ]

  # Une seule réponse transmise, et une seule fois.
  #
  # On compte dans le CODE, commentaires exclus (ils parlent de cette réponse,
  # justement pour l'encadrer), et on compte des OCCURRENCES, pas des lignes :
  # `grep -c` comptait des lignes, si bien que `printf 'y\ny\n'` — deux
  # approbations sur une seule ligne, donc une question de plus approuvée à la
  # place de l'utilisateur — passait la garde au vert (revue de sécurité M1).
  ligne_approbation=$(grep -v -E '^[[:space:]]*#' "$MAJ" | grep -F "printf 'y" || true)
  [ "$(printf '%s\n' "$ligne_approbation" | grep -c .)" -eq 1 ] || {
    echo "il n'y a pas exactement une ligne qui transmet une approbation :"
    printf '%s\n' "$ligne_approbation"
    return 1
  }
  # Et cette ligne unique ne transmet qu'un seul « y ».
  nb_y=$(printf '%s' "$ligne_approbation" | grep -oE 'y\\n' | grep -c . || true)
  [ "$nb_y" -eq 1 ] || {
    echo "l'approbation transmise porte $nb_y réponses au lieu d'une :"
    printf '%s\n' "$ligne_approbation"
    return 1
  }
}

@test "le panneau montre le journal de l'unité, et ne fabrique pas son verdict" {
  WIDGET="$RACINE/packages/eschaton-dms-plugin-update/EschatonUpdateWidget.qml"

  # La progression vient du journal de l'unité — la sortie de pacman, telle
  # quelle. C'est ce qui remplace le terminal, pas un résumé.
  run grep -F '"/usr/bin/journalctl"' "$WIDGET"
  [ "$status" -eq 0 ]
  run grep -F '"-u", "eschaton-update.service"' "$WIDGET"
  [ "$status" -eq 0 ]
  run grep -F '"-f",' "$WIDGET"
  [ "$status" -eq 0 ]
  # Donnée machine : affichée telle quelle, jamais interprétée comme du balisage.
  run grep -F 'textFormat: Text.PlainText' "$WIDGET"
  [ "$status" -eq 0 ]

  # Le verdict est LU (fichier d'état de la transaction), jamais déduit du seul
  # code de sortie de la porte : `pkexec` rend 0 dès que l'unité est lancée.
  run grep -F '/run/eschaton-update/etat' "$WIDGET"
  [ "$status" -eq 0 ]
  # Une unité arrêtée sans verdict écrit n'est pas un succès.
  run grep -F 'terminer("interrompu"' "$WIDGET"
  [ "$status" -eq 0 ]
  bloc=$(awk '/function terminer\(/,/^    }/' "$WIDGET")
  [[ "$bloc" == *'nouveauResultat === "succes"'* ]] || {
    echo "le succès n'est pas conditionné au résultat lu : $bloc"
    return 1
  }

  # Aucun shell : chaque Process a un argv constant.
  run grep -E '"/usr/bin/(ba)?sh"|"-lc"|"-c"' "$WIDGET"
  [ "$status" -eq 1 ]

  # La boîte du journal n'existe QUE pendant et après une transaction. Un
  # `visible:` perdu lors d'une retouche l'a laissée affichée, vide, sur le
  # panneau au repos (constaté le 2026-08-30).
  bloc=$(awk '/La sortie de pacman, telle quelle/,/^                }/' "$WIDGET")
  [[ "$bloc" == *'visible: root.phase !== ""'* ]] || {
    echo "la boîte du journal n'est plus conditionnée à une transaction"
    return 1
  }

  # À la fin, le journal est RELU en entier, sans `-f`. Mesuré le 2026-08-30 :
  # arrêter le suiveur à l'instant où l'unité s'éteint perdait la fin du
  # journal, et le panneau du cas « décision humaine » affichait tout sauf LA
  # question. Une relecture bornée supprime la course.
  run grep -F 'journalFinalProcess.running = true' "$WIDGET"
  [ "$status" -eq 0 ]
  bloc=$(awk '/id: journalFinalProcess/,/^    }/' "$WIDGET")
  [[ "$bloc" == *"journalModel.clear()"* ]] || {
    echo "la relecture finale ne remplace pas le contenu : $bloc"
    return 1
  }
  # …et elle est bornée à CETTE transaction, jamais au journal entier.
  run grep -F '"--since", "@" + _debutEpoch' "$WIDGET"
  [ "$status" -eq 0 ]
}

@test "un service tombé pendant la transaction n'est pas un succès (archétype dovecot)" {
  source "$RACINE/packages/eschaton-base/lib.sh"

  # dovecot 2.4 (nouvelle Arch du 2025-10-31) : pacman réussit, le service ne
  # redémarre plus. Seules les unités NOUVELLEMENT en échec comptent — celles
  # qui étaient déjà cassées ne sont pas le fait de cette mise à jour.
  avant=$'systemd-vconsole-setup.service'
  apres=$'dovecot.service\nsystemd-vconsole-setup.service'
  run unites_nouvellement_en_echec "$avant" "$apres"
  [ "$output" = "dovecot.service" ]

  # Rien de neuf : rien à signaler, même si des unités sont en échec.
  run unites_nouvellement_en_echec "$avant" "$avant"
  [ -z "$output" ]

  # Une unité réparée par la mise à jour ne doit pas être signalée non plus.
  run unites_nouvellement_en_echec "$apres" "$avant"
  [ -z "$output" ]

  # Listes vides des deux côtés : pas de faux positif dû aux lignes vides.
  run unites_nouvellement_en_echec "" ""
  [ -z "$output" ]
  run unites_nouvellement_en_echec "" $'dovecot.service'
  [ "$output" = "dovecot.service" ]
}

@test "la transaction publie de quoi revenir en arrière, et n'annonce pas un succès dégradé" {
  MAJ="$RACINE/packages/eschaton-base/eschaton-update"

  # Le point de retour est calculé AVANT d'agir : après coup, il serait trop
  # tard pour distinguer l'état d'avant de l'état d'après.
  ligne_snapshot=$(grep -n -F 'snapshot_avant=$(dernier_snapshot)' "$MAJ" | head -1 | cut -d: -f1)
  ligne_transaction=$(grep -n -F -- 'pacman -Su "$@"' "$MAJ" | head -1 | cut -d: -f1)
  [ -n "$ligne_snapshot" ] && [ -n "$ligne_transaction" ]
  [ "$ligne_snapshot" -lt "$ligne_transaction" ] || {
    echo "le point de retour est calculé après la transaction"
    return 1
  }
  # …et il est publié dans le fichier d'état, sinon l'interface ne saurait pas
  # quoi proposer.
  run grep -F 'snapshot_avant=%s' "$MAJ"
  [ "$status" -eq 0 ]

  # Le verdict « succes » n'est atteint qu'après le contrôle des services.
  ligne_degrade=$(grep -n -F 'ecrire_etat succes-degrade 0' "$MAJ" | head -1 | cut -d: -f1)
  ligne_succes=$(grep -n -F 'ecrire_etat succes 0' "$MAJ" | tail -1 | cut -d: -f1)
  [ -n "$ligne_degrade" ] && [ -n "$ligne_succes" ]
  [ "$ligne_degrade" -lt "$ligne_succes" ] || {
    echo "le succès est écrit avant le contrôle des services"
    return 1
  }
  run grep -F 'unites_nouvellement_en_echec "$echecs_avant" "$echecs_apres"' "$MAJ"
  [ "$status" -eq 0 ]
}

@test "l'état ne reste jamais sur « en-cours », même tué en plein contrôle" {
  MAJ="$RACINE/packages/eschaton-base/eschaton-update"
  # Mesuré le 2026-08-30 : une annulation arrivée APRÈS l'installation, pendant
  # le contrôle des services, tuait le script sur son `sleep` (`set -e`, code
  # 143) avant qu'il ait rendu son verdict. L'état restait « en-cours » pour
  # toujours et l'interface annonçait « interrompue sans résultat » alors que
  # le système ÉTAIT à jour.
  run grep -F 'trap finaliser EXIT' "$MAJ"
  [ "$status" -eq 0 ]
  bloc=$(awk '/^finaliser\(\)/,/^}/' "$MAJ")
  [[ "$bloc" == *'"$etat_final_ecrit" && return 0'* ]] || {
    echo "le filet de sortie écrase un verdict déjà rendu : $bloc"
    return 1
  }
  # Interrompu après l'installation : on ne cache pas que le système est à
  # jour, et on ne prétend pas avoir vérifié les services.
  [[ "$bloc" == *"succes-non-verifie"* ]]
  # Interrompu avant : annulation si elle a été demandée, sinon « interrompu ».
  [[ "$bloc" == *"ecrire_etat annule"* ]]
  [[ "$bloc" == *"ecrire_etat interrompu"* ]]
  # Et le `sleep` du contrôle ne peut plus tuer le script à lui seul.
  run grep -F 'sleep 3 || true' "$MAJ"
  [ "$status" -eq 0 ]

  # L'interface connaît le nouvel état — sans quoi elle l'afficherait comme un
  # résultat vide.
  run grep -F 'case "succes-non-verifie":' \
    "$RACINE/packages/eschaton-dms-plugin-update/EschatonUpdateWidget.qml"
  [ "$status" -eq 0 ]
}

@test "après un échec, le panneau propose le retour en arrière par la porte du rollback" {
  WIDGET="$RACINE/packages/eschaton-dms-plugin-update/EschatonUpdateWidget.qml"

  # Exactement l'argv du panneau de restauration : même binaire, même action
  # polkit. Aucun second chemin privilégié n'est ouvert pour cette porte de
  # sortie.
  run grep -F '"/usr/bin/pkexec", "/usr/bin/eschaton-rollback",' "$WIDGET"
  [ "$status" -eq 0 ]
  run grep -F '"--yes", String(snapshotAvant)' "$WIDGET"
  [ "$status" -eq 0 ]
  # Deux clics, comme le panneau de restauration : l'action est destructive.
  run grep -F 'confirmRestauration' "$WIDGET"
  [ "$status" -eq 0 ]

  # Elle n'est proposée que quand elle a un sens : après un pré-vol qui n'a
  # rien modifié, proposer un rollback serait du bruit alarmiste.
  bloc=$(awk '/readonly property bool restaurationUtile/,/snapshotAvant > 0/' "$WIDGET")
  [[ "$bloc" == *'"echec"'* ]]
  [[ "$bloc" == *'"succes-degrade"'* ]]
  [[ "$bloc" != *'"echec-prevol"'* ]] || {
    echo "le rollback est proposé alors que rien n'a été modifié"
    return 1
  }
  [[ "$bloc" == *"snapshotAvant > 0"* ]]

  # Un succès dégradé n'est jamais annoncé comme un succès.
  run grep -F 'Mise à jour installée, système dégradé' "$WIDGET"
  [ "$status" -eq 0 ]
  bloc_echec=$(awk '/readonly property bool resultatEstUnEchec/,/^$/' "$WIDGET")
  [[ "$bloc_echec" == *'"succes-degrade"'* ]] || {
    echo "un succès dégradé n'est pas traité comme un échec par l'interface"
    return 1
  }

  # Et le paquet déclare la dépendance qui fournit l'action `org.eschaton.rollback`.
  run grep -F 'eschaton-dms-plugin-rollback' "$RACINE/packages/eschaton-dms-plugin-update/PKGBUILD"
  [ "$status" -eq 0 ]
}

@test "le verrou est libéré sur TOUTE sortie, pas seulement après la transaction" {
  MAJ="$RACINE/packages/eschaton-base/eschaton-update"
  # REVUE DE SÉCURITÉ I5. Seule la branche d'annulation de la TRANSACTION
  # libérait le verrou. Une annulation pendant le PRÉ-VOL en sortait sans rien
  # libérer — et c'est la fenêtre la plus longue, celle qui contient le `-Sy`.
  # Le filet de sortie couvre désormais tous les chemins.
  bloc=$(awk '/^finaliser\(\)/,/^}/' "$MAJ")
  [[ "$bloc" == *"liberer_verrou_orphelin"* ]] || {
    echo "le filet de sortie ne libère pas le verrou : $bloc"
    return 1
  }
  # `local code=$?` doit rester la PREMIÈRE instruction du filet : tout appel
  # avant elle écraserait le code de sortie qu'on capture.
  premiere=$(printf '%s\n' "$bloc" | sed -n '2p')
  [[ "$premiere" == *'local code=$?'* ]] || {
    echo "le filet de sortie ne capture plus le code en premier : « $premiere »"
    return 1
  }
}

@test "eschaton-update refuse le mode transaction à un appelant non privilégié" {
  if [ "$EUID" -eq 0 ]; then
    skip "test écrit pour un appelant non privilégié"
  fi
  BANC="$BATS_TEST_TMPDIR/banc2"
  mkdir -p "$BANC/bin"
  sed "s#^source /usr/lib/eschaton/lib.sh\$#source $RACINE/packages/eschaton-base/lib.sh#" \
    "$RACINE/packages/eschaton-base/eschaton-update" > "$BANC/eschaton-update"
  chmod +x "$BANC/eschaton-update"
  for outil in pacman sudo; do
    printf '#!/bin/sh\necho "$0 $*" >> "%s/appels.txt"\nexit 0\n' "$BANC" > "$BANC/bin/$outil"
    chmod +x "$BANC/bin/$outil"
  done
  printf '#!/bin/sh\nprintf "Avail\\n99999999\\n"\n' > "$BANC/bin/df"
  chmod +x "$BANC/bin/df"
  : > "$BANC/appels.txt"

  run env PATH="$BANC/bin:$PATH" "$BANC/eschaton-update" --transaction
  [ "$status" -ne 0 ]
  [[ "$output" == *"doit être lancé comme root"* ]]
  [ ! -s "$BANC/appels.txt" ]
}
