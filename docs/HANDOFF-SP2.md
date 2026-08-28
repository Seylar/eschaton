# Revue finale SP2 (Bureau) — passage de relais à Claude

- **Date** : 2026-08-28
- **Branche à reviewer** : `bureau`
- **Interdit explicite** : ne pas fusionner dans `main` et ne pas créer le tag
  `v0.2.0` avant la revue complète demandée.

## 1. Résultat

Les Tasks 1 à 4 ont été relues, corrigées et retestées. Les Tasks 5 à 9 sont
implémentées et documentées. La VM `eschaton-dev` a réellement installé le meta
depuis le dépôt, chargé les deux plugins, exécuté une mise à jour depuis DMS,
restauré un snapshot depuis DMS et redémarré sur l'état restauré.

Preuves de référence :

- spec et DoD : `docs/superpowers/specs/2026-08-28-bureau-design.md`, §6.1 ;
- déroulé VM détaillé : `tools/vm-dev.md`, §§14–17 ;
- code à comparer : `origin/main...bureau` (le checkout local `main` de la
  machine est ancien et contient des modifications utilisateur non liées).

## 2. Correctifs importants trouvés par la review et le dogfooding

### Tasks 1–4

- `eschaton-session` : amorçage DMS idempotent et respect d'un retrait
  volontaire du hook utilisateur ;
- `check-desktop-deps` : une panne API/outillage rend désormais rc=2, jamais un
  faux « paquet absent » ;
- `tools/vm-serial` : arguments invalides sans traceback ;
- `eschaton-update --yes` : traduction stricte vers `pacman --noconfirm` ;
- tests Bats ajoutés pour ces contrats.

### Tasks 5–9

- dépendance `fakeroot` ajoutée au plugin update (`checkupdates` échouait dans la
  vraie VM) ;
- provisioning DMS automatique des plugins et du wallpaper, sans écraser les
  choix utilisateur ; cycle systemd initial supprimé par un drop-in de
  `dms.service` ;
- `xdg-desktop-portal-gtk` ajouté : le backend Hyprland ne fournit pas
  FileChooser ;
- listes update/rollback rafraîchies à l'ouverture des popouts ;
- publication Pacman rendue immuable : une archive déjà publiée sous le même
  nom/version est téléchargée, vérifiée et réutilisée octet pour octet. La CI
  précédente republiait des octets différents sous le même pkgrel et cassait les
  caches clients. Les workflows complets sont en plus sérialisés : sérialiser
  seulement le job Pages laisserait deux builds concurrents produire le même
  nouveau pkgrel avant sa première publication.

## 3. Rollback : surface exacte à reviewer

Le plan initial est obsolète sur ce point. Snapper n'expose pas de rollback
adapté à la disposition Arch d'Eschaton. Le chemin livré est :

```text
DMS → pkexec /usr/bin/eschaton-rollback --yes NUMÉRO
    → action org.eschaton.rollback
    → remplacement btrfs de @ par un snapshot inscriptible
```

La règle Polkit exige un sujet local, actif et membre de `wheel`, et compare
l'exécutable exact. L'état précédent est conservé dans un sous-volume
`@.avant-rollback-*`. La lecture de la liste passe par `snapper --jsonout` et la
configuration Snapper `ALLOW_GROUPS=wheel` ; aucune action polkit Snapper
imaginaire n'a été ajoutée.

## 4. Preuve dynamique minimale

Update depuis le widget :

```text
pacman -Syu --noconfirm
snapshot 32 pre → snapshot 33 post
eschaton-desktop-config 0.1.0-3 → 0.1.0-4
entrées 32/33 présentes dans /boot/limine.conf
```

Rollback depuis le widget vers 33, après installation de `cowsay` :

```text
cowsay absent après reboot
~/MARQUEUR-AVANT présent
findmnt / → /dev/vda2[/@]
ancien état → @.avant-rollback-20260828-132747
```

Le service de provisioning après reboot est `active (exited)` avec
`status=0/SUCCESS`; `dms.service` est `active (running)`.

## 5. Réserves honnêtes

- La VM UTM a été créée avec `-audio none`. PipeWire/WirePlumber et l'interface
  DMS sont actifs, mais aucun test ne peut prouver la sélection d'un périphérique
  audio matériel inexistant.
- `LIBGL_ALWAYS_SOFTWARE=1` reste une surcharge propre à la VM dans
  `greetd.toml`, jamais un défaut du paquet.
- Le sous-volume de secours du rollback est volontairement conservé pour la
  review ; ne le supprimer qu'après validation.
- La CI et la policy Pages acceptent temporairement `bureau` pour le dogfooding.
  Les refermer sur `main` au moment de la fusion.

## 6. Checklist Claude

1. Reviewer `git diff origin/main...bureau`, en priorité les helpers privilégiés, les
   règles Polkit, les unités systemd et `repo/build-repo`.
2. Rejouer `shellcheck`, `bats tests/`, le build des quatre paquets desktop et
   les validations QML DMS 1.5.3.
3. Vérifier la dernière CI `bureau` et la consommation du dépôt aarch64/x86_64.
4. Si la review est approuvée : refermer la CI/Pages sur `main`, fusionner,
   relancer la CI de `main`, puis seulement créer/pousser `v0.2.0`.
5. Si un correctif est demandé : bump obligatoire du `pkgrel` concerné ; le
   dépôt refuse désormais implicitement de remplacer une archive du même nom.
