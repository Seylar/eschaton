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
  INSTALL="$RACINE/installer/eschaton-install"
}

paquets_t2() { grep -vE '^[[:space:]]*(#|$)' "$VARIANT/packages.x86_64"; }

# `! commande` EN POSITION NON FINALE EST INERTE dans un test bats, et ce
# fichier en était rempli. bash(1), section `set -e` : « The shell does not exit
# if the command that fails … is being inverted with `!` ». Une assertion niée
# qui n'est pas la dernière ligne du test ne peut donc RIEN faire échouer.
# Constaté ici même : « le job de publication ne ramasse pas une image T2 par
# joker » était au vert alors que sa négation était fausse. Une garde qui ne
# peut pas échouer est pire que pas de garde — c'est la règle que ce dépôt
# s'applique déjà au contrôle d'inventaire de build-iso.
refute() { # $@ = commande qui DOIT échouer
  if "$@"; then
    echo "assertion : « $* » a réussi alors qu'elle devait échouer" >&2
    return 1
  fi
}

# Répétition à blanc de l'installeur, avec la machine simulée : l'architecture
# est forcée (ce poste est un Mac Apple Silicon) et le marqueur de variant est
# pointé où le test veut. Aucun disque, aucun root, aucune écriture.
plan_installation() { # $1 = valeur du marqueur ou "" ; $@ suivants = arguments
  local marqueur="$1"; shift
  local fichier="$BATS_TEST_TMPDIR/marqueur-absent"
  if [ -n "$marqueur" ]; then
    fichier="$BATS_TEST_TMPDIR/variant"
    printf '%s\n' "$marqueur" > "$fichier"
  fi
  ESCHATON_ARCH=x86_64 ESCHATON_MARQUEUR_VARIANT="$fichier" \
    "$INSTALL" --dry-run --disk /dev/vda --user seylar "$@" 2>&1
}

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
  refute grep -qx 'apple-bce' <(paquets_t2)
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
  refute grep -qx 'mkinitcpio-archiso-t2' <(paquets_t2)
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
  refute grep -rq 'arch-mact2' "$AIROOTFS"
  refute grep -q 'arch-mact2' "$PROFIL/pacman.conf"
  refute grep -q 'arch-mact2' "$PROFIL/packages.x86_64"
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
  # (ADR 0004 §4.1). C'est une dépendance de PAQUET que l'on interdit ici —
  # l'installeur, lui, le pose bien, mais sur le seul chemin `--variant t2`
  # (voir « le chemin nominal n'installe RIEN de T2 » plus bas).
  refute grep -q 'eschaton-t2' "$RACINE/packages/eschaton-base/PKGBUILD"
  refute grep -q 'eschaton-t2' "$RACINE/packages/eschaton-desktop/PKGBUILD"
}

@test "la liste des noyaux refusés est la MÊME dans le crochet et dans la garde" {
  # Deux listes, deux fichiers, aucun mécanisme pour les tenir ensemble : alpm
  # ne déclenche que sur les `Target =` du crochet, et le script ne voit que ce
  # qu'alpm lui présente. Retirer `Target = linux-zen` du seul crochet laissait
  # la suite au vert — l'ancien test ne vérifiait qu'une entrée, `linux`.
  hook="$RACINE/packages/eschaton-t2/90-eschaton-t2-noyau.hook"
  cibles="$(sed -n 's/^Target[[:space:]]*=[[:space:]]*//p' "$hook" | sort)"
  liste="$(bash "$GARDE" lister-noyaux | sort)"
  [ -n "$liste" ]
  [ "$cibles" = "$liste" ] || {
    echo "crochet :"; echo "$cibles"
    echo "garde   :"; echo "$liste"
    return 1
  }
  # Et la liste est bien celle des six noyaux officiels, pas une liste vide qui
  # coïnciderait avec un crochet vidé.
  [ "$(printf '%s\n' "$liste" | wc -l | tr -d ' ')" -eq 6 ]
}

