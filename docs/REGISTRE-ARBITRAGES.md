# Registre des arbitrages pris sans l'utilisateur

- **Date** : 2026-08-29 — établi à la demande de l'utilisateur (« beaucoup d'arbitrages ont été pris sans moi… j'ai peur qu'il y ait un sacré décalage entre mes attendus et le rendu »)
- **Portée** : SP1 (Socle, fusionné) + SP2 (Bureau, fusionné) + SP3 (Assistant, en attente de fusion)
- **Sources** : bilans d'exécution ([Socle](superpowers/bilans/2026-08-28-socle-execution.md) 22 rulings, [Bureau](superpowers/bilans/2026-08-28-bureau-execution.md) 13 rulings), ADR [0001](decisions/0001-shell-du-bureau.md)/[0003](decisions/0003-service-secrets-assistant.md), amendements de specs, handoff §9/§11/§13, ledgers SDD.

## Comment lire ce document

Le **brief initial** sert d'étalon : « un nouveau Windows » — système complet pour tous, **léger, fluide, joli**, **IA intégrée au cœur / assistant omniprésent**, mises à jour gérées, Steam/Proton, **zéro-terminal**, tactile + souris, dogfooding v1.

Onze arbitrages de produit, classés par **risque de désaccord**, pas par ordre chronologique. Chacun porte son coût de retour en arrière. Les ~30 décisions purement techniques (contraintes de terrain constatées : Landlock sous Docker, gradle cassé, ICMP/NAT UTM, méthode *replace* de Snapper, ESP 4 Gio, symlinks LICENSE, `-d` pour les meta-paquets…) ne figurent pas ici : ce sont des constats, pas des choix de produit. Ils restent dans les bilans.

**Biais systématique assumé** : à chaque bifurcation, l'arbitrage a penché du même côté — **la rigueur et la sécurité contre la fluidité**. Chaque décision est défendable isolément ; leur cumul tire le produit vers « sérieux et un peu austère », ce qui n'est pas exactement « léger, fluide, joli ».

---

## 🔴 Rouge — contredit un attendu explicite du brief

### R1. L'assistant n'est pas omniprésent : 3 outils dans un panneau latéral

- **Décidé** : catalogue **fermé** à `system_status`, `trigger_update`, `propose_rollback` ([spec Assistant §5](superpowers/specs/2026-08-28-assistant-design.md)).
- **Motif** : tout contenu système est hostile par construction ; refus de l'anti-modèle Omarchy (auto-approve) ; surface d'attaque minimale pour un v1.
- **Ce que ça te coûte** : l'assistant ne peut ni ouvrir une application, ni changer un réglage, ni parler de tes fichiers, ni agir sur le bureau. Tu avais coché « **assistant omniprésent** » au brainstorming.
- **Retour en arrière** : **moyen**. L'architecture est faite pour ça (trajectoire A→B, contrat `AssistantCore`) — ajouter un outil ≈ une tâche (exécuteur + porte polkit + tests). Mais chaque outil rouvre la question de sécurité.
- **Question qui t'appartient** : élargit-on le catalogue en v1 ? Avec quels outils exactement ?

### R2. Chaque rollback exige ton mot de passe

- **Décidé** : suppression, en revue, de la règle polkit qui autorisait le rollback sans authentification ([bilan Bureau, ruling 8](superpowers/bilans/2026-08-28-bureau-execution.md)).
- **Motif** : le rollback réécrit la racine ; cohérence avec la posture sudo du Socle ; « on part fermé ».
- **Ce que ça te coûte** : de la friction sur **la fonctionnalité phare**, celle qui doit rassurer un débutant (« si ça casse, un clic et c'est réparé » devient « un clic, un mot de passe, et c'est réparé »).
- **Retour en arrière** : **trivial** — une règle polkit, un fichier, un bump.
- **Question qui t'appartient** : mot de passe, ou clic simple pour l'utilisateur propriétaire de la machine ?

### R3. Après une lecture système, l'assistant est désarmé

- **Décidé** : durcissement de terrain Task 7 — après `system_status`, plus aucun outil n'est exposé ; agir exige **un nouveau message humain** ([spec §5.3](superpowers/specs/2026-08-28-assistant-design.md)).
- **Motif** : le test d'injection a **réellement mordu** — une description de snapshot piégée a fait tenter une action privilégiée au modèle. La consigne textuelle seule ne suffisait pas.
- **Ce que ça te coûte** : « regarde mon système et corrige ce qui ne va pas » est **structurellement impossible en un tour**. Toujours deux messages minimum.
- **Retour en arrière** : techniquement facile — mais c'est le **seul rempart prouvé** contre l'injection. **Recommandation : garder.**
- **Question qui t'appartient** : acceptes-tu cette friction, ou veux-tu explorer un compromis (ex. désarmer seulement quand du contenu hostile est détecté) ?

