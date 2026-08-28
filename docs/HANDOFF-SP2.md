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
`status=0/SUCCESS`; `dms.service` est `active (running)`. Le premier test frais
sur le pkgrel 7 ne prouvait que fichiers et IPC et a donc laissé passer le défaut
de rendu décrit au §7. La preuve corrigée installe depuis Pages
`eschaton-desktop-config 0.1.0-9` (SHA-256 publié
`fe81891f33aafa68e07c64afae33c494317dc1dd871b91d0d9f4e6ea2322d076`),
force plugins à `false`, widgets absents et stamp absent, puis effectue deux
boots consécutifs. Les deux donnent `loaded,loaded`, `[true,true]`, un exemplaire
de chaque widget sur disque **et en mémoire**, et les captures montrent les deux
pastilles. Code : `4c91c79`; CI bi-architecture et publication : `33179345260` ;
détail et empreintes des captures : `tools/vm-dev.md` §14.5.

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


## 7. Résolution Codex — rendu des pastilles au boot frais

*(Section ajoutée par Claude après la re-revue de la vague de fix — le commit précédent l'annonçait par erreur, la voici réellement.)*

**Le constat** (vm-dev §14.4, spec §6.1 ligne 6, confirmé en re-revue sur captures) : au **boot frais**, les deux pastilles Eschaton sont intégralement déclarées actives — IPC `plugins list` → `loaded`, `plugin_settings.json` → `true,true`, `rightWidgets` complet — mais **ne sont pas rendues** dans la DankBar. `systemctl --user restart dms.service` les fait apparaître immédiatement et durablement. `dms ipc call plugins reload <id>` ne répare PAS. La Task 7 n'avait jamais testé le rendu (fichiers+IPC seulement).

**Mission accomplie sur `4c91c79`.** Le problème n'était pas un scan tardif des
plugins : DMS 1.5.3 ne recharge pas `settings.json`, tandis que son IPC
`settings set` refuse les tableaux. Le helper ajoutait correctement les ids sur
disque mais le `barConfigs` en mémoire restait ancien. Un reload de plugin ne
peut pas créer les hôtes de widgets absents.

Le pkgrel 9 compare désormais l'état mémoire après provisioning et demande, si
nécessaire, `systemctl --user --no-block restart dms.service`. Le restart est
unique, différé pour ne pas bloquer l'ordre systemd, et sera automatiquement
évité si DMS sait un jour recharger la liste. Deux tests Bats couvrent la
détection et l'appel exact.

Preuve sur le paquet Pages, détaillée dans `tools/vm-dev.md` §14.5 :

1. boot frais après état `false,false`, widgets absents et stamp absent : les
   deux pastilles sont rendues ; fichier/IPC `1,1`, statuts `loaded,loaded` ;
2. reboot consécutif sans réinitialisation : les deux pastilles restent rendues
   et le journal confirme `recompose_messages=0` ;
3. CI `33179345260` entièrement verte, paquet publié puis réinstallé en VM.

Le bloqueur technique est levé. **Ne pas tagger et ne pas fusionner** : la revue
Claude de ce correctif reste le gate demandé.

**Rappels** : la règle polkit supprimée ne se réintroduit pas (auth_admin par la modale DMS, prouvée) ; immutabilité du dépôt (bump systématique, jamais des octets différents sous un même pkgrel) ; jamais `ping` ; correctifs toujours au repo.


## 8. Dossier SP3 pour Codex — l'Assistant (à démarrer APRÈS validation du §7 par la revue Claude)

Le sous-projet 3 est spécifié et planifié :
- **Spec (autorité)** : `docs/superpowers/specs/2026-08-28-assistant-design.md` — trajectoire A→B, contrat `AssistantCore`, catalogue d'outils fermé, sécurité (permissions DMS décoratives — les frontières réelles sont le catalogue + les portes polkit).
- **Plan d'exécution (8 tâches)** : `docs/superpowers/plans/2026-08-28-assistant.md` — Task 1 = spike de terrain `dms-ai-assistant` + mesure du streaming QML (décision A vs B-remontée AVANT d'écrire le moteur).
- **Veille (autorité factuelle, ses §7.2 interdits sont contraignants)** : `docs/veille/2026-08-28-sp3-assistant.md`.

