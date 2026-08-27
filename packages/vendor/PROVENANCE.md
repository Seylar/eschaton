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
| Revue de sécurité | 2026-08-27 — voir `.superpowers/sdd/2026-08-27-socle/task-6-report.md` |

Consommé par : `depends` de `eschaton-base`.

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
| Revue de sécurité | 2026-08-27 — voir `.superpowers/sdd/2026-08-27-socle/task-6-report.md` |

Le nom du paquet et celui de son upstream diffèrent : `limine-mkinitcpio-hook`
est construit depuis le dépôt `limine-entry-tool` (le PKGBUILD `provides` et
`conflicts` avec `limine-entry-tool`).

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
