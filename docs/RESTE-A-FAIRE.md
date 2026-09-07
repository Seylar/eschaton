# Eschaton — ce qu'il reste à faire

- **Date** : 2026-09-07
- **Destinataire** : Codex (exécution). Les gates de revue, les rulings, les tags et les fusions restent à Claude.
- **État de référence** : `main` = `3d8feb6`, tag **`v0.3.0`** posé. Le Socle, le Bureau, l'Assistant et l'ISO nominal y sont fusionnés.

---

## 0. Conventions non négociables

Elles ont toutes été payées par un incident réel. Ne les renégocie pas en cours de route.

1. **Jamais de push sur `main`, jamais de tag, jamais de fusion.** Tu travailles sur une branche, tu notifies, la fusion est une cérémonie Claude.
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
| `iso-t2` | **en cours de correction**, non fusionnée | voir §2 |

---

## 2. En cours — le variant ISO pour Mac T2

Branche `iso-t2`. Le variant existe, se construit (1,18 Gio) et a passé une revue qui l'a jugé solide sur le fond : cloisonnement du dépôt tiers à double garde, delta de paquets sans fourche du profil, garde d'épinglage du noyau qui tranche sur le nom exact et échoue fermée, réserves honnêtes. **Une vague de correction est en vol au moment où ce document est écrit.** Vérifie son état avant de reprendre.

Ce qu'elle doit avoir réglé — **revérifie chaque point, ne fais pas confiance au rapport** :

- **C-1 — `--draft` ne doit pas être perdu à la fusion.** La branche a été écrite avant le commit `92cbf0e` de `main` et réécrit le même bloc de `.github/workflows/iso.yml`, supprimant `--draft`. Sans lui, **poser un tag publie l'ISO en téléchargement public** — ce que `iso/PROVENANCE.md` et `iso/README.md` interdisent tant que la licence et les choix de média de développement ne sont pas tranchés. La résolution doit garder **les deux** apports : `--draft` et son commentaire de `main`, plus l'énumération sans joker et l'étape « Refuser tout artefact T2 » de la branche.
- **C-2 — l'installeur posait le noyau amont sur la cible.** Un système installé depuis l'ISO T2 ne pouvait pas démarrer : `linux` ne voit pas le NVMe piloté par la puce T2. Décision tranchée : sur le chemin T2 **et lui seul**, l'installeur pose `linux-t2` + `apple-bcm-firmware`, configure le dépôt `arch-mact2` **sur la cible** (ADR 0004 §4.2 l'anticipait), affiche le compromis à l'utilisateur, et installe `eschaton-t2` pendant l'installation. **Le chemin nominal ne change en rien**, et un test doit le verrouiller.
- **I-1** — deux « corrections » de `tools/vm-dev.md` §20.1 étaient fausses (le compte de tests et la numérotation de sections) : mesurées contre une base périmée, puis rationalisées. Seule celle sur `apple-bce` était juste.
- **I-2** — collision de numérotation dans `vm-dev.md` (§20 occupé par `main`) : la section T2 devient **§36**.
- **I-3** — l'échappatoire `pacman -Rns eschaton-t2` que le script propose est bloquée par son propre hook quand `linux-t2` est une dépendance.
- **I-4** — commentaire « écart à ratifier » périmé dans `packages/eschaton-t2/PKGBUILD` : `main` a ratifié.

**Ensuite** : re-revue scopée, puis fusion (Claude). **Rien de ce qui touche la vraie machine n'est faisable sans elle** — voir §4.

---

## 3. Chantiers ouverts, par ordre

### 3.1 SP4c — Première ouverture de session *(le plus gros morceau disponible)*

C'est le dernier sous-projet entièrement débloqué. Il solde trois dettes ouvertes depuis le Socle :

- **greeter authentifié** et **fin de l'auto-login** (aujourd'hui : session ouverte sans mot de passe, nom d'utilisateur **en dur** dans `greetd.toml`) ;
- **PAM / trousseau** ([ADR 0003](decisions/0003-service-secrets-assistant.md) §8) : aujourd'hui le trousseau est **en clair au repos** parce que rien ne le déverrouille à l'ouverture de session. C'est affiché à l'utilisateur, mais ça reste vrai ;
- **verrouillage de session**.

Il n'existe **ni veille, ni spec, ni plan**. Commence par la veille datée (ADR 0002), propose la spec, attends le gate.

### 3.2 SP4a — Signature du dépôt *(spec et plan prêts, mais §4 d'abord)*

[Spec](superpowers/specs/2026-08-28-signature-design.md) et [plan](superpowers/plans/2026-08-28-signature.md) existent et sont à jour. Le dépôt sert des paquets **non signés** depuis le premier jour — c'est un prérequis bloquant de toute distribution à des tiers.

