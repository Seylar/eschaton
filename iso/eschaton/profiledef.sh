#!/usr/bin/env bash
# shellcheck disable=SC2034
# Profil archiso d'Eschaton — dérivé de `releng` (archiso 89-1), voir ../PROVENANCE.md.
# Spec : docs/superpowers/specs/2026-08-29-iso-design.md §3.

# UN SEUL PROFIL POUR LES DEUX IMAGES (spec §3.1).
# `iso/build-iso --variant t2` pose ESCHATON_ISO_VARIANT avant d'appeler
# mkarchiso ; tout ce que le variant change ICI, c'est le NOM de l'image — le
# reste du delta (paquets, dépôt de construction, nom du noyau) est appliqué par
# build-iso à une copie de travail. Le nom compte : c'est lui qui rend le
# variant reconnaissable, et donc filtrable par la CI qui ne doit jamais le
# publier (ADR 0004 §4.5).
if [[ "${ESCHATON_ISO_VARIANT:-nominal}" == t2 ]]; then
  iso_name="eschaton-t2"
  iso_application="Eschaton — variant T2 (Mac 2019), NON PUBLIABLE"
else
  iso_name="eschaton"
  iso_application="Eschaton — média d'installation x86_64"
fi
# Étiquette de volume : [A-Z0-9_] et 32 caractères au plus (contrainte mkarchiso).
iso_label="ESCHATON_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Eschaton <https://github.com/Seylar/eschaton>"
# ESCHATON_ISO_VERSION permet à la CI d'estampiller le tag publié ; à défaut, la
# date du jour (ou SOURCE_DATE_EPOCH, pour une construction reproductible).
iso_version="${ESCHATON_ISO_VERSION:-$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)}"
# 8 caractères au plus, [a-z0-9] (contrainte mkarchiso). « eschaton » tient tout juste.
install_dir="eschaton"
buildmodes=('iso')

# UEFI SEULEMENT — le BIOS hérité est retiré de `releng`, délibérément.
# `eschaton-install` refuse de tourner hors UEFI (« boot UEFI requis », test sur
# /sys/firmware/efi). Garder `bios.syslinux` produirait un environnement live qui
# démarre sur une machine BIOS mais où l'installation s'arrête aussitôt : une
# promesse que le média ne peut pas tenir. Effet de bord utile : `syslinux` sort
# de la liste de paquets et l'arborescence `syslinux/` disparaît du profil.
bootmodes=('uefi.systemd-boot')

pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd:19 plutôt que le `xz -Xbcj x86` de `releng`. La compression est plusieurs
# fois plus rapide (la CI et la construction locale émulée en dépendent) et la
# DÉCOMPRESSION l'est bien davantage — c'est elle qui s'exerce à chaque lecture de
# fichier dans l'environnement live. Le surcoût de taille se paie sur un budget de
# 2 Gio (spec §3.4) qu'on n'approche pas : mesure réelle dans ../README.md.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
# `releng` y ajoute ["/root"]="0:0:750" parce que son airootfs contient
# /root/.zlogin ; le nôtre ne pose rien dans /root, et mkarchiso avertit alors
# « Cannot change permissions of … /root : does not exist ». Le paquet
# `filesystem` livre déjà /root en 750 : l'entrée serait redondante ET bruyante.
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/usr/local/bin/eschaton-install"]="0:0:755"
  ["/usr/local/bin/lib.sh"]="0:0:644"
)
