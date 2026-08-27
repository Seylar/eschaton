# Paquets vendorés — provenance

Ce dossier contient des PKGBUILDs **copiés depuis l'AUR**, sans modification.
Ils ne sont pas des paquets Eschaton : nous les reconstruisons simplement pour
les publier dans notre dépôt `[eschaton]`, parce qu'ils sont absents des dépôts
Arch officiels (spec §8, risque 3 — confirmé aussi pour ALARM par le spike Task 1).

Leurs métadonnées d'origine (mainteneur, licence, `url`) sont conservées telles
quelles : ce sont les paquets de leurs auteurs, pas les nôtres. Le motif
« LICENSE partagé » des paquets `eschaton-*` ne s'applique donc pas ici.

## Règle de resynchronisation

1. **Jamais de modification locale sans note dans ce fichier.** Un PKGBUILD
   vendoré est une copie conforme de l'AUR. Si un correctif local devient
   indispensable, il est documenté ici (quoi, pourquoi, quand) et signalé en
   commentaire dans le PKGBUILD concerné.
2. **La resynchronisation est manuelle** : on refait `git clone` du dépôt AUR,
   on compare, on remplace, on met à jour le tableau ci-dessous. Aucun
   automatisme ne tire de l'AUR — du code tiers ne doit pas entrer sans regard humain.
3. **Toute resynchronisation impose une nouvelle revue de sécurité** du PKGBUILD
   et de ses fichiers annexes (`source=` toujours sur l'upstream attendu, sommes
   de contrôle présentes, pas de `.install` ni de commande inattendue). Une
   version qui monte n'est pas une raison de sauter la relecture.
   **Les résumés de revue par paquet, plus bas dans ce fichier, sont la trace
   d'audit de référence** : ils sont auto-porteurs et versionnés avec le dépôt.
   Toute nouvelle revue les remplace ; on ne renvoie jamais vers un document
   externe au dépôt (les rapports de session détaillés ne survivent pas au
   checkout).
4. Le `.gitignore` de chaque dossier vient de l'AUR (`*` sauf `PKGBUILD` et
   `.SRCINFO`). Il est conservé tel quel, et il a un effet utile : les artefacts
   de `makepkg` (`src/`, `pkg/`, tarballs GraalVM de plusieurs centaines de Mo,
   `*.pkg.tar.zst`) ne peuvent pas être committés par accident.
   **Corollaire à connaître** : tout fichier ajouté à la main dans ces dossiers
   (un patch, par exemple) serait ignoré silencieusement par git — il faudrait
   l'ajouter avec `git add -f` et le noter ici.

## Paquets vendorés

### `limine-snapper-sync`

| | |
|---|---|
| AUR | https://aur.archlinux.org/limine-snapper-sync.git |
| Commit AUR copié | `35aff513bf1f0284380c8592d3de213f00bb6a7b` (« 1.31.0 », 2026-06-30) |
| Date de la copie | 2026-08-27 |
| Version | `1.31.0-1` |
| Upstream | https://gitlab.com/Zesko/limine-snapper-sync (tag `1.31.0`) |
| Mainteneur AUR | Zesko — également l'auteur upstream |
| Licence | GPL3 |
| Fichiers copiés | `PKGBUILD`, `.SRCINFO`, `.gitignore` (aucun `.install`, aucun patch) |
| Revue de sécurité | 2026-08-27 — résumé ci-dessous |

Consommé par : `depends` de `eschaton-base`.

**Revue de sécurité du 2026-08-27** (PKGBUILD lu intégralement) :

- `source=` pointe le dépôt **upstream du projet**, épinglé sur un tag :
  `git+https://gitlab.com/Zesko/limine-snapper-sync.git#tag=1.31.0`. Tag vérifié
  comme existant et résolvant le commit upstream `0df30174795c47bc3f85fe701de92c308aeee840`.
- La toolchain de construction vient des builds **GraalVM CE officiels** :
  `https://github.com/graalvm/graalvm-ce-builds/releases/download/jdk-25.0.2/graalvm-community-jdk-25.0.2_linux-{aarch64,x64}_bin.tar.gz`.
- **3 sommes sha256 réelles, aucun `SKIP`** — y compris pour la source git, que
  pacman 7 vérifie par hachage de contenu : le `#tag=`, référence mutable en soi,
  est donc adossé à une somme. Les 4 sommes ont été **validées à l'exécution**
  lors de la construction (`Validating source files with sha256sums... Passed`).
- `.SRCINFO` **concorde exactement** avec le PKGBUILD (le piège du `.SRCINFO`
  divergent est écarté).
- **Aucun `.install`, aucun patch, aucun script annexe** : le dépôt AUR ne
  contient que `PKGBUILD`, `.SRCINFO`, `.gitignore`. Aucun scriptlet AUR ne
  s'exécute en root à l'installation.
- `prepare()`/`build()`/`package()` : **aucune commande suspecte** — pas de
  `curl`/`wget`, pas de `eval`, pas de pipe-vers-shell, pas de `sudo`, aucune
  écriture hors `$srcdir`/`$pkgdir`.