@test "le PÉRIMÈTRE de la garde est écrit, pas subi" {
  # M-2 : la liste couvre les six noyaux officiels et pas les noyaux tiers
  # (`linux-mainline`, `linux-xanmod`, AUR). C'est correct pour la menace visée
  # — un noyau amont qui arrive sans que personne ne l'ait voulu — mais un
  # lecteur doit pouvoir le savoir sans relire la liste ligne à ligne.
  grep -q 'PÉRIMÈTRE' "$GARDE"
  grep -q 'linux-mainline' "$GARDE"
  # Le comportement correspondant, constaté : un noyau tiers PASSE.
  run bash "$GARDE" refuser-noyau-standard <<<'linux-xanmod'
  [ "$status" -eq 0 ]
  # …et le README le dit aussi, là où l'auteur le lira.
  grep -q 'linux-mainline\|linux-xanmod' "$RACINE/iso/README.md"
}

@test "l'échappatoire proposée par la garde n'est pas bloquée par la garde" {
  # I-3 : le message proposait `pacman -Rns eschaton-t2`. Si `linux-t2` a été
  # installé comme DÉPENDANCE, le `-s` cascade dessus et déclenche
  # 91-eschaton-t2-retrait (AbortOnFail), qui refuse toute la transaction :
  # l'issue de secours se referme sur elle-même.
  run bash "$GARDE" refuser-noyau-standard <<<'linux'
  [ "$status" -ne 0 ]
  [[ "$output" == *"pacman -Rn eschaton-t2"* ]]
  refute grep -q -- '-Rns eschaton-t2' "$GARDE"
  # …et la condition est nommée, pas seulement contournée.
  [[ "$output" == *"91-eschaton-t2-retrait"* ]]
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
  refute grep -qE 'build-iso.*--variant|ESCHATON_ISO_VARIANT' "$wf"
}

# Extrait le corps `run:` d'une étape nommée du workflow, désindenté, pour
# l'EXÉCUTER. Vérifier par `grep` qu'une garde existe ne dit rien de ce qu'elle
# fait ; c'est précisément l'erreur que ce dépôt a déjà payée avec le contrôle
# d'inventaire qui ne pesait pas les fichiers.
etape_du_workflow() {
  local nom="$1" wf="$RACINE/.github/workflows/iso.yml"
  # Le corps d'un bloc `run: |` est exactement ce qui est indenté de dix
  # espaces : on s'arrête à la première ligne qui ne l'est pas, sans quoi on
  # emporte l'en-tête de l'étape suivante — et `bash` tente d'exécuter « - ».
  # La comparaison est LITTÉRALE, pas une expression régulière : le nom d'étape
  # « GitHub Release (brouillon) » contient des parenthèses, que `$0 ~ (nom "$")`
  # prendrait pour un groupe — l'étape ne serait jamais trouvée, `$script`
  # sortirait vide, et le test échouerait sans rien dire du workflow.
  # « la ligne se termine exactement par `- name: <nom>` » se dit avec index().
  awk -v nom="$nom" '
    { cible = "- name: " nom; pos = index($0, cible) }
    !etape && pos > 0 && length($0) == pos + length(cible) - 1 { etape = 1; next }
    etape && /run: \|/ { corps = 1; next }
    corps {
      if ($0 ~ /^          /) { sub(/^          /, ""); print; next }
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      exit
    }
  ' "$wf"
}

@test "l'étape de CI qui refuse les artefacts T2 refuse VRAIMENT" {
  script="$(etape_du_workflow 'Refuser tout artefact T2')"
  [ -n "$script" ]

  cd "$BATS_TEST_TMPDIR"

  # a) Un artefact nominal seul : la publication est autorisée.
  mkdir -p iso-out
  : > iso-out/eschaton-2026.08.30-x86_64.iso
  : > iso-out/eschaton-2026.08.30-x86_64.iso.sha256
  run bash -c "$script"
  [ "$status" -eq 0 ]

  # b) L'image T2 s'y glisse : refus.
  : > iso-out/eschaton-t2-2026.08.30-x86_64.iso
  run bash -c "$script"
  [ "$status" -ne 0 ]

  # c) Même renommée, le marqueur déposé à côté suffit à la faire refuser —
  # c'est tout l'intérêt d'avoir DEUX marques plutôt qu'une.
  rm iso-out/eschaton-t2-2026.08.30-x86_64.iso
  : > iso-out/NE-PAS-PUBLIER.txt
  run bash -c "$script"
  [ "$status" -ne 0 ]
}

