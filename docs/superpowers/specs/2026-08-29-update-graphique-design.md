# Eschaton — Spec de conception : la mise à jour graphique (veto O1)

- **Date** : 2026-08-29
- **Statut** : rédigée sur passe de veille datée ([rapport](../../veille/2026-08-29-update-graphique.md), 444 lignes sourcées) — publiée pour relecture ; exécution Codex, gates Claude
- **Amendée le 2026-08-30** au titre de l'[ADR 0002](../../decisions/0002-veille-avant-spec.md), après le spike de terrain de la Task 1 ([`tools/vm-dev.md` §27](../../../tools/vm-dev.md)) : le §3.1 est **réécrit** (sa prémisse était fausse), le motif de rejet du §3.2 est remplacé, et la table des risques §6 est mise à jour. **L'architecture retenue ne change pas.**
- **Déclencheur** : **veto utilisateur** du 2026-08-29 — « pour update, faut taper le sudo dans le terminal, c'est non » ([registre des arbitrages, O1](../../REGISTRE-ARBITRAGES.md))
- **Amont** : [Spec du Bureau](2026-08-28-bureau-design.md) (le widget update actuel), [Spec de l'Assistant](2026-08-28-assistant-design.md) §5 (l'outil `trigger_update` emprunte le même chemin)
- **Bloque** : le tag `v0.3.0` et la fusion du SP3

---

## 1. Position

La mise à jour d'Eschaton souffre aujourd'hui de **deux défauts**, dont un seul était connu.

1. **Le défaut vetoé** : la pastille ouvre un terminal `foot` visible où `sudo pacman -Syu` réclame le mot de passe **au clavier, dans le terminal**. C'est la trahison du zéro-terminal à l'endroit le plus fréquent de la vie du système.
2. **Le défaut découvert par la veille, non tracé jusqu'ici** : le widget passe `--yes`, que [`lib.sh`](../../../packages/eschaton-base/lib.sh) traduit en **`--noconfirm`**. Autrement dit, **la mise à jour d'Eschaton est déjà auto-approuvée** : pacman répond « oui » tout seul aux remplacements de paquets, aux retraits de conflits et aux imports de clés. C'est précisément l'anti-modèle que nous avons banni partout ailleurs, et il est actif aujourd'hui, y compris via l'outil `trigger_update` de l'assistant.

Le rollback, lui, fait déjà correctement : `pkexec` → **modale polkit** `auth_admin` → authentification graphique. C'est le modèle à étendre — mais **pas naïvement**, pour la raison du §3.1.

## 2. Périmètre

**Livrable** : mettre le système à jour depuis l'interface, **sans terminal et sans auto-approbation**, avec une authentification graphique, une progression visible, et un échec qui reste réversible sans ligne de commande.

**Non-buts** : un gestionnaire de paquets complet (installation/suppression à la demande), la mise à jour hors-ligne façon PackageKit (cassée sur alpm et contraire à « sortie visible »), la résolution automatique des cas exigeant une décision humaine (§4).

## 3. Architecture

### 3.1 Pourquoi `pkexec` ne porte pas la transaction

> **Amendement du 2026-08-30 (ADR 0002) — la version initiale de ce §3.1 était fausse.** Elle affirmait que `pkexec` armant `prctl(PR_SET_PDEATHSIG, SIGTERM)`, la fin d'un fil de l'interface QML enverrait SIGTERM à `pacman` en pleine transaction. **Le spike de la Task 1 a mesuré le contraire** (preuves : [`tools/vm-dev.md` §27.3](../../../tools/vm-dev.md)). Le texte ci-dessous est la version corrigée ; l'architecture, elle, ne change pas — seules ses raisons changent.

**Ce qui est vrai.** La sémantique de `prctl(2)` est bien celle que redoutait la veille : le « parent » est **le fil d'exécution**, pas le processus. Mesuré en VM — un processus dont `PR_SET_PDEATHSIG` est armé reçoit SIGTERM à l'instant précis où meurt *le fil* qui l'a créé, alors que le processus créateur, lui, vit toujours.

