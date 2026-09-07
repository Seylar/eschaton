#!/usr/bin/env bash
# Fonctions d'eschaton-install. DRY_RUN=1 => run_cmd imprime au lieu d'exécuter.

run_cmd() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then echo "DRY: $*"; else "$@"; fi
}

# Écrit un contenu dans un fichier SANS passer par une chaîne shell.
# Motif : `bash -c "echo '$VAR' > fichier"` interpole VAR dans du code shell ;
# une valeur contenant une apostrophe ou un `;` s'y exécuterait. Les valeurs
# concernées (hostname) sont désormais validées en amont, mais la validation et
# l'absence d'interpolation sont deux défenses distinctes : on garde les deux.
write_file() { # $1 = chemin, $2 = contenu (une ligne)
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "DRY: écrire « $2 » dans $1"
  else
    printf '%s\n' "$2" > "$1"
  fi
}

detect_arch() {
  # macOS dit « arm64 » là où Linux dit « aarch64 » : les tests bats tournent
  # sur le Mac, le script sur le live env — un seul dialecte en sortie.
  #
  # `ESCHATON_ARCH` n'est honorée QUE en répétition à blanc, et c'est la
  # condition qui la rend acceptable : le chemin T2 n'existe que sur x86_64, or
  # le poste de développement est un Mac Apple Silicon — sans cette porte, le
  # plan d'une installation T2 ne serait vérifiable nulle part avant la vraie
  # machine. Sur le chemin réel la variable est ignorée : mentir sur
  # l'architecture d'une VRAIE installation ne rendrait service à personne.
  if [[ "${DRY_RUN:-0}" == "1" && -n "${ESCHATON_ARCH:-}" ]]; then
    echo "${ESCHATON_ARCH}"; return 0
  fi
  local m; m="$(uname -m)"
  [[ "$m" == "arm64" ]] && m="aarch64"
  echo "$m"
}

# --- LE CHEMIN T2, ET COMMENT IL SE SIGNALE (ADR 0004) ------------------------
#
# Il y a DEUX chemins d'installation, et un seul par défaut.
#
#   nominal — le livrable. Noyau amont, aucun dépôt tiers. Il ne bouge pas.
#   t2      — la machine de dogfooding de l'auteur (MacBook Pro 2019). Noyau
#             `linux-t2`, et le dépôt tiers `arch-mact2` configuré SUR LA CIBLE.
#
# POURQUOI LE CHEMIN T2 DOIT CONFIGURER LE DÉPÔT SUR LA CIBLE, alors que tout le
# reste du variant s'échine à l'en tenir éloigné. Le cloisonnement de l'ADR 0004
# §4.2 vise l'ISO NOMINAL et les paquets du projet : un dépôt non signé n'entre
# pas dans la configuration par défaut d'Eschaton. Il n'a jamais voulu dire
# qu'une machine T2 vivrait sans son dépôt — elle n'aurait alors ni noyau qui
# démarre, ni mise à jour de ce noyau. L'ADR le dit lui-même au §4.2 : « le dépôt
# T2 est ajouté séparément, avec sa politique propre, sur une machine T2
# uniquement, et ce compromis est affiché à l'utilisateur ». C'est exactement ce
# que fait ce chemin — et l'affichage n'est pas décoratif, il est exigé.
#
# COMMENT LE CHEMIN SE CHOISIT — trois règles, dans cet ordre :
#  1. `--variant` explicite fait foi, toujours.
#  2. Sinon, le MARQUEUR que `iso/build-iso` dépose dans l'environnement live :
#     une image T2 dit qu'elle est une image T2. Ce n'est pas une devinette,
#     c'est le constructeur de l'image qui l'a écrit.
#  3. Sinon : NOMINAL. Aucune détection matérielle, aucune heuristique DMI. Un
#     live tiers (archboot, ISO Arch) n'a pas de marqueur et installe donc le
#     chemin nominal ; qui veut le chemin T2 depuis un tel média le DEMANDE.
#
# Un marqueur illisible n'est pas un doute, c'est une contradiction : personne
# d'autre que `build-iso` n'écrit ce fichier. On refuse alors — avant le moindre
# effacement — plutôt que de choisir à la place de l'utilisateur. C'est la règle
# déjà posée pour `--disk` indiqué deux fois.