- Mainteneur AUR = auteur upstream (Zesko) : pas d'intermédiaire entre l'upstream
  et le paquet ; historique AUR régulier, un commit par version.
- Revue étendue à l'arbre `install/arch-linux/` de l'upstream (ce qui s'exécute
  en root chez nous, faute de `.install`) : **aucun appel réseau, aucun `eval`**.
  Le script privilégié `usr/share/libalpm/scripts/limine-snapper-lock` est
  trivial (attente de mutex).
- **Limite assumée** : le cœur de l'outil est un binaire natif compilé par
  GraalVM depuis des sources Java, non audité. La confiance repose sur l'upstream
  identifié, les sources épinglées par somme, et la compilation par nos soins.
- **Constat namcap sur le paquet construit** : `hicolor-icon-theme` manque aux
  `depends` alors qu'une icône est livrée dans la hiérarchie hicolor, et `GPL3`
  n'est pas un identifiant SPDX valide. Défauts upstream, **non corrigés** chez
  nous (règle : pas de modification locale).

### `limine-mkinitcpio-hook`

| | |
|---|---|
| AUR | https://aur.archlinux.org/limine-mkinitcpio-hook.git |
| Commit AUR copié | `0f6dc5eb0072fa72f135fd016b64978a4de39cf5` (« 1.37.1 », 2026-07-16) |
| Date de la copie | 2026-08-27 |
| Version | `1.37.1-1` |
| Upstream | https://gitlab.com/Zesko/limine-entry-tool (tag `1.37.1`) |
| Mainteneur AUR | Zesko — également l'auteur upstream |
| Licence | GPL3 |
| Fichiers copiés | `PKGBUILD`, `.SRCINFO`, `.gitignore` (aucun `.install`, aucun patch) |
| Revue de sécurité | 2026-08-27 — résumé ci-dessous |

Le nom du paquet et celui de son upstream diffèrent : `limine-mkinitcpio-hook`
est construit depuis le dépôt `limine-entry-tool` (le PKGBUILD `provides` et
`conflicts` avec `limine-entry-tool`). Vérifié : ce n'est pas une substitution de
source, c'est bien le dépôt du même auteur pour le même outil.

**Revue de sécurité du 2026-08-27** (PKGBUILD lu intégralement) :

- `source=` pointe le dépôt **upstream du projet**, épinglé sur un tag :
  `git+https://gitlab.com/Zesko/limine-entry-tool.git#tag=1.37.1`. Tag vérifié
  comme existant et résolvant le commit upstream `26b1879c862a55bae4e8777d48b2f917c68ef347`.
- Toolchain depuis les builds **GraalVM CE officiels** :
  `https://github.com/graalvm/graalvm-ce-builds/releases/download/graal-25.1.3/graalvm-community-jdk-25i1-25.0.3_linux-{aarch64,x64}_bin.tar.gz`.
- **3 sommes sha256 réelles, aucun `SKIP`** (source git comprise), **validées à
  l'exécution** lors de la construction.
- `.SRCINFO` **concorde exactement** avec le PKGBUILD.
- **Aucun `.install`, aucun patch, aucun script annexe.**
- `prepare()`/`build()`/`package()` : **aucune commande suspecte**, aucune
  écriture hors `$srcdir`/`$pkgdir`. `package()` ne copie que les sous-arbres
  `limine-entry-tool/` et `limine-mkinitcpio-hook/` — pas `limine-dracut-support/`,
  qui est le paquet AUR frère.
- Mainteneur AUR = auteur upstream (Zesko).
- Revue étendue à l'arbre `install/arch-linux/` (code exécuté en root) :
  **aucun appel réseau, aucun `eval`, aucun pipe-vers-shell**. Le script
  `usr/share/libalpm/scripts/limine-mkinitcpio-install` (280 l., lancé à chaque
  installation de noyau) est du bash défensif correct : `mktemp -d`, `rm -r` gardé
  par un test de préfixe, contrôle d'appartenance `pacman -Qqo`, `trap … EXIT`.
  `usr/lib/limine/auth-helper` élève les privilèges par ré-exec en validant la
  commande (`command -v`) lue dans un fichier de configuration root.

**Trois comportements intrusifs à connaître** — légitimes pour cet outil, mais
notre distribution en hérite (ce ne sont pas des failles, ce sont des choix) :

1. **`/usr/local/bin/mkinitcpio`** : le paquet installe un *wrapper* dans le
   territoire de l'administrateur, qui précède `/usr/bin` dans le `PATH` et
   **intercepte donc tout appel à `mkinitcpio`** (namcap le signale :
   « File (usr/local/bin/mkinitcpio) exists in a non-standard directory »). Il
   appelle le vrai binaire, puis sur `-P`/`-p` propose *interactivement* de lancer
   `limine-mkinitcpio`. Deux pièges en automatisation : le `read` reçoit EOF en
   contexte non interactif, la réponse vide correspond à la branche « oui » et
   **`limine-mkinitcpio` se lance tout seul** ; et le wrapper **ne propage pas le
   code de retour** du vrai `mkinitcpio`, ce qui peut masquer un échec.
