#!/usr/bin/env bats
#
# Garde-fous du variant T2 (SP4b-1, Task 4) — ADR 0004 : le Mac T2 est *toléré
# et cloisonné*, jamais supporté.
#
# Ce fichier ne construit rien : il verrouille les quatre invariants que la
# tâche exige, et dont la violation ne se verrait ni à la construction ni au
# démarrage, mais bien plus tard — le jour où un firmware Apple partirait en
# Release publique, ou celui où un `-Syu` remplacerait le noyau d'un Mac par un
# `linux` standard qui ne voit pas son disque.
#
#   1. le variant est une LISTE DE PAQUETS, pas une fourche du profil ;
#   2. le dépôt tiers `arch-mact2` ne sort jamais de la construction ;
#   3. la garde d'épinglage refuse le noyau standard ;
#   4. AUCUN chemin de CI ne peut publier ce variant.
#
# Comme tests/iso-profil.bats, les assertions travaillent par `grep` et jamais
# en sourçant profiledef.sh (bash 3.2 sur macOS ne sait ni `date --date=@…` ni
# les tableaux associatifs).

setup() {
  RACINE="$BATS_TEST_DIRNAME/.."
  PROFIL="$RACINE/iso/eschaton"
  AIROOTFS="$PROFIL/airootfs"
  VARIANT="$RACINE/iso/variants/t2"
  BUILD="$RACINE/iso/build-iso"
  GARDE="$RACINE/packages/eschaton-t2/t2-garde-noyau"
}

paquets_t2() { grep -vE '^[[:space:]]*(#|$)' "$VARIANT/packages.x86_64"; }

# --- 1. Le variant est une liste de paquets, pas une fourche --------------------

@test "le variant T2 n'est qu'une liste de paquets et une conf, jamais une copie du profil" {
  # La spec §3.1 : « les deux ISO partagent tout sauf le noyau et les paquets
  # matériels ; la divergence doit rester une liste de paquets, jamais une
  # fourche du profil ». Ce test l'énonce littéralement : rien, sous
  # iso/variants/, ne doit dupliquer un fichier du profil.
  [ -d "$VARIANT" ]
  [ ! -e "$VARIANT/profiledef.sh" ]
  [ ! -e "$VARIANT/airootfs" ]
  [ ! -e "$VARIANT/efiboot" ]
  # Un seul profil archiso dans tout le dépôt.
  [ "$(find "$RACINE/iso" -name profiledef.sh | wc -l | tr -d ' ')" -eq 1 ]
}

@test "le variant embarque le noyau T2 et le firmware Wi-Fi, et retire le linux standard" {
  # Sans `linux-t2`, l'ISO ne voit AUCUN disque (la T2 est le contrôleur NVMe) ;
  # sans `apple-bcm-firmware`, pas de Wi-Fi au premier démarrage — or le
  # MacBook Pro 2019 n'a pas d'Ethernet (veille §5.2).
  run paquets_t2
  [[ "$output" == *"linux-t2"* ]]
  [[ "$output" == *"apple-bcm-firmware"* ]]
  # Et le `linux` standard est explicitement retiré de la liste nominale : le
  # garder embarquerait DEUX noyaux dans l'image (linux-t2 *fournit* linux, donc
  # rien ne signalerait le doublon).
  grep -qx '\-linux' "$VARIANT/packages.x86_64"
}

@test "le variant ne réclame PAS de paquet apple-bce : il n'existe pas" {
  # Le plan Task 4.1 et la spec §3.3 nomment « apple-bce » comme un paquet.
  # Vérification faite le 2026-08-30 contre l'index réel de
  # https://mirror.funami.tech/arch-mact2/os/x86_64/arch-mact2.db : le dépôt
  # publie 37 paquets et AUCUN ne s'appelle apple-bce. Le pilote apple-bce est
  # compilé DANS `linux-t2` — c'est même sa raison d'être. L'inscrire dans la
  # liste ferait échouer le pacstrap sur « target not found », très tard.
  [ -f "$VARIANT/packages.x86_64" ]
  ! grep -qx 'apple-bce' <(paquets_t2)
  # …et la liste dit POURQUOI, sans quoi le prochain lecteur le rajoutera.
  grep -q 'apple-bce' "$VARIANT/packages.x86_64"
}

