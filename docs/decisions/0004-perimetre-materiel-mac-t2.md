# ADR 0004 — Le Mac T2 est toléré et cloisonné, pas supporté

- **Date** : 2026-08-29
- **Statut** : **proposé** — recommandation du contrôleur, en attente de ratification par l'utilisateur (trois points ouverts au §6)
- **Portée** : sous-projet 4b (première vraie machine), et par ricochet la doctrine de packaging du Socle
- **Contexte amont** : [veille Mac Intel T2 du 2026-08-29](../veille/2026-08-29-mac-intel-t2.md) (296 lignes sourcées), [Spec du Socle](../superpowers/specs/2026-08-27-socle-design.md) §3 (« pas de migrations », paquets `arch=(any)`)

---

## 1. Contexte

La machine de dogfooding est désormais connue : **un MacBook Pro i7 de 2019, 16 Gio**, donc équipé de la puce **T2**. C'est sur elle que l'utilisateur installera Eschaton dès qu'un ISO existera, et c'est là que le produit sera ajusté.

La veille datée établit trois faits qui ne se négocient pas :

1. **La T2 est le contrôleur NVMe.** Un ISO Arch standard — donc le nôtre — ne voit aucun disque et échoue avant de partitionner. Il faut un ISO bâti sur le noyau `linux-t2`.
2. **`linux-t2` vient d'un dépôt tiers** (`arch-mact2`), à mainteneur unique, **non signé** (`SigLevel = Never`), qui suit l'amont **avec retard**. Un `pacman -Syu` peut casser l'installation ; c'est documenté sur les forums Arch.
3. **Touch ID est définitivement inaccessible** : le capteur est câblé à la Secure Enclave, qui ne renvoie aucun verdict exploitable à l'OS. Aucun `fprintd`/PAM/polkit n'y accédera jamais.

Le reste du matériel s'en sort correctement (clavier, trackpad, audio et webcam via le pilote `apple-bce`, **compilé dans `linux-t2`** et non empaqueté séparément — constaté le 2026-08-30 ; Wi-Fi grâce au firmware pré-empaqueté `apple-bcm-firmware`), avec des réserves connues (micro faible, veille et Touch Bar fragiles, GPU AMD dédié à gérer en hybride sur les 15″/16″).

**Le retard du noyau, désormais chiffré** : la construction des deux variants le même jour (2026-08-30) donne `extra/linux` **7.1.11** contre `arch-mact2/linux-t2` **7.1.8** — trois versions correctives de retard. La veille donnait ce risque comme « qualitativement avéré, pas chiffré » ; il porte maintenant un chiffre, et c'est celui-là qu'il faut surveiller dans la durée.

## 2. Le problème posé au produit

Eschaton vise « un nouveau Windows » : un système pour tout le monde, sur du matériel ordinaire. Or **le Mac T2 est l'un des matériels les moins ordinaires qui soient sous Linux**. Deux dangers distincts :

- **La déformation du produit** : à force d'adapter la distro à cette machine, on optimiserait pour un cas particulier non représentatif du public visé.
- **La rupture de doctrine** : notre packaging est `arch=(any)`, sans migrations, avec un dépôt qu'on veut bientôt **signé** ([SP4a](../superpowers/specs/2026-08-28-signature-design.md)). Le chemin T2 impose un noyau spécifique (donc non-`any`), un dépôt tiers **non signé**, et un épinglage — c'est-à-dire l'exact inverse sur les trois points.

## 3. Options considérées

- **A — T2 dans le périmètre produit.** Eschaton supporte officiellement les Mac T2 : ISO principal bâti sur `linux-t2`, adaptations dans le méta-paquet. *Rejeté* : impose à tous les utilisateurs un noyau tiers non signé, et fait porter au produit entier le risque de cadence d'un mainteneur unique.
- **B — T2 toléré et cloisonné.** Le produit reste conçu pour du matériel ordinaire ; le support T2 existe, mais dans des artefacts séparés et clairement étiquetés, sans jamais entrer dans le chemin nominal. **Retenu.**
- **C — Refuser le T2 et changer de banc d'essai.** *Rejeté* : c'est la machine dont l'utilisateur dispose, et l'attente d'un autre matériel bloquerait le dogfooding, qui est la raison d'être de la v1.

