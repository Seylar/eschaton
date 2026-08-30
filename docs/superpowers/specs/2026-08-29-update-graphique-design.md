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

### 4.1 Conséquences assumées du modèle d'autorisation (2026-08-30, revue de sécurité)

Trois conséquences ne sont pas des défauts à corriger mais des choix, et elles sont écrites ici pour être contestables plutôt que découvertes.

**a) Tout membre de `wheel` peut annuler la transaction d'un autre utilisateur.** L'annulation passe par l'action `org.eschaton.update`, dont `allow_active=auth_admin` : *n'importe quel* administrateur de la machine, une fois authentifié, arrête l'unité — y compris une mise à jour lancée par quelqu'un d'autre. polkit autorise une *action*, pas la propriété d'une transaction, et l'unité est un objet système unique. C'est acceptable sur le poste personnel que vise Eschaton, où `wheel` est le propriétaire de la machine ; ce ne le serait pas sur une machine partagée entre administrateurs mutuellement méfiants. Le coût d'une annulation abusive est d'ailleurs borné : elle ne détruit rien, la transaction écrit `resultat=annule` et le point de retour reste disponible.

**b) Annuler coûte une authentification, comme mettre à jour.** Il n'existe pas de second chemin privilégié : arrêter une transaction de paquets en vol est une action privilégiée comme une autre.

**c) L'assistant ouvre la modale de mise à jour sans clic de confirmation préalable — contrairement au rollback.** `propose_rollback` s'arrête sur `awaiting_confirmation` et n'appelle `pkexec` qu'après un clic humain explicite dans l'intention inline ; `trigger_update` ouvre la modale directement. **L'asymétrie est assumée**, pour trois raisons :

- la borne tient dans les deux cas — le modèle **ne peut pas répondre** à la modale, qui exige un mot de passe qu'il n'a pas et une session locale active ;
- les deux opérations ne pèsent pas le même poids. Une restauration remplace le sous-volume racine : c'est l'opération la plus destructive du système, et elle mérite un cran de plus. Une mise à jour est additive, et **elle-même réversible** par le rollback (§4.3) ;
- le clic de confirmation du rollback sert d'abord à faire LIRE à l'utilisateur *quel* snapshot il s'apprête à restaurer — une information que le modèle a choisie. `trigger_update` n'a aucun paramètre : il n'y a rien à relire.

**Risque résiduel, nommé** : un modèle sous injection peut faire apparaître des modales polkit à volonté, et fabriquer ainsi une **fatigue d'authentification** — l'utilisateur finit par saisir son mot de passe par réflexe. Le contrôle actuel est la borne de fréquence naturelle (une modale à la fois : `startUpdate()` refuse si une action privilégiée est déjà en cours) et le fait que la modale nomme l'opération. Aligner `trigger_update` sur `propose_rollback` fermerait ce risque ; cela demande de bâtir pour la mise à jour la même surface d'intention inline que pour le rollback, ce qui est une évolution produit et non un correctif de sécurité. **Non fait, et assumé comme tel.**

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
| 10 | *(nouveau, 2026-08-30)* `pacman --print` **répond lui-même** aux questions sans rien afficher (`cb_question`, `src/pacman/callback.c`) | Un pré-vol bâti dessus est structurellement aveugle. Le pré-vol emprunte le vrai chemin, entrée standard sur `/dev/null` ; un test interdit le retour de `--print` (`vm-dev.md` §31.3). |
| 11 | *(nouveau, 2026-08-30)* DMS **plafonne** la hauteur d'un popout de greffon (479 px mesurés) | La rangée de boutons — dont la porte de sortie — sortait du cadre exactement dans le cas d'échec. Le journal se rétracte désormais ; à surveiller si le panneau s'enrichit (`vm-dev.md` §31.4). |
| 12 | *(revue de sécurité, 2026-08-30)* Un binaire cible de `pkexec` livré **sans** l'action qui l'épingle : `pkexec` ne refuse pas, il retombe sur `org.freedesktop.policykit.exec` — `auth_admin` sur `allow_any` ET `allow_inactive`, là où nos actions posent `no` | C'était le cas des DEUX binaires du socle, dont les actions venaient de greffons que l'installeur ne pacstrape pas. Les actions voyagent désormais avec leurs binaires dans `eschaton-base` ; `tests/actions-avec-binaires.bats` l'exige pour toute action annotée `exec.path` (`vm-dev.md` §33.1). |
| 13 | *(revue de sécurité, 2026-08-30)* Le pré-vol comptait des **lignes** et non des invites : deux questions sur une même ligne passaient pour une seule, et l'unique « y » de la transaction allait approuver la première | Comptage des occurrences, et l'unique invite doit être portée par la ligne du sommaire. Le `case` du verdict est en outre **fail-closed** : un mot inattendu arrête la transaction au lieu de la poursuivre. |