**Ce qui est faux.** `pkexec` ne déclenche pas ce mécanisme. Son source (relu le 2026-08-30, `github.com/polkit-org/polkit`) arme le signal **avant** de changer d'identité (`setgroups`/`initgroups`/`setregid`/`setreuid`), et le noyau remet `pdeath_signal` à zéro à tout changement d'euid/egid/fsuid/fsgid (`commit_creds()`). Sur le chemin d'Eschaton, l'appelant (`seylar`) et la cible (`root`) diffèrent toujours : **le réglage est effacé, et le processus privilégié survit à la mort du fil appelant** — vérifié avec le vrai `pkexec`, et isolé par une variante qui reproduit exactement cet ordre.

**Ce qui justifie quand même de ne pas laisser `pkexec` porter la transaction** — deux raisons de conception, mesurées :

1. **L'annulation serait impossible sans un second chemin privilégié.** Une interface à uid 1000 ne peut pas signaler un processus root : `kill` rend `EPERM` (mesuré). Annuler une transaction portée par `pkexec` exigerait donc une *deuxième* porte privilégiée — ce que les invariants du projet interdisent. Portée par une unité systemd, l'annulation est un `systemctl stop` passé par **la même porte**, et ne laisse aucun orphelin.
2. **La sortie doit être visible sans coupler la transaction au panneau.** L'unité journalise ; l'interface lit le journal. Un `pkexec` ne rend sa sortie qu'à travers un tube dont la durée de vie est celle de l'appelant.

*S'y ajoute, non mesuré à ce stade et à vérifier en Task 4 : Quickshell termine les `Process` qu'il possède quand le composant est détruit ou la configuration rechargée.*

**Conséquence sur le rollback** : la « note de vigilance » de la version initiale est **sans objet**. Le rollback ne porte aucun risque résiduel de PDEATHSIG.

### 3.2 La décision : `pkexec` ouvre la porte, systemd porte la transaction

1. Une action polkit **`org.eschaton.update`**, calquée sur celle du rollback : `auth_admin`, **sans `_keep`** — chaque mise à jour est une authentification.
2. `pkexec` lance un **assistant privilégié minuscule**, dont le seul travail est de démarrer la transaction puis de rendre la main.
3. Une fois **déjà root**, cet assistant lance `pacman` dans une **unité systemd transitoire**. `pacman` a alors **PID 1 pour parent** : il est immunisé contre la mort d'un fil de l'interface, contre la fermeture du panneau, contre la fin de session.
4. La progression est **suivie par le journal** de l'unité, affichée dans l'interface. L'annulation passe par la même porte.

Le point subtil qui rend ce montage légitime : `systemd-run` **appelé par l'utilisateur** exigerait le droit polkit `org.freedesktop.systemd1.manage-units`. Appelé **par root après la modale**, il ne déclenche **aucun** contrôle polkit — *vérifié en VM le 2026-08-30, trafic du bus système à l'appui* (`tools/vm-dev.md` §27.1) : l'utilisateur ne reçoit jamais ce droit.

> **Amendement du 2026-08-30 (ADR 0002).** La version initiale motivait le rejet de l'option « `systemd-run` côté utilisateur » par le défaut systemd **#17224** — « `StartTransientUnit()` ne transmet pas le nom de l'unité à polkit ». **C'est faux sur systemd 261** : le nom de l'unité *et* le verbe sont bien transmis (message capturé, §27.1). Le motif du rejet est remplacé par un motif plus fort : les détails transmis à polkit se limitent à `unit` et `verb` — **la ligne de commande (`ExecStart`) n'y figure pas**. Une règle autorisant « l'unité `eschaton-update.service` » autoriserait donc *n'importe quel programme* démarré sous ce nom. Seule l'annotation `org.freedesktop.policykit.exec.path` épingle réellement le programme, et elle n'existe que sur le chemin `pkexec`.

**Deux conséquences de conception issues du spike**, à traiter dans l'implémentation :