### R4. Le tactile a été déclassé en « nice-to-have » — il n'existe nulle part

- **Décidé** : [ADR 0001 §1](decisions/0001-shell-du-bureau.md) recentre le différenciateur n°1 sur le zéro-terminal, « ni le tactile (déclassé en nice-to-have) ». **Vérification faite le 2026-08-29 : le mot « tactile » n'apparaît que dans cet ADR, et aucun paquet ne contient une ligne de code tactile.**
- **Motif** : Omarchy 4 était passé à Hyprland + Quickshell le 14 août 2026 ; il fallait un différenciateur qui tienne, et le zéro-terminal a été jugé plus solide.
- **Ce que ça coûte** : Hyprland est un gestionnaire de fenêtres **en mosaïque, piloté au clavier** (`SUPER`+touche) — structurellement l'opposé d'une interface tactile. Or ton brief disait « **mais tactile/souris** », précisément pour te démarquer du tout-clavier d'Omarchy. C'est l'attendu le plus silencieusement abandonné du projet.
- **Retour en arrière** : **coûteux** — Hyprland n'a qu'un support tactile partiel et DMS est pensé pour le bureau. Un vrai bureau tactile relève d'un autre choix de fondation, ou d'un travail conséquent.
- **Question qui t'appartient** : le tactile est-il un objectif v1, un objectif v2, ou est-ce qu'on l'abandonne franchement et qu'on le retire du brief ?

> **Note d'honnêteté** : cet arbitrage manquait à la première version de ce registre. Je l'ai trouvé en relisant l'ADR 0001 après coup — ce qui illustre exactement ta crainte : les décisions prises en autonomie se diluent dans la documentation et deviennent invisibles.

---

## 🟠 Orange — promesse entamée, friction ajoutée

### O1. Les mises à jour ouvrent un terminal visible et demandent sudo — ⛔ VETO REÇU (2026-08-29) · ✅ CORRIGÉ, EN ATTENTE DE TA REVUE (2026-08-30)

> **Verdict utilisateur** : « pour update, faut taper le sudo dans le terminal, c'est non. » Arbitrage **rejeté**. L'update doit passer par une **modale polkit graphique**, exactement comme le rollback. **Le tag v0.3.0 attendra la nouvelle conception.**

- **Motif (rejeté)** : jamais de second chemin privilégié ; réutilisation du flux existant ; l'humain authentifie — mais l'authentification passait par le terminal, ce qui est le point rejeté.
- **Coût constaté** : le « zéro terminal » était entamé **à l'endroit le plus fréquent** de la vie d'un système.
- **Livré le 2026-08-30** : action polkit `org.eschaton.update` (`auth_admin`, sans `_keep`), assistant privilégié minuscule, transaction portée par une **unité systemd** — plus aucun terminal. Progression = le journal de l'unité, affiché tel quel dans le panneau. Prouvé de bout en bout en VM : pastille → modale graphique → journal → « Mise à jour installée » ([`tools/vm-dev.md` §31](../tools/vm-dev.md)).
- **Ce qu'il reste à décider, et qui t'appartient** : **annuler une mise à jour coûte une seconde authentification**, parce qu'il n'existe volontairement pas de second chemin privilégié. Et une mise à jour qui demande une décision humaine (renommage de paquet, conflit) **s'arrête** au lieu de choisir à ta place : tu vois la question de pacman, mot pour mot, et un bouton « Revenir à l'état d'avant ». **Le veto n'est levé que par ta revue, pas par ce document.**

### O1bis. La mise à jour était **auto-approuvée** — défaut jamais arbitré, découvert le 2026-08-29

- **Ce qui existait** : `lib.sh` traduisait `--yes` (interface Eschaton) en `pacman --noconfirm`, et le widget comme `trigger_update` passaient `--yes`. La mise à jour répondait donc « oui » toute seule aux remplacements de paquets, aux retraits de conflits et aux imports de clés.
- **Ce que ça vaut** : c'est exactement l'anti-modèle Omarchy que R1 refuse pour l'assistant — actif, en production, sur le chemin le plus fréquent du système. **Personne ne l'avait décidé** : il est né d'une commodité d'implémentation et a traversé deux vagues de revue sans être vu.
- **Corrigé le 2026-08-30** : toute option qui répondrait à la place de l'utilisateur est **refusée** ; un pré-vol joue la transaction à blanc et s'arrête si une question précède le sommaire ; une garde de dépôt, contre-testée, empêche le retour du défaut.
- **Rien à arbitrer** — c'est consigné ici parce qu'un défaut de cette nature mérite d'être vu, pas parce qu'il ouvre une question.

