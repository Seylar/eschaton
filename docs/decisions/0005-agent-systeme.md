# ADR 0005 — Un expert intégré au système

- Date : 2026-09-07.
- Statut : **cap produit et niveau d'autonomie actés par le pilote**.
  Architecture ci-dessous proposée pour l'implémentation ; non livrée.
- Source : clarification de Seylar dans la conversation de reprise : réparer
  les paquets, traiter les problèmes de sécurité, personnaliser le bureau et
  disposer en plus de son agent généraliste préféré. Référence exprimée :
  l'idée d'un « Hermes OS ».
- Réponse explicite sur l'autonomie : « Il détecte et corrige seul les problèmes
  courants réversibles ; il me sollicite pour les changements importants. »
- Veille : [constats et sources](../veille/2026-09-07-agent-systeme.md).

## Écart avec la v1

La sidebar, les trois outils fixes et l'interdiction d'agir après une collecte
de statut ne satisfont pas le besoin. La PR 8 fournit une connexion Codex utile,
mais pas un expert système : l'orchestration vit encore dans QML, les tâches
ne survivent pas au shell et les moyens d'action sont trop limités. Les anciens
critères « Assistant terminé » décrivent uniquement la v1.

## Décision produit

Un seul produit offre deux usages : entretenir/personnaliser la machine, et
réaliser les autres tâches de l'utilisateur avec son agent préféré. Ils
partagent les intégrations de fournisseurs et l'expérience, avec des droits,
un contexte et une mémoire adaptés à chaque tâche. Une conversation générale
n'hérite pas automatiquement d'un mandat d'administration.

Une demande déclenche une boucle complète : **observer → diagnostiquer →
préparer → exécuter → vérifier → terminer ou récupérer**. L'agent peut consulter
des sources, utiliser des outils et adapter son plan ; l'exécution ne se limite
pas à choisir entre trois boutons. Il conserve la provenance des observations,
l'historique des interventions et les préférences utiles à la machine.

L'agent reçoit aussi des événements système sans attendre un message dans le
chat. Les collecteurs locaux détectent des signaux vérifiables ; ils regroupent
les incidents et ne font pas tourner un LLM en continu pour surveiller un log.
L'utilisateur voit surtout les résultats, les échecs et les décisions requises.

## Architecture proposée

1. **Service agent indépendant de DMS**, exécuté sous l'identité utilisateur.
   Il conserve les tâches, leurs étapes et leur état sur disque ; reconnexion
   du panneau, redémarrage du shell et reprise d'un travail sont distincts.
2. **Observateurs système** : santé des unités, état des transactions de
   paquets, espace disponible, configuration et signaux de sécurité sourcés.
   Chaque événement porte une origine, un horodatage et un périmètre ; les
   doublons n'ouvrent pas une série de réparations concurrentes.
3. **Moteur agent et intégrations** : réutiliser les capacités du runtime Codex
   officiel pour le premier parcours. Extraire le transport et l'orchestration
   du plugin ; qualifier séparément le parcours d'abonnement Claude. Le moteur
   généraliste conserve les outils nécessaires aux tâches de fichiers/projets.
   Le choix du modèle ne doit pas imposer un autre système d'autorisations.
4. **Exécution et politique locales** : moyens extensibles de diagnostic,
   modification de fichiers, réglages, services et paquets. Les outils standard
   de l'agent opèrent dans le périmètre de sa tâche. Les opérations nécessitant
   davantage de droits passent par une porte dédiée qui vérifie le mandat et
   les préconditions, indépendamment du texte produit par le LLM.
5. **Changements vérifiables** : état préalable, périmètre annoncé, verrou,
   sauvegarde adaptée, effet attendu, exécution, contrôle indépendant et
   récupération. Une mise à jour globale Arch n'est pas assimilée à une petite
   correction de fichier ; un snapshot Btrfs ne garantit pas de restaurer les
   données externes, l'ESP ou un service tiers.