Ordre impératif : finir le §7 (rendu pastilles) → revue Claude → [Claude : fusion + tag v0.2.0] → SP3 Task 1. Mêmes règles que toujours : pousser sur **`assistant`** (créée depuis main post-fusion v0.2.0 — c'est TA branche de travail SP3), CI verte à chaque vague, preuves vm-dev, jamais de tag/fusion.

## 9. Checkpoint vague SP3 T1-4 — verdict Claude et ouverture de la Task 5

**Verdict : « With fixes » — Task 5 autorisée, à condition d'ouvrir par ces deux correctifs** (findings Important de la revue de vague, qui a rejoué 52/52 bats, 69/69 assertions fixtures et 42 attaques local-only — toutes refusées ; les 3 amendements ADR 0003 sont conformes) :

1. **[Important] Body JSON en argv → E2BIG garanti** — `providers/OpenAIAdapter.js:70` et `AnthropicAdapter.js:148` passent le body en un argument ; Linux borne chaque argument à 131 072 octets, or `maxResponseChars` (262 144) + l'historique le dépassent (démontré : 262 266 o → execve échoue). La Task 5 aggrave (résultats d'outils 64 Kio réinjectés). **Correctif : body par stdin (`--data-binary @-`, motif `stdinEnabled` déjà maîtrisé dans KeyringBridge)** — avec un test qui envoie un body > 131 072 o et prouve que curl démarre.
2. **[Important + ruling] `toolCall` n'émet pas `callId`** — `AssistantCore.qml:68` : `signal toolCall(string name, string argsJson)` alors que `toolResult(callId, …)` l'exige : contrat inopérant pour un exécuteur externe, la trajectoire B serait une réécriture. **Ruling contrôleur : la signature devient `toolCall(callId, name, argsJson)`** — la spec §3 est déjà amendée ; adapte le signal, les stubs et les tests.

**Minor à intégrer en T5 au fil de l'eau** (autorisé) : garde-fou sur l'`index` d'outil OpenAI manquant dans des chunks séparés (`OpenAIAdapter.js:128`). **Minors différés au ledger** (post-tag) : contrat UI réel plus large que §3 à documenter (messages/busy/cancel/clear — et ne plus passer l'objet core entier au Panel, `apiKey` accessible) ; `refreshCredentials` sans retry si trousseau occupé ; arithmétique vm-dev §20.2 (170,97 t/s) ; dropdown désynchronisé après refus busy ; timeout ProviderCatalog.

Ensuite, la Task 5 telle que planifiée — rappels : catalogue FERMÉ, refus loggé de tout outil inconnu, contenu système = données étiquetées jamais concaténées au prompt système, `pkexec eschaton-rollback --yes N` seulement après affichage de l'intention, JAMAIS d'auto-approve.

## 10. File d'attente Codex après le SP3 — SP4a Signature & keyring

Le SP4 est découpé (veille + roadmap actée) : **4a Signature** (court, bloquant, indépendant) → 4b Première vraie machine → 4c Première ouverture de session. Dès que le SP3 est clos (ou pendant une attente de revue) : **SP4a**.
- Spec (autorité, sa séquence §3.3 EST l'architecture) : `docs/superpowers/specs/2026-08-28-signature-design.md`
- Plan (6 tâches) : `docs/superpowers/plans/2026-08-28-signature.md`
- ⚠️ Task 1 contient un **point utilisateur obligatoire** (garde de la clé privée : sauvegarde chiffrée + passphrase remises à l'utilisateur AVANT tout secret GitHub) et deux décisions restent **à veto utilisateur** (threat model clé-en-CI, spec §3.1 ; requalification de l'atomique, roadmap Socle §1.2) — les signaler au lancement.