- une **annulation** arrête l'unité sur `status=143`, que systemd rapporte en `Failed with result 'exit-code'`. Une annulation **n'est pas un échec** : l'unité (ou l'interface) doit les distinguer explicitement ;
- `/etc/polkit-1/actions/` **masque** `/usr/share/polkit-1/actions/` sur polkit 127. Une action livrée par un paquet Eschaton peut être redéfinie silencieusement par un fichier d'`/etc` de même nom.

### 3.3 Ce qui est écarté, et pourquoi

- **PackageKit** — *rédhibitoire* : son action `system-update` est livrée en `allow_active=yes`, donc **sans aucune authentification**. L'adopter réintroduirait exactement la règle « oui sans authentification » que la revue du Bureau a supprimée du rollback le 2026-08-28. S'y ajoutent une CVE 2026 sur son démon et un mode hors-ligne cassé sur le backend alpm.
- **pamac** — *architecture juste, dépendance impossible* : son démon root et ses vraies modales (fournisseurs, dépendances optionnelles, clés) sont le bon modèle, mais son épinglage `libalpm.so=16` **a déjà bloqué une mise à jour de pacman** chez ses utilisateurs, et `libpamac` est compilé, donc hors `arch=(any)`.
- **`systemd-run` côté utilisateur** — écarté : accorder `manage-units` reste un passe-partout, puisque `ExecStart` échappe à polkit (§3.2, amendement du 2026-08-30).

### 3.4 La leçon transposable, et l'interdit qu'elle pose

`libpamac`, utilisée seule, **choisit le premier fournisseur** et **n'importe aucune clé** : l'interactivité vit dans la couche graphique, jamais dans la bibliothèque. Un composant Eschaton dépourvu de surface de dialogue **reproduirait l'auto-approbation sans le vouloir** — c'est littéralement ce que fait notre `--noconfirm` d'aujourd'hui.

**Règle posée** : `--noconfirm` est **interdit** dans le chemin de mise à jour. Toute question de pacman doit soit remonter en modale, soit faire échouer proprement la transaction. La traduction `--yes` → `--noconfirm` de `lib.sh` doit disparaître de ce chemin.

## 4. Le cas qu'aucune architecture ne résout — et notre réponse

Certaines mises à jour Arch **exigent une intervention humaine en ligne de commande**. L'archétype est `linux-firmware` (2025-06-21) : `pacman -Syu` **s'arrête** sur `… exists in filesystem` et impose un `pacman -Rdd` suivi d'une réinstallation. **Aucun drapeau ne passe outre, et aucune des solutions étudiées ne résout ce cas.** Le prétendre serait mentir.

Ce que cette conception garantit à la place :
1. **Le cas courant est graphique de bout en bout.**
2. **L'échec est visible** — le journal est affiché, pas avalé.
3. **L'échec est réversible sans ligne de commande** : le snapshot pré-transaction et le rollback graphique, déjà prouvés en réel, sont la porte de sortie. **Personne d'autre ne l'a** — c'est notre différenciateur qui absorbe la faiblesse d'Arch.
4. Une **porte de secours** assumée et documentée pour ces cas, plutôt qu'un contournement silencieux.

**Piège supplémentaire à traiter** : le cas `dovecot 2.4` (2025-10-31), où **pacman réussit** mais le service ne redémarre pas. Un updater qui ne lit que le code de retour **annoncerait un succès**. La vérification doit donc dépasser le code de sortie.

## 5. Vérification — définition de « terminé »

1. Une mise à jour réelle se déroule **sans terminal** : modale polkit graphique, progression affichée, résultat annoncé — prouvé en VM.
2. **Aucun `--noconfirm`** n'existe dans le chemin de mise à jour (garde de test).
3. La transaction **survit** à la fermeture du panneau et à la destruction du composant de l'interface — et **l'annulation reste possible depuis l'interface**, par la même porte, sans transaction orpheline (§3.1 amendé le 2026-08-30 : c'est l'annulation, non le PDEATHSIG, qui porte cette exigence).
4. Une transaction nécessitant une décision humaine **échoue proprement et visiblement**, avec le rollback offert dans l'interface.
5. Le cas `dovecot` est couvert : un service en échec après une transaction réussie **n'est pas annoncé comme un succès**.
6. L'outil `trigger_update` de l'assistant emprunte ce nouveau chemin, sans second chemin privilégié.
7. L'annulation fonctionne et ne laisse pas de transaction orpheline.

