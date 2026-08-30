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
  # réel. Résultat mesuré, pour les trois cas :
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