@test "le variant n'embarque pas mkinitcpio-archiso-t2, qui entrerait en conflit" {
  # `arch-mact2` publie un `mkinitcpio-archiso-t2` (version 73) qui livre les
  # MÊMES chemins que le `mkinitcpio-archiso` d'Arch (version alignée sur
  # archiso 89) sans déclarer ni `conflicts` ni `provides` : les deux installés
  # ensemble donnent un conflit de fichiers, et lui seul donnerait des crochets
  # d'initramfs de seize versions en retard.
  [ -f "$VARIANT/packages.x86_64" ]
  ! grep -qx 'mkinitcpio-archiso-t2' <(paquets_t2)
  grep -q 'mkinitcpio-archiso-t2' "$VARIANT/packages.x86_64"
}

# --- 2. Le dépôt tiers ne sort jamais de la construction ------------------------

@test "arch-mact2 n'apparaît QUE dans le fragment de construction" {
  # ADR 0004 §4.2 : « le dépôt tiers ne contamine pas la confiance ». Il est
  # non signé (SigLevel = Never) ; le laisser fuiter dans le système installé
  # ferait tomber la garantie de signature que le SP4a doit fermer.
  [ -f "$VARIANT/arch-mact2.conf" ]
  grep -q '^\[arch-mact2\]' "$VARIANT/arch-mact2.conf"
  grep -q 'SigLevel[[:space:]]*=[[:space:]]*Never' "$VARIANT/arch-mact2.conf"

  # …et nulle part ailleurs dans le profil versionné.
  ! grep -rq 'arch-mact2' "$AIROOTFS"
  ! grep -q 'arch-mact2' "$PROFIL/pacman.conf"
  ! grep -q 'arch-mact2' "$PROFIL/packages.x86_64"
}

@test "build-iso injecte le dépôt tiers dans la copie de travail, jamais dans airootfs" {
  # La distinction est tout le sujet : $profil est la COPIE de travail que
  # mkarchiso consomme pour construire ; $profil/airootfs/etc/pacman.conf est
  # le fichier qui PART DANS L'IMAGE, puis dans le système installé.
  grep -q 'arch-mact2.conf' "$BUILD"
  # L'injection vise le pacman.conf de construction…
  grep -qE '>>[[:space:]]*"\$profil/pacman\.conf"' "$BUILD"
  # …et le script vérifie lui-même que rien n'a fui côté live.
  grep -q 'airootfs/etc/pacman.conf' "$BUILD"
}

@test "build-iso refuse de livrer une image T2 dont le pacman.conf live cite le dépôt tiers" {
  # Garde de dernier recours : même si quelqu'un ajoutait le dépôt au mauvais
  # fichier, la construction doit s'arrêter avant de produire l'image.
  grep -qE 'le dépôt tiers .*(a fui|ne doit pas)|fuite du dépôt tiers' "$BUILD"
}

# --- 3. La garde d'épinglage du noyau -------------------------------------------

@test "la garde refuse l'installation du noyau linux standard" {
  # Le scénario de brique de la veille §2.3 : une mise à jour tire le `linux`
  # stock, la machine redémarre sans disque, sans clavier et sans trackpad.
  run bash "$GARDE" refuser-noyau-standard <<<'linux'
  [ "$status" -ne 0 ]
  [[ "$output" == *"linux-t2"* ]]
}

@test "la garde refuse aussi les autres saveurs de noyau amont" {
  [ -x "$GARDE" ]
  for noyau in linux-lts linux-zen linux-hardened; do
    run bash "$GARDE" refuser-noyau-standard <<<"$noyau"
    [ "$status" -ne 0 ] || { echo "noyau accepté à tort : $noyau"; return 1; }
    [[ "$output" == *"$noyau"* ]] || { echo "refus muet sur : $noyau"; return 1; }
  done
}

@test "la garde laisse passer ce qui n'est pas un noyau, linux-t2 compris" {
  # Une garde qui refuse tout n'est pas une garde, c'est une panne. `linux-t2`
  # *fournit* `linux` : si le crochet alpm sur-déclenchait sur le fournisseur,
  # c'est ici que le script doit trancher — sur le NOM exact.
  run bash "$GARDE" refuser-noyau-standard <<<'linux-t2'
  [ "$status" -eq 0 ]
  run bash "$GARDE" refuser-noyau-standard <<<'linux-firmware'
  [ "$status" -eq 0 ]
  printf 'vim\nhtop\nlinux-t2-headers\n' | bash "$GARDE" refuser-noyau-standard
}

@test "la garde refuse le retrait du dernier noyau T2" {
  [ -x "$GARDE" ]
  run bash "$GARDE" refuser-retrait <<<'linux-t2'
  [ "$status" -ne 0 ]
  [[ "$output" == *"linux-t2"* ]]
  # …et ne s'émeut pas d'un retrait ordinaire.
  run bash "$GARDE" refuser-retrait <<<'htop'
  [ "$status" -eq 0 ]
}

