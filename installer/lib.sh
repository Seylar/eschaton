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

# --- attente des périphériques de partition ----------------------------------

attendre_bloc() { # $1 = chemin attendu, $2 = délai maximal en secondes (10 par défaut)
  # Le noyau relit la table de partitions de façon ASYNCHRONE : `sgdisk` rend la
  # main avant que /dev/<disque>1 n'existe, et le `mkfs.vfat` qui suit échoue
  # alors par intermittence — d'autant plus pénible que la panne dépend de la
  # vitesse du disque et ne se reproduit pas en VM rapide.
  # `udevadm settle` seul ne suffit pas : il attend que la file d'événements
  # udev se vide, pas que l'événement d'ajout de partition y soit entré.
  local chemin="$1" essais=$(( ${2:-10} * 10 ))
  while ((essais-- > 0)); do
    [[ -b "$chemin" ]] && return 0
    sleep 0.1
  done
  echo "eschaton-install : $chemin n'est pas apparu dans le délai imparti." >&2
  echo "  Le noyau n'a pas relu la table de partitions. Vérifier que le disque" >&2
  echo "  n'est pas occupé (montage, LVM, RAID) : lsblk, findmnt." >&2
  return 1
}
