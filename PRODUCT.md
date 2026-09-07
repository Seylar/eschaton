# Product

## Register

product

## Users

Eschaton s'adresse d'abord aux personnes qui veulent un système beau, moderne
et vivant sans devenir administratrices Linux. Elles utilisent le bureau au
quotidien, à la souris comme au clavier, et doivent pouvoir comprendre l'état
du système puis agir sans ouvrir un terminal. Les utilisateurs avancés restent
bienvenus, mais ne dictent ni le vocabulaire ni la densité par défaut.

## Product Purpose

Eschaton est un système d'exploitation avec un expert intégré. Cet agent
connaît l'état de la machine, détecte ses incidents, cherche leur cause,
réalise les changements autorisés, vérifie leur effet et récupère d'un échec.
Il sait aussi personnaliser le bureau à la demande, sans configuration
manuelle à imposer à l'utilisateur.

L'autonomie par défaut, confirmée par le pilote le 2026-09-07 : **détecter et
corriger seul les problèmes courants réversibles ; solliciter l'utilisateur
pour les changements importants**. Une opération réversible peut néanmoins
être importante si elle affecte les accès, les données ou la disponibilité.
Le modèle ne décide pas lui-même d'étendre ses droits.

Le même produit donne accès à l'agent généraliste préféré de l'utilisateur
pour travailler sur ses fichiers, ses projets et ses applications. Abonnements
Codex puis Claude : les intégrations officiellement supportées sont à qualifier.
Le panneau de conversation est une interface parmi d'autres ; fermer le panneau
ne doit pas supprimer une tâche ou arrêter la surveillance du système.

La promesse se mesure à des incidents effectivement résolus et à des tâches
terminées. Le bureau, le réseau et les mécanismes de récupération doivent
continuer à fonctionner quand le modèle est indisponible. Aucune garantie
d'infaillibilité du LLM ou de réparation de toute panne n'est revendiquée.

Décision de référence : [ADR 0005](docs/decisions/0005-agent-systeme.md).
L'ancien catalogue de trois outils décrit l'implémentation v1, pas la cible
produit. Le moteur système décrit ici reste à construire.

## Brand Personality

Accueillant, dynamique, moderne, playful. Le futur doit sembler habitable, pas
réservé aux initiés. Le ton est direct, calme et sans jargon ; la sophistication
vient du comportement du système, jamais d'une surcharge visuelle.

## Anti-references

- Omarchy quand le terminal, le TUI ou l'édition de configuration deviennent
  l'interface système.
- Le Linux ancien : icônes dépareillées, densité arbitraire, vocabulaire de
  wiki et états implicites.
- Les assistants génériques posés dans une sidebar sans connaissance ni action
  système.
- Les interfaces « IA » à gradients violets, cartes décoratives, HUD saturé ou
  animation sans information.

## Design Principles

1. Faire au lieu de dicter : aucune commande shell n'est donnée comme réponse
   à une tâche que l'interface peut accomplir.
2. Rendre l’autonomie compréhensible : état, intervention effectuée, résultat
   vérifié et possibilité d’annuler sont visibles ; les changements importants
   demandent une décision concrète, les réparations courantes ne multiplient
   pas les interruptions.
3. S'intégrer avant de se distinguer : réutiliser le vocabulaire DMS et ses
   composants familiers ; réserver l'accent Eschaton aux actions et états.
4. Montrer l'état réel : vide, chargement, streaming, erreur, annulation et
   troncature ont chacun une présentation lisible.
5. Garder une porte de sortie : les changements passent par une exécution
   contrôlée, avec vérification et récupération adaptée à leur portée.
6. Être présent dans le système : réglages, erreurs, notifications et tâches
   partagent le même moteur ; aucune capacité centrale ne dépend de la sidebar.

## Accessibility & Inclusion

L'interface doit rester intégralement utilisable au clavier, conserver des
cibles généreuses pour le tactile, ne jamais coder un état par la couleur
seule et suivre le thème DMS pour le contraste et la taille du texte. Le
mouvement signale un changement d'état et respecte les préférences de mouvement
réduit du shell. Les libellés restent en français courant et les erreurs
expliquent l'action possible sans exposer le jargon du transport.