@test "la garde d'alignement constate un noyau T2 réellement installé" {
  # « Désaligner linux-t2 », concrètement : après la transaction, l'arbre de
  # modules du noyau qui va démarrer n'a pas apple-bce — donc au prochain
  # démarrage, ni clavier ni trackpad internes.
  faux="$BATS_TEST_TMPDIR/racine"
  mkdir -p "$faux/boot" "$faux/usr/lib/modules/7.1.8-t2/kernel/drivers/misc"
  printf 'linux-t2\n' > "$faux/usr/lib/modules/7.1.8-t2/pkgbase"
  : > "$faux/usr/lib/modules/7.1.8-t2/kernel/drivers/misc/apple-bce.ko.zst"
  : > "$faux/boot/vmlinuz-linux-t2"
  ESCHATON_T2_RACINE="$faux" bash "$GARDE" verifier-alignement
}

@test "la garde d'alignement voit l'arbre de modules amputé d'apple-bce" {
  faux="$BATS_TEST_TMPDIR/racine"
  mkdir -p "$faux/boot" "$faux/usr/lib/modules/7.1.8-t2/kernel"
  printf 'linux-t2\n' > "$faux/usr/lib/modules/7.1.8-t2/pkgbase"
  : > "$faux/boot/vmlinuz-linux-t2"
  run env ESCHATON_T2_RACINE="$faux" bash "$GARDE" verifier-alignement
  [ "$status" -ne 0 ]
  [[ "$output" == *"apple-bce"* ]]
}

@test "la garde d'alignement voit un noyau standard revenu par la bande" {
  faux="$BATS_TEST_TMPDIR/racine"
  mkdir -p "$faux/boot" "$faux/usr/lib/modules/7.1.8-t2/kernel/drivers/misc"
  printf 'linux-t2\n' > "$faux/usr/lib/modules/7.1.8-t2/pkgbase"
  : > "$faux/usr/lib/modules/7.1.8-t2/kernel/drivers/misc/apple-bce.ko.zst"
  : > "$faux/boot/vmlinuz-linux-t2"
  : > "$faux/boot/vmlinuz-linux"          # le noyau qu'on ne veut jamais voir
  run env ESCHATON_T2_RACINE="$faux" bash "$GARDE" verifier-alignement
  [ "$status" -ne 0 ]
  [[ "$output" == *"vmlinuz-linux"* ]]
}

@test "les crochets alpm branchent bien la garde, et avortent la transaction" {
  hooks="$RACINE/packages/eschaton-t2"
  # PreTransaction + AbortOnFail : c'est le seul couple qui ARRÊTE pacman. Un
  # PostTransaction en échec n'est qu'un avertissement.
  grep -q 'When[[:space:]]*=[[:space:]]*PreTransaction' "$hooks/90-eschaton-t2-noyau.hook"
  grep -q 'AbortOnFail' "$hooks/90-eschaton-t2-noyau.hook"
  grep -q 'NeedsTargets' "$hooks/90-eschaton-t2-noyau.hook"
  grep -q 'Target[[:space:]]*=[[:space:]]*linux$' "$hooks/90-eschaton-t2-noyau.hook"
  grep -q 'refuser-noyau-standard' "$hooks/90-eschaton-t2-noyau.hook"
  grep -q 'AbortOnFail' "$hooks/91-eschaton-t2-retrait.hook"
  grep -q 'refuser-retrait' "$hooks/91-eschaton-t2-retrait.hook"
  grep -q 'When[[:space:]]*=[[:space:]]*PostTransaction' "$hooks/92-eschaton-t2-alignement.hook"
}

@test "le paquet eschaton-t2 livre la garde et n'entre dans aucune dépendance du socle" {
  pkg="$RACINE/packages/eschaton-t2/PKGBUILD"
  grep -q '^pkgname=eschaton-t2$' "$pkg"
  grep -q 't2-garde-noyau' "$pkg"
  # Le socle ne doit JAMAIS le tirer : le T2 est toléré, pas supporté
  # (ADR 0004 §4.1). Il s'installe à la main, sur la machine concernée.
  ! grep -q 'eschaton-t2' "$RACINE/packages/eschaton-base/PKGBUILD"
  ! grep -q 'eschaton-t2' "$RACINE/installer/eschaton-install"
}

# --- 4. Aucun chemin de CI ne peut publier ce variant ---------------------------

