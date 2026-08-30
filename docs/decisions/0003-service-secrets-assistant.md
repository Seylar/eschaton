# ADR 0003 — Le trousseau de l'Assistant appartient à la session, pas au plugin

- **Date** : 2026-08-28
- **Statut** : **accepté le 2026-08-28** (adjudication contrôleur, amendements §8)
- **Portée** : sous-projet 3 (Assistant), intégration de session Eschaton
- **Contexte amont** : [Spec de l'Assistant](../superpowers/specs/2026-08-28-assistant-design.md) §2

---

## 1. Problème découvert en VM

La spec prévoit de conserver les clés des fournisseurs distants avec `secret-tool`, fourni par `libsecret`. Le test réel de la tâche 4 dans la VM Arch Linux a invalidé une hypothèse implicite : **installer `libsecret` ne fournit pas de trousseau**.

`libsecret` et `secret-tool` sont des clients du protocole freedesktop **Secret Service**. Ils ont besoin d'un service D-Bus qui implémente ce protocole. Sans backend, l'appel échoue :

```text
secret-tool: The name is not activatable
```

Le code du plugin n'est pas en cause dans cet échec. L'environnement de session ne fournit simplement aucun service de secrets.

## 2. Pourquoi `gnome-keyring` sous Hyprland

`gnome-keyring` est un nom trompeur dans ce contexte : le paquet ne force ni GNOME Shell, ni Mutter, ni une session GNOME. Son démon peut fonctionner dans une session Hyprland et fournit précisément l'implémentation Secret Service attendue par `libsecret`.

L'installer dans Eschaton est donc techniquement cohérent. En revanche, en faire une dépendance directe du plugin Assistant serait une mauvaise séparation des responsabilités :

- le plugin consomme l'API Secret Service via `libsecret` ;
- la session Eschaton choisit, démarre et déverrouille un backend compatible ;
- l'authentification de session, via greetd/PAM, doit permettre le déverrouillage du trousseau.

Autrement dit, le backend est une capacité du bureau, pas une bibliothèque privée de l'Assistant.

## 3. Blocage réel : l'autologin

Après installation de `gnome-keyring` dans la VM, D-Bus sait lancer `gnome-keyring-daemon`. Le stockage ne devient toutefois pas transparent : Eschaton démarre actuellement Hyprland par une `initial_session` greetd sans saisie de mot de passe.

Le trousseau de connexion ne reçoit donc aucun secret de PAM avec lequel se déverrouiller. Au premier accès, `secret-tool` déclenche une invite graphique de création ou de déverrouillage. Un appel non interactif peut rester bloqué dans l'attente de cette invite.

Ce résultat interdit deux raccourcis :

1. déclarer que `gnome-keyring` suffit parce que le paquet est installé ;
2. déclarer la tâche validée uniquement parce que le démon D-Bus démarre.

La chaîne complète doit être éprouvée : démarrage de session, déverrouillage, écriture, lecture et suppression.

## 4. Options examinées

| Option | Avantage | Limite | Avis |
|---|---|---|---|
| `gnome-keyring` | Backend Secret Service standard, utilisable sans bureau GNOME, intégrable à PAM | Le déverrouillage automatique exige une vraie authentification de session | Choix proposé pour Eschaton |
| KeePassXC | Implémente Secret Service | Imposerait une application, une base et son déverrouillage ; mauvais backend système par défaut | À laisser comme choix utilisateur éventuel |
| KWallet | Backend de secrets mature | Introduit une pile KDE sans bénéfice particulier sous Hyprland | Rejeté par défaut |
| Fichier chiffré ou stockage maison | Contrôle total apparent | Gestion des clés maîtresses, permissions, rotation et prompts à réinventer ; surface de sécurité inutile | Rejeté |
| Clé en configuration ou variable persistante | Simple | Secret en clair et facilement exfiltrable | Interdit |

## 5. Décision proposée

1. Le paquet du plugin Assistant conserve `libsecret` et n'embarque aucune implémentation de trousseau.
2. La couche bureau/session Eschaton fournit `gnome-keyring` comme backend Secret Service par défaut.
3. Le futur greeter authentifié configure le module PAM de `gnome-keyring` pour déverrouiller le trousseau de connexion avec la session.
4. Tant que l'autologin est conservé, l'interface doit annoncer honnêtement qu'une invite de création ou de déverrouillage peut apparaître. Le pont QML doit aussi borner l'attente et rapporter l'échec, jamais rester bloqué indéfiniment.
5. Le plugin continue de passer les secrets à `curl` par l'environnement du processus, jamais dans les arguments, les logs ou un fichier de configuration.

Cette décision ne prétend pas résoudre aujourd'hui le déverrouillage PAM : elle fixe la bonne frontière architecturale et rend la dette explicite.

## 6. Critères de validation

L'intégration est terminée seulement lorsque les preuves suivantes passent dans une session VM fraîche :

1. un backend Secret Service est disponible sans commande manuelle dans un terminal ;
2. le premier stockage suit un parcours graphique compréhensible ;
3. après une connexion authentifiée, le trousseau se déverrouille par PAM sans redemander le mot de passe ;
4. `secret-tool store`, `lookup` et `clear` passent de bout en bout ;
5. l'annulation ou l'absence de backend produit une erreur bornée et exploitable dans l'UI ;
6. aucun secret n'apparaît dans `ps`, les journaux, les arguments de processus ou les fichiers de configuration ;
7. le packaging et le comportement sont vérifiés sur x86_64 et aarch64.

## 7. Conséquence pour la tâche 4

Le test VM a rempli son rôle : il a trouvé une dépendance de session absente et un conflit avec l'autologin avant que le faux sentiment de sécurité n'entre sur `main`.

La tâche 4 peut livrer le catalogue de fournisseurs, le pont `libsecret`, la gestion des erreurs et la documentation de cette dette. Elle ne doit en revanche pas revendiquer un déverrouillage transparent tant que l'intégration greetd/PAM n'a pas été mise en place et testée.

## 8. Adjudication (contrôleur, 2026-08-28)

Décision **validée** — la frontière est la bonne et le test VM a fait exactement son travail. Trois amendements contraignants :

1. **Véhicule concret** : `gnome-keyring` entre dans les `depends` du meta `eschaton-desktop` (bump), pas ailleurs — c'est la « couche bureau » du §5.2 rendue vérifiable ; la garde CI `check-desktop-deps` couvre la nouvelle dépendance (vérifié par la veille SP3 : `extra`, les deux architectures).
2. **Le mot de passe vide est un piège nommé** : sous autologin, l'invite de création propose un trousseau sans mot de passe — qui stocke alors les secrets **en clair au repos** (`~/.local/share/keyrings/*.keyring` lisible). L'UI honnête du §5.4 doit le dire explicitement (recommandation : définir un mot de passe de trousseau, saisi une fois par session jusqu'à l'arrivée du déverrouillage PAM) ; et le critère §6.6 s'étend : « …ni stocké dans un trousseau à mot de passe vide sans avertissement affiché ».
3. **La dette PAM est tracée côté SP4** : le greeter authentifié du sous-projet 4 hérite d'une exigence ferme — module PAM `gnome-keyring` configuré, déverrouillage au login prouvé (critère §6.3 rejoué à ce moment-là). Consigné dans la spec Assistant §8.
