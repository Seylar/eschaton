# Veille — mise à jour graphique sans terminal — passe datée du 2026-08-29

- **Déclencheur** : veto utilisateur sur la conception actuelle — « pour update, faut taper le sudo dans le terminal — c'est non ». La pastille de mise à jour ouvre un terminal `foot` visible dans lequel `sudo` réclame le mot de passe. Incompatible avec le différenciateur n°1 (zéro-terminal).
- **Objet** : établir l'état de l'art AVANT la réécriture de la spec, conformément à l'[ADR 0002](../../docs/decisions/0002-veille-avant-spec.md).
- **Date de la passe** : **2026-08-29**. Toute affirmation porte cette date sauf mention contraire.
- **Couverture** : cinq axes sur six aboutis. **Un seul trou majeur subsiste** — la détection préalable de l'interactivité de `pacman` (§8.1). Il est nommé, non comblé par extrapolation.

> **Démentis de terrain du 2026-08-30** — ce rapport reste la photographie du 2026-08-29 et n'est pas réécrit, mais **deux de ses constats ont été mesurés faux** par le spike de la Task 1 ([`tools/vm-dev.md` §27](../../tools/vm-dev.md)), et la [spec](../superpowers/specs/2026-08-29-update-graphique-design.md) porte les corrections :
> - **§7.1 / §1 constat 2 / §10 risque 2 — « `pkexec` tue `pacman` quand le fil appelant meurt » : FAUX.** La sémantique `prctl(2)` est bien celle décrite, mais `pkexec` arme le signal *avant* de changer d'identité, et le noyau efface le réglage à ce changement. Mesuré avec le vrai `pkexec` et isolé par contre-épreuve.
> - **§7.2 / §9.1 option D — le bug systemd #17224 : FAUX sur systemd 261.** `StartTransientUnit()` transmet bien `unit` et `verb` à polkit. Ce qu'il ne transmet pas, c'est `ExecStart` — motif de rejet plus fort, retenu à la place.
>
> Les recommandations §9.2 (porte `pkexec` + transaction portée par systemd) et l'interdiction de `--noconfirm` **restent valides** ; seules leurs justifications changent.

## Convention de provenance

| Marque | Sens |
|---|---|
| **(V1)** | Source récupérée et lue **de première main par moi** pendant cette passe. |
| **(V2)** | **Source primaire** (fichier de code amont, page de manuel, API) lue par la passe de recherche, URL et date consignées. |
| **(R)** | **Relevé** au niveau recherche ou source secondaire — à contrôler avant de devenir porteur. |

---

## 1. Synthèse — les six constats qui décident