# Le marqueur, et de quoi le déplacer pour les tests (aucun Mac T2 ici).
: "${ESCHATON_MARQUEUR_VARIANT:=/usr/local/share/eschaton/variant}"

# Le dépôt tiers. Ces deux valeurs DOUBLENT `iso/variants/t2/arch-mact2.conf` —
# l'ISO le déclare pour CONSTRUIRE, l'installeur le déclare pour INSTALLER, et
# les deux fichiers ne se rencontrent jamais à l'exécution. La duplication est
# assumée et verrouillée par un test qui compare les deux.
DEPOT_T2_NOM="arch-mact2"
DEPOT_T2_URL="https://mirror.funami.tech/arch-mact2/os/x86_64"

lire_marqueur_variant() { # absence réelle : succès/vide ; toute erreur : refus
  local contenu parent
  if [[ ! -e "$ESCHATON_MARQUEUR_VARIANT" && ! -L "$ESCHATON_MARQUEUR_VARIANT" ]]; then
    # -e est également faux quand un répertoire parent interdit l'accès.
    # Remonter jusqu'au premier parent existant distingue ce cas de l'absence.
    parent=$(dirname -- "$ESCHATON_MARQUEUR_VARIANT")
    while [[ ! -e "$parent" && ! -L "$parent" && "$parent" != / && "$parent" != . ]]; do
      parent=$(dirname -- "$parent")
    done
    if [[ -d "$parent" && -x "$parent" ]]; then return 0; fi
    echo "eschaton-install : accès impossible au marqueur de variant." >&2
    return 1
  fi
  if [[ ! -f "$ESCHATON_MARQUEUR_VARIANT" || ! -r "$ESCHATON_MARQUEUR_VARIANT" ]]; then
    echo "eschaton-install : marqueur de variant illisible ou non régulier." >&2
    return 1
  fi
  # Lire tout le fichier, sans pipeline qui masque l'échec de la lecture.
  if ! contenu=$(cat -- "$ESCHATON_MARQUEUR_VARIANT"); then
    echo "eschaton-install : lecture du marqueur de variant impossible." >&2
    return 1
  fi
  if [[ "$contenu" =~ ^[[:space:]]*$ ]]; then
    echo "eschaton-install : marqueur de variant vide ; installation refusée." >&2
    return 1
  fi
  # Tolérer seulement les espaces autour d'une valeur, jamais au milieu ni une
  # deuxième valeur sur la ligne suivante. Les anciennes fins CRLF restent lues.
  if [[ "$contenu" =~ ^[[:space:]]*(nominal|t2)[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$contenu"
  fi
}

resoudre_variante() { # $1 = valeur de --variant (vide si l'option est absente)
  local demande="${1:-}" marqueur
  if [[ -n "$demande" ]]; then
    case "$demande" in
      nominal|t2) printf '%s\n' "$demande"; return 0 ;;
      *)
        echo "eschaton-install : variant inconnu « $demande » — attendu « nominal » ou « t2 »." >&2
        return 1 ;;
    esac
  fi
  marqueur="$(lire_marqueur_variant)" || return 1
  case "$marqueur" in
    # Le cas de loin le plus fréquent : pas de marqueur, donc chemin nominal.
    "")         printf 'nominal\n' ;;
    nominal|t2) printf '%s\n' "$marqueur" ;;
    *)
      echo "eschaton-install : le marqueur de variant $ESCHATON_MARQUEUR_VARIANT" >&2
      echo "  contient « $marqueur », que ce script ne connaît pas. Seul iso/build-iso" >&2
      echo "  écrit ce fichier, et il n'y écrit que « nominal » ou « t2 » : cette" >&2
      echo "  valeur est invalide ou le média a été altéré." >&2
      echo "  On refuse de choisir un chemin d'installation à votre place — le" >&2
      echo "  mauvais chemin donne un système qui ne démarre pas. Indiquez" >&2
      echo "  --variant nominal ou --variant t2." >&2
      return 1 ;;
  esac
}