## 4. Décision

**Option B.** Le Mac T2 est une cible **tolérée**, jamais une cible **supportée**. Concrètement :

1. **Artefacts séparés.** Les adaptations T2 vivent dans un paquet dédié (`eschaton-t2`) et un **variant d'ISO** distinct, jamais dans `eschaton-base`, `eschaton-desktop` ni l'ISO principal.

   > **Correction du 2026-08-30 (ADR 0002)** : cette décision annonçait `eschaton-t2` « forcément non-`any` puisqu'il dépend de `linux-t2` ». **C'est faux, deux fois.** L'architecture d'un paquet décrit ce qu'il *contient*, pas ce dont il dépend — or celui-ci ne contient que trois fichiers texte et un script. Et surtout, `repo/build-repo` construit **tous** les PKGBUILD dans les **deux** jobs d'architecture : `arch=(x86_64)` casserait le job aarch64. Le paquet est donc livré en `arch=(any)`, et la doctrine `any` du projet n'a **aucune exception** — ce qui est meilleur que ce que cet ADR proposait.
2. **Le dépôt tiers ne contamine pas la confiance.** `arch-mact2` étant non signé, il n'entre jamais dans la configuration par défaut. Quand le SP4a fermera l'exigence de signature sur `[eschaton]`, cette exigence reste entière : le dépôt T2 est ajouté séparément, avec sa politique propre, sur une machine T2 uniquement, et ce compromis est **affiché à l'utilisateur**.
3. **Le noyau est épinglé et gardé.** Sur une machine T2, le paquet `linux` standard n'est jamais installé, et une garde empêche une mise à jour de le réintroduire ou de désaligner `linux-t2`.
4. **Le rollback devient le filet, et le banc d'essai devient un atout.** Un noyau tiers qui retarde est précisément le scénario que notre rollback sur snapshot existe pour absorber. Le Mac T2 n'est donc pas seulement une contrainte : c'est le **test de résistance le plus sévère de notre fonctionnalité phare**, et à ce titre il a une valeur réelle pour le projet.
5. **Aucune promesse publique.** La documentation dira que le T2 fonctionne « avec des réserves connues et un noyau tiers », jamais qu'il est supporté. Les défauts constatés par la veille (micro, veille, Touch Bar, GPU hybride) sont listés honnêtement.

## 5. Conséquences

- Le SP4b se dédouble : **l'ISO nominal** (matériel ordinaire, la vraie cible produit) et **le variant T2** (le banc de l'auteur). Le premier reste le livrable ; le second est un outil de dogfooding.
- **Touch ID sort définitivement du champ des possibles.** Toute idée d'authentification biométrique pour les actions privilégiées est abandonnée sur cette machine ; le veto sur le terminal ([O1 du registre](../REGISTRE-ARBITRAGES.md)) devra donc être satisfait par une **modale graphique classique**, pas par le doigt.
- Le chiffrement au repos ne peut pas s'appuyer sur celui de la T2 (transparent pour Linux) : ce sera **LUKS** ou rien.
- **Réserve honnête assumée** : dogfooder sur un matériel atypique retarde la découverte des vrais problèmes du grand public (pilotes Nvidia, écrans VRR, matériel bas de gamme). Il faudra un second banc représentatif avant toute distribution à des tiers.

## 6. Points ouverts — à trancher par l'utilisateur

1. **Taille d'écran du MacBook** : 13″ (iGPU seul, cas simple) ou 15″/16″ (GPU AMD dédié à gérer en hybride, un modèle donnant un écran noir sans `nomodeset`).
2. **macOS** : effacer le disque entier (recommandé — l'ESP d'Apple fait 300 Mo là où notre spec en exige 4 Gio) ou tenter une cohabitation.
3. **Ratification** : cette décision de périmètre est-elle acceptée telle quelle ?
