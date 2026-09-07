# Priorité de reprise : une VM utilisable avant le Mac

Date : 2026-09-07. Pilotage : Codex, sur délégation de Seylar.
Retour utilisateur : « la VM est vraiment bancale encore ».
Références : [veille de session](../../veille/2026-09-07-premiere-session.md),
[proposition SP4c](../specs/2026-09-07-premiere-session-design.md),
[audit général](../../audits/2026-09-07-projet-global.md).

## Décision

La prochaine livraison est une **VM de dogfooding fonctionnelle et réactive**.
La disponibilité de paquets ou une CI verte ne suffit pas à franchir ce jalon.
Les corrections T2 restent conservées ; elles ne prennent plus la priorité sur
les défauts quotidiens déjà visibles dans la VM. Aucune installation remplaçant
macOS tant que ce jalon puis les vérifications du média T2 ne sont pas passés.

## Terrain observé aujourd'hui

Le fichier UTM `eschaton-dev.utm/config.plist` indique : QEMU/aarch64, hyperviseur
activé, 4 vCPU, 8192 Mio, affichage `virtio-gpu-pci`, aucun périphérique audio.
Le journal antérieur décrit un compositeur en rendu logiciel (§12 de
`tools/vm-dev.md`) ; son moteur actif n'a pas été recontrôlé dans cette passe.

La VM a démarré et affiché la barre DMS sur un bureau au fond sombre. Elle s'est
ensuite retrouvée arrêtée pendant l'observation ; la cause n'est pas établie.
La tentative de connexion série attendait « Password: » alors que le système
présentait « Mot de passe : ». Aucun diagnostic invité ni test d'ouverture du
panneau n'a été achevé. Il serait faux d'en conclure à un crash du bureau ou à
une mesure de performance. Les versions installées restent à relever.

## 1. Établir un banc stable et mesurable

- Conserver une copie récupérable de la VM actuelle avant les modifications.
- Relever les versions réellement installées, les rapprocher des paquets CI et
  installer explicitement la vague testée dans le banc. Une PR n'actualise pas
  la VM. Vérifier les versions après installation.
- Relever le renderer actif, la résolution/fréquence, la charge CPU/mémoire,
  les unités en échec et les erreurs de session pendant les interactions.
- Éprouver les possibilités d'accélération du banc et ajouter une carte audio
  virtuelle adaptée. Ne pas attribuer toute lenteur à UTM sans mesure ; ne pas
  promettre qu'un réglage GL sera compatible sans l'avoir testé.
- Garder une configuration VM reproductible, séparée des réglages du vrai Mac.

## 2. Corriger les parcours du quotidien

Ordre : défauts bloquants signalés par l'utilisateur, session et provisioning,
applications/fenêtres/réglages, assistant, mise à jour et restauration.
La connexion authentifiée, le trousseau et le verrouillage SP4c font partie de
ce jalon. Audio, réseau, clavier/souris, presse-papiers et redimensionnement
font partie du banc utilisable ; l'absence de carte audio n'est plus une excuse
pour reporter toute la chaîne audio à l'installation matérielle.

Pour chaque défaut : reproduire, corriger la cause, livrer le paquet dans la
VM, rejouer le parcours et noter les résultats. Ne pas remplacer cette boucle
par une assertion textuelle sur le QML. Ne pas masquer un défaut de fond par
une refonte visuelle.

## 3. Conditions de passage de la VM

- Trois démarrages à froid avec une session complète : fond, barre, plugins et
  réglages persistants ; aucune commande de réparation pour utiliser le bureau.
- Connexion, verrouillage, refus de mauvais mot de passe et déconnexion éprouvés.
- Lancement des applications et gestion des fenêtres sans blocage ; dix cycles
  d'ouverture/fermeture des panneaux, sans doublon, contenu perdu ou plantage.
- Mesures de réponse sous une configuration fixe. Cibles initiales de travail :
  retour visuel d'un clic en 100 ms et ouverture d'un panneau local déjà chargé
  en 500 ms. Ce sont des objectifs, pas des performances déjà obtenues ; toute
  limite du banc doit être isolée et explicitée.
- Navigateur/réseau, lecture audio, saisie et réglages usuels utilisables. Les
  applications indispensables de Seylar complètent cette liste dès son retour.
- Assistant connecté : configuration du fournisseur, conversation, état système,
  annulation et erreur réseau ; aucun secret réel dans les preuves.
- Mise à jour puis restauration avec redémarrage constaté ; refus et annulation
  respectent les portes d'authentification du produit.
- Au moins une heure d'utilisation continue sans crash ni réparation manuelle,
  puis prise en main par Seylar pour juger la fluidité et les usages essentiels.

La couverture des tests et la CI restent nécessaires. Elles ne remplacent pas
ces observations de fonctionnement et la prise en main.

## 4. Passage au Mac A1990

Une fois la VM qualifiée : construire le média T2 puis démarrer le Mac dessus
**avant l'installation**, pour vérifier disque visible, clavier/trackpad,
affichage et réseau. Relever le GPU exact et choisir les paramètres testés.
Ensuite seulement : installation Eschaton seul, validation des pilotes,
thermiques, audio, veille/autonomie et rollback sur la machine réelle.

La VM ARM ne prouve ni le GPU hybride Intel/AMD, ni la puce T2, ni les pilotes
x86_64 du Mac. Une VM réussie autorise cette étape de qualification matérielle,
pas l'annonce que le Mac fonctionnera sans autre travail. La diffusion à des
tiers reste postérieure au dogfooding et aux prérequis de publication.

## Précision utilisateur et première implémentation — abonnements

Le pilote exige les **abonnements Claude et Codex**, avec Codex en premier.
Un formulaire de clés API ou le petit modèle local de démonstration ne répond
pas à ce besoin. L'abonnement Claude reste à intégrer ; le fournisseur
Anthropic par clé API existant n'en tient pas lieu.

Le 7 septembre, la branche `codex/vm-stabilisation-2026-09-07` ajoute Codex
app-server 0.139.0, épinglé pour ARM et x86, et le parcours de connexion ChatGPT
par code dans le panneau. Le catalogue de modèles vient du compte ; aucun
jeton de l'hôte n'est importé. Le runtime utilise un répertoire privé de
l'utilisateur invité et les trois outils du même `ToolExecutor` que le
transport historique. Les appels natifs de shell et d'édition sont désactivés,
l'accès aux environnements est désactivé, le sandbox est en lecture seule et
les demandes d'élévation sont refusées. Après `system_status`, le transport
refuse tout nouvel outil jusqu'au prochain message utilisateur.

La connexion personnelle et une conversation avec de vraies réponses sont
encore à valider. Le chargement réel du panneau, le protocole natif non
connecté et les tests de comportement ne remplacent pas cette validation.

La VM de référence est conservée. Les essais se font dans son clone
`eschaton-stabilisation`. Le pilote `virtio-gpu-gl-pci` expose un render node,
mais retirer `LIBGL_ALWAYS_SOFTWARE=1` fait échouer l'initialisation EGL du
compositeur. Le réglage logiciel a donc été restauré. Cela identifie une
limite du banc actuel ; **la fluidité n'est pas acquise**. Les entrées de
contrôle automatisées ne ciblent pas correctement les boutons de l'invité ;
une vérification manuelle a été demandée au pilote. Voir `tools/vm-dev.md` §39.
