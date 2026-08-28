# Plan d'implémentation : Signature & keyring (SP4a)

> **Exécution : Codex** (après le SP3, ou en créneau si le SP3 attend une revue), gates : Claude. Conventions habituelles (branche de travail indiquée par Claude au lancement, CI verte par vague, preuves vm-dev, pkgrel bumps, pas de tag/fusion). **Spec (autorité)** : `docs/superpowers/specs/2026-08-28-signature-design.md` — sa séquence §3.3 EST l'architecture : ne jamais inverser les marches.

**Goal:** Les paquets `[eschaton]` sont signés, les clients l'exigent (`Required DatabaseOptional`), l'amorçage marche sur installations neuves ET existantes, et un paquet altéré est refusé — prouvé.

### Task 1 : Spike signature en CI + génération de la clé

1. **Spike conteneur** : prouver `gpg --detach-sign --batch --pinentry-mode loopback` dans le conteneur CI (GNUPGHOME temporaire, import depuis variable d'env, purge) — les pièges Landlock/agent gpg du risque 3, réglés AVANT d'écrire build-repo. Consigner le motif exact.
2. **Génération de la clé** (Ed25519, « Eschaton Package Signing Key ») **localement sur le Mac, jamais en CI**. ⚠️ **Point utilisateur obligatoire** : la sauvegarde chiffrée de la privée et sa passphrase appartiennent à l'utilisateur — lui remettre l'export et la consigne AVANT de mettre la privée dans le secret GitHub (environnement `github-pages`, protégé). Rien ne se publie tant que la garde n'est pas confirmée.
3. Commit docs (spike) ; la clé ne rentre jamais dans le repo.

### Task 2 : Paquet `eschaton-keyring`

Clé publique au format keyring pacman (`/usr/share/pacman/keyrings/eschaton.{gpg,trusted,revoked}` — vérifier le format exact avec `pacman-key --populate` en conteneur), hook alpm idempotent avec garde d'existence (motif du hook preset SP2 — spec §3.2/risque 4), motif Socle complet, bats sur la logique du hook, entrée dans `depends` d'`eschaton-base` (bump). Build `-d`, tar/hook vérifiés. PAS de flip SigLevel ici.

### Task 3 : Signature dans `build-repo` + CI

Signature par paquet si clé présente (motif du spike), `.sig` ajoutés à `repo-add`, immutabilité étendue aux `.sig`, **échec bruyant si publication sans clé**, branches de validation non signées OK. Garde bats/shellcheck. Push, CI verte (la clé étant en secret d'environnement, seule la publication signe).

### Task 4 : Marche 1 — la confiance s'installe (sans être exigée)

Publier (keyring + base bump + dépôt signé, clients encore `Optional`). Preuves VM ×2 : `-Syu` amène le keyring, `pacman-key --list-keys` montre la clé, les `.sig` servis sont valides (`pacman -U` d'un paquet téléchargé + vérif manuelle). Consigner.

### Task 5 : Marche 2 — l'exigence se referme + preuves adverses

1. Flip `SigLevel = Required DatabaseOptional` (bump eschaton-base), publier.
2. Preuves VM ×2 : `-Syu` vert en Required.
3. **Cas « saut de version »** : un clone/snapshot de VM resté en marche 0 fait UN `-Syu` → keyring + flip dans la même transaction → aboutit (spec §3.3.2).
4. **Paquet altéré REFUSÉ** : `.pkg` modifié post-signature et `.sig` tronquée → erreurs de signature attendues, transaction échoue — sorties consignées (spec §4.3).

### Task 6 : Installation neuve + clôture

`eschaton-install` : keyring au pacstrap + populate au chroot (bats dry-run mis à jour) ; réinstallation de la VM x86 smoke → naît en Required, transaction verte. Rotation testée à blanc (nouveau keyring pkgrel, runbook écrit). DoD spec §4 point par point, statut spec, **notifier pour revue Claude** (pas de tag — 4a se fond dans la release SP4 ou une v0.x dédiée, décision Claude à la clôture).