@test "le job de publication énumère l'image nominale et publie en BROUILLON" {
  # DEUX gardes, complémentaires, et il faut les deux : l'énumération choisit
  # QUEL fichier part, `--draft` décide QUI peut le voir. La fusion de `main`
  # dans cette branche pouvait en perdre une des deux — c'était le conflit.
  #
  # On EXÉCUTE l'étape au lieu de la grepper. L'ancienne version de ce test
  # cherchait l'absence de `iso-out/*.iso` dans tout le fichier : la chaîne
  # figure dans le commentaire qui explique justement pourquoi on n'en veut pas,
  # et l'assertion — niée, en position non finale — était de toute façon inerte.
  script="$(etape_du_workflow 'GitHub Release (brouillon)')"
  [ -n "$script" ]

  cd "$BATS_TEST_TMPDIR"
  mkdir -p iso-out faux-bin
  : > iso-out/eschaton-2026.08.30-x86_64.iso
  : > iso-out/eschaton-2026.08.30-x86_64.iso.sha256
  : > iso-out/eschaton-t2-2026.08.30-x86_64.iso     # l'image qui ne doit pas partir
  : > iso-out/eschaton-t2-2026.08.30-x86_64.iso.sha256
  : > notes.md
  # `gh` de paille : il consigne ses arguments au lieu de publier quoi que ce soit.
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$PWD/gh-args"\n' > faux-bin/gh
  chmod +x faux-bin/gh

  PATH="$PWD/faux-bin:$PATH" GITHUB_REF_NAME=v0.1.0 GITHUB_REPOSITORY=Seylar/eschaton \
    run bash -c "$script"
  [ "$status" -eq 0 ]

  # a) L'image T2 n'est PAS dans ce qui part.
  refute grep -q 'eschaton-t2' gh-args
  # b) L'image nominale, si.
  grep -qx 'iso-out/eschaton-2026.08.30-x86_64.iso' gh-args
  grep -qx 'iso-out/eschaton-2026.08.30-x86_64.iso.sha256' gh-args
  # c) Et la Release est un BROUILLON : un tag ne met rien en ligne publiquement
  # tant que la double licence GPL/MIT et les choix de média de développement ne
  # sont pas tranchés (iso/PROVENANCE.md, iso/README.md).
  grep -qx -- '--draft' gh-args
}