6. **Interfaces natives** : conversation, recherche d'action, réglages,
   notification d'incident et historique des interventions interrogent le même
   service. Le chat reste aussi disponible pour les usages libres.

Hermes constitue une référence à évaluer pour les tâches, outils et mémoire.
Cette analogie ne décide ni de l'installation d'Hermes ni du remplacement du
runtime Codex. Le choix d'un framework demande une comparaison de terrain,
notamment sur les abonnements, la reprise des tâches et les droits système.

## Autonomie actée et traduction technique à réaliser

Une réparation automatique exige un mandat existant et un périmètre connu,
une précondition observable, une récupération réellement disponible et un
contrôle du résultat. Une correction inconnue ou un changement dont l'impact
est incertain demande une décision. Le modèle ne peut pas déclarer son propre
plan « sans risque » pour l'autoriser.

| Situation | Comportement cible |
|---|---|
| Réglage utilisateur demandé, par exemple déplacer l'horloge | Appliquer, vérifier la position et proposer Annuler, sans seconde confirmation routinière |
| Incident courant couvert par une procédure réversible vérifiée | Détecter, diagnostiquer et réparer sous le mandat permanent ; rendre le résultat consultable |
| Paquet cassé nécessitant une mise à jour globale, une suppression ou une modification du noyau | Préparer le changement et la récupération, puis solliciter l'utilisateur |
| Défaut de sécurité | Établir les faits et corriger automatiquement seulement dans le périmètre courant autorisé ; solliciter pour les changements importants d'accès, réseau ou disponibilité |
| Compromission suspectée | Éviter d'effacer les preuves sous couvert de nettoyage ; escalader le diagnostic et la récupération appropriée |
| Quota épuisé, réseau absent ou fournisseur indisponible | Conserver la tâche, continuer les fonctions déterministes du système et signaler la limite ; aucun achat/API payante de repli implicite |

Cette décision remplace comme cible la règle « authentification humaine à
chaque opération privilégiée ». Établir ou élargir un mandat privilégié exige
une authentification humaine ; son usage courant peut ensuite être automatique
sur les opérations explicitement couvertes. Elle ne vaut pas implémentation :
**les portes polkit actuelles restent en place tant que le remplaçant n'est pas
construit et éprouvé**. Pas de sudo global ni de désactivation générale du sandbox.

Les journaux, noms de paquets et contenus de fichiers restent des données non
fiables. La future boucle peut agir après les avoir lus, mais ces contenus ne
peuvent ni créer un mandat, ni élargir les droits, ni remplacer une décision
humaine. Le blocage v1 après `system_status` ne sera retiré qu'avec cette
séparation d'autorité et des tests adversariaux du nouveau chemin.

## Première preuve de produit

Le prochain jalon doit démontrer une chaîne complète dans le clone de VM avec
le vrai abonnement Codex, puis l'étendre aux incidents. Critères :

1. « Mets l'heure à gauche » : le runtime lit la configuration réelle, effectue
   la modification dans les réglages DMS, vérifie le résultat à l'écran et sait
   l'annuler. Il ne rend pas un tutoriel ni une réponse simulée.
2. Une panne contrôlée d'un paquet/service de test est détectée sans chat ouvert,
   diagnostiquée et corrigée ; le test de santé redevient vert. L'incident est
   créé uniquement dans un banc jetable, pas dans la machine de référence.
3. Un défaut de sécurité volontaire et réversible sur une ressource de test
   est détecté, corrigé et recontrôlé. Un changement important exige une décision.
4. Une tâche libre agit sur un projet/fichier de test sans passer par les trois
   outils système v1 et sans obtenir leurs privilèges.
5. Fermer le panneau, redémarrer le shell, annuler, injecter un log hostile et
   perdre le réseau n'entraînent ni double exécution ni faux succès.

L'exemple de l'horloge est un critère d'acceptation, pas une instruction de
modifier immédiatement le bureau du pilote. La fluidité de la VM reste un
chantier parallèle bloquant le dogfooding : un agent ne compense pas une
interface lente. Ces preuves ne sont pas réalisées à la date de cette décision.