### O2. Auto-login sans mot de passe au démarrage

- **Motif** : dette assumée du Bureau (`user = seylar` en dur dans `greetd.toml`), routée au SP4c.
- **Coût** : une posture de sécurité que tu n'as pas choisie ; corollaire, le trousseau de clés reste **en clair au repos** (affiché à l'utilisateur, mais quand même).
- **Retour en arrière** : c'est précisément le contenu du SP4c (greeter authentifié, PAM, verrouillage).

### O3. `btrfs-assistant` retiré du meta-paquet

- **Motif** : sa condition de sortie explicite (rollback natif prouvé dans le shell) était remplie avant le retrait.
- **Coût** : plus de filet graphique de secours pour les snapshots en dehors de notre propre plugin.
- **Retour en arrière** : trivial (une ligne de `depends`).

---

## 🟡 Jaune — structurant, coûteux à défaire

### J1. Ton `~/.config/hypr/` entier appartient au bureau, pas à toi

- **Constaté en VM** : DMS possède l'arbre complet ; l'accroche passe par `dms/binds-user.lua` (le canal béni de l'amont) et un wrapper de session.
- **Coût** : tu ne peux pas éditer ta configuration Hyprland à la main comme sur une Arch classique — elle serait écrasée. **Pour un auteur qui daily-drive et bricole, c'est le point le plus susceptible d'exaspérer.**
- **Retour en arrière** : **coûteux** — c'est le contrat d'intégration avec l'amont ; le défaire, c'est reprendre la propriété et perdre le canal béni.

### J2. DankMaterialShell comme base du bureau (ADR 0001)

- **Motif** : seul shell Quickshell offrant un **registre de plugins** — extensibilité sans fork.
- **Coût** : on hérite de ses bugs (pastilles non rechargées après changement de config, notifications au-dessus des jeux en plein écran) et de son rythme amont.
- **Retour en arrière** : **très coûteux** — c'est la fondation du SP2 tout entier.

### J3. `gnome-keyring` entre au meta-paquet (ADR 0003)

- **Motif** : découverte en VM — sans lui, **aucun service de secrets** n'existe sous Hyprland ; `secret-tool` échoue.
- **Retour en arrière** : facile en théorie, mais rien d'autre ne fournit Secret Service simplement.

### J4. Le SP4 découpé en trois (4a signature / 4b machine / 4c session)

- **Motif** : la signature est bloquante et sans dépendance ; la machine réelle conditionne le reste.
- **Retour en arrière** : c'est du planning — tu peux réordonner librement.

---

## ⚠️ Deux vetos déjà en attente de toi (rien n'a été fait)

1. **La clé privée de signature vivrait dans un secret GitHub** ([spec Signature §3.1](superpowers/specs/2026-08-28-signature-design.md)) : un compromis du compte GitHub permettrait de signer des paquets malveillants. L'alternative (signer localement à chaque publication) casse le flux CI→Pages. **Rien ne démarre tant que tu n'as pas tranché, et la sauvegarde chiffrée de la clé doit t'être remise avant.**
2. **La requalification de « atomique »** dans la roadmap du Socle (§1.2).

---

## Le trou que ce registre ne comble pas

**Tu n'as jamais vu la distro.** Tout est prouvé par des agents dans une VM ARM, en rendu logiciel, sans audio. Les captures ont servi à vérifier que des éléments s'affichent — **pas qu'ils sont beaux**.

Sur **« joli »** et **« fluide »**, deux critères explicites du brief initial, il n'y a eu **aucun humain dans la boucle, jamais**. Aucun document ne peut combler ça : seule une prise en main réelle le peut.

## Recommandation

1. **Prendre la VM en main** avant tout tag — vingt minutes de clics diront plus que trente rapports, et le décalage sortira sur le produit plutôt que sur le papier.
2. **Opposer un veto ligne par ligne** sur les rouges et les oranges ci-dessus. Les rouges R1/R2 sont bon marché à défaire — c'est maintenant qu'il faut le dire, pas après la fusion.
3. Les deux vetos en attente bloquent l'ouverture du SP4a.

**Rien n'est irréversible aujourd'hui** : `main` ne porte que le Socle et le Bureau, l'Assistant est sur une branche, il n'existe aucun utilisateur, et un tag n'engage personne.
