# Eschaton — Spec de conception : Signature du dépôt & keyring (SP4a)

- **Date** : 2026-08-28
- **Statut** : rédigée sur passe de veille datée ([rapport](../../veille/2026-08-28-sp4-grand-public.md) §3) — publiée pour relecture ; exécution Codex (après SP3 ou en créneau libre), gates Claude
- **Sous-projet** : 4a/5 — le SP4 est découpé en trois (décision issue de la veille, §« découpage ») : **4a Signature & keyring** (ce document — court, bloquant, sans dépendance), 4b « Première vraie machine » (ISO/archinstall/LUKS/matériel), 4c « Première ouverture de session » (greeter, fin de l'autologin, PAM/trousseau, onboarding)
- **Amont** : [Spec du Socle](2026-08-27-socle-design.md) §5.3 (la dette : `SigLevel = Optional TrustAll`, « obligatoire avant toute distribution à des tiers »)

---

## 1. Position

Le dépôt `[eschaton]` sert des paquets **non signés** depuis le premier jour — dette explicite du Socle, prérequis bloquant de toute distribution. La veille (§3) fournit un patron public et daté (Omarchy, 2026-08-24) : bascule `Optional TrustAll` → **`Required DatabaseOptional`** avec un amorçage auto-réparant qui nomme le piège central — *exiger des signatures avec une clé pas encore fiable ferait échouer la transaction même qui installerait la confiance*. Eschaton reprend le patron en le pliant à sa doctrine : **pas de système de migrations** (spec Socle §3) — l'amorçage passe par un paquet keyring et son hook alpm versionné et idempotent, l'exception prévue.

## 2. Périmètre

**Livrable** : les paquets du dépôt `[eschaton]` sont signés ; les clients exigent la signature (`Required DatabaseOptional` sur `[eschaton]` seul — les dépôts Arch gardent leur politique) ; la confiance s'amorce proprement sur une installation neuve COMME sur les installations existantes (nos deux VM) ; un paquet altéré est **refusé** — prouvé.

**Non-buts 4a** : signature de la base de données (DatabaseOptional — cohérent avec le patron éprouvé ; la base est servie en HTTPS par Pages), infra de clés multi-mainteneurs, HSM, reproducibilité des builds, signature des ISO (4b).

## 3. Architecture

### 3.1 La clé et sa garde

- **Une clé de signature de dépôt dédiée** (« Eschaton Package Signing Key <pkg@eschaton> », Ed25519), générée **localement** sur le Mac (jamais en CI), sauvegardée hors ligne (export chiffré — consigne à l'utilisateur), **la privée entre dans un secret GitHub d'environnement** (`github-pages`, protégé — mêmes protections que le déploiement), la publique est packagée.
- **Threat model écrit et assumé** (décision à veto utilisateur) : la clé privée vit dans les secrets GitHub → un compromis du workflow ou du compte GitHub permet de signer des paquets malveillants. Atténuations : environnement protégé (politiques de branche déjà en place), workflow modifiable uniquement par commit revu sur main, `pacman` vérifie ce que Pages sert (l'hébergement seul ne suffit plus à empoisonner), **procédure de rotation documentée** (révocation = nouveau keyring pkgrel + nouvelle clé + re-signature du dépôt). L'alternative — signer localement à chaque publication — casserait le flux CI→Pages ; rejetée pour v1, réévaluable.

### 3.2 Le paquet `eschaton-keyring`

- `arch=(any)`, motif Socle. Livre la clé publique sous `/usr/share/pacman/keyrings/` (`eschaton.gpg`, `eschaton-trusted`, `eschaton-revoked` — le format que `pacman-key --populate` consomme).
- **Hook alpm** post-install/upgrade, idempotent : `pacman-key --populate eschaton` (avec garde d'existence du keyring pacman initialisé) — l'exception versionnée de la doctrine, même motif que le hook preset du Bureau.
- Entre dans les `depends` d'`eschaton-base` (bump) : toute machine existante le reçoit au prochain `-Syu` **pendant que le dépôt est encore en `Optional`** — c'est la première marche de l'amorçage.

### 3.3 La séquence d'amorçage (l'ordre est l'architecture)

1. **Marche 1 — la confiance s'installe sans être exigée** : publier `eschaton-keyring` + bump d'`eschaton-base` ; le dépôt signe désormais ses paquets en CI (`makepkg` puis `gpg --detach-sign` par paquet dans `build-repo`, `repo-add` avec les `.sig`) mais les clients restent `Optional` — les signatures sont servies, pas exigées.
2. **Marche 2 — l'exigence se referme** : une fois la marche 1 publiée et vérifiée sur les deux VM (`pacman-key --list-keys` montre la clé, `-Syu` propre), bump d'`eschaton-base` qui change `eschaton-repo.conf` → `SigLevel = Required DatabaseOptional`. Un client qui aurait sauté la marche 1 reste réparable : le hook du keyring (déjà dans ses dépendances) s'exécute dans la même transaction que le flip — à PROUVER en VM (le cas « saut de version »).
3. **Installation neuve** : `eschaton-install` ajoute `eschaton-keyring` au pacstrap et `pacman-key --populate eschaton` au chroot (à côté du populate archlinux existant) ; le live env garde `Optional` le temps du pacstrap (il n'a pas encore la clé), le système installé naît en `Required`.

### 3.4 CI

- `build-repo` : signature par paquet si la clé est présente dans l'environnement (variable d'env → gpg éphémère importé dans un GNUPGHOME temporaire, purgé) ; **échec bruyant si la clé attendue manque en contexte de publication** ; les jobs de validation (branches non publiantes) buildent sans signer.
- L'immutabilité existante (jamais deux octets sous un même nom) s'étend aux `.sig`.

## 4. Vérification — définition de « 4a terminé »

1. Marche 1 prouvée : les deux VM reçoivent le keyring par `-Syu`, la clé est listée, le dépôt sert des `.sig` valides.
2. Marche 2 prouvée : après le flip, `-Syu` passe en `Required` sur les deux VM ; **le cas « saut de version » est prouvé** (un client resté en marche 0 fait un unique `-Syu` qui installe keyring + flip et aboutit).
3. **Un paquet altéré est refusé** : un `.pkg.tar.zst` modifié après signature (ou sa `.sig` tronquée) fait échouer la transaction avec l'erreur de signature attendue — test réel consigné.
4. Installation neuve (VM jetable ou réinstallation x86 smoke) : naît en `Required`, transaction initiale verte.
5. La rotation est documentée (procédure pas à pas, testée à blanc au moins pour la partie « nouveau keyring »).
6. CI : publication signée verte ; branche de validation non signée verte ; garde d'absence de clé prouvée.

## 5. Risques (table datée 2026-08-28)

| # | Risque | Traitement |
|---|---|---|
| 1 | Ordre d'amorçage cassé (exigence avant confiance) | La séquence §3.3 est l'architecture ; le cas « saut de version » est un critère de DoD, pas une hypothèse. |
| 2 | Clé privée dans les secrets GitHub | Threat model §3.1 assumé et écrit ; environnement protégé ; rotation documentée ; à réévaluer si l'infra grossit (veto utilisateur possible sur toute la §3.1). |
| 3 | `gnupg`/`pacman-key` en conteneur CI (Landlock, TTY, agent gpg) | GNUPGHOME temporaire + `--batch --pinentry-mode loopback` ; à valider en tâche 1 du plan (spike CI). |
| 4 | Le hook keyring tourne avant l'init du keyring pacman (chroot/pacstrap) | Garde d'existence dans le hook (motif du hook preset SP2, prouvé en chroot). |
| 5 | Rotation jamais exercée | Test à blanc au DoD §4.5 ; la vraie rotation reste un runbook. |