---

## 7. Vérification exécutée (2026-08-30)

| # du §5 | Verdict | Preuve |
|---|---|---|
| 1. Mise à jour réelle sans terminal | **Satisfait** | Pastille → panneau → **modale polkit graphique** → journal de l'unité affiché → « Mise à jour installée ». `qt6-base` réellement installé, `checkupdates` à 0. `vm-dev.md` §31.1 |
| 2. Aucun `--noconfirm` dans le chemin | **Satisfait** | Refus à l'exécution (`eschaton-update` rejette `--noconfirm`, `--yes`, `--ask`, `--overwrite`) **et** garde de dépôt dont la liste de fichiers est elle-même vérifiée complète : `tests/update-sans-auto-approbation.bats`. Contre-testée : réintroduire `--yes` la fait échouer |
| 3. Survie + annulation sans orphelin | **Satisfait, portée précisée le 2026-08-30** | Le shell entier est redémarré en pleine transaction (PID 479 → 17654) ; la transaction garde PID 1 pour parent et se termine (§31.2). Annulation par la même porte : `resultat=annule`, unité non `failed`, aucun verrou, rien d'installé (§30.4). **Ce qui n'était pas couvert et l'est maintenant** : la mesure d'« annulation sans orphelin » ne portait que sur la phase *transaction* — une annulation pendant le **pré-vol** sortait sans libérer le verrou, et c'est la fenêtre la plus longue puisqu'elle contient le `-Sy` (revue I5, corrigé : le filet de sortie libère sur toute sortie). Et le **rendu du panneau** après un redémarrage du shell n'était pas prouvé — il ne l'était pas parce qu'il n'existait pas : la sonde n'était armée que par un clic sur « Installer » (revue I3, corrigé par la réconciliation au démarrage du composant) |
| 4. Décision humaine : échec propre et visible, rollback offert | **Satisfait** | Remplacement de paquet fabriqué (archétype `varnish`→`vinyl-cache`) : `resultat=decision-humaine`, rien de modifié, **question verbatim à l'écran** (§31.3). Le rollback n'est *pas* proposé ici, à dessein : rien n'a bougé |
| 5. Cas `dovecot` : un service en échec n'est pas un succès | **Satisfait** | `resultat=succes-degrade`, `unites_en_echec=…`, panneau : « Le code de retour de pacman disait « succès » — pas nous », et le bouton **« Revenir à l'état d'avant »** (§31.4) |
| 6. `trigger_update` sur le même chemin, sans second chemin privilégié | **Satisfait sur l'artefact, non rejoué en dialogue** | Le `ToolExecutor.qml` **installé** porte `pkexec /usr/bin/eschaton-update-helper --apply`, argv pour argv identique au panneau ; plus aucune mention de `foot` des deux côtés (§31.5). Un tour de conversation réel avec un modèle n'a pas été rejoué. **Correction du 2026-08-30** : la promesse faite au modèle par `tool-catalog.json` — « sa progression s'affiche dans le panneau » — était **fausse**. Le panneau n'armait sa sonde qu'après un clic sur « Installer » : une mise à jour déclenchée par l'assistant n'affichait rien. L'artefact décrivait un comportement qui n'existait pas. Corrigé (revue I3) : le panneau réconcilie au démarrage et **adopte** toute transaction en vol, quelle que soit son origine |
| 7. L'annulation ne laisse pas de transaction orpheline | **Satisfait après correction** | Le premier essai laissait `/var/lib/pacman/db.lck` derrière lui. Corrigé et remesuré : plus de verrou, plus de processus (§30.3-30.4) |