@test "build-iso REFUSE de construire le variant T2 sous CI" {
  # La garde la plus importante du lot, et elle est en amont de tout : le
  # firmware Apple redistribué est une zone grise (spec §3.3), donc l'image ne
  # doit même pas EXISTER sur un runner. Le refus est délibérément placé avant
  # les contrôles de root et d'architecture, pour qu'il soit atteignable — et
  # vérifiable — depuis ce Mac.
  run env GITHUB_ACTIONS=true bash "$BUILD" --variant t2
  [ "$status" -ne 0 ]
  [[ "$output" == *"publi"* ]]

  run env CI=true bash "$BUILD" --variant t2
  [ "$status" -ne 0 ]
}

@test "le chemin nominal reste inchangé sous CI" {
  # Le corollaire : la garde ne doit pas gêner l'ISO nominal, qui lui SE PUBLIE.
  # Sans root le script s'arrête plus loin, sur son propre message — c'est la
  # preuve qu'il a dépassé le refus de variant.
  run env GITHUB_ACTIONS=true bash "$BUILD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"root"* ]]
}

@test "build-iso refuse un variant inconnu plutôt que de construire le nominal" {
  run bash "$BUILD" --variant t3
  [ "$status" -ne 0 ]
  [[ "$output" == *"t3"* ]]
}

@test "le workflow ISO ne construit jamais le variant" {
  wf="$RACINE/.github/workflows/iso.yml"
  ! grep -qE 'build-iso.*--variant|ESCHATON_ISO_VARIANT' "$wf"
}

@test "le job de publication ne ramasse pas une image T2 par joker" {
  # `gh release create … iso-out/*.iso` publie ce qu'il trouve. Le jour où
  # quelqu'un ferait construire les deux images dans le même job, le joker
  # emporterait le variant sans qu'une seule ligne ne change.
  wf="$RACINE/.github/workflows/iso.yml"
  ! grep -qE 'iso-out/\*\.iso' "$wf"
  # …et une étape refuse activement tout artefact T2 avant la publication.
  grep -q 'NE-PAS-PUBLIER\|eschaton-t2' "$wf"
}

@test "build-iso marque l'image T2 comme non publiable, dans son nom et à côté d'elle" {
  # Deux marques, parce qu'un nom peut être renommé et un fichier oublié.
  grep -q 'eschaton-t2' "$PROFIL/profiledef.sh"
  grep -q 'NE-PAS-PUBLIER' "$BUILD"
}

# --- Les deux points laissés ouverts par l'auteur -------------------------------

@test "la taille d'écran est un PARAMÈTRE d'amorçage, pas une reconstruction" {
  # ADR 0004 §6.1 : 13″ (iGPU seul) ou 15″/16″ (Radeon dédiée, écran noir sur
  # 5600M sans `nomodeset`). La réponse ne doit pas obliger à refaire l'image :
  # le variant offre une entrée d'amorçage de repli qui porte `nomodeset`.
  grep -q 'nomodeset' "$BUILD"
  # …et le choix reste pilotable à la construction, sans toucher au profil.
  grep -q 'ESCHATON_T2_GPU' "$BUILD"
}

@test "les paramètres noyau T2 exigés par la veille sont posés" {
  # veille §2.1 : `intel_iommu=on iommu=pt pm_async=off`.
  for p in 'intel_iommu=on' 'iommu=pt' 'pm_async=off'; do
    grep -q "$p" "$BUILD" || { echo "paramètre absent : $p"; return 1; }
  done
}

@test "l'image T2 embarque le noyau T2, et le contrôle d'inventaire le sait" {
  # Le contrôle de contenu de build-iso nomme `vmlinuz-linux` en dur : sur le
  # variant, le fichier s'appelle `vmlinuz-linux-t2` et le contrôle passerait
  # au vert sur une image sans noyau… ou échouerait sur une image saine.
  grep -qF 'vmlinuz-linux$suffixe_noyau' "$BUILD"
  grep -qF 'initramfs-linux$suffixe_noyau.img' "$BUILD"
  # …et le preset mkinitcpio suit le nom du paquet noyau, sinon aucun initramfs
  # n'est généré et l'image sort sans de quoi démarrer.
  grep -qF 'linux-t2.preset' "$BUILD"
}

@test "les réserves matérielles sont écrites, pas sous-entendues" {
  # ADR 0004 §4.5 : « aucune promesse publique ». La documentation doit nommer
  # ce qui ne marchera pas — sinon l'auteur le découvrira sur sa machine.
  readme="$RACINE/iso/README.md"
  grep -qi 'touch id' "$readme"
  grep -qi 'touch bar' "$readme"
  grep -qi 'veille' "$readme"
  grep -qi 'micro' "$readme"
  # …et la marche à suivre matérielle : démarrage sécurisé, effacement.
  grep -qi 'Startup Security Utility\|démarrage sécurisé' "$readme"
}
