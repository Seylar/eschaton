# SP4c : veille avant conception

Date : 2026-09-07. Statut : sources et disponibilité des paquets vérifiées ;
connexion, chiffrement du trousseau et verrouillage non validés de bout en bout.

## Terrain

La VM `eschaton-dev` démarre et sa console série répond. Relevé réel :
`systemd 261.2-1`, `dms-shell 1.5.3-1`, `quickshell 0.3.1-1`,
`greetd 0.10.3-2`, `gnome-keyring 1:50.0-1`. DMS est actif.

Les index de paquets, contrôlés par `tools/check-desktop-deps`, donnent :

| Paquet | Arch x86_64 | ALARM aarch64 |
|---|---|---|
| dms-shell | 1.6.0-2 | 1.6.0-2 |
| greetd | 0.10.3-2 | 0.10.3-2 |
| gnome-keyring | 1:50.0-1 | 1:50.0-1 |
| greetd-regreet | 0.5.0-1 | 0.5.0-1 |
| cage | 0.3.1-1 | 0.3.1-1 |
| hyprland | 0.56.2-2 | 0.56.1-3 |

Ce contrôle prouve la publication des dépendances directes, pas leur
installation ni leur fonctionnement. `pacman -Si` sur une cible x86_64
actualisée reste à jouer. Ne pas confondre DMS installé et documentation 1.6.

## Options de greeter

[DMS 1.6](https://danklinux.com/docs/dankgreeter/) présente un greeter séparé,
`dms-greeter`. Sa [documentation d'installation](https://danklinux.com/docs/dankgreeter/installation)
passe sur Arch par l'AUR ; les anciens appels `dms greeter` sont dépréciés.
Les commandes d'installation/synchronisation modifient aussi configuration et
permissions. Les rejouer depuis un hook de paquet Eschaton contredirait notre
propriété déclarative des fichiers. Le packaging bi-architecture de ce greeter
n'est pas validé par le contrôle de `dms-shell`.

[ReGreet](https://github.com/rharish101/ReGreet) utilise GTK, permet de choisir
un compte et une session, et documente Cage comme compositeur du greeter.
Les deux paquets candidats existent des deux côtés. ReGreet est moins cohérent
visuellement avec DMS, mais évite un nouveau binaire maison à maintenir.
Recommandation pour le premier spike : ReGreet + Cage. Le choix reste proposé.

## Authentification et secrets

Le [module PAM GNOME Keyring](https://wiki.gnome.org/Projects/GnomeKeyring/Pam/Manual)
réutilise le mot de passe fourni par un module précédent. Sans mot de passe,
il peut réussir sans déverrouiller quoi que ce soit : un code PAM positif ne
prouve donc pas le déverrouillage. Le compte existant peut aussi avoir un
trousseau à mot de passe vide ou différent ; ajouter PAM ne prouve pas que cet
ancien fichier a été chiffré.

La [politique du greeter DMS](https://danklinux.com/docs/dankgreeter/authentication)
et celle du [verrouillage DMS](https://danklinux.com/docs/dankmaterialshell/lock-screen-authentication)
sont séparées. La documentation 1.6 prévoit un mode où le système possède la
politique PAM. Il faudra vérifier son équivalent sur la version réellement
retenue ; une intégration du login ne valide pas automatiquement le verrou.

Le [code actuel de greetd](https://github.com/kennylevinsen/greetd/blob/master/greetd/src/config/mod.rs)
expose `general.service`. Sa disponibilité dans le paquet 0.10.3 doit être
confirmée avant de prévoir un service PAM Eschaton distinct : ne pas transposer
une capacité de `master` à une version publiée sans preuve.

## Verrouillage et reprise

L'[IPC DMS](https://danklinux.com/docs/dankmaterialshell/keybinds-ipc)
expose `lock lock` et `lock isLocked`. Cela fournit un point d'entrée, pas une
preuve de verrouillage résistant au crash ni de verrouillage avant suspension.
Ces deux propriétés exigent des tests du compositeur et de logind en VM,
puis sur matériel pour la suspension réelle.

Pour la correction de provisioning indépendante de SP4c, la
[documentation systemd](https://github.com/systemd/systemd/blob/main/man/systemd.service.xml)
autorise `Restart=on-failure` sur les services oneshot. La limite de démarrage,
le délai et l'arrêt avec la session restent explicites dans l'unité Eschaton.

## Risques et portes de sortie

- DMS 1.6 n'est pas la version de la preuve Bureau : rejouer l'intégration
  avant d'affirmer la compatibilité, y compris pour les trois plugins.
- Une erreur PAM peut empêcher le login : conserver une console de secours
  pendant les essais et ne pas toucher à sa pile d'authentification.
- Pas de conclusion de santé des mainteneurs à partir d'un numéro de version.
  Relever les tags/commits retenus et leur activité au spike.
- Pas de biométrie dans ce lot : aucun matériel de preuve, aucun mot de passe
  récupérable pour déverrouiller automatiquement le trousseau.
- Le chiffrement du trousseau ne remplace pas LUKS, ne protège pas une session
  déjà ouverte et ne révoque pas une clé éventuellement exposée auparavant.
