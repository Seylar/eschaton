# Eschaton — ce qu'il reste à faire

- **Date** : 2026-09-07
- **Pilotage** : Codex reprend le projet à la demande explicite de Seylar le 2026-09-07 (« full autorité, c’est toi qui reprend le sujet »). Les anciennes réservations de revue/fusion à Claude sont remplacées par cette délégation ; les preuves techniques et les décisions de produit non encore tranchées restent à documenter.
- **État de référence distant** : `origin/main` = `1d87d83` (passation #5 fusionnée), version de code **`v0.3.0`** à `3d8feb6`. Le Socle, le Bureau, l'Assistant et l'ISO nominal y sont fusionnés. Attention : le checkout racine `main` est encore à `1b10b85`.
- **Reprise Codex du 2026-09-07** : branche `codex/audit-reprise-2026-09-07`, depuis `handoff` à `32c9e70`, dans `.worktrees/socle`. [Audit global](audits/2026-09-07-projet-global.md), preuves §37 de `tools/vm-dev.md`. Corrections enregistrées localement (`31a90c2`) : 154 tests, core Quickshell et builds ARM verts. **Publication explicitement autorisée : [PR #6](https://github.com/Seylar/eschaton/pull/6). [Première CI](https://github.com/Seylar/eschaton/actions/runs/34132966375) verte sur les deux architectures ; deuxième exécution touchée par un HTTP 504 de GraalVM (§37.9).** Aucune fusion dans `main` ni publication ISO.


### Cap utilisateur confirmé le 2026-09-07

- **Machine personnelle** : MacBook Pro A1990, 15 pouces, GPU Intel + AMD ;
  modèle exact de Radeon et inventaire à relever ([source et limites](veille/2026-09-07-premiere-session.md#complément-du-2026-09-07--machine-et-priorité-confirmées)).
- **Installation visée** : Eschaton uniquement, sans cohabitation macOS.
- **Premier objectif** : usage quotidien personnel satisfaisant ; diffusion
  ensuite, conditionnée aux résultats. Priorité à la connexion sécurisée,
  au démarrage T2, au réseau/audio/reprise et au couple mise à jour/rollback.
- **Cloisonnement T2 maintenu par décision de pilotage** : ADR 0004 accepté
  pour ce dogfooding ; cela ne promet pas de support public des Mac T2.

---

## Priorité active — VM et abonnements IA

Retour pilote : lenteur générale, IA centrale bancale, rendu visuel inachevé.
Les fournisseurs attendus sont les **abonnements Codex et Claude**, Codex en
premier. Le transport à clés API existant ne satisfait pas ce besoin.

- [x] Ajouter le runtime Codex officiel et un parcours ChatGPT par code au panneau.
- [x] Construire et installer dans le clone les paquets corrigés du bureau,
  de l'assistant et des mises à jour ; vérifier le dialogue QML ↔ Codex réel.
- [ ] Finaliser la connexion personnelle et éprouver les vraies réponses,
  les erreurs de quota/réseau, l'annulation et les actions système.
- [ ] Résoudre le rendu de la VM : le test VirGL échoue encore sans le forçage
  logiciel. Ne pas annoncer la fluidité comme acquise.
- [ ] Vérifier l'entrée souris/clavier avec le pilote, puis terminer la finition
  graphique et le parcours d'utilisation quotidienne.
- [ ] Intégrer l'abonnement Claude par un mécanisme officiellement supporté.

Preuves : `tools/vm-dev.md` §39. Branche :
`codex/vm-stabilisation-2026-09-07`. Aucun déploiement sur le Mac à ce stade.

---

## 0. Conventions non négociables

Elles ont toutes été payées par un incident réel. Ne les renégocie pas en cours de route.

1. **Travail sur branche et revue par PR.** Aucun push direct sur `main`. Le pilotage des revues et fusions est repris par Codex sur délégation explicite de Seylar ; une fusion exige une revue du diff et la CI verte. Un tag ou une sortie publique exige aussi que les conditions de publication soient remplies.
2. **CI verte à chaque vague** avant de rendre la main.
3. **`pkgrel` bumpé dès qu'un octet du paquet change** — même pour un commentaire. Le dépôt est immuable : jamais deux contenus différents sous un même nom.
4. **Preuves dans `tools/vm-dev.md`**, numérotées, avec les sorties réelles. Ce qui n'a pas été exécuté est **annoncé comme non exécuté**. N'invente jamais une sortie.
5. **ADR 0002** : toute spec s'ouvre par une passe de veille datée, et **tout constat de terrain qui contredit un document remonte dans ce document**. Mais vérifie contre la **bonne base** : une « correction » mesurée sur un `main` périmé a déjà produit deux affirmations fausses (voir §2, I-1).
6. **Jamais d'auto-approbation.** Une action privilégiée = une authentification humaine. Pas de `--noconfirm` dans un chemin de mise à jour. Pas de second chemin privilégié.
7. **Le contenu système est hostile par construction** (descriptions de snapshots, noms de paquets, journaux) : données étiquetées, jamais concaténées à un prompt système, jamais interprétées comme une approbation.
8. **Pas de migrations.** Les hooks alpm idempotents sont la seule exception admise.
9. **Paquets `arch=(any)`.** `repo/build-repo` construit tous les PKGBUILD dans les **deux** jobs d'architecture : un `arch=(x86_64)` casserait le job aarch64.
10. **Une promesse fausse sur une opération irréversible est pire que pas de promesse.** Cette règle a coûté deux défauts critiques (un installeur qui effaçait avant de valider, un message « rien n'a été écrit » après effacement). En cas de doute, retombe sur le **pire cas**.

---

## 1. Branches

| Branche | État | À faire |
|---|---|---|
| `main` | Socle + Bureau + Assistant + ISO, tag `v0.3.0` | — |
| `assistant` | **fusionnée** (PR #4) | supprimable |
| `iso` | **fusionnée** (PR #3) | supprimable |
| `iso-t2` | Ancienne base T2, reprise dans `codex/t2-reprise-2026-09-07` | voir §2 |

---

## 2. En cours — le variant ISO pour Mac T2

Branche `iso-t2`, tête **`8b982ab`**. Le variant existe, se construit (1,18 Gio) et a passé une revue qui l'a jugé solide sur le fond : cloisonnement du dépôt tiers à double garde, delta de paquets sans fourche du profil, garde d'épinglage du noyau qui tranche sur le nom exact et échoue fermée, réserves honnêtes.

Les corrections interrompues ont été reprises dans
[PR #7](https://github.com/Seylar/eschaton/pull/7), branche
`codex/t2-reprise-2026-09-07` (`.worktrees/t2-reprise`), commit `0b23a23`, puis
réunies localement avec la vague générale. Le worktree original
`.claude/worktrees/agent-a186b0e417ae099d8` est intact. Le chemin T2, les gardes
sur erreurs de lecture et `pkgrel=2` sont écrits ; **94 tests ciblés et 206 tests
sur la branche T2 seule passent**. Le contenu réuni passe **214 tests locaux** ; sa validation CI et la
preuve matérielle restent distinctes. Preuves : `tools/vm-dev.md` §36.9 et §37.9.

- **C-1 — ✅ RÉGLÉ** (`8b982ab`). La branche, écrite avant le commit `92cbf0e` de `main`, réécrivait le même bloc de `.github/workflows/iso.yml` et **supprimait `--draft`** — sans lui, poser un tag publie l'ISO en téléchargement public, ce que `iso/PROVENANCE.md` et `iso/README.md` interdisent tant que la licence et les choix de média de développement ne sont pas tranchés. La fusion de `main` garde bien **les deux** protections : l'énumération sans joker et l'étape « Refuser tout artefact T2 » de la branche, plus `--draft` et son commentaire. *Vérifié : `--draft` est présent, l'étape s'appelle « GitHub Release (brouillon) ».*
- **C-2 — CORRIGÉ dans la reprise `0b23a23`, démarrage matériel non prouvé.** Description de la panne dans l’ancien commit `8b982ab` : Un système installé depuis l'ISO T2 **ne peut pas démarrer** : `linux` ne voit pas le NVMe piloté par la puce T2, et n'a pas `apple-bce`. `grep -rn 'linux-t2' installer/ iso/eschaton/` ne renvoie rien — le delta T2 ne touche que l'environnement **live**, l'installeur n'a aucune conscience du variant. Aggravant : le dépôt tiers n'étant pas dans le `pacman.conf` du live, `pacstrap` ne *pourrait* pas tirer `linux-t2` même si on le lui demandait. Et `iso/README.md` prescrit « après le premier démarrage, `pacman -S eschaton-t2` » — une étape qui présuppose un démarrage impossible.

  **Décision de conception déjà tranchée** (l'[ADR 0004](decisions/0004-perimetre-materiel-mac-t2.md) §4.2 l'anticipait) : sur une machine T2, le dépôt `arch-mact2` **doit** être configuré sur le système cible — sinon il n'y a ni noyau qui démarre, ni mise à jour de ce noyau. Le cloisonnement protège l'ISO nominal et les paquets du projet ; il n'a jamais voulu dire qu'une machine T2 vivrait sans son dépôt. Donc, sur le chemin T2 **et lui seul** : l'installeur pose `linux-t2` + `apple-bcm-firmware`, configure `arch-mact2` sur la cible **en affichant le compromis à l'utilisateur** (dépôt tiers, non signé, mainteneur unique), et installe `eschaton-t2` **pendant** l'installation. **Le chemin nominal ne change en rien** — c'est l'invariant, à verrouiller par un test. Comment le chemin T2 se signale à l'installeur est à concevoir : **préfère l'explicite au deviné**, et échoue fermé (dans le doute, le chemin nominal). Corrige le mode opératoire de `iso/README.md` en conséquence.

  ⚠️ **Ce correctif ne sera pas prouvable sans la vraie machine.** Livre le code et **écris la réserve** ; ne prétends rien avoir vérifié au démarrage.
- **I-1** — deux « corrections » de `tools/vm-dev.md` §20.1 étaient fausses (le compte de tests et la numérotation de sections) : mesurées contre une base périmée, puis rationalisées. Seule celle sur `apple-bce` était juste.
- **I-2** — collision de numérotation dans `vm-dev.md` (§20 occupé par `main`) : la section T2 devient **§36**.
- **I-3** — l'échappatoire `pacman -Rns eschaton-t2` que le script propose est bloquée par son propre hook quand `linux-t2` est une dépendance.
- **I-4** — commentaire « écart à ratifier » périmé dans `packages/eschaton-t2/PKGBUILD` : `main` a ratifié.

**Ensuite** : CI de la branche réunie, puis décision de fusion par le pilote du projet. **Rien de ce qui touche la vraie machine n'est faisable sans elle** — voir §4.

---

## 3. Chantiers ouverts, par ordre

### 3.0 PRIORITÉ — qualifier la VM avant toute installation sur le Mac

Retour de Seylar le 2026-09-07 : la VM reste « vraiment bancale ». Le prochain
livrable est donc une **VM fonctionnelle et réactive**, installée avec les
corrections actuelles, puis réellement utilisée. Les PR vertes ne ferment pas
ce point. Voir le [plan de stabilisation et ses critères de passage](superpowers/plans/2026-09-07-vm-dogfooding.md).

Ordre : diagnostic du banc et mise à niveau effective, correction des parcours,
connexion/trousseau/verrouillage, audio/réseau, mise à jour/rollback, prise en
main. Le travail T2 est conservé ; la qualification du vrai Mac vient ensuite.


### 3.1 SP4c — Première ouverture de session *(le plus gros morceau disponible)*

C'est le dernier sous-projet entièrement débloqué. Il solde trois dettes ouvertes depuis le Socle :

- **greeter authentifié** et **fin de l'auto-login** (aujourd'hui : session ouverte sans mot de passe, nom d'utilisateur **en dur** dans `greetd.toml`) ;
- **PAM / trousseau** ([ADR 0003](decisions/0003-service-secrets-assistant.md) §8) : aucun déverrouillage PAM n'est intégré. Un trousseau créé avec un mot de passe vide conserve les secrets **en clair au repos** ; un trousseau protégé demande un déverrouillage manuel. L'auto-login ne prouve donc pas, à lui seul, que tous les trousseaux sont en clair ;
- **verrouillage de session**.

La [veille du 2026-09-07](veille/2026-09-07-premiere-session.md) et une [proposition de spec](superpowers/specs/2026-09-07-premiere-session-design.md) sont maintenant rédigées. ReGreet + Cage est le premier spike proposé ; les deux paquets existent sur les deux architectures. **Spec non validée : revue prévue avant implémentation PAM/greeter.** Aucun auto-login ni trousseau existant n'a été modifié.

### 3.2 SP4a — Signature du dépôt *(avant diffusion à des tiers ; §4 d'abord)*

[Spec](superpowers/specs/2026-08-28-signature-design.md) et [plan](superpowers/plans/2026-08-28-signature.md) existent et sont à jour. Le dépôt sert des paquets **non signés** depuis le premier jour — c'est un prérequis bloquant de toute distribution à des tiers.

⚠️ **La Task 1 contient un point utilisateur obligatoire** et deux vetos en attente : ne lance rien avant §4.

### 3.3 Première session lente : correctif écrit, preuve graphique à rejouer

Le script attend désormais un objet JSON lisible pendant 90 s ; le service retente dans la même session, au plus trois démarrages par fenêtre de 30 min, avec délai maximal de 5 min par essai. Tests du programme complet avec apparition tardive et reprise après échec passés ; unité acceptée par `systemd-analyze` dans la VM. **La première session graphique lente avec ce nouveau paquet reste à rejouer** (§37), avant de fermer ce point.

### 3.4 La preuve dynamique jamais faite

**Rollback à travers un changement de noyau.** Le protocole est écrit (`tools/vm-dev.md` §9.10) et attend la première mise à jour de noyau ALARM. C'est la seule preuve du Socle qui n'a jamais pu être jouée.

---

## 4. Bloqué sur l'utilisateur — NE PAS DÉMARRER

Aucun de ces points ne s'ouvre sans une réponse explicite de Seylar. Le [registre des arbitrages](REGISTRE-ARBITRAGES.md) les détaille avec leur coût de retour arrière.

### Décisions qui bloquent du travail

1. **Garde de la clé de signature** (SP4a, Task 1) : la sauvegarde chiffrée et sa passphrase doivent être **remises à l'utilisateur avant** que la clé privée n'entre dans un secret GitHub. Et le **threat model** de la spec §3.1 (clé privée en CI = un compromis du compte permet de signer des paquets malveillants) est à veto.
2. **Licence de l'ISO** : `iso/eschaton/` dérive de `configs/releng` d'archiso, **GPL-3.0-or-later**, dans un dépôt MIT. Inventaire exact dans `iso/PROVENANCE.md`. À trancher **avant** toute mise en ligne étiquetée — trois issues possibles : réécrire les fichiers empruntés, donner à `iso/` sa propre licence, ou passer le dépôt en GPL.
3. **Publication de l'ISO** : elle est en **brouillon** depuis le 2026-08-30. Retirer `--draft` est une décision de produit, jamais un nettoyage.
4. **ADR 0004 : débloqué pour le dogfooding le 2026-09-07.** A1990/15 pouces et Eschaton seul confirmés ; cloisonnement maintenu par le pilote du projet. Restent l’inventaire GPU exact et les preuves matérielles, pas une nouvelle question sur macOS.
5. **Requalification du mot « atomique »** dans la feuille de route du Socle (§1.2).

### Arbitrages de produit en attente

- **R1** — l'assistant est limité à **trois outils** (état, mise à jour, rollback) là où le brief demandait un assistant omniprésent. *Élargir coûte une tâche par outil.*
- **R2** — le rollback exige un mot de passe. *Trivial à défaire : une règle polkit.*
- **R3** — l'assistant est **désarmé** après avoir lu des données système ; agir exige un second message. *C'est le seul rempart prouvé contre l'injection : recommandation de garder.*
- **R4** — le **tactile** a été déclassé sans arbitrage explicite et n'existe nulle part dans le code, alors que le brief disait « tactile/souris ». *Coûteux à rattraper.*
- **Le nouveau flux de mise à jour** : livré et prouvé, mais **le veto O1 n'est levé que par l'utilisateur**. Deux compromis à accepter : annuler coûte une seconde authentification, et une mise à jour qui exige une décision humaine s'arrête au lieu de choisir.

### Bloqué par le matériel

- **Task 5 du plan ISO** — installation réelle sur le MacBook Pro 2019. Mode opératoire pas à pas dans `iso/README.md`. **Rien n'a jamais été démarré : une puce T2 ne se simule pas.** Tout le DoD §4 de la spec ISO reste ouvert pour le variant.
- **SP5 Gaming** — aucun banc possible en VM (pas de multilib sur ALARM, zéro `lib32`). Veille faite (`docs/veille/2026-08-28-sp5-gaming.md`) : la valeur différenciante est de **rendre la pile graphique lisible dans le plugin rollback**, pas le méta-paquet gaming, déjà servi par la concurrence. **Multilib doit être activé à l'installation** — c'est une exigence à porter dans l'installeur.

---

## 5. Dette et mineurs différés

Aucun ne bloque. Ils sont consignés dans les ledgers `.superpowers/sdd/*/progress.md`.

**Assistant** : contrat UI plus large que la spec à documenter · le core entier est passé au panneau (la clé d'API y est accessible) · `refreshCredentials` sans retry si le trousseau est occupé · dropdown désynchronisé après un refus · timeout du `ProviderCatalog`. **Corrigé dans la reprise Codex** : stubs désactivés par défaut ; Stop ne relance plus le streaming après les résultats d'outils (tests Node et harnais Quickshell en VM passés).

**Mise à jour** : **corrigé dans la reprise Codex** : le message d'annulation tardive distingue avec/sans snapshot ; les résultats inconnus conservent la présentation d'attention et le journal compact (expressions QML testées). Restent : `interrompu` ne consulte pas le point de non-retour · tout membre de `wheel` peut annuler la transaction d'un autre · l'assistant peut faire apparaître une modale de mise à jour sans clic de confirmation préalable, contrairement au rollback (fatigue d'authentification, borne tenue).

**ISO** : le média s'identifie encore **« Arch Linux »** et non « Eschaton » — plus profond qu'il n'y paraît, réserve écrite dans `iso/README.md` · **corrigé dans la reprise T2** : les erreurs de `grep` sont propagées et la garde d'après-construction s'exerce sur les deux chemins (94 tests ciblés passés) · aucune confirmation interactive avant `sgdisk --zap-all` : la garde `--disk` est la seule protection.

**Couverture** : les tests QML historiques restent surtout statiques. La reprise ajoute des tests Node qui exécutent les fonctions/expressions de production pour Stop et les verdicts, plus un test Quickshell réel de Stop en VM. Les bindings, le rendu et le reste des scénarios exigent toujours les harnais VM. Le transfert série teste désormais aussi les écritures partielles et un pseudo-terminal réel.

---

## 6. Où sont les documents

| Quoi | Où |
|---|---|
| Le journal de terrain, toutes les preuves | `tools/vm-dev.md` (preuves T2 §36 ; reprise générale §37) |
| Specs | `docs/superpowers/specs/` |
| Plans d'exécution | `docs/superpowers/plans/` |
| Décisions d'architecture | `docs/decisions/` (0001 à 0004) |
| Veilles datées | `docs/veille/` |
| Bilans d'exécution (rulings) | `docs/superpowers/bilans/` |
| Arbitrages pris sans l'utilisateur | `docs/REGISTRE-ARBITRAGES.md` |
| Ledgers de gate (non versionnés) | `.superpowers/sdd/*/progress.md` |