| # | Constat | Portée |
|---|---|---|
| 1 | **Le chemin actuel d'Eschaton cumule deux défauts**, pas un : mot de passe au terminal **et** `--noconfirm` implicite. | §2.1 — correction due immédiatement. |
| 2 | **`pkexec` est dangereux pour une opération longue.** Il arme `PR_SET_PDEATHSIG=SIGTERM`, et le « parent » est **le fil d'exécution** qui a lancé l'appel : dans une interface multi-thread, la fin de ce fil **tue `pacman` en pleine transaction**. | §7.1 — **invalide la solution naïve**. |
| 3 | **PackageKit est rédhibitoire** : `allow_active=yes` sur `system-update`, c'est-à-dire aucune authentification. | §4.3. |
| 4 | **pamac est architecturalement juste et son interface traite vraiment les décisions de pacman** — mais son épinglage de soname `libalpm` **a déjà bloqué une mise à jour de pacman**, et il n'est pas `arch=(any)`. | §3 — écarté comme dépendance, retenu comme référence de conception. |
| 5 | **Deux distributions ont résolu le zéro-terminal** : Octopi (`qt-sudo` + sortie dans l'interface) et surtout **Shelly** (CachyOS, avril 2026, GTK4 lisant `libalpm` directement). EndeavourOS et Garuda, non : leur bouton « mettre à jour » ouvre un terminal. | §6. |
| 6 | **Aucune ne résout le cas de la décision humaine.** L'archétype `linux-firmware` **arrête** `pacman -Syu` et exige deux commandes manuelles. | §5.3. |

**Conclusion structurante** : *un update purement graphique ne peut pas être complet ; il peut être complet pour le cas courant et **échouer proprement, lisiblement et de façon réversible** pour le reste.* Ce n'est pas un renoncement — c'est l'avantage d'Eschaton, seule à disposer déjà d'un instantané `snap-pac` avant chaque transaction et d'un rollback graphique prouvé.

---

## 2. Le point de départ réel — lecture du dépôt (V1)

### 2.1 Le chemin de mise à jour actuel

`packages/eschaton-dms-plugin-update/EschatonUpdateWidget.qml`, lignes 69-78 (V1) :

```qml
Process {
    id: updateProcess
    command: [
        "/usr/bin/foot", "--hold",
        "--title=Eschaton · Mise à jour",
        "/usr/bin/eschaton-update", "--yes"
    ]
```

et ligne 33, le message qui acte le renoncement :

```qml
ToastService.showInfo("Mise à jour Eschaton", "La progression s'affiche dans le terminal.");
```

`packages/eschaton-base/eschaton-update` ligne 15 (V1) : `sudo pacman -Syu "${pacman_args[@]}"`.
`packages/eschaton-base/lib.sh` lignes 15-23 (V1) : `pacman_update_args()` traduit `--yes` en **`--noconfirm`**.

> **Constat aggravant, non relevé jusqu'ici.** Le veto porte sur le mot de passe au terminal. Mais le même chemin porte un second défaut, plus grave au regard de la contrainte (d) : **le widget passe `--yes`, donc `pacman --noconfirm`**. La mise à jour graphique d'Eschaton est aujourd'hui **auto-approuvée**. Les deux défauts se corrigent ensemble : retirer le terminal sans retirer `--noconfirm` déplacerait le problème.

### 2.2 Le chemin de rollback — le modèle à reproduire

`packages/eschaton-dms-plugin-rollback/org.eschaton.rollback.policy` (V1) :

```xml
<action id="org.eschaton.rollback">
  <defaults>
    <allow_any>no</allow_any>
    <allow_inactive>no</allow_inactive>
    <allow_active>auth_admin</allow_active>
  </defaults>
  <annotate key="org.freedesktop.policykit.exec.path">/usr/bin/eschaton-rollback</annotate>
</action>
```

Le commentaire en tête du fichier est déjà l'argumentaire de cette veille, écrit le 2026-08-28 (V1) :

> « […] **le widget de mise à jour hérite donc d'une demande de mot de passe**. Une règle YES faisait de la RESTAURATION […] la SEULE action privilégiée du bureau à ne rien demander. […] **Desserrer plus tard […] est un ajout de fichier ; resserrer après coup sur des machines déjà installées ne l'est pas. On part donc fermé.** »

Deux acquis réutilisables tels quels :

1. **L'agent polkit de DMS affiche sa modale dans la session Wayland** — matrice `pkcheck` de la Task 2 (`tools/vm-dev.md` §12.9). Le zéro-terminal ne bute pas sur l'absence de surface d'authentification.
2. **L'interface privilégiée est délibérément minuscule** — `lib.sh` lignes 55-63 : `noninteractive_rollback_number()` n'accepte que `--yes N`, au motif écrit que « **pkexec authentifie le PROGRAMME, pas ses arguments** ». Règle à reporter intégralement sur l'update.

### 2.3 La détection actuelle

Ligne 47 (V1) : `command: ["/usr/bin/checkupdates"]`, `rc=2` traité comme « aucune mise à jour ». Correct et **non privilégié** — à conserver. Sa limite est établie au §5.4.

---

## 3. pamac — le patron de référence, et pourquoi on ne le prend pas

Cet axe est désormais documenté sur **sources primaires** (fichiers du dépôt amont, API RPC de l'AUR). Réserve de méthode : `gitlab.manjaro.org` était **injoignable** pendant la passe ; tout provient du **miroir GitHub officiel** (`github.com/manjaro/pamac`, `github.com/manjaro/libpamac`), celui que les paquets AUR déclarent comme amont.

### 3.1 L'architecture (V2)

- **Démon D-Bus système exécuté comme root**, activé à la demande : `Name=org.manjaro.pamac.daemon`, `User=root`, `SystemdService=pamac-daemon.service`, unité en `Type=dbus` — `data/dbus/org.manjaro.pamac.daemon.service.in` et `data/systemd/pamac-daemon.service.in` (V2).
- La politique du bus réserve la propriété du nom à root : `<policy user="root"><allow own="org.manjaro.pamac.daemon"/>` — `data/dbus/org.manjaro.pamac.daemon.conf` (V2).
- Les interfaces (`pamac-manager` en GTK4, `pamac-tray` en GTK3, l'extension GNOME Shell, la CLI `pamac`) sont **non privilégiées** et passent par `libpamac`, dont `TransactionInterfaceDaemon` relaie chaque opération au démon — `src/transaction_interface_daemon.vala` (V2).
- **Il n'existe pas de greffon GNOME Software** dans l'arbre : `src/fake_gnome_software.vala` est une coquille qui enregistre `org.gnome.Software` et relance `pamac-manager --details-id=…` (V2). *(À corriger si une note antérieure du projet l'affirmait.)*

### 3.2 Le privilège (V2)

- Action polkit **`org.manjaro.pamac.commit`**, description « Install, update, or remove packages », avec **`auth_admin_keep` sur les trois** `allow_any` / `allow_inactive` / `allow_active` — `data/polkit/org.manjaro.pamac.policy.in` (V2).
- Le démon fait **lui-même** son contrôle : `Polkit.Subject subject = new Polkit.SystemBusName (sender);` puis `authority.check_authorization (subject, "org.manjaro.pamac.commit", …, Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION)` — `src/daemon.vala` (V2). Le drapeau `ALLOW_USER_INTERACTION` **déclenche la modale graphique** de l'agent polkit ; ce n'est jamais une invite de terminal.
- Le mot de passe est demandé **une fois puis conservé**, à deux niveaux : `auth_admin_keep` côté polkit, plus un cache applicatif `authorized_senders` avec un `remove_authorization(sender)` explicite — `src/daemon.vala` (V2).
- Note de sécurité : passer le **nom de bus** (`SystemBusName`) plutôt qu'un PID évite les courses de réutilisation de PID ; c'est pourquoi le sujet `unix-process` de polkit transporte aussi `start-time` — interface `org.freedesktop.PolicyKit1.Authority` (V2, la copie récupérable était celle de polkit 0.96, interface stable).

### 3.3 Comment pamac traite les décisions interactives de pacman — la réponse (V2)

C'était la question la plus utile de la veille. Réponse : **la bibliothèque choisit par défaut, l'interface graphique demande.**

- Dans la classe de base, les décisions sont des méthodes **virtuelles** aux défauts non interactifs : `choose_provider` → **premier fournisseur**, `choose_optdeps` → aucune, `ask_import_key` → **pas d'import** — `src/transaction.vala` (V2).
- L'interface GTK **les surcharge par de vraies modales** : `choose_provider` → `ChooseProviderDialog` (« Choose a provider for %s »), `choose_optdeps` → `ChoosePkgsDialog` (« Choose optional dependencies for %s »), plus `ask_import_key` et `ask_commit` — `src/transaction-gtk.vala`, avec les widgets dédiés `choose_provider_dialog.vala`, `choose_pkgs_dialog.vala`, `transaction_sum_dialog.vala` (V2).
- Conflits et remplacements ne sont **pas** des fenêtres séparées : ils apparaissent dans le **récapitulatif de transaction** soumis à confirmation (`ask_commit` / `TransactionSummary`) (V2).
- Corroboration datée : le correctif « fix(ui): Ensure cancel button is always available » (#539, **2026-04-23**) décrit « a series of modal dialogs asking for input on optional dependencies or providers » (V2).

> **La leçon transposable, et elle est majeure pour Eschaton** : *l'interactivité vit dans la couche graphique, pas dans la bibliothèque.* Tout appelant qui ne surcharge pas ces méthodes — un démon sans interface, un script — **choisit silencieusement le premier fournisseur et n'importe aucune clé**. C'est exactement l'auto-approve que la contrainte (d) interdit. **Une conception Eschaton qui déléguerait la transaction à un composant sans surface de dialogue reproduirait ce défaut sans le vouloir.**

### 3.4 Le packaging hors Manjaro — sain, mais structurellement piégé (V2)

API RPC de l'AUR, consultée le 2026-08-29 (V2) :

| Paquet | Version | Votes | Mainteneur | Dernière modif. | Périmé |
|---|---|---|---|---|---|
| `pamac-aur` (GUI GTK) | 11.7.5-1 | 409 | Zeph | **2026-05-11** | non |
| `pamac-all` | 11.7.5-1 | 46 | patlefort | 2026-07-04 | non |
| `libpamac-aur` | 11.7.4-2 | 50 | Zeph | **2025-12-14** | non |
| `pamac-cli` | 11.7.4-1 | 18 | patlefort | 2025-12-01 | non |

`pamac-gtk` **n'existe pas** comme nom de paquet AUR (V2). Le packaging est donc **activement maintenu en 2026** — il faut cesser de dire l'inverse.

**Mais deux faits le disqualifient comme dépendance d'Eschaton :**

1. **L'épinglage de soname `libalpm` peut bloquer une mise à jour de pacman.** `libpamac-aur` dépend de `libalpm.so=16, pacman>=7.1` (V2). Précédent vérifié — fil Arch BBS du **2024-09-15** : la mise à jour échouait sur `installation of pacman (7.0.0.r3.g7736133-1) breaks dependency 'pacman<6.2' required by libpamac-aur`, et le contournement était de désinstaller `libpamac-aur`, mettre à jour, puis reconstruire (`https://bbs.archlinux.org/viewtopic.php?id=299436`) (V2). **Pour une distribution rolling dont l'argument est la mise à jour sûre, faire dépendre l'updater d'un paquet capable de bloquer pacman est une contradiction dans les termes.**
2. **`libpamac` est compilé (Vala/C)** → **incompatible avec `arch=(any)`**, contrainte (f) (V2).

S'y ajoutent : `auth_admin_keep` (plus permissif que le `auth_admin` de notre rollback), un **démon root permanent** (contrainte (c), et voir §4.4), et une dernière activité `libpamac` confirmable au **2025-12-12** sur le miroir, avec le commit fonctionnel « support libalpm 16 » du **2025-12-08** (V2) — l'état canonique sur GitLab n'a pas pu être vérifié.

*(Côté vitalité de l'interface, en revanche : `pamac` poussé le 2026-06-20, tag 11.7.5 et « Add GNOME 50 support » le 2026-04-10 (V2). Aucune annonce de dépréciation ni de réécriture trouvée — absence de preuve, GitLab étant injoignable.)*

---

## 4. PackageKit et son backend `alpm` — pourquoi c'est non (R, détaillé)

### 4.1 État de maintenance : « mode maintenance », pas « abandonné »

La formule « backend alpm semi-abandonné » est **imprécise** :

- Dernier commit dans `backends/alpm` : **2026-03-29** (R).
- Arch livre **`packagekit 1.3.6-1`, du 2026-06-17** (Christian Hesse) ; `libpk_backend_alpm.so` y est le seul backend non-test (R).
- Cadence : **3 commits en 2024, 2 en 2025, 1 en 2026** (R).
- Richard Hughes, mainteneur, écrivait le **2019-02-14** que le projet est en « mode maintenance » et sans « maintenance active depuis environ 2014 » (R).

Vivant, mais à une cadence de survie. Pas une base pour un différenciateur.

### 4.2 Le risque d'ABI libalpm est réel et récurrent

`pacman 7.0` (2024-07-14) a exigé un commit de compatibilité « libalpm 14 » daté du **2024-06-13** ; `pacman 7.1.0` (~2025-11-01) a porté le soname à **`libalpm.so.15`** (R). Un backend à 1-3 commits/an adossé à une ABI qui bouge à chaque majeure est **structurellement en retard**.

### 4.3 Le point rédhibitoire : `allow_active=yes`

- L'action **`org.freedesktop.packagekit.system-update`** est livrée en **`allow_active=yes`** — **aucune authentification** pour l'utilisateur local actif (R).
- `package-install` est en `auth_admin_keep` (R).
- Le wiki Arch qualifie PackageKit d'outil qui « ouvre les permissions système par défaut », « non recommandé pour un usage général » (R).

Ceci contredit la contrainte (d) **et** la décision écrite d'Eschaton du 2026-08-28. L'adopter réintroduirait par l'update la règle « YES sans authentification » que la revue de vague Bureau a **supprimée** du rollback. **Refusé.**

> **Corollaire pour notre propre politique** : `auth_admin_keep` est aussi à proscrire pour l'update. `polkit(8)` (V1, polkit 127-3) définit `auth_admin_keep` comme « comme `auth_admin` mais l'autorisation est conservée pendant une brève période (p. ex. cinq minutes) », et précise que les contrôles suivants pour la même action et le même sujet réussissent **« même si les variables transmises avec le contrôle sont différentes »**. Une autorisation mémorisée couvrirait un appel privilégié ultérieur invisible. **`auth_admin` sans `_keep`, comme le rollback.** *(C'est là que nous divergeons délibérément de pamac, qui a choisi `keep` pour le confort d'enchaîner les opérations.)*

### 4.4 Un démon root permanent est une surface d'attaque

- **CVE-2026-41651 « Pack2TheRoot »**, **2026-04-22** (Telekom Security) : course TOCTOU dans le traitement D-Bus `InstallFiles` de `packagekitd` → **élévation de privilèges locale** (R). Précédent : CVE-2020-16121 (R).

Argument qui vaut aussi contre pamac (§3) et contre toute conception à démon root permanent.

### 4.5 La mise à jour hors-ligne ne convient pas

Le mécanisme freedesktop est propre — **V1** sur `systemd.offline-updates(7)`, systemd 261.2-1 : étagement dans `/var/lib/system-update`, création du lien `/system-update`, redémarrage, redirection de `default.target` vers `system-update.target` par un générateur, application avant les services normaux, lien retiré ensuite. `dnf` est cité comme implémenteur. L'unité PackageKit correspondante existe (`packagekit-offline-update.service`, `FailureAction=reboot`, action `org.freedesktop.packagekit.trigger-offline-update`) (V2).

**Deux raisons de l'écarter pour Eschaton :**
1. **Contrainte (e) violée** : la sortie défile au démarrage, hors session. Ni streaming ni annulation en session — l'inverse du « rassurant pendant l'opération ».
2. **Étager puis appliquer fabrique une mise à jour partielle**, que le wiki Arch interdit explicitement : « partial upgrades are not supported », « never run `pacman -Sy`; instead, always use `pacman -Syu` » (V2).

Accessoirement, le chemin hors-ligne est **cassé sur alpm** (`/var/lib/system-update` vide — issue #755 du 2024-05-18) (R).

### 4.6 Les autres distributions le déconseillent

- Garuda : PackageKit « n'est pas une méthode supportée pour gérer les paquets sur Garuda Linux » (R).
- EndeavourOS, par un modérateur le **2025-04-13** (V2) : « GUI application managers like gnome-software or discover, use packagekit as backend, **something which is discouraged to use for managing packages on Arch and its derivatives** ».

---

## 5. Le point dur — `pacman -Syu` est interactif

### 5.1 Ce que `--noconfirm` fait, et ne fait pas

`pacman(8)`, **version 7.1.0, page datée du 2026-05-06** (V1) :

> `--noconfirm` : « Bypass any and all "Are you sure?" messages. **It's not a good idea to do this unless you want to run pacman from a script.** »

Deux options distinctes, à ne pas confondre :

> `--overwrite <glob>` : « Bypass file conflict checks and overwrite conflicting files. »

`--noconfirm` **n'implique pas** `--overwrite`. Un conflit de fichiers **arrête** une transaction `--noconfirm`.

**Non établi (§8.1)** : le texte exact des invites, leur réponse par défaut, et surtout **ce que `--noconfirm` choisit pour la sélection de fournisseur**. La page de manuel ne documente **aucune option dédiée** au choix de fournisseur ni d'option `--ask` (V1 — absence constatée dans la page, ce qui ne prouve pas l'absence du comportement).

> Indice fort venant de pamac (§3.3) : la bibliothèque `libpamac` choisit le **premier fournisseur** par défaut. Ce n'est **pas** une preuve du comportement de `pacman --noconfirm`, mais cela indique la convention du domaine. **À vérifier, pas à supposer.**

### 5.2 `.pacnew` — pas une invite, mais une dette silencieuse

pacman **n'interroge pas** sur les `.pacnew` : il écrit le fichier et le signale. Le risque n'est donc pas un blocage mais une **divergence de configuration qui s'accumule sans surface graphique**. *(Statut : à confirmer — §8.1.)*

Non théorique : `eschaton-base` déclare `backup=(etc/pacman.d/eschaton.conf etc/snapper/configs/root etc/default/limine)` (V1) — trois fichiers producteurs de `.pacnew`.

### 5.3 L'archétype qui tranche : `linux-firmware` (V1, verbatim)

Nouvelle Arch du **2025-06-21**, Jan Alexander Steffens (V1, `https://archlinux.org/news/linux-firmware-2025061312fe085f-5-upgrade-requires-manual-intervention/`) :

- Erreur pendant `pacman -Syu` : `linux-firmware-nvidia: /usr/lib/firmware/nvidia/ad103 exists in filesystem`
- Action requise, en **deux commandes** :
  ```
  # pacman -Rdd linux-firmware
  # pacman -Syu linux-firmware
  ```

**Trois démonstrations d'un coup :** `pacman -Syu` **s'arrête** et aucun `--noconfirm` ne le fait passer ; le contournement exige de **casser les dépendances** (`-Rdd`) puis de réinstaller — une décision humaine, pas un drapeau ; et un updater conçu pour « toujours réussir » aurait ici échoué en silence, ou pire s'il ajoutait un `--overwrite` générique « par robustesse ».

### 5.4 Détecter à l'avance : ce que `checkupdates` ne dit pas

`checkupdates(8)`, **pacman-contrib 1.13.1-1, page datée du 2025-12-11** (V1) :

- Travaille sur **une base pacman séparée** dans `TMPDIR` (ou `$CHECKUPDATES_DB`) — ce qui le rend sûr et non privilégié.
- « outputs a list of updates with the old and new version ».
- Codes de sortie : `0` normal, `1` échec inconnu, `2` « No updates are available ».

**La page ne mentionne ni remplacements, ni conflits, ni choix de fournisseur.**

> **Conséquence** : la détection actuelle du widget répond à « y a-t-il des mises à jour ? » et **pas** à « cette transaction exige-t-elle une décision humaine ? ». C'est la seconde question qui conditionne le zéro-terminal, et **le pré-vol fiable reste à concevoir (§8.1)**.

Piste vérifiée mais insuffisante seule : `pacman --print` / `-p` — « Only print the targets instead of performing the actual operation » — avec `--print-format` exposant `%R` (replaces), `%H` (conflicts), `%P` (provides) (V1). **Je n'ai pas établi** qu'elle révèle les conflits de *fichiers* du type `linux-firmware`, détectés à l'extraction et non à la résolution.

---

## 6. Comment les autres survivent — et les deux qui ont réussi le zéro-terminal

### 6.1 Le catalogue des interventions manuelles (V1 pour l'index et trois entrées)

Index `https://archlinux.org/news/` (V1) :

| Date | Entrée | Action requise |
|---|---|---|
| 2026-07-21 | `virtualbox-ext-vnc >= 7.2.12-2` | `--overwrite '/usr/lib/virtualbox/ExtensionPacks/VNC/*'` (R) |
| **2026-05-25** | **`varnish` renommé en `vinyl-cache`** | migration chemins/utilisateurs/services (V1) |
| 2026-04-07 | `kea >= 1:3.0.3-6` | intervention manuelle |
| 2025-12-20 | NVIDIA 590 abandonne Pascal | choix de pilote |
| 2025-12-11 | Paquets .NET | `pacman -Rs aspnet-runtime` (R) |
| 2025-11-06 | `waydroid >= 1.5.4-3` | `--overwrite /usr/lib/waydroid/tools/*__pycache__/*` (R) |
| **2025-10-31** | **`dovecot >= 2.4`** | migration de configuration (V1) |
| **2025-06-21** | **`linux-firmware`** | `-Rdd` puis réinstallation (V1, §5.3) |
| 2025-06-20 | Plasma 6.4.0 sous X11 | installer `plasma-x11-session` (R) |
| 2025-04-17 | Valkey remplace Redis | remplacement de paquet |
| 2024-09-14 | pacman 7.0.0 et dépôts locaux | `chown :alpm -R` + fusion de `.pacnew` (R) |
| 2024-07-01 | openssh-9.8p1 | redémarrer `sshd` |

**Deux classes distinctes, et la seconde est un piège :**

- **`dovecot >= 2.4`** (2025-10-31, Thore Bödecker — V1) : « the dovecot service will no longer be able to start until the configuration file was migrated, requiring manual intervention ». **`pacman` réussit** ; c'est le service qui est cassé après coup. **Un updater qui ne lit que le code de retour déclare un succès.**
- **`varnish` → `vinyl-cache`** (2026-05-25, Sven-Hendrik Haase — V1) : « The Varnish project has renamed itself to Vinyl Cache. We followed this rename with a new `vinyl-cache` package. »

> **Note de méthode, à consigner au titre de l'ADR 0002.** Ma première vérification de l'entrée `varnish` a conclu « page inexistante, probablement fabriquée » — **à tort**. Cause : l'outil de lecture a raisonné que « 2026 est dans le futur » (artefact de sa propre date de coupure) et a pris une réponse bloquée pour une absence. Une seconde récupération, en demandant le contenu brut **sans jugement de plausibilité**, a rendu titre, date, auteur et corps. **Leçon : ne jamais conclure « source fabriquée » sur un seul échec de récupération, et se méfier des outils qui jugent la plausibilité d'une date.**

### 6.2 Les clients tiers : deux modèles opposés

| Client | Escalade | Sortie | Terminal ? |
|---|---|---|---|
| **Octopi** | **`qt-sudo`** (dialogue graphique) + helper **`octphelper`** qui exécute pacman (V2) | **onglet « Output » dans l'interface** (Alt+4), terminal intégré optionnel via `qtermwidget` (V2) | **Non** |
| **bauh** | dialogue de mot de passe root + `sudo` interne ; `store_root_password` (V2) | interface | Non |
| **pacseek** (TUI) | délègue à `yay` → `sudo pacman` ; « **suspend pacseek until the execution finished** » (V2) | terminal | **Oui** |
| **pacui** | script Bash + `sudo` (V2) | terminal | **Oui** |
| **pkgbrowser** | **aucune** — « cannot be used for installing, removing or updating packages » (V2) | — | s.o. |

Sur Octopi, source datée : « **Qt-sudo is the only privilege escalation tool compatible with Octopi. It expects the user to be a member of the wheel group** » (LinuxLinks, **2025-09-16**) (V2) ; CHANGELOG v0.19.0 du **2026-04-23** « removed hardcoded qt-sudo path » (V2). **Octopi démontre que « dialogue graphique + sortie dans l'interface » est faisable** — mais `qt-sudo` est une façade de `sudo`, pas polkit.

### 6.3 Les distributions

- **CachyOS — le précédent le plus important de cette veille.** Le wiki d'après-installation liste, dans l'ordre : « Shelly (GUI & CLI) », « Using Octopi (GUI) », « Using Pacman », « Offline System Update », « Cachy-Update » (V2). **Shelly**, livré en **avril 2026**, « **replaces Octopi entirely** », « **reads real libalpm state instead of parsing terminal output, has a live install progress panel** » et « fully replaces Octopi as the default in every CachyOS installation » (fosslinux, **2026-04-28**) (R) ; le site amont confirme « directly interacts with **libalpm** … built with **GTK 4** » (V2). Un notificateur de barre `Cachy-Update` existe depuis **2025-08-25** (R).
  **Réserves explicites** : le **mécanisme d'élévation de Shelly n'est pas documenté en source primaire** (une synthèse de recherche évoquait `pkexec`, non confirmé), et sa pile est rapportée de façon contradictoire (le dépôt indique Zig 0.16.0 + Vala + GTK4, un article dit « Rust »).
- **EndeavourOS** — pas de logithèque par défaut ; le bouton « Update System » de l'application Welcome **exécute la mise à jour dans un terminal** via `eos-update` (V2) ; PackageKit/Discover/GNOME Software explicitement déconseillés (V2, §4.6).
- **Garuda** — « `garuda-update` is Garuda Linux's **preferred update solution** », « **Executing garuda-update in a terminal will start the update procedure** » (wiki, V2) ; le bouton de l'application Rani l'enveloppe dans une fenêtre Konsole (R, niveau forum). pamac **n'est plus livré par défaut** depuis le **2021-08-12** (V2).
- **Manjaro** — rétention de 1 à 2 semaines et fil d'annonce curé à la main comportant « Known issues and solutions » (R). **Filet éditorial et humain, pas technique.**
- **Hooks de nouvelles** : `informant` bloque pacman jusqu'à lecture des nouvelles, mais son projet documente que « pacman is not designed to work with an interactive pacman hook » et il **échoue** sous `--noconfirm` (R) ; **`arch-manwarn`** ne bloque que si une nouvelle correspond à « manual intervention » (R) — **l'idée de pré-vol la plus réutilisable**, à exécuter en amont dans l'interface, jamais comme hook interactif.

---

## 7. Le motif polkit pour une action longue — le constat qui change tout

### 7.1 `pkexec` : le streaming marche, le cycle de vie tue

**Ce qui marche.** `pkexec` ne ferme en exclusivité que les descripteurs **à partir de 3** (`fdwalk(set_close_on_exec, GINT_TO_POINTER(3))`) avant l'`execv()` : **les descripteurs 0/1/2 sont hérités**, donc la sortie se streame si l'appelant fournit un tube — lecture de `src/programs/pkexec.c` (V2). Et l'autorisation polkit étant évaluée **une seule fois avant** l'`execv()`, **aucune ré-authentification ne survient en cours d'opération** (V2). *(La page `pkexec(1)` (V1) est muette sur ces trois points — elle ne documente ni les flux, ni la durée, ni la mort du parent.)*

**Ce qui tue.** `pkexec` arme délibérément un signal de mort du parent :

> `/* make sure we are nuked if the parent process dies */` puis `prctl (PR_SET_PDEATHSIG, SIGTERM)` — `src/programs/pkexec.c` (V2, durcissement CVE-2011-1485).

Ce réglage **survit à l'`execv()`** final, puisque la cible (`eschaton-update`, `pacman`) est un binaire ordinaire non setuid — `prctl(2)`, Linux man-pages 6.18, **2026-02-08** : « The parent-death signal setting is cleared … when executing a set-user-ID or set-group-ID binary … ; **otherwise, this value is preserved across execve(2)** » (V2).

Et le piège décisif, même page (V2) :

> « The 'parent' in this case is considered to be **the thread that created this process** … the signal will be sent when **that thread** terminates … rather than after all of the threads in the parent process terminate. »

> **Conséquence pour Eschaton, et elle est disqualifiante.** L'interface est **Quickshell/QML, donc multi-thread**. Si le fil qui a lancé `pkexec` se termine — sans que l'application plante — le `pacman -Syu` root reçoit **SIGTERM en pleine transaction**. Pour le rollback (opération courte, déjà prouvée) le risque est négligeable ; **pour une mise à jour de plusieurs minutes, c'est le scénario catastrophe que tout le socle cherche à éviter.** S'y ajoute que le processus root reste dans le cgroup de session de l'interface, sans unité propre (V2, non documenté dans `pkexec(1)`).

**`pkexec` appelant directement `pacman` est donc écarté pour l'update.** Ce constat n'existait pas quand la première version de ce rapport a été rédigée ; il invalide la solution naïve.

### 7.2 `systemd-run` et les unités transitoires

`systemd-run(1)`, systemd 261.2-1 (V1) :

- Mode **service** (défaut) : « It will run in a clean and detached execution environment, **with the service manager as its parent process** », et l'unité « shows up in the output of `systemctl list-units` like any other unit » → **elle survit à l'interface** et s'arrête par `systemctl stop`.
- **Nuance décisive** (V2) : `--scope` est l'inverse — « it will be executed by systemd-run itself as parent process and will thus inherit the execution environment of the caller ». **Un scope ne survit pas à l'appelant. Utiliser le mode service, jamais `--scope`.**
- `--pipe` : « standard input, output, and error of the transient service **are inherited from the systemd-run command itself** » (V1) — mais le tube est alors lié à la vie du client `systemd-run`, ce qui recrée le couplage qu'on fuit. Pour une interface, préférer le **journal**.

**Le privilège**, en revanche, n'est pas documenté dans `systemd-run(1)` (V1). Il l'est dans `org.freedesktop.systemd1(5)` (V2) : « Operations which modify unit state (StartUnit(), StopUnit(), … SetProperty()) require **`org.freedesktop.systemd1.manage-units`** ».

> **Et c'est là que `systemd-run` appelé par l'utilisateur échoue sur la contrainte (c).** Le bug systemd **#17224** (V2) établit que `StartTransientUnit()` **ne transmet pas le nom de l'unité à polkit**, contrairement à `StartUnit()`. Une règle ne peut donc pas autoriser « seulement l'unité de mise à jour d'Eschaton » : accorder `manage-units` à l'utilisateur, **c'est lui donner le droit de manipuler n'importe quelle unité système** — un passe-partout, pas une porte. **Inacceptable.**

### 7.3 Le patron « démon D-Bus root + polkit » (pamac, PackageKit)

Établi en source primaire au §3.1-3.2 : activation à la demande, contrôle polkit par le service lui-même sur le nom de bus de l'appelant avec `ALLOW_USER_INTERACTION`, **progression par signaux D-Bus** (`emit_action_progress`, `emit_download_progress`, `emit_hook_progress`) et **annulation par méthode** (`trans_cancel` → `cancellable.cancel()`) — `src/daemon.vala` (V2).

C'est le seul patron qui satisfait nativement *streaming vers l'interface* **et** *annulation en session*. Son coût : un démon root, du code de service, et la surface d'attaque du §4.4.

---

## 8. Ce que cette veille n'a pas pu établir

### 8.1 La détection préalable de l'interactivité de `pacman` — **le seul trou majeur restant**

C'est le cœur technique de toute solution zéro-terminal, et l'axe qui n'a pas abouti.

**Manque :**
- Le **texte exact et la réponse par défaut** de chaque invite : remplacement (`:: Replace X with repo/Y? [Y/n]`), conflit (`:: X and Y are in conflict. Remove Y? [y/N]`), sélection de fournisseur, import de clé PGP.
- **Ce que `--noconfirm` répond à chacune**, en particulier le fournisseur retenu. *(Le défaut « premier fournisseur » de `libpamac` (§3.3) est un indice, pas une preuve.)*
- Confirmation que pacman **n'interroge pas** sur les `.pacnew` (§5.2 reste « à confirmer »).
- **Le chemin libalpm** : `alpm_trans_prepare()` remplit-il une liste de conflits (`alpm_conflict_t`) et de dépendances manquantes **avant** le commit ? Si oui, **c'est la voie propre du pré-vol**, et elle change la conception. À lire dans `alpm(3)` et les sources pacman. *(Shelly, §6.3, prouve qu'attaquer `libalpm` directement est faisable et livré.)*
- Si les conflits de **fichiers** (cas `linux-firmware`) sont détectables avant extraction. *Mon hypothèse est « non », **non vérifiée**.*

### 8.2 Points secondaires à contrôler

- **PackageKit (§4)** : constats (R) cohérents et datés, à spot-checker sur les deux qui décident — le **`allow_active=yes`** de `system-update` (lecture directe du fichier de politique) et la **CVE-2026-41651**.
- **Shelly (§6.3)** : **mécanisme d'élévation non documenté en source primaire** — c'est pourtant le précédent le plus proche de notre besoin. À instruire.
- **pamac** : état canonique sur `gitlab.manjaro.org` (hôte injoignable pendant la passe) ; date exacte du portage GTK4.
- **Journal et droits de lecture** : qu'un utilisateur non privilégié puisse suivre `journalctl -u <unité>` d'une unité **système** dépend de son appartenance à `systemd-journal`/`adm`. **Non vérifié**, et c'est une dépendance directe de la recommandation (§9.2).
- **`systemd-run` exécuté par root** : qu'il ne déclenche aucun contrôle polkit (root étant déjà autorisé) est **hautement probable mais non vérifié**. Dépendance directe de la recommandation.

---

## 9. Recommandation

### 9.1 Les options écartées, et pourquoi

| Option | Verdict |
|---|---|
| **A — PackageKit + GNOME Software / Discover** | **Écartée.** `allow_active=yes` sans authentification (§4.3), rédhibitoire et contraire à une décision déjà écrite d'Eschaton. S'y ajoutent le retard d'ABI (§4.2), la CVE 2026 (§4.4), le hors-ligne cassé et inadapté (§4.5), et le déconseil général (§4.6). |
| **B — pamac comme dépendance** | **Écartée**, malgré une architecture juste et de vraies modales pour les décisions de pacman (§3.3). Motifs : l'épinglage `libalpm.so=16` **a déjà bloqué une mise à jour de pacman** (§3.4), `libpamac` est compilé donc hors `arch=(any)`, et il ajoute un démon root permanent. **Retenue comme référence de conception, pas comme dépendance.** |
| **C — `pkexec` appelant directement `pacman`** | **Écartée par le §7.1** : `PR_SET_PDEATHSIG=SIGTERM` lié au **fil** appelant → risque de SIGTERM en pleine transaction depuis une interface QML multi-thread. *C'était la solution évidente ; les sources la condamnent.* |
| **D — `systemd-run --system` appelé par l'utilisateur** | **Écartée par le §7.2** : exige `org.freedesktop.systemd1.manage-units`, que le bug #17224 empêche de restreindre à une seule unité. **Un passe-partout sur toutes les unités système** — contrainte (c) violée. |

### 9.2 Option retenue — `pkexec` comme porte unique, `systemd` comme porteur de la transaction

**Principe : garder la porte déjà prouvée sur ce système, et lui faire déléguer immédiatement l'exécution à systemd — de sorte que la transaction ne dépende plus du cycle de vie de l'interface.**

1. **Porte privilégiée unique** — une action polkit `org.eschaton.update` calquée sur `org.eschaton.rollback` (§2.2) : `allow_any=no`, `allow_inactive=no`, **`allow_active=auth_admin` sans `_keep`** (motivé au §4.3), plus l'annotation `org.freedesktop.policykit.exec.path` vers `/usr/bin/eschaton-update`. **`sudo` disparaît du chemin graphique** — contraintes (b) et (c) tenues.
2. **Interface privilégiée minuscule** — reprendre littéralement la règle de `lib.sh` (« pkexec authentifie le PROGRAMME, pas ses arguments ») : n'accepter qu'un jeu de formes exactes (`--apply`, `--cancel`), refuser tout le reste, exiger `EUID==0`.
3. **La transaction est portée par systemd, pas par `pkexec`** — une fois root, le script lance la transaction dans une **unité transitoire en mode service** (`systemd-run --system --unit=eschaton-update …`). Étant **déjà root**, il ne déclenche aucun contrôle `manage-units` : **l'utilisateur ne reçoit jamais ce droit**, ce qui évite le passe-partout du §7.2. `pacman` a alors **PID 1 pour parent** : il est immunisé contre la mort d'un fil de l'interface (§7.1), survit à un redémarrage du shell, et s'arrête proprement par `systemctl stop`.
4. **Sortie visible** — l'unité journalise ; l'interface suit le journal et affiche la progression dans le popout, à la place du terminal. *(Le widget lit déjà un flux de `Process` pour `checkupdates` (V1) : le mécanisme d'affichage existe.)*
5. **Annulation** — par la même porte, forme `--cancel`, qui fait `systemctl stop` de l'unité. Pas de second chemin privilégié.
6. **Suppression de l'auto-approve** — **retirer `--yes`/`--noconfirm` du chemin graphique** (§2.1). Correction due indépendamment du reste, au titre de la contrainte (d).
7. **Packaging** — script shell + QML + XML de politique : **`arch=(any)` conservé**, contrainte (f) tenue.

**Vérification des contraintes** : (a) zéro terminal ✓ — modale polkit + sortie dans l'interface ; (b) une seule porte ✓ ; (c) pas de second chemin ✓ — le droit `manage-units` n'est jamais accordé à l'utilisateur ; (d) pas d'auto-approve ✓ — `auth_admin` sans `keep`, `--noconfirm` retiré ; (e) sortie visible ✓ ; (f) `arch=(any)` ✓.

### 9.3 Ce dont elle dépend, et ce qui la ferait basculer

| Dépendance | Statut | Bascule |
|---|---|---|
| `systemd-run` exécuté **par root** ne déclenche aucun contrôle polkit | **Non vérifié** (§8.2) — probable | Si un contrôle survenait malgré tout, revenir à un démon D-Bus maison (option E ci-dessous). |
| L'utilisateur peut **suivre le journal** d'une unité système | **Non vérifié** (§8.2) | Repli : faire écrire l'unité dans un fichier de trace lisible, ou passer par un canal explicite. Ne pas ajouter de privilège pour lire. |
| **Le pré-vol d'interactivité** | **Trou ouvert** (§8.1) | Si `alpm_trans_prepare()` expose conflits et remplacements avant commit, le pré-vol devient fiable et la porte de secours (§9.4) se déclenche bien plus rarement. **Travail à faire en premier.** |

**Option E, si les deux premières dépendances tombent** : écrire un **petit service D-Bus activé à la demande** sur le modèle pamac (§7.3) — progression par signaux, annulation par méthode, contrôle polkit sur `org.eschaton.update`. C'est l'aboutissement propre, au prix d'un vrai composant de service (et probablement de la perte d'`arch=(any)` s'il est compilé). **Ne pas s'y engager avant d'avoir tenté 9.2**, qui obtient l'essentiel avec un script.

**Ce qui rouvrirait l'option B** : rien à court terme. L'épinglage de soname (§3.4) est structurel.

### 9.4 Comment cette recommandation se comporte face au point dur — réponse honnête

**Elle ne résout pas le cas de la décision humaine, et aucune architecture ne le résout.** Le cas `linux-firmware` (§5.3) le prouve : `pacman -Syu` s'arrête et la sortie exige `-Rdd` puis une réinstallation. Ce n'est pas un défaut de l'option retenue — c'est une propriété d'Arch. **Ce cas nécessitera une porte de secours**, et il faut l'assumer dans la spec plutôt que de le découvrir en production.

| Situation | Comportement |
|---|---|
| Transaction propre (l'immense majorité) | Modale polkit → transaction portée par systemd → sortie streamée dans le panneau → instantanés `snap-pac` avant/après. **Zéro terminal, bout en bout.** |
| Transaction qui pose une question (conflit, remplacement, fournisseur) | Sans `--noconfirm`, `pacman` **attend sur l'entrée standard**. Il faut **détecter et s'arrêter proprement** plutôt que laisser pendre. **La forme de ce garde-fou dépend du §8.1 et n'est pas arrêtée ici.** Certitude : on **n'ajoute pas `--noconfirm`** pour faire disparaître le symptôme. **Leçon de pamac (§3.3) : un composant sans surface de dialogue choisit silencieusement — c'est précisément ce qu'il faut refuser.** |
| Transaction qui s'arrête (type `linux-firmware`) | Échec. L'interface affiche **la sortie exacte de pacman** et la nouvelle Arch correspondante, sans la paraphraser. **Porte de secours assumée**, explicite et rare — hors du parcours nominal. |
| Transaction qui réussit mais casse un service (type `dovecot`) | **Non détecté par le code de retour.** Un contrôle post-transaction des unités en échec est à prévoir (§6.1). |
| `.pacnew` produits | Aucune surface aujourd'hui ; dette qui s'accumule (§5.2) sur trois fichiers d'`eschaton-base`. |

**Deux atouts qu'Eschaton possède déjà et qui rendent cette position tenable** — et qui manquent à toutes les distributions du §6 : `snap-pac` prend un instantané **avant et après chaque transaction**, et **le rollback est déjà graphique et prouvé**. Une mise à jour qui échoue n'est donc pas une impasse : c'est un retour arrière en quelques clics.

**Pré-vol recommandé** : reprendre l'idée d'`arch-manwarn` (§6.3) — vérifier les nouvelles Arch pour le motif « manual intervention » **avant** de lancer la transaction, dans l'interface, et prévenir l'utilisateur. **Jamais comme hook interactif de pacman**, dont `informant` documente l'échec sous `--noconfirm`.

**Formulation défendable du différenciateur au 2026-08-29** : *Eschaton ne promet pas que toute mise à jour réussira sans terminal — personne ne peut le promettre sur Arch, et CachyOS lui-même ne le promet pas. Elle promet que le cas courant est graphique de bout en bout, et que l'échec est visible, réversible et sans ligne de commande pour en sortir.*

---

## 10. Table des risques (2026-08-29)

| # | Risque | Probabilité | Impact | Statut / parade |
|---|---|---|---|---|
| 1 | **Le chemin graphique actuel est auto-approuvé** (`--yes` → `--noconfirm`) en plus du mot de passe au terminal | **Avéré** | Élevé — contredit (d) et la posture écrite du socle | **Correction due** : retirer `--yes` (§9.2 point 6). Indépendant du reste. |
| 2 | **`pkexec` SIGTERM en pleine transaction** si le fil appelant se termine | **Élevée** avec une interface QML multi-thread | **Critique** — transaction pacman interrompue | **Parade retenue** : déléguer la transaction à une unité systemd (§9.2 point 3). Ne jamais laisser `pacman` être l'enfant direct de `pkexec`. |
| 3 | Une transaction exige une décision humaine et l'interface reste bloquée sur l'entrée standard | Moyenne à élevée | Élevé — interface figée | Garde-fou à concevoir ; **dépend du §8.1**. Ne pas « résoudre » par `--noconfirm`. |
| 4 | Une intervention manuelle annoncée arrête `-Syu` (archétype `linux-firmware`) | **Certaine à l'échelle d'une année** — au moins 8 entrées entre 2024-07 et 2026-07 | Moyen | Porte de secours explicite + pré-vol sur les nouvelles Arch (§9.4). Filet : `snap-pac` + rollback graphique. |
| 5 | Une mise à jour « réussit » mais casse un service (type `dovecot` 2.4) | Faible à moyenne | Moyen — succès annoncé à tort | Contrôle post-transaction des unités en échec. **Non conçu.** |
| 6 | Accorder `manage-units` à l'utilisateur donnerait un passe-partout sur toutes les unités (bug systemd #17224) | — | Élevé | **Option D écartée** ; `systemd-run` n'est appelé **que par root** (§9.2). |
| 7 | L'utilisateur ne peut pas lire le journal de l'unité système | Inconnue | Moyen — casse la contrainte (e) | §8.2 à instruire ; repli par fichier de trace, **sans ajouter de privilège**. |
| 8 | Dépendre de pamac ferait bloquer une mise à jour de pacman par l'épinglage de soname | **Avérée par précédent** (BBS 2024-09-15) | Élevé | **Option B écartée** (§3.4). |
| 9 | Un composant sans surface de dialogue choisit silencieusement (premier fournisseur, aucune clé) | **Avérée sur `libpamac`** | Élevé — auto-approve involontaire | Exiger que toute décision remonte à l'interface ou arrête la transaction (§9.4). |
| 10 | Adopter PackageKit réintroduirait une autorisation sans mot de passe | — | Rédhibitoire | **Option A écartée** (§4.3). |
| 11 | Un démon root permanent est une surface d'attaque (CVE-2026-41651 sur `packagekitd`) | — | Élevé | Options A et B écartées ; l'option E (§9.3) devra en tenir compte si on y vient. |
| 12 | Accumulation silencieuse de `.pacnew` (3 fichiers `backup=` d'`eschaton-base`) | Élevée dans la durée | Moyen — dérive de configuration | Aucune surface prévue. À traiter dans la spec. |
| 13 | **Le pré-vol d'interactivité reste non instruit** | **Avéré** | Élevé si la spec est écrite maintenant | **Ne pas clore la spec avant d'avoir traité le §8.1.** |
| 14 | Risque de méthode : conclure « source fabriquée » sur un échec de récupération | **Avéré une fois dans cette passe** (§6.1) | Moyen — une source réelle a failli être écartée | Recouper sur deux canaux avant d'écarter une source. |

---

## 11. Ce qu'il faut faire ensuite, par ordre de rendement

1. **§8.1 — le pré-vol libalpm.** `alpm_trans_prepare()` donne-t-il conflits et remplacements avant le commit ? Décide si l'update graphique peut être *sûr* ou seulement *optimiste*. **Shelly (CachyOS) prouve que la voie libalpm est praticable et livrée** — la regarder de près.
2. **Correction immédiate, sans attendre la spec** : retirer `--yes` du chemin graphique (risque 1) — auto-approve non voulu et non tracé.
3. **Les deux vérifications dont dépend la recommandation** (§8.2) : `systemd-run` appelé par root ne déclenche pas de contrôle polkit ; lecture du journal par l'utilisateur non privilégié.
4. **Le mécanisme d'élévation de Shelly** (§6.3) — précédent le plus proche de notre besoin, non documenté en source primaire.
5. **§8.2** — spot-check des deux constats PackageKit qui portent la décision (`allow_active=yes`, CVE).