### 7.1 Ce que la revue de sécurité du 2026-08-30 a corrigé dans ce §7

Le tableau ci-dessus était **exact sur ce qu'il mesurait**, et c'est précisément ce qui posait problème : trois affirmations dépassaient leur mesure.

- **« La porte n'exécute plus rien par le PATH »** (commit `5f6cfa2`) — vrai pour `eschaton-update-helper`, dont les deux commandes sont des constantes absolues ; **faux pour la charge**, qui résout une quinzaine d'outils par le `PATH`. L'affirmation est corrigée ici plutôt que le code, et la raison est mesurée (§33.3 de `vm-dev.md`) : le `PATH` de l'unité est celui de **systemd**, pas celui de l'appelant (vérifié : un `PATH=/tmp/pirate` injecté n'apparaît pas), et ses deux répertoires prioritaires sont `root:root 755`. Il n'y a donc rien à fermer. Surtout, l'épingler **casserait le démarrage** : `/usr/local/bin/mkinitcpio` est l'enveloppe de `limine-mkinitcpio-hook`, appelée par les hooks de pacman pendant la transaction. Portée exacte, désormais : *la porte* n'exécute rien par le `PATH` ; *la charge*, si — dans un `PATH` que systemd fixe et que seul root peut peupler.
- **Le point 3** ne mesurait l'absence d'orphelin que sur la phase transaction, et ne prouvait pas le rendu du panneau. Voir la ligne corrigée.
- **Le point 6** promettait au modèle une progression que le panneau ne fournissait pas. Voir la ligne corrigée.

**Et un défaut que ce §7 ne pouvait pas voir**, parce qu'il vérifiait le comportement d'une VM où *tout* était installé : les deux binaires privilégiés du socle étaient livrés **sans les actions polkit qui les contraignent** (elles venaient de greffons DMS que l'installeur ne pacstrape pas). `pkexec` retombait alors sur l'action générique, qui autorise l'authentification depuis une session distante ou inactive — ce que nos actions ferment. Mesuré, corrigé et gardé par test : `vm-dev.md` §33.1, `tests/actions-avec-binaires.bats`. La leçon de méthode : **une preuve prise sur un système complet ne dit rien de ce que l'installeur produit réellement.**

**Réserves honnêtes.**

- **Une annulation tardive ment, et laisse l'utilisateur sans porte de sortie** — trouvé le 2026-08-30 en rejouant le parcours, **non corrigé**. Si l'annulation arrive après le point de non-retour de `pacman` (mesuré : pendant un `post_upgrade`), les paquets **sont** installés, mais le panneau annonce « Mise à jour annulée. Rien n'a été installé. » et `restaurationUtile` n'inclut pas `annule` — donc aucun retour arrière n'est proposé, dans le seul cas où l'utilisateur vient d'exprimer qu'il ne voulait pas de cette mise à jour. Le correctif demande de distinguer deux résultats d'annulation dans le fichier d'état et de les rendre différemment : une décision de conception, pas un ajustement. Détail et mesure : `vm-dev.md` §33.5.
- La **course de l'annulation** (`deactivating` observé par la sonde) n'a pas été reproduite en VM : `pacman`, arrêté pendant un `sleep`, se replie en moins de 300 ms. Le comportement nominal de l'annulation est prouvé ; le traitement de `deactivating` ne l'est que par le code et par sa garde de test (`vm-dev.md` §33.4).
- Le **conflit de fichiers** (archétype `linux-firmware`) n'a pas été fabriqué : il est détecté à l'extraction, donc *après* le sommaire. Il produira un `echec` visible avec le point de retour, pas un `decision-humaine`. Comportement attendu par construction, **non mesuré**.
- La preuve du cas `dovecot` utilise un service fabriqué qui échoue *pendant* la transaction. Une casse qui ne se manifesterait qu'au redémarrage suivant **n'est pas couverte** par ce contrôle.
- Le journal de la transaction est en anglais (`LC_ALL=C.UTF-8`), contrepartie assumée du déterminisme de la réponse (risque n°8).