kernel_pkgs_for() { # $1 = aarch64|x86_64, $2 = nominal|t2 (nominal par défaut)
  local arch="$1" variante="${2:-nominal}"
  if [[ "$variante" == "t2" ]]; then
    # Le chemin T2 n'existe que sur du Mac Intel : la puce T2 n'a jamais été
    # posée sur autre chose. Refuser plutôt que de composer une liste absurde.
    if [[ "$arch" != "x86_64" ]]; then
      echo "eschaton-install : le chemin T2 suppose un Mac Intel (x86_64), pas $arch." >&2
      return 1
    fi
    # `linux-t2` et NON `linux` : sur ce matériel la puce T2 est le contrôleur
    # NVMe et le pilote apple-bce (compilé dans ce noyau) porte le clavier et le
    # trackpad. Le noyau amont donne une machine sans disque et sans clavier au
    # premier démarrage — c'est-à-dire irréparable sur place.
    # `apple-bcm-firmware` est nommé ICI et pas seulement laissé aux dépendances
    # d'`eschaton-t2` : c'est le SEUL réseau de cette machine, qui n'a aucun port
    # Ethernet. Un jour où le méta-paquet cesserait de le déclarer, le système
    # installé démarrerait sans le moindre moyen de se réparer.
    # Microcode : tous les Mac T2 sont des Intel, il n'y a rien à détecter.
    echo "linux-t2 intel-ucode apple-bcm-firmware"
    return 0
  fi
  case "$arch" in
    aarch64) echo "linux-aarch64" ;;
    x86_64)  echo "linux intel-ucode amd-ucode" ;;
    *) echo "architecture non gérée : $1" >&2; return 1 ;;
  esac
}

# Paquets du projet à poser en plus, selon le chemin. Sur T2 la garde
# d'épinglage du noyau s'installe PENDANT l'installation et non « après le
# premier démarrage » : ce premier démarrage est précisément le moment où une
# machine dont le noyau serait mal épinglé n'a plus ni clavier ni disque.
paquets_eschaton_for() { # $1 = nominal|t2
  if [[ "${1:-nominal}" == "t2" ]]; then
    echo "eschaton-base eschaton-branding eschaton-t2"
  else
    echo "eschaton-base eschaton-branding"
  fi
}

# Remplace les microcodes CANDIDATS par celui du processeur réellement présent.
# En répétition à blanc il n'y a rien à détecter — la liste garde les deux, et
# c'est bien ce que le plan doit afficher.
restreindre_microcode() { # $1 = liste de paquets ; imprime la liste filtrée
  local ucode p; ucode="$(microcode_for_cpu)"
  local -a entree=() sortie=()
  read -ra entree <<< "$1"
  for p in "${entree[@]}"; do
    case "$p" in
      intel-ucode|amd-ucode)
        if [[ "$p" == "$ucode" ]]; then sortie+=("$p"); fi ;;
      *) sortie+=("$p") ;;
    esac
  done
  printf '%s\n' "${sortie[*]}"
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

# --- le dépôt tiers, posé sur la CIBLE et nulle part ailleurs ------------------

# ⚠️ LE NOM DE SECTION EST ASSEMBLÉ, PAS ÉCRIT LITTÉRALEMENT, et ce n'est pas une
# coquetterie. `iso/build-iso` copie ce fichier et `eschaton-install` dans
# l'`airootfs` de l'image, puis passe dessus une garde qui refuse toute image
# dont un fichier porte une ligne « [arch-mact2] » : c'est elle qui garantit que
# le dépôt non signé n'entre pas dans la configuration livrée. Un script qui
# COMPOSE cette section à l'installation n'est pas une configuration de l'image
# — mais un `grep` ne sait pas faire la différence, et affaiblir la garde pour
# lui apprendre la nuance serait la désarmer. Une variable coûte moins cher.
# NE PAS « simplifier » en heredoc : la garde de build-iso refuserait l'image.
ecrire_depot_t2() { # $1 = chemin du fragment à écrire
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "DRY: écrire le dépôt $DEPOT_T2_NOM ($DEPOT_T2_URL) dans $1"
    return 0
  fi
  mkdir -p "$(dirname "$1")"
  printf '%s\n' \
    "# Dépôt tiers $DEPOT_T2_NOM — posé par eschaton-install sur une machine Mac T2." \
    "#" \
    "# NON SIGNÉ (SigLevel = Never), mainteneur unique, suit l'amont avec du" \
    "# retard. Ce n'est PAS la configuration par défaut d'Eschaton : ce fragment" \
    "# n'existe que sur une machine T2, où il n'y a pas d'alternative — le noyau" \
    "# qui voit le disque de cette machine ne se trouve nulle part ailleurs." \
    "# ADR 0004 §4.2. Le retirer rend la machine non maintenable, pas plus sûre." \
    "" \
    "[$DEPOT_T2_NOM]" \
    "SigLevel = Never" \
    "Server = $DEPOT_T2_URL" > "$1"
}