@test "deux images nominales arrêtent la publication au lieu d'en choisir une" {
  # Le pendant du test précédent : l'énumération doit REFUSER l'ambiguïté, pas
  # publier la première venue.
  script="$(etape_du_workflow 'GitHub Release (brouillon)')"
  cd "$BATS_TEST_TMPDIR"
  mkdir -p iso-out faux-bin
  : > iso-out/eschaton-2026.08.30-x86_64.iso
  : > iso-out/eschaton-2026.08.31-x86_64.iso
  : > notes.md
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$PWD/gh-args"\n' > faux-bin/gh
  chmod +x faux-bin/gh
  PATH="$PWD/faux-bin:$PATH" GITHUB_REF_NAME=v0.1.0 GITHUB_REPOSITORY=Seylar/eschaton \
    run bash -c "$script"
  [ "$status" -ne 0 ]
  [ ! -e gh-args ]
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

# --- 5. LE SYSTÈME INSTALLÉ DÉMARRE — le chemin T2 de l'installeur -------------
#
# Jusqu'ici tout ce fichier vérifiait le MÉDIA. Or le média n'installe rien : ce
# que la machine démarre, c'est ce que `eschaton-install` a posé sur le disque.
# L'installeur ignorait le variant : il posait le `linux` amont — le seul noyau
# qui ne voit pas le NVMe d'un Mac T2, la puce T2 en étant le contrôleur. Une
# installation T2 réussissait donc, et ne démarrait jamais.
#
# ⚠️ CE QUE CES TESTS PROUVENT : le PLAN d'installation. Ils exercent la
# répétition à blanc, sur un Mac, sans disque et sans root. Ils ne prouvent
# RIEN du démarrage réel — cela demande la machine de l'auteur (iso/README.md,
# « ce qui reste à prouver sur la vraie machine »).

@test "le chemin nominal n'installe RIEN de T2 — l'invariant à ne pas casser" {
  # Le livrable ne bouge pas. Ce test est le verrou : si un jour le chemin T2
  # débordait sur le nominal, c'est ici que ça se verrait.
  run plan_installation ""      # aucun marqueur : c'est le cas d'un live tiers
  [ "$status" -eq 0 ]
  [[ "$output" == *"pacstrap -K /mnt base linux intel-ucode amd-ucode"* ]]
  [[ "$output" != *"linux-t2"* ]]
  [[ "$output" != *"arch-mact2"* ]]
  [[ "$output" != *"eschaton-t2"* ]]
  [[ "$output" != *"apple-bcm-firmware"* ]]
  [[ "$output" != *"intel_iommu"* ]]
  [[ "$output" == *"default_entry: Eschaton/linux"* ]]
  # La ligne de commande du noyau est celle d'avant, mot pour mot.
  [[ "$output" == *"cmdline: root=LABEL=eschaton rootflags=subvol=@ rw quiet"$'\n'* ]]
}

@test "un marqueur « nominal » installe le chemin nominal" {
  run plan_installation "nominal"
  [ "$status" -eq 0 ]
  [[ "$output" != *"linux-t2"* ]]
  [[ "$output" != *"arch-mact2"* ]]
}

@test "le chemin T2 pose linux-t2 et le firmware, jamais le noyau amont" {
  # LA panne : `linux` sur un Mac T2 donne au premier démarrage une machine sans
  # disque visible, sans clavier et sans trackpad — irréparable sur place.
  run plan_installation "" --variant t2
  [ "$status" -eq 0 ]
  [[ "$output" == *"pacstrap"*"linux-t2"* ]]
  # `apple-bcm-firmware` explicitement : c'est le SEUL réseau de cette machine,
  # qui n'a aucun port Ethernet. Le laisser aux seules dépendances d'un
  # méta-paquet, c'est accepter qu'un jour il disparaisse en silence.
  [[ "$output" == *"apple-bcm-firmware"* ]]
  # Le noyau amont n'est nulle part dans le plan : ni pacstrap, ni amorçage.
  refute grep -qE 'pacstrap .*(^| )linux( |$)' <<<"$output"
  [[ "$output" == *"default_entry: Eschaton/linux-t2"* ]]
  [[ "$output" == *"boot():/vmlinuz-linux-t2"* ]]
  [[ "$output" == *"boot():/initramfs-linux-t2.img"* ]]
}

@test "le chemin T2 configure le dépôt arch-mact2 SUR LA CIBLE, et l'affiche" {
  # Sans dépôt sur la cible, la machine n'a aucune source pour son propre noyau :
  # plus une seule mise à jour de `linux-t2`, et la garde refuse tout retour au
  # noyau amont. L'ADR 0004 §4.2 l'anticipait — « ajouté séparément, avec sa
  # politique propre, sur une machine T2 uniquement » — et exige que le
  # compromis soit AFFICHÉ.
  run plan_installation "" --variant t2
  [ "$status" -eq 0 ]
  # a) sur la cible…
  [[ "$output" == *"/mnt/etc/pacman.d/arch-mact2.conf"* ]]
  [[ "$output" == *"Include = /etc/pacman.d/arch-mact2.conf"* ]]
  # b) …et dans le live, sans quoi pacstrap ne trouverait pas linux-t2.
  [[ "$output" == *"DRY: écrire le dépôt arch-mact2"* ]]
  # c) le compromis est montré, et il est montré AVANT le premier sgdisk.
  [[ "$output" == *"n'est PAS signé"* ]]
  [[ "$output" == *"mainteneur unique"* ]]
  avant="${output%%sgdisk*}"
  [[ "$avant" == *"CHEMIN T2"* ]]
}

@test "le chemin T2 installe la garde d'épinglage PENDANT l'installation" {
  # Le README prescrivait « après le premier démarrage, pacman -S eschaton-t2 ».
  # Ce premier démarrage est précisément celui qu'un noyau mal choisi rend
  # impossible : la garde doit être là avant, pas après.
  run plan_installation "" --variant t2
  [ "$status" -eq 0 ]
  [[ "$output" == *"pacstrap"*"eschaton-t2"* ]]
  [[ "$output" == *"/mnt/usr/lib/eschaton/t2-garde-noyau"* ]]
  refute grep -qi 'après le premier démarrage' "$RACINE/iso/README.md"
}

@test "le variant se déduit du marqueur du média, pas d'une détection matérielle" {
  # Explicite plutôt que deviné : c'est `build-iso` qui écrit ce fichier, en
  # sachant quelle image il construit.
  run plan_installation "t2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"linux-t2"* ]]
  [[ "$output" == *"marqueur du média"* ]]
  # Aucune reniflette DMI/modèle dans l'installeur : le mauvais chemin ne doit
  # jamais venir d'une supposition.
  refute grep -qE 'dmidecode|/sys/class/dmi|MacBookPro' "$INSTALL"
  refute grep -qE 'dmidecode|/sys/class/dmi|MacBookPro' "$RACINE/installer/lib.sh"
}

@test "le drapeau explicite prime sur le marqueur, dans les deux sens" {
  run plan_installation "t2" --variant nominal
  [ "$status" -eq 0 ]
  [[ "$output" != *"linux-t2"* ]]
  run plan_installation "nominal" --variant t2
  [ "$status" -eq 0 ]
  [[ "$output" == *"linux-t2"* ]]
}

@test "un marqueur de valeur inconnue fait REFUSER, il ne fait pas deviner" {
  # Ce fichier n'est écrit que par build-iso, et il n'y écrit que deux valeurs.
  # Autre chose n'est pas un doute, c'est une contradiction — et le mauvais
  # chemin donne un système qui ne démarre pas. Même règle que --disk répété.
  run plan_installation "t3"
  [ "$status" -ne 0 ]
  [[ "$output" == *"t3"* ]]
  # …et rien de destructeur n'a été annoncé.
  [[ "$output" != *"sgdisk"* ]]
  # Un --variant inconnu est refusé de la même façon.
  run plan_installation "" --variant t3
  [ "$status" -ne 0 ]
  [[ "$output" != *"sgdisk"* ]]
}

@test "build-iso dépose le marqueur, pour les deux variants" {
  grep -q 'usr/local/share/eschaton/variant' "$BUILD"
  # Écrit HORS du bloc `if [[ "$variante" == t2 ]]` : le nominal en a un aussi,
  # ce qui fait de « marqueur absent » le cas des seuls médias non Eschaton.
  bloc="$(sed -n '/^if \[\[ "\$variante" == t2 \]\]; then$/,/^fi$/p' "$BUILD")"
  [ -n "$bloc" ]
  refute grep -q 'usr/local/share/eschaton/variant' <<<"$bloc"
  # …et l'installeur lit exactement ce chemin-là.
  grep -q '/usr/local/share/eschaton/variant' "$RACINE/installer/lib.sh"
}

@test "l'adresse du dépôt tiers est la MÊME dans l'ISO et dans l'installeur" {
  # Duplication assumée : le fragment de l'ISO sert à CONSTRUIRE, celui de
  # l'installeur à INSTALLER, et les deux ne se rencontrent jamais à
  # l'exécution. Ce test est ce qui la rend sûre.
  url_iso="$(sed -n 's/^Server[[:space:]]*=[[:space:]]*//p' "$VARIANT/arch-mact2.conf")"
  url_installeur="$(sed -n 's/^DEPOT_T2_URL="\(.*\)"$/\1/p' "$RACINE/installer/lib.sh")"
  [ -n "$url_iso" ]
  [ "$url_iso" = "$url_installeur" ]
}

@test "l'installeur ne porte AUCUNE section [arch-mact2] littérale" {
  # `build-iso` copie l'installeur dans l'airootfs de l'image, puis refuse toute
  # image dont un fichier porte une ligne « [arch-mact2] ». Un script qui
  # COMPOSE cette section n'est pas une configuration de l'image — mais le
  # `grep` de la garde ne sait pas faire la différence, et l'affaiblir pour lui
  # apprendre la nuance serait la désarmer. Le nom de section est donc assemblé.
  refute grep -qE '^[[:space:]]*\[arch-mact2\]' "$INSTALL"
  refute grep -qE '^[[:space:]]*\[arch-mact2\]' "$RACINE/installer/lib.sh"
}

@test "la garde d'après-construction s'exerce sur les DEUX variants" {
  # M-4 : elle ne tournait que sur le T2. Sur le nominal une fuite est
  # invraisemblable — donc personne ne la regarderait, donc c'est là qu'elle
  # vivrait le plus longtemps. Et le nominal est l'image qui se publie.
  bloc="$(sed -n '/Le dépôt tiers ne doit pas non plus/,/aucune configuration pacman du système livré/p' "$BUILD")"
  [ -n "$bloc" ]
  refute grep -qE 'if \[\[ "\$variante" == t2 \]\]' <<<"$bloc"
  grep -q 'mkarchiso/x86_64/airootfs' <<<"$bloc"
}
