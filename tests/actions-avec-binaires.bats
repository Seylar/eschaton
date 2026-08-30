#!/usr/bin/env bats
#
# UN BINAIRE PRIVILÉGIÉ VOYAGE AVEC L'ACTION QUI LE CONTRAINT.
#
# `pkexec` cherche l'action dont l'annotation `org.freedesktop.policykit.exec.path`
# désigne le programme demandé. S'il n'en trouve AUCUNE, il ne refuse pas : il
# retombe sur l'action générique `org.freedesktop.policykit.exec` livrée par
# polkit. Mesuré le 2026-08-30 sur polkit 127-3, action retirée puis
# `pkexec /usr/bin/eschaton-update-helper --apply` (tools/vm-dev.md §33.1) :
#
#     ==== AUTHENTICATING FOR org.freedesktop.policykit.exec ====
#     Authentication is needed to run `/usr/bin/eschaton-update-helper --apply'
#     as the super user
#
# Ce repli n'est pas neutre. Les `<defaults>` de l'action générique valent
# `auth_admin` sur les TROIS axes — `allow_any`, `allow_inactive`, `allow_active`
# (relu dans org.freedesktop.policykit.policy, §33.1) — là où nos actions posent
# `no/no/auth_admin`. Une session distante ou inactive, à qui nos actions
# n'offrent aucun chemin d'authentification, en retrouve donc un. Et la modale
# cesse de nommer l'opération : elle annonce « run a program as another user ».
#
# Le défaut était structurel, pas accidentel : le binaire vivait dans
# `eschaton-base`, l'action dans un greffon DMS, et RIEN ne liait les deux —
# l'installeur ne pacstrape que `eschaton-base` et `eschaton-branding`. Le même
# patron valait pour `eschaton-rollback`. Cette garde rend la réintroduction
# impossible : elle exige que le paquet qui livre le binaire livre aussi
# l'action.

setup() {
  RACINE="$BATS_TEST_DIRNAME/.."
}

# Les PKGBUILD du dépôt, hors répertoires de construction de makepkg.
pkgbuilds() {
  find "$RACINE/packages" -name PKGBUILD -not -path '*/pkg/*' -not -path '*/src/*' \
    | sort
}

# Les fichiers de politique du dépôt, hors répertoires de construction.
politiques() {
  find "$RACINE/packages" -name '*.policy' -not -path '*/pkg/*' -not -path '*/src/*' \
    | sort
}

# Le PKGBUILD qui installe un chemin donné dans `$pkgdir`, ou rien.
# On cherche la destination de l'`install`, pas le nom du fichier source : c'est
# le chemin ABSOLU sur le système installé qui compte pour polkit et pour pkexec.
paquet_installant() { # $1 = chemin absolu sur le système installé
  local cible=$1 pkgbuild
  for pkgbuild in $(pkgbuilds); do
    if grep -qF "\$pkgdir$cible" "$pkgbuild"; then
      basename "$(dirname "$pkgbuild")"
      return 0
    fi
  done
  return 1
}

@test "toute action polkit du dépôt épingle un programme par exec.path" {
  # Une action sans `exec.path` n'épingle rien : `pkexec` ne la trouverait
  # jamais, et le binaire retomberait sur l'action générique. Les deux actions
  # d'Eschaton servent exactement à contraindre un programme.
  local politique
  for politique in $(politiques); do
    run grep -F 'org.freedesktop.policykit.exec.path' "$politique"
    [ "$status" -eq 0 ] || {
      echo "$politique n'épingle aucun programme : pkexec l'ignorerait"
      return 1
    }
  done
}

@test "le paquet qui livre un binaire privilégié livre aussi son action" {
  # Le cœur de la garde. Pour chaque action annotée :
  #   1. quel paquet installe le BINAIRE que l'annotation épingle ?
  #   2. quel paquet installe l'ACTION elle-même ?
  #   3. c'est le MÊME, sinon le binaire peut arriver seul sur une machine.
  local politique binaire nom_action paquet_binaire paquet_action verifiees=0
  for politique in $(politiques); do
    # Toutes les annotations exec.path du fichier, une par ligne.
    while read -r binaire; do
      [ -n "$binaire" ] || continue
      nom_action=$(basename "$politique")

      paquet_binaire=$(paquet_installant "$binaire") || {
        echo "action $nom_action : aucun PKGBUILD du dépôt n'installe $binaire"
        echo "  (soit l'annotation est morte, soit le binaire a changé de nom)"
        return 1
      }

      paquet_action=$(paquet_installant "/usr/share/polkit-1/actions/$nom_action") || {
        echo "action $nom_action : aucun PKGBUILD ne l'installe"
        return 1
      }

      [ "$paquet_binaire" = "$paquet_action" ] || {
        echo "L'ACTION NE VOYAGE PAS AVEC SON BINAIRE :"
        echo "  binaire $binaire            → livré par $paquet_binaire"
        echo "  action  $nom_action → livrée par $paquet_action"
        echo
        echo "Sur une machine qui a $paquet_binaire sans $paquet_action,"
        echo "pkexec ne trouve aucune action pour ce programme et retombe sur"
        echo "org.freedesktop.policykit.exec — dont les <defaults> valent"
        echo "auth_admin sur allow_any ET allow_inactive, là où nos actions"
        echo "posent no/no. Livre l'action depuis $paquet_binaire."
        return 1
      }
      verifiees=$((verifiees + 1))
    done < <(grep -oE 'exec\.path">[^<]+<' "$politique" | sed 's/^exec\.path">//; s/<$//')
  done

  # Une garde qui ne vérifie rien passe au vert en silence. Le dépôt porte deux
  # actions ; si ce nombre tombe, c'est que l'extraction ne mord plus.
  [ "$verifiees" -ge 2 ] || {
    echo "seulement $verifiees action(s) vérifiée(s) : l'extraction des annotations ne mord plus"
    return 1
  }
}

@test "aucun paquet ne livre deux fois la même action (conflit de fichiers)" {
  # Déplacer une action d'un paquet à l'autre sans la retirer de l'ancien
  # fabriquerait un conflit de fichiers à l'installation. pacman sait résoudre
  # le cas quand les deux paquets sont mis à jour DANS LA MÊME transaction,
  # mais rien ne garantit qu'ils le soient — et une installation neuve, elle,
  # échouerait franchement.
  local politique nom_action porteurs pkgbuild
  for politique in $(politiques); do
    nom_action=$(basename "$politique")
    porteurs=""
    for pkgbuild in $(pkgbuilds); do
      if grep -qF "\$pkgdir/usr/share/polkit-1/actions/$nom_action" "$pkgbuild"; then
        porteurs="$porteurs $(basename "$(dirname "$pkgbuild")")"
      fi
    done
    [ "$(printf '%s\n' $porteurs | grep -c .)" -eq 1 ] || {
      echo "l'action $nom_action est livrée par :$porteurs"
      echo "  un seul paquet doit la porter, sinon conflit de fichiers"
      return 1
    }
  done
}
