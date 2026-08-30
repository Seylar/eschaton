# Plan d'implémentation : la mise à jour graphique (veto O1)

> **Exécution : Codex.** Gates : Claude. Branche `assistant` (le SP3 y attend son tag). Conventions habituelles : CI verte par vague, preuves `vm-dev`, bumps de `pkgrel`, jamais de tag ni de fusion.
> **Spec (autorité)** : [`2026-08-29-update-graphique-design.md`](../specs/2026-08-29-update-graphique-design.md) — son §3.1 (le piège `PR_SET_PDEATHSIG`) est la raison d'être de toute l'architecture : ne jamais y revenir par simplification.

**Goal :** mettre le système à jour depuis l'interface, **sans terminal et sans auto-approbation**, avec authentification graphique, progression visible et échec réversible — puis débloquer le tag `v0.3.0`.

> **État au 2026-08-30 : les six tâches sont exécutées.** Le spike de la Task 1
> a **démenti** le §3.1 de la spec — `pkexec` ne tue pas sa cible quand le fil
> appelant meurt, parce qu'il efface lui-même le réglage en changeant
> d'identité. L'architecture ne change pas ; ses raisons, si (annulation
> impossible sans second chemin privilégié, sortie couplée au panneau). Les
> corrections sont remontées dans la spec au titre de l'ADR 0002, et la spec
> porte désormais son **§7 — vérification exécutée**, point par point, avec ses
> réserves. Preuves : [`tools/vm-dev.md` §27 à §31](../../../tools/vm-dev.md).
>
> Quatre défauts trouvés par le terrain, hors périmètre initial du plan, sont
> corrigés en chemin : `--print` aveugle à l'interactivité, « rien à faire »
> pris pour un succès alors qu'une décision attendait, verrou pacman orphelin
> après une annulation, et trois défauts d'affichage du panneau.

---

### Task 1 : Spike — prouver les deux hypothèses non vérifiées (BLOQUANT)

La spec repose sur deux points que la veille n'a **pas** pu confirmer. Tant qu'ils ne sont pas prouvés en VM, n'écris aucun code définitif.

1. **`systemd-run` lancé par root ne déclenche-t-il aucun contrôle polkit ?** Mesure-le réellement (unité transitoire lancée depuis un processus déjà root, journal polkit à l'appui). Si un contrôle survient, bascule sur le repli documenté (petit service D-Bus, modèle pamac) et **remonte-le dans la spec** (ADR 0002).
2. **Un utilisateur non privilégié peut-il suivre le journal d'une unité *système* ?** (`journalctl --user-unit` ne convient pas ; tester `journalctl -u` selon l'appartenance aux groupes `systemd-journal`/`adm`.) Si non, l'assistant privilégié devra relayer la sortie — décide sur mesure, pas sur hypothèse.
3. **Contre-épreuve du §3.1** : démontre concrètement le danger que l'architecture évite — un `pkexec` dont le fil parent meurt, et le processus fils qui reçoit `SIGTERM`. Cette preuve justifie tout le reste ; consigne-la.

Livrable : section `vm-dev` dédiée, conclusions écrites, spec amendée si le terrain contredit.

### Task 2 : La correction due immédiatement — supprimer l'auto-approbation

Indépendante de l'architecture, et **la plus urgente** : la mise à jour est aujourd'hui auto-approuvée (`--yes` → `--noconfirm` via `lib.sh`).

1. Retirer `--noconfirm` du chemin de mise à jour ; `lib.sh` ne doit plus produire cette traduction pour l'update.
2. Décider et documenter le comportement immédiat en attendant l'interface complète : une question de pacman doit faire **échouer proprement et visiblement** la transaction, jamais l'approuver.
3. **Test bats de garde** : aucun `--noconfirm` dans le chemin de mise à jour. Ce test doit être impossible à satisfaire par accident.
4. Vérifier l'impact sur `trigger_update` de l'assistant (même chemin).

### Task 3 : La porte privilégiée

1. Action polkit **`org.eschaton.update`** calquée sur celle du rollback : `auth_admin`, **sans `_keep`** — une mise à jour = une authentification.
2. **Assistant privilégié minuscule** : lancé par `pkexec`, son unique travail est de démarrer la transaction dans une **unité systemd transitoire** puis de rendre la main. Surface d'attaque minimale, argv strict, aucune interpolation.
3. Tests : argv constant, refus d'arguments inattendus, motif de la revue T5 (validation côté exécution).

### Task 4 : La progression et l'annulation dans l'interface

1. Suivi du journal de l'unité, affiché dans le panneau — **la sortie est visible, jamais avalée**.
2. Annulation par la même porte, sans transaction orpheline.
3. **Preuve de survie** (DoD §5.3) : la transaction continue quand le panneau est fermé et quand un fil de l'interface meurt.

### Task 5 : Les échecs honnêtes

1. **Cas exigeant une décision humaine** (archétype `linux-firmware`) : échec propre, message clair, **et le rollback proposé dans l'interface**. C'est le cœur de notre valeur : l'échec reste réversible sans ligne de commande.
2. **Cas `dovecot`** : pacman réussit mais le service ne redémarre pas. La vérification doit dépasser le code de sortie — un service en échec n'est **pas** un succès.
3. Tests sur les deux comportements.

### Task 6 : Bascule, preuves et clôture

1. `trigger_update` de l'assistant emprunte le nouveau chemin — **aucun second chemin privilégié**, aucun terminal.
2. Mise à jour **réelle** en VM, de bout en bout, sans terminal : modale, progression, résultat. Captures et journal consignés.
3. DoD spec §5 point par point, statut de la spec, garde CI à jour.
4. **Notifier pour la revue Claude** — c'est cette revue qui rouvrira le tag `v0.3.0`.