## 6. Risques (table datée 2026-08-29, mise à jour le 2026-08-30 par le spike Task 1)

| # | Risque | Traitement |
|---|---|---|
| 1 | `systemd-run` lancé par root déclenche malgré tout un contrôle polkit | **Levé le 2026-08-30.** Mesuré : aucun `CheckAuthorization` sur le bus quand root lance l'unité ; un contrôle `manage-units` apparaît quand l'utilisateur la lance (`vm-dev.md` §27.1). Le repli « service D-Bus » n'est pas ouvert. |
| 2 | L'utilisateur ne peut pas suivre le journal d'une unité **système** depuis sa session | **Levé le 2026-08-30.** `journalctl -u` et `journalctl -f -u` fonctionnent sans privilège via l'ACL `group:wheel:r-x` du magasin de journal (`vm-dev.md` §27.2). Le repli « relais par l'assistant privilégié » est abandonné. |
| 3 | Détection préalable de l'interactivité de pacman | **Refermé pour notre usage le 2026-08-30** (`vm-dev.md` §29), sans passer par libalpm : un pré-vol `pacman -Syu --print` avec l'entrée standard sur `/dev/null` ne modifie rien et **ne peut rien approuver** (sur EOF, `question()` rend NON — source relue). Toute question laisse une trace détectée par un marqueur générique (`[Y/n]`, `[y/N]`, `Enter a number`, `Enter a selection`), et la transaction s'arrête. Réserve honnête : le pré-vol ne voit pas les conflits de **fichiers**, détectés à l'extraction (archétype `linux-firmware`) — ceux-là échouent pendant la transaction, visiblement, avec le rollback en porte de sortie (§4). |
| 4 | ~~Le risque `PR_SET_PDEATHSIG` subsiste sur le rollback~~ | **Sans objet au 2026-08-30.** `pkexec` efface lui-même le réglage en changeant d'identité (§3.1 amendé, `vm-dev.md` §27.3). |
| 5 | Régression de sécurité en corrigeant l'ergonomie | La modale reste `auth_admin` **sans `_keep`** : une action privilégiée = une authentification. Jamais d'auto-approve. |
| 6 | *(nouveau, 2026-08-30)* Une annulation est rapportée par systemd comme un échec (`status=143`, `Failed with result 'exit-code'`) | À distinguer explicitement dans l'unité ou l'interface — une annulation n'est pas un échec (`vm-dev.md` §27.3). |
| 7 | *(nouveau, 2026-08-30)* Une action polkit livrée par un paquet peut être masquée par un fichier de même nom dans `/etc/polkit-1/actions/` | Constaté sur polkit 127. À garder en tête pour toute revue de sécurité du chemin privilégié. |
| 8 | *(nouveau, 2026-08-30)* `pacman` répond à la **traduction locale** de « Y » : en français, `_("Y")` vaut « O ». Une réponse codée en dur en anglais y signifie NON | La transaction force `LC_ALL=C.UTF-8` sur ses deux phases. Le défaut est sûr (refus, jamais approbation) mais aurait rendu la mise à jour graphique inopérante sur toute machine non anglophone (`vm-dev.md` §29.3). |
| 9 | *(nouveau, 2026-08-30)* Un `pacman` tué en vol laisse `/var/lib/pacman/db.lck` — l'orphelin que le DoD §5.7 interdit | Mesuré et corrigé : la transaction libère le verrou au démarrage et après une annulation, **uniquement** quand plus aucun `pacman` ne tourne (`vm-dev.md` §30.3). |
