# SP4c : connexion, trousseau et verrouillage

Date : 2026-09-07. **Proposition pour revue, non validée.**
Veille : [sources et paquets vérifiés le même jour](../../veille/2026-09-07-premiere-session.md).
Références : ADR 0002, ADR 0003 §8, RESTE-A-FAIRE §3.1.

## Résultat attendu

Un compte créé par l'installeur, quel que soit son nom, arrive sur une connexion
graphique. Son mot de passe ouvre la session Eschaton et déverrouille son
trousseau protégé. Le bureau peut être verrouillé puis déverrouillé sans
terminal. Un refus d'authentification ne doit jamais ouvrir le bureau.

Le compte `seylar` ne doit plus être codé dans un paquet. Ni auto-login, ni
création silencieuse d'un trousseau vide, ni clé d'API dans un fichier de config.

## Proposition d'architecture

1. Conserver greetd et le point d'entrée `/usr/bin/eschaton-session`.
2. Éprouver **ReGreet + Cage**, disponibles sur les deux architectures, comme
   premier greeter graphique. DankGreeter reste une alternative si la revue
   préfère assumer son packaging séparé et son intégration DMS 1.6.
3. Retirer `[initial_session]` du défaut livré par Eschaton. Le greeter tourne
   comme compte système, puis greetd ouvre la session de l'utilisateur choisi.
   L'entrée `.desktop` Eschaton reste l'unique commande de session.
4. Faire posséder les configs par des paquets, pas par `dms-greeter install`,
   `dms auth sync` ou un script de migration. Ne pas écraser les fichiers PAM
   possédés par greetd ou pambase. Premier spike : confirmer qu'un service PAM
   propre peut être sélectionné par la version installée de greetd. Sinon,
   présenter le conflit de propriété en revue avant de modifier l'architecture.
5. Intégrer `pam_gnome_keyring` après l'authentification par mot de passe et dans
   la session. Backend fourni par `eschaton-desktop`, client `libsecret` dans
   le plugin : frontière de l'ADR 0003 conservée. Une panne du trousseau laisse
   le bureau accessible mais rend l'assistant distant indisponible avec un
   message d'erreur, sans repli vers un stockage en clair.
6. Utiliser le verrou DMS avec sa politique PAM vérifiée séparément. Exposer
   « Verrouiller » dans la session et un raccourci clavier explicite. Éprouver
   le verrouillage avant suspension par le mécanisme logind/compositeur retenu,
   avec accusé de verrouillage ; ne pas se contenter d'un délai arbitraire.

Les trois paquets de configuration Eschaton restent `arch=(any)` ; les
programmes natifs viennent des dépôts vérifiés. Aucune dépendance ne change
avant validation de la proposition.

## Parcours et cas d'erreur

- **Compte neuf** : choix du compte, mot de passe, bureau ; aucun autre compte
  n'est ouvert automatiquement. Tester un nom différent de `seylar`.
- **Mauvais mot de passe** : message clair, champ resaisissable, bureau masqué.
  Respecter la politique de tentatives PAM, ne pas la contourner dans l'UI.
- **Trousseau neuf** : vérifier création protégée, écriture, lecture, suppression,
  puis lecture après reconnexion. Employer un secret de test, jamais une clé
  fournisseur réelle dans les preuves.
- **Ancien trousseau vide** : proposer explicitement de lui donner un mot de
  passe via un outil graphique éprouvé. Pas de conversion silencieuse, pas de
  suppression du trousseau, pas d'annonce « protégé » avant vérification.
  Cette étape est un parcours utilisateur, pas une migration de paquet.
- **Mot de passe différent ou changé** : conserver le trousseau et ses données,
  expliquer le déverrouillage manuel. Éprouver séparément le changement de mot
  de passe et la mise à jour du secret du trousseau par PAM.
- **Verrouillage** : l'assistant et les autres fenêtres ne sont pas accessibles ;
  un refus ou une panne du verrou ne révèle pas le contenu. Le greeter et le
  verrou ne doivent jamais conserver le mot de passe dans un journal ou argv.
- **Déconnexion** : arrêter les services attachés à la session, puis permettre
  une nouvelle connexion ; pas d'autologin de repli.

Le fond d'écran et les libellés suivent Eschaton, le reste conserve les
composants familiers du greeter. Aucun accès du compte greeter aux clés ou à
l'ensemble du home n'est nécessaire pour afficher ce fond système.

## Mise à jour des machines existantes

`/etc/eschaton/greetd.toml` est déjà déclaré dans `backup=()`. Un simple bump
peut produire un `.pacnew` si le fichier a été personnalisé. Il ne garantit
**pas** la disparition de l'auto-login sur ces machines.

Deux chemins à prouver : installation neuve avec nouveau défaut ; compte
existant avec configuration locale préservée et adoption explicite du nouveau
réglage. La revue doit choisir le parcours graphique d'adoption avant de
prétendre que SP4c est terminé pour les installations existantes.

Un rollback peut restaurer les anciennes configs de connexion, alors que
`@home` conserve le trousseau récent. Tester cette combinaison et annoncer
clairement le retour éventuel à une ancienne politique ; ne pas promettre
qu'un snapshot est neutre pour la sécurité de session.

## Critères de validation

- [ ] Paquets installables sur aarch64 et x86_64, versions consignées.
- [ ] Propriété des configs et ordre PAM vérifiés sur les fichiers installés.
- [ ] Compte neuf avec autre nom : login valide, refus invalide, déconnexion.
- [ ] Trousseau neuf protégé, ancien vide et ancien à mot de passe différent.
- [ ] Store / lookup / clear après reconnexion ; aucune fuite du secret de test.
- [ ] Changement du mot de passe de session, puis reconnexion et trousseau.
- [ ] Verrouillage manuel, mauvais mot de passe, reprise, crash du processus de
      verrouillage, arrêt/redémarrage DMS, changements de VT.
- [ ] Verrou avant suspension et au retour, vérifié avec logind ; réserve
      matérielle explicite si la VM ne permet pas de conclure.
- [ ] Ancienne config modifiée : préservation, `.pacnew`, adoption utilisateur.
- [ ] Rollback vers une version antérieure : login et trousseau encore récupérables.
- [ ] CI et builds verts, preuves numérotées dans `tools/vm-dev.md`.

## Ordre d'exécution proposé après revue

1. Spike isolé des versions, du greeter et de la propriété PAM ; aucune bascule
   durable avant preuve de retour à la session actuelle.
2. Paquets et fin de l'auto-login sur compte neuf ; tests de refus.
3. Trousseau protégé et parcours d'adoption des comptes existants.
4. Verrouillage et suspension ; tests de crash et de reconnexion.
5. Build bi-architecture, revue, puis adoption volontaire en dogfooding.

Hors périmètre : clé de signature, licence/publication de l'ISO, installation
T2 réelle, biométrie, LUKS, gaming. Les vetos du registre restent ouverts.