⚠️ **La Task 1 contient un point utilisateur obligatoire** et deux vetos en attente : ne lance rien avant §4.

### 3.3 Le défaut du Bureau trouvé pendant l'ISO, jamais corrigé

Sur une machine lente, `eschaton-dms-provision` abandonne à la première session parce que le bureau n'a pas encore écrit sa configuration → **la première session s'ouvre sans les pastilles**. La reprise fonctionne et a été prouvée, mais c'est la toute première impression du produit qui est ratée. Trouvé en installant depuis le média réel, hors périmètre de la vague d'alors.

### 3.4 La preuve dynamique jamais faite

**Rollback à travers un changement de noyau.** Le protocole est écrit (`tools/vm-dev.md` §9.10) et attend la première mise à jour de noyau ALARM. C'est la seule preuve du Socle qui n'a jamais pu être jouée.

---

## 4. Bloqué sur l'utilisateur — NE PAS DÉMARRER

Aucun de ces points ne s'ouvre sans une réponse explicite de Seylar. Le [registre des arbitrages](REGISTRE-ARBITRAGES.md) les détaille avec leur coût de retour arrière.

### Décisions qui bloquent du travail

1. **Garde de la clé de signature** (SP4a, Task 1) : la sauvegarde chiffrée et sa passphrase doivent être **remises à l'utilisateur avant** que la clé privée n'entre dans un secret GitHub. Et le **threat model** de la spec §3.1 (clé privée en CI = un compromis du compte permet de signer des paquets malveillants) est à veto.
2. **Licence de l'ISO** : `iso/eschaton/` dérive de `configs/releng` d'archiso, **GPL-3.0-or-later**, dans un dépôt MIT. Inventaire exact dans `iso/PROVENANCE.md`. À trancher **avant** toute mise en ligne étiquetée — trois issues possibles : réécrire les fichiers empruntés, donner à `iso/` sa propre licence, ou passer le dépôt en GPL.
3. **Publication de l'ISO** : elle est en **brouillon** depuis le 2026-08-30. Retirer `--draft` est une décision de produit, jamais un nettoyage.
4. **ADR 0004** (périmètre T2) : toujours en statut **proposé**. Trois points ouverts — taille d'écran du MacBook (le 15/16 pouces ajoute un GPU AMD à gérer en hybride), sort de macOS (effacer est recommandé : l'ESP d'Apple fait 300 Mio contre 4 Gio exigés), et ratification du principe « toléré mais cloisonné ».
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

**Assistant** : contrat UI plus large que la spec à documenter · le core entier est passé au panneau (la clé d'API y est accessible) · `refreshCredentials` sans retry si le trousseau est occupé · dropdown désynchronisé après un refus · timeout du `ProviderCatalog` · `stubTools` à `true` par défaut (le démon force `false`, mais l'inverse serait plus sûr) · le bouton stop relance un tour de streaming.

**Mise à jour** : `annule-trop-tard` peut être annoncé **sans porte de sortie** quand aucun snapshot n'a été calculé (le message et l'offre se contredisent) · `resultatEstUnEchec` est restée une liste d'**autorisation** alors que `restaurationUtile` a été renversée en liste d'exclusion · `interrompu` ne consulte pas le point de non-retour · tout membre de `wheel` peut annuler la transaction d'un autre · l'assistant peut faire apparaître une modale de mise à jour sans clic de confirmation préalable, contrairement au rollback (fatigue d'authentification, borne tenue).

**ISO** : le média s'identifie encore **« Arch Linux »** et non « Eschaton » — plus profond qu'il n'y paraît, réserve écrite dans `iso/README.md` · `fuite_depot_tiers` neutralise les erreurs de `grep` (une arborescence illisible se lirait « aucune fuite ») · la garde d'après-construction ne s'exerce que sur le variant · aucune confirmation interactive avant `sgdisk --zap-all` : la garde `--disk` est la seule protection.

**Couverture** : les tests QML sont des greps de chaînes — la logique n'est réellement exécutée qu'en VM par les harnais. C'est un compromis assumé (QML inexécutable en CI GitHub), pas un oubli.

---

## 6. Où sont les documents

| Quoi | Où |
|---|---|
| Le journal de terrain, toutes les preuves | `tools/vm-dev.md` (36 sections) |
| Specs | `docs/superpowers/specs/` |
| Plans d'exécution | `docs/superpowers/plans/` |
| Décisions d'architecture | `docs/decisions/` (0001 à 0004) |
| Veilles datées | `docs/veille/` |
| Bilans d'exécution (rulings) | `docs/superpowers/bilans/` |
| Arbitrages pris sans l'utilisateur | `docs/REGISTRE-ARBITRAGES.md` |
| Ledgers de gate (non versionnés) | `.superpowers/sdd/*/progress.md` |