# Le compromis, AFFICHÉ — l'ADR 0004 §4.2 l'exige en toutes lettres, et il
# l'exige parce qu'un dépôt non signé accepté en silence n'est pas un compromis,
# c'est une régression. Affiché AVANT le premier geste destructeur : qui n'en
# veut pas peut encore partir.
afficher_compromis_t2() {
  echo ""
  echo "  ─────────────────────────────────────────────────────────────────────"
  echo "  CHEMIN T2 — Mac toléré, jamais supporté (ADR 0004)."
  echo ""
  echo "  Ce système recevra le noyau linux-t2 et le dépôt tiers $DEPOT_T2_NOM :"
  echo "      $DEPOT_T2_URL"
  echo ""
  echo "  Ce dépôt n'est PAS signé (SigLevel = Never), il a un mainteneur unique"
  echo "  et il suit l'amont avec du retard (trois versions correctives le"
  echo "  2026-08-30). Chaque mise à jour du noyau vient donc d'une source que ni"
  echo "  Arch ni Eschaton ne contrôlent."
  echo ""
  echo "  C'est le compromis, et il n'a pas d'alternative sur ce matériel : la"
  echo "  puce T2 est le contrôleur NVMe, un noyau amont ne voit aucun disque."
  echo "  Le filet est le snapshot d'avant mise à jour et « eschaton-rollback »."
  echo ""
  echo "  Le paquet eschaton-t2 est installé en même temps que le système : il"
  echo "  refuse toute transaction qui réintroduirait un noyau amont."
  echo "  ─────────────────────────────────────────────────────────────────────"
  echo ""
}

# --- validation des arguments (différés SP4 du bilan du Socle) ----------------

# Comptes que `base` crée TOUJOURS sur une cible Arch. `useradd` les refuserait
# — mais il ne tourne qu'à l'étape 4, c'est-à-dire APRÈS l'effacement du disque
# et après le pacstrap : l'installation s'arrêterait sur un disque déjà vidé.
# Liste volontairement courte : ce sont les comptes du paquet `filesystem`
# (/usr/lib/sysusers.d/basic.conf) plus les trois que `base` amène avec systemd,
# dbus et util-linux. Le préfixe « systemd- » couvre le reste de la famille.
COMPTES_RESERVES=(root bin daemon mail ftp http nobody dbus uuidd polkitd)

