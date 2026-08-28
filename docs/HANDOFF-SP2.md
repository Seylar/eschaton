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
  `dms.service`. Le helper attend séparément la cible IPC `bar` : `plugins list`
  peut réussir plusieurs secondes avant elle et `Target not found.` rend rc=0.
  Il active ensuite les plugins et exige deux états `loaded` consécutifs avant
  de poser son marqueur : un `plugins enable` accepté trop tôt était sinon
  annulé par le chargement tardif de `plugin_settings.json` ;
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

L'action est annotée sur l'exécutable exact et ne porte que ses `<defaults>` :
`allow_any=no`, `allow_inactive=no`, `allow_active=auth_admin`. Une restauration
demande donc une **authentification** à chaque fois, servie par la modale de
l'agent polkit de DMS. *(Amendé le 2026-08-28 par la revue de vague : la version
0.1.0-2 livrait en plus une règle `rules.d` rendant `YES` — sans mot de passe —
pour un sujet `wheel` local et actif ; elle est supprimée en 0.1.0-3. Voir
l'en-tête de `org.eschaton.rollback.policy`.)* L'état précédent est conservé
dans un sous-volume
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
`status=0/SUCCESS`; `dms.service` est `active (running)`. Le test frais final a
installé `eschaton-desktop-config 0.1.0-7` depuis Pages, forcé plugins à
`false`, widgets absents et stamp absent, puis rebooté. Les assertions donnent
`loaded,loaded`, `[true,true]`, un exemplaire de chaque widget et un stamp
présent ; une seconde lecture 15 s plus tard donne encore le même état. Code :
`840d0fc`; CI bi-architecture et publication : `33169926022`.

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


## 7. Tâche suivante pour Codex — fix du rendu des pastilles (BLOQUEUR du tag v0.2.0)

*(Section ajoutée par Claude après la re-revue de la vague de fix — le commit précédent l'annonçait par erreur, la voici réellement.)*

**Le constat** (vm-dev §14.4, spec §6.1 ligne 6, confirmé en re-revue sur captures) : au **boot frais**, les deux pastilles Eschaton sont intégralement déclarées actives — IPC `plugins list` → `loaded`, `plugin_settings.json` → `true,true`, `rightWidgets` complet — mais **ne sont pas rendues** dans la DankBar. `systemctl --user restart dms.service` les fait apparaître immédiatement et durablement. `dms ipc call plugins reload <id>` ne répare PAS. La Task 7 n'avait jamais testé le rendu (fichiers+IPC seulement).

**Mission** :
1. **Diagnostiquer la course** dans la VM (`eschaton-dev`, `tools/vm-serial`) : pourquoi la barre compose-t-elle avant que les plugins système soient visibles au premier démarrage, alors qu'un restart règle tout ? Pistes : ordre `eschaton-dms-provision.service` (Wants/Before de `dms.service`) vs le moment où `PluginService` scanne `/etc/xdg/quickshell/dms-plugins/` ; le chargement tardif de `plugin_settings.json` (mensonge IPC n°2, déjà capturé par `tests/dms-provision.bats`) ; un besoin de re-notification de la barre après enregistrement tardif.
2. **Corriger dans les paquets** (jamais VM-seulement) — le correctif le plus PETIT qui tient : ordonnancement d'unités, séquence de provisioning, ou signal de recomposition documenté côté DMS s'il existe. Si le défaut est amont (DMS ne recompose pas sur enregistrement tardif d'un plugin système), contournement packagé le plus propre + note upstream consignée.
3. **Prouver au boot frais** : reboot complet → les 2 pastilles rendues SANS action manuelle (capture, méthode §12.5), **deux boots de suite**. Ajouter l'assertion de rendu à la checklist (vm-dev) pour que le trou de T7 ne se reproduise pas.
4. pkgrel bump des paquets touchés, push, CI verte, `pacman -Syu` en VM avant preuve. Bats pour toute logique nouvelle.
5. **Ne pas tagger, ne pas fusionner** — la revue Claude reste le gate du tag.

**Rappels** : la règle polkit supprimée ne se réintroduit pas (auth_admin par la modale DMS, prouvée) ; immutabilité du dépôt (bump systématique, jamais des octets différents sous un même pkgrel) ; jamais `ping` ; correctifs toujours au repo.
