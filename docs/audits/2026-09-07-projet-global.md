# Audit de reprise Eschaton, 2026-09-07

## Verdict

Le projet a un socle de prototype sérieux : packaging, rollback et séparation
des privilèges ont été travaillés et testés. Il n'est pas prêt pour un usage
grand public. La connexion sans mot de passe, le stockage des secrets des
comptes existants, la distribution non signée et l'installation matérielle non
prouvée sont plus importants que l'ajout de fonctions ou d'habillage.

Le problème de pilotage est concret : la racine est sur un ancien `main`
`1b10b85`, tandis que le code repris vit dans `.worktrees/socle`. Les références
distantes ont été actualisées ; la branche de correction part de `32c9e70`
(handoff). Aucun travail de la racine ou des autres worktrees n'a été remplacé.

## Périmètre examiné

Lecture du document de reprise, du produit et des décisions ; inspection des
chemins installateur/ISO, du packaging et de la CI, du provisioning de session,
du core/exécuteur assistant et du panneau de mise à jour. Exécution des tests
existants et de nouvelles régressions. Lecture des modifications T2 non
commitées et exécution de leurs tests ciblés. Ce n'est ni une preuve matérielle,
ni une revue exhaustive de chaque ligne de chaque dépendance amont.

## Corrections de cette branche

| Défaut | Correction | Preuve |
|---|---|---|
| Première session sans pastilles si settings arrive tard | Attente d'un objet JSON complet jusqu'à 90 s ; service relancé sur échec, délai et fréquence bornés, arrêt avec la session | Programme exécuté avec DMS simulé : création à 65 ticks, fichier incomplet, absence, refus de recomposition, idempotence |
| Stop pendant un outil relance le fournisseur | L'intention d'arrêt couvre les outils en attente ; leurs résultats sont conservés, aucune nouvelle requête ne part | Fonctions QML de production exécutées sous Node ; harnais Qt fourni |
| Stubs actifs par défaut dans le core | Stubs désactivés par défaut ; activation de test explicite | Test du défaut livré |
| Verdict inconnu dans le panneau traité comme un état ordinaire | Présentation compacte et signal d'attention conservés pour tout verdict non explicitement rassurant | Expressions QML réellement exécutées |
| Annulation tardive promet une restauration absente | Message conditionné par le point de retour effectivement disponible | Cas avec/sans snapshot exécutés |
| Console série rejoue une commande après saturation | Offset conservé après écriture partielle/EAGAIN ; lecture de l'écho entre les écritures ; erreur fatale propagée | Tests d'écritures partielles et de transfert sur pseudo-terminal |
| Guide utilisateur périmé | Nouveau flux polkit, exception binds-user.lua, portée réelle de l'assistant et du banc ARM | Comparaison avec les chemins de production |

`pkgrel` : desktop-config 10 → 11 ; assistant 10 → 11 ; update 15 → 16.
Les outils/tests/documents ne sont pas des octets de paquet livré.

## Re-revue ciblée T2

État inspecté : `origin/iso-t2=8b982ab`, plus les modifications préexistantes
dans `.claude/worktrees/agent-a186b0e417ae099d8`. Le rapport sépare les commits
publiés du travail local pour éviter de déclarer livré un correctif absent.

| Point | Constat au 2026-09-07 |
|---|---|
| C-1 | Corrigé dans le commit : `--draft`, commentaire, énumération explicite et garde anti-artefacts T2 présents |
| C-2 | Absent du commit, implémentation locale présente : variant explicite ou marqueur du média, noyau T2, firmware, dépôt live/cible, garde dès pacstrap |
| I-1 | Le §20.1 conserve les preuves Assistant ; les corrections de base périmée n'y ont pas été réintroduites |
| I-2 | La section T2 est bien §36 |
| I-3 | Le travail local propose `pacman -Rn eschaton-t2`, qui conserve les dépendances |
| I-4 | Le commentaire local reconnaît l'ADR corrigé |

Les 84 tests ciblés installer + variant passent sur ce travail local.
**Cela ne suffit pas à le rendre fusionnable** : `eschaton-t2` contient des
changements mais garde `pkgrel=1`. Il faut terminer la vague, relever le
pkgrel, enregistrer les preuves et la soumettre à la revue prévue.

Deux réserves de code encore visibles dans ce worktree :

- `fuite_depot_tiers` neutralise encore les erreurs de grep par `|| true` : une
  lecture impossible n'est pas une preuve d'absence de dépôt tiers.
- `lire_marqueur_variant` rend succès/vide si le marqueur n'est pas lisible ;
  `resoudre_variante` assimile le vide au nominal. Le test intitulé « marqueur
  illisible » exerce un contenu inconnu, pas l'erreur d'accès. Tester fichier
  absent, permissions refusées, lecture en erreur et fichier vide séparément.

Aucun fichier de ce worktree n'a été modifié par cette reprise. Le vrai
MacBook et son choix de GPU restent indispensables à la preuve de démarrage.

## Priorités suivantes

1. Finir et revoir la vague T2 ci-dessus avant toute tentative d'installation.
2. Faire revoir la [proposition SP4c](../superpowers/specs/2026-09-07-premiere-session-design.md),
   issue de la [veille datée](../veille/2026-09-07-premiere-session.md). Le point
   délicat est autant l'adoption des anciens trousseaux et `.pacnew` que le greeter.
3. Rejouer les plugins sous DMS 1.6 : publié des deux côtés, alors que la VM
   de preuve est encore en 1.5.3. Les tests statiques ne garantissent pas cette
   compatibilité.
4. Signature/clé, licence de l'ISO et publication : arbitrages explicites
   toujours ouverts. Une CI verte ne les remplace pas.
5. Rollback à travers un changement de noyau, installation réelle, GPU et gaming :
   maintenir les réserves tant que les protocoles n'ont pas été exécutés.

## Dette conservée

Timeout du ProviderCatalog, retry du trousseau, resynchronisation du dropdown,
frontière de visibilité de la clé en mémoire, annulation d'une transaction par
un autre membre de wheel et point de non-retour du résultat `interrompu` restent
à traiter. Aucun agrandissement du catalogue d'outils ni assouplissement polkit.

`DESIGN.md` manque ; l'extraction du vocabulaire DMS vers ce document serait
utile avant une refonte, sans être nécessaire aux corrections fonctionnelles
actuelles. Les composants DMS existants restent la référence visuelle.

Les sorties et limites exactes de validation sont consignées dans
[`tools/vm-dev.md`, §37](../../tools/vm-dev.md#37-reprise-codex--audit-et-corrections-2026-09-07).

## Livraison

Corrections enregistrées dans `31a90c2`. Après un premier refus automatique,
Seylar a explicitement autorisé la publication, puis confié la reprise du
pilotage à Codex. La [PR #6](https://github.com/Seylar/eschaton/pull/6) est
ouverte en brouillon ; la [CI distante](https://github.com/Seylar/eschaton/actions/runs/34132966375)
est en cours. Les résultats locaux sont détaillés au §37 du journal.
Cette délégation remplace la réservation des revues/fusions à Claude dans
l’ancien document de passation ; elle ne constitue pas une preuve des essais
matériels ni une décision technique sur les arbitrages encore ouverts.