2. **`/etc/pacman.d/hooks/90-mkinitcpio-install.hook`** : hook déposé dans le
   répertoire de l'administrateur, prioritaire sur `/usr/share/libalpm/hooks/` —
   il **remplace le hook homonyme de `mkinitcpio`** pour rediriger la génération
   d'initramfs. Il n'est pas dans `backup=()` : pacman écrasera une modification
   locale.
3. Les scripts exécutent en root les hooks administrateur de
   `/etc/boot/hooks/{pre,post}.d/` — par conception et documenté par l'upstream.

**Limite assumée** : cœur de l'outil = binaire natif GraalVM, non audité.
**Constat namcap** : `GPL3` n'est pas un identifiant SPDX valide (défaut upstream,
non corrigé chez nous).

## Paquets vérifiés, non vendorés

- **`limine`** : présent dans les dépôts, aucune raison de le vendorer.
  Vérifié le 2026-08-27 côté ALARM aarch64 (`tools/sandbox`) :
  `extra/limine 12.6.1-1`, `Architecture : aarch64`. La contingence prévue par
  le brief de la Task 6 (vendorer aussi `limine`) est donc **sans objet**.

## Contrainte de construction connue

Ces deux paquets sont `arch=('x86_64' 'aarch64')` — ce sont des binaires natifs
(GraalVM `native-image`), pas des paquets `any` comme les `eschaton-*`. Deux
conséquences pour l'outillage :

- `tools/build-pkg` et `tools/sandbox` choisissent l'image ALARM sur un hôte
  arm64 « puisque les paquets sont `arch=(any)` » ; **ce raisonnement ne tient
  pas pour `packages/vendor/`**, où l'architecture de construction est celle du
  paquet produit.
- `makedepends=('git' 'gradle')` : **aucune des deux architectures ne fournit
  aujourd'hui un `gradle` utilisable** (constaté le 2026-08-27) :
  - **aarch64 / ALARM** : `gradle` est absent des dépôts (`pacman -Si gradle` →
    « package 'gradle' was not found » ; `pacman -Ss gradle` → aucun résultat).
  - **x86_64 / Arch** : `extra/gradle 9.7.0-1` est présent (`arch=any`) mais
    **cassé** — sa distribution ne contient pas le module
    `gradle-public-api-legacy` (425 jars dans `/usr/share/java/gradle/lib/`,
    aucun ne correspond ; `pacman -Ql gradle` non plus). Toute configuration de
    projet Gradle échoue, y compris un projet trivial n'utilisant que le plugin
    interne `application` : `Cannot find module 'gradle-public-api-legacy' in
    distribution directory '/usr/share/java/gradle'`. Ce n'est donc pas un
    défaut des PKGBUILDs vendorés.

  Conséquence : sans intervention, ces deux paquets ne sont constructibles sur
  aucune des deux architectures.

### Contournement en place : `tools/provision-gradle`

Puisque aucun dépôt ne fournit de `gradle` utilisable, l'environnement de
construction se le procure lui-même : **`tools/provision-gradle`** installe la
distribution Gradle officielle (9.7.1) dans le conteneur, vérifiée contre une
**somme SHA-256 épinglée en dur** dans le script, et la lie en `/usr/bin/gradle`
— le chemin absolu qu'appellent les deux PKGBUILDs. **Aucun PKGBUILD vendoré
n'est modifié** : le contournement vit entièrement dans l'environnement de build.

Le script s'exécute en root dans le conteneur, avant `makepkg` :

```bash
tools/provision-gradle
```

Il est **autosuffisant dans un conteneur frais** : il ne suppose ni bases de
données pacman synchronisées, ni `DisableSandbox` préalablement activé dans
`pacman.conf`. Il porte lui-même son `-Syu` et son `--disable-sandbox` (le bac à
sable Landlock de pacman 7 est refusé par le profil seccomp de Docker). Aucune
préparation du conteneur n'est donc requise avant de l'appeler — c'est ce qui le
rend utilisable tel quel dans la CI de la Task 8.

Deux points à connaître pour construire ces paquets :

- **`makepkg -d` et non `-s`** : makepkg résout les `makedepends` via la base de
  données pacman, pas via le `PATH`. Il réclamerait donc le *paquet* `gradle`
  (inexistant sur ALARM) malgré `/usr/bin/gradle` bien présent. On installe
  l'autre makedepend (`git`) à la main et on saute la vérification.
- **règle sudoers** : `makepkg` tourne sous l'utilisateur `builder` et appelle
  `sudo pacman` ; le conteneur n'a aucune règle sudo par défaut. À ajouter
  (conteneur jetable uniquement) :
  `echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder`.

**À réévaluer** : ce provisioning est un contournement, pas une cible. Dès
qu'Arch aura réparé `extra/gradle` (et, pour la branche aarch64, si ALARM
finit par distribuer `gradle`), il faudra revérifier si le `gradle` des dépôts
suffit et, le cas échéant, supprimer `tools/provision-gradle` du flux de build.
Tant que le script est utilisé, sa version et sa somme SHA-256 sont à tenir à
jour comme n'importe quelle dépendance épinglée.