valider_utilisateur() { # $1 = nom de compte
  # Règle de useradd(8) telle qu'appliquée par shadow : commence par une
  # minuscule ou un souligné, puis minuscules, chiffres, souligné ou tiret ;
  # 32 caractères au plus. Volontairement plus stricte que « ce que useradd
  # accepte » : ce nom finit dans un `arch-chroot … useradd`, dans un chemin de
  # /home et dans une invite `passwd`.
  local nom="$1"
  if [[ ! "$nom" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "eschaton-install : nom d'utilisateur invalide « $nom »." >&2
    echo "  Attendu : minuscule ou « _ » en tête, puis [a-z0-9_-], 32 signes au plus." >&2
    return 1
  fi
  # La regex seule laisse passer « root » : conforme à useradd(8) dans sa forme,
  # impossible dans les faits. Deux filets, dans cet ordre :
  local reserve
  for reserve in "${COMPTES_RESERVES[@]}"; do
    if [[ "$nom" == "$reserve" ]]; then
      echo "eschaton-install : « $nom » est un compte SYSTÈME, pas un compte d'utilisateur." >&2
      echo "  useradd le refuserait — mais seulement après l'effacement du disque" >&2
      echo "  et le pacstrap, sur un système déjà à moitié installé." >&2
      return 1
    fi
  done
  if [[ "$nom" == systemd-* ]]; then
    echo "eschaton-install : « $nom » est réservé aux comptes de service systemd." >&2
    return 1
  fi
  # …et, hors répétition à blanc, une interrogation de la base locale : l'ISO
  # Eschaton et le système cible partagent leurs paquets, donc leurs comptes
  # système. Elle attrape ce que la liste ci-dessus ignore. Écartée en dry-run :
  # la répétition se fait souvent sur son propre poste, où le compte que l'on
  # s'apprête à créer sur la cible existe déjà — le refus y serait faux.
  if [[ "${DRY_RUN:-0}" != "1" ]] && command -v getent >/dev/null 2>&1 &&
     getent passwd "$nom" >/dev/null 2>&1; then
    echo "eschaton-install : le compte « $nom » existe déjà dans cet environnement." >&2
    echo "  L'environnement live et la cible partagent leurs paquets, donc leurs" >&2
    echo "  comptes système : useradd échouerait sur la cible, après l'effacement." >&2
    return 1
  fi
}

valider_hote() { # $1 = nom d'hôte
  # RFC 1123 : lettres, chiffres et tirets ; ni tiret ni point en tête ou en
  # queue ; 63 caractères au plus pour une étiquette. On n'accepte qu'une seule
  # étiquette (pas de point) : /etc/hostname n'est pas un FQDN.
  local nom="$1"
  if [[ ! "$nom" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    echo "eschaton-install : nom d'hôte invalide « $nom »." >&2
    echo "  Attendu : [a-zA-Z0-9-], sans tiret en tête ni en queue, 63 signes au plus." >&2
    return 1
  fi
}

# --- validation du disque cible ----------------------------------------------

valider_disque() { # $1 = valeur de --disk ; imprime le chemin CANONIQUE du disque
  # `[[ -b ]]` NE DISTINGUE PAS un disque entier d'une partition, d'un volume
  # LVM ou d'un lien /dev/disk/by-id/… — le test suit les liens. Le message
  # d'erreur promettait pourtant « un disque ENTIER » sans que rien ne le
  # vérifie, et l'unique opération irréversible du dépôt (`sgdisk --zap-all`)
  # s'exécutait AVANT que les noms de partition dérivés ne soient confrontés au
  # réel. Trois cas, relevés par la revue de sécurité et confirmés en relisant
  # l'ordre des appels (le zap précédait `attendre_bloc`) :
  #   /dev/sda1                → le zap s'appliquait à la PARTITION, puis abandon
  #   /dev/disk/by-id/nvme-…   → la table du disque était effacée, puis abandon
  #                              (udev nomme la partition « -part1 », pas « 1 »)
  #   /dev/mapper/vg-lv        → le volume logique était effacé, puis abandon
  # Le cas by-id est le pire : c'est la façon canonique et prudente de désigner
  # un disque, donc l'utilisateur le plus soigneux perdait sa table. Une fausse
  # promesse de sécurité sur la seule opération irrattrapable du dépôt est pire
  # que pas de promesse du tout.
  local demande="$1" reel type
  if [[ ! -b "$demande" ]]; then
    echo "eschaton-install : « $demande » n'est pas un périphérique bloc." >&2
    echo "  Attendu un disque ENTIER (/dev/sda, /dev/nvme0n1, /dev/vda), pas une" >&2
    echo "  partition ni un fichier. Pour lister les candidats : lsblk -dno NAME,SIZE,MODEL" >&2
    return 1
  fi
  # On résout AVANT de juger : /dev/disk/by-id/… est légitime, mais seuls les
  # noms de noyau (sda, nvme0n1) portent la règle de dérivation des partitions.
  reel="$(readlink -f -- "$demande")" || reel="$demande"
  if ! command -v lsblk >/dev/null 2>&1; then
    echo "eschaton-install : lsblk introuvable — impossible de vérifier que" >&2
    echo "  « $demande » est un disque entier. On refuse plutôt que d'effacer à l'aveugle." >&2
    return 1
  fi
  type="$(lsblk -dno TYPE "$reel" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$type" != "disk" ]]; then
    echo "eschaton-install : « $demande » désigne $reel, de type « ${type:-inconnu} »." >&2
    echo "  Attendu « disk », c'est-à-dire un disque ENTIER : ni partition (« part »)," >&2
    echo "  ni volume LVM (« lvm »), ni RAID, ni chiffré (« crypt »)." >&2
    echo "  Pour lister les candidats : lsblk -dno NAME,SIZE,MODEL" >&2
    return 1
  fi
  printf '%s\n' "$reel"
}

valider_forme_disque() { # $1 = valeur de --disk, quand le périphérique est ABSENT
  # Répétition à blanc depuis une machine qui n'a pas le disque cible sous la
  # main : il n'y a rien à interroger, `valider_disque` ne peut donc RIEN
  # constater. La répétition s'en dispensait entièrement — et rendait `status 0`
  # avec un plan d'effacement pour les trois entrées mêmes que la garde existe
  # pour refuser (une partition, un lien by-id nvme, un lien by-id ata).
  # `valider_noms_partitions` ne rattrapait rien : son test
  # `"$p" == "$disque"[0-9p]*` est satisfait par « /dev/sda1 » → « /dev/sda1p1 ».
  # Ce qui reste jugeable sans périphérique, c'est la FORME du nom.
  #
  # CE QUE CE CONTRÔLE NE PEUT PAS FAIRE, et qu'il ne faut donc pas laisser
  # croire : dire le TYPE. `/dev/dm-0`, `/dev/md0` ou un nom de famille inconnue
  # passent ici et ne seront refusés que par `valider_disque`, le jour de la
  # vraie installation. C'est moins que la garde complète ; ce n'est pas rien ;
  # et ce n'est plus une promesse fausse.
  local nom="$1" ressemble_a_une_partition=0
  case "$nom" in
    /dev/*/*)
      # /dev/disk/by-id/…, /dev/mapper/…, /dev/disk/by-path/… : désigner un
      # disque ainsi est légitime et même prudent, mais le chemin réel les
      # CANONISE avant d'en dériver les partitions, et cette résolution demande
      # le périphérique. Sans lui, tout ce qu'on afficherait serait faux : udev
      # nomme « …-part1 » là où la répétition écrivait « …1 », et un lien nvme
      # canonisé donne « /dev/nvme0n1p1 » et non « …_1234561 ».
      echo "eschaton-install : « $nom » n'est pas un nom de nœud noyau, et le" >&2
      echo "  périphérique est absent de cette machine : il n'y a rien à résoudre." >&2
      echo "  Le chemin réel canonise ce genre de lien AVANT d'en dériver les noms" >&2
      echo "  de partition ; sans le disque sous la main, la répétition à blanc" >&2
      echo "  n'afficherait que des noms inventés — c'est ce qu'elle faisait." >&2
      echo "  Répétez avec le nom de nœud (/dev/sda, /dev/nvme0n1), ou depuis la" >&2
      echo "  machine qui porte réellement ce disque." >&2
      return 1 ;;
    /dev/?*) ;;
    *)
      echo "eschaton-install : « $nom » n'est pas un nœud de périphérique." >&2
      echo "  Attendu un disque ENTIER sous /dev (/dev/sda, /dev/nvme0n1, /dev/vda)." >&2
      return 1 ;;
  esac
  # Familles de noms du noyau où le suffixe distingue la partition du disque :
  # sd/vd/hd/xvd + chiffre, et nvme…n…p… / mmcblk…p… / loop…p… pour celles où le
  # « p » s'intercale. Le disque lui-même (« /dev/sda », « /dev/nvme0n1 ») ne
  # correspond à aucun de ces motifs.
  case "$nom" in
    /dev/sd[a-z]*[0-9]|/dev/vd[a-z]*[0-9]|/dev/hd[a-z]*[0-9]|/dev/xvd[a-z]*[0-9])
      ressemble_a_une_partition=1 ;;
    /dev/nvme[0-9]*n[0-9]*p[0-9]*|/dev/mmcblk[0-9]*p[0-9]*|/dev/loop[0-9]*p[0-9]*)
      ressemble_a_une_partition=1 ;;
  esac
  if ((ressemble_a_une_partition)); then
    echo "eschaton-install : « $nom » est un nom de PARTITION." >&2
    echo "  Attendu un disque ENTIER (/dev/sda, /dev/nvme0n1, /dev/vda)." >&2
    echo "  Le chemin réel le refuse ; la répétition à blanc le refuse donc aussi," >&2
    echo "  plutôt que d'annoncer un effacement qui n'aura jamais lieu." >&2
    return 1
  fi
}

nom_partition() { # $1 = chemin du disque, $2 = numéro de partition
  # nvme0n1 → nvme0n1p1, mmcblk0 → mmcblk0p1, sda → sda1 : le « p » s'intercale
  # quand le nom du disque se termine par un chiffre.
  if [[ "$1" == *[0-9] ]]; then printf '%s\n' "${1}p$2"; else printf '%s\n' "${1}$2"; fi
}

valider_noms_partitions() { # $1 = disque, $2… = noms dérivés
  # Rien d'irréversible ne doit précéder la validation COMPLÈTE. Les noms des
  # partitions se DÉDUISENT du nom du disque, et jusqu'ici cette déduction
  # n'était confrontée au réel qu'après le `sgdisk --zap-all` : quand elle était
  # fausse, l'installeur détruisait d'abord et abandonnait ensuite.
  local disque="$1"; shift
  local p vus=""
  for p in "$@"; do
    if [[ -z "$p" || "$p" == "$disque" || "$p" != "$disque"[0-9p]* ]]; then
      echo "eschaton-install : nom de partition dérivé invalide — « $p » pour $disque." >&2
      echo "  Le disque doit être désigné par son nom de noyau (/dev/sda, /dev/nvme0n1)." >&2
      return 1
    fi
    case " $vus " in
      *" $p "*) echo "eschaton-install : deux partitions porteraient le même nom « $p »." >&2; return 1 ;;
    esac
    vus="$vus $p"
  done
}

# --- relecture de la table de partitions -------------------------------------

# Dit l'état RÉEL du disque au moment où l'on abandonne. « Rien n'a été écrit »
# figurait dans un message appelé DEUX fois : avant le zap, où c'est vrai, et
# après `sgdisk --zap-all` et les deux `sgdisk -n`, où c'est faux. Un utilisateur
# dont la table de partitions vient d'être effacée lisait donc qu'il ne s'était
# rien passé — et pouvait renoncer à toute tentative de récupération. C'est la
# règle qu'énonce déjà `valider_disque` : une fausse promesse sur l'opération
# irrattrapable est pire que pas de promesse du tout.
etat_du_disque() { # $1 = disque, $2 = intact | table-reecrite
  if [[ "$2" == "intact" ]]; then
    echo "  Rien n'a été écrit sur $1 : sa table de partitions est intacte." >&2
    return 0
  fi
  # `table-reecrite` décrit exactement le point où l'installeur en est au second
  # appel : les trois `sgdisk` ont eu lieu, AUCUN `mkfs` n'a encore tourné.
  echo "" >&2
  echo "  ATTENTION — $1 A DÉJÀ ÉTÉ MODIFIÉ. Sa table de partitions a été" >&2
  echo "  effacée (sgdisk --zap-all) puis réécrite avec deux partitions neuves." >&2
  echo "  En revanche aucun formatage n'a encore eu lieu : le CONTENU des" >&2
  echo "  anciennes partitions est toujours sur le disque, c'est la carte qui" >&2
  echo "  a disparu. Si ce disque portait des données à récupérer :" >&2
  echo "    1. n'écrivez plus rien dessus et ne relancez pas l'installeur ;" >&2
  echo "    2. --zap-all détruit AUSSI la sauvegarde GPT de fin de disque : la" >&2
  echo "       table ne se restaure pas telle quelle, il faut retrouver les" >&2
  echo "       anciennes partitions en balayant le disque (testdisk, gpart)," >&2
  echo "       depuis un autre système et sans monter $1." >&2
}

# `blockdev --rereadpt` brut rendrait « BLKRRPART: Device or resource busy » —
# exact, et parfaitement inutile à qui installe. On explique.
#
# PÉRIMÈTRE RÉEL de cette garde, parce que l'ancien message le donnait trop
# large : l'ioctl BLKRRPART ne rend EBUSY que si une PARTITION du disque est
# encore ouverte. Un disque entier utilisé CRU — PV LVM, conteneur LUKS, membre
# btrfs ou ZFS posé directement sur le disque, sans table de partitions — n'a
# aucune partition à libérer : il franchit cette garde, et il franchit aussi
# `valider_disque`, qui ne lui reproche rien (lsblk lui donne le type « disk »).
# Aucun Linux ici pour l'éprouver — raison de plus pour que le message n'affirme
# que ce que le code vérifie.
relire_table() { # $1 = disque, $2 = moment, $3 = état du disque : intact|table-reecrite
  # $3 par défaut au PIRE cas : un appelant qui oublierait l'argument sur-avertit
  # au lieu de rassurer à tort. C'est le sens de la marche qu'on veut.
  local disque="$1" moment="$2" etat="${3:-table-reecrite}"
  # `blockdev` absent rend 127, que la suite prenait pour un EBUSY : l'utilisateur
  # lisait « une partition est OCCUPÉE » et partait chercher un montage qui
  # n'existe pas. Un diagnostic faux coûte plus cher qu'un test de présence.
  # En répétition à blanc, `run_cmd` n'exécute rien : le cas ne se pose pas — et
  # `blockdev` n'existe de toute façon pas sur le poste de développement macOS.
  if [[ "${DRY_RUN:-0}" != "1" ]] && ! command -v blockdev >/dev/null 2>&1; then
    echo "eschaton-install : blockdev introuvable — impossible de vérifier que le" >&2
    echo "  noyau relit la table de partitions de $disque ($moment)." >&2
    echo "  blockdev est livré par util-linux : pacman -S util-linux." >&2
    echo "  On s'arrête plutôt que de partitionner sans cette garde." >&2
    etat_du_disque "$disque" "$etat"
    exit 1
  fi
  run_cmd blockdev --rereadpt "$disque" && return 0
  echo "eschaton-install : le noyau refuse de relire la table de partitions de $disque" >&2
  echo "  ($moment). C'est qu'une de ses PARTITIONS est encore ouverte : montée," >&2
  echo "  swap actif (swapon), prise par LVM, par un RAID ou par LUKS, ou tenue" >&2
  echo "  par un processus — ou c'est le média depuis lequel vous avez démarré." >&2
  echo "  Pour voir qui la retient :" >&2
  echo "      lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS $disque" >&2
  echo "      findmnt --source $disque ; swapon --show" >&2
  etat_du_disque "$disque" "$etat"
  exit 1
}

# --- attente des périphériques de partition ----------------------------------

attendre_bloc() { # $1 = chemin attendu, $2 = délai maximal en secondes (10 par défaut)
  # Le noyau relit la table de partitions de façon ASYNCHRONE : `sgdisk` rend la
  # main avant que /dev/<disque>1 n'existe, et le `mkfs.vfat` qui suit échoue
  # alors par intermittence — d'autant plus pénible que la panne dépend de la
  # vitesse du disque et ne se reproduit pas en VM rapide.
  # `udevadm settle` seul ne suffit pas : il attend que la file d'événements
  # udev se vide, pas que l'événement d'ajout de partition y soit entré.
  #
  # CE QUE CETTE FONCTION NE PEUT PAS FAIRE — et pourquoi elle ne suffit pas
  # seule. Elle constate une PRÉSENCE. Sur un disque déjà partitionné dont le
  # noyau refuse de relire la table (partition montée, LVM, RAID), `sgdisk`
  # rend 0 en avertissant, les ANCIENS nœuds /dev/sdX1 sont toujours là, et
  # cette attente rend 0 immédiatement — sur l'ancienne géométrie, que le
  # `mkfs.vfat` suivant formate. Le message d'erreur ci-dessous nommait
  # exactement ce cas sans que le code puisse jamais l'atteindre.
  # La détection réelle est `blockdev --rereadpt`, appelé par eschaton-install
  # avant ET après le partitionnement : l'ioctl BLKRRPART rend EBUSY quand le
  # noyau ne peut pas relire, donc un code de retour non nul, donc un arrêt.
  # C'est le `partprobe` que le plan Task 2.3 prescrivait, avec un outil déjà
  # présent (util-linux, tiré par `base`) plutôt qu'un paquet de plus.
  local chemin="$1" essais=$(( ${2:-10} * 10 ))
  while ((essais-- > 0)); do
    [[ -b "$chemin" ]] && return 0
    sleep 0.1
  done
  echo "eschaton-install : $chemin n'est pas apparu dans le délai imparti." >&2
  echo "  Le noyau n'a pas créé le nœud de partition. Vérifier que le disque" >&2
  echo "  n'est pas occupé (montage, LVM, RAID) : lsblk, findmnt." >&2
  return 1
}
