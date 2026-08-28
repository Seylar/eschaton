# ADR 0002 — Toute spec s'ouvre par une passe de veille datée

- **Date** : 2026-08-27
- **Statut** : acté
- **Portée** : tous les sous-projets

---

## 1. Le problème constaté

La spec du Socle a été écrite sans vérifier l'état courant des technologies qu'elle nomme. Résultat, au premier jour d'implémentation, six écarts entre la spec et le réel — dont deux qui cassaient silencieusement le filet de sécurité (ESP sous-dimensionnée, couplage du nom d'OS), et un qui n'apparaissait dans aucune analyse de risque (`gradle` inutilisable sur les deux architectures).

Aucun de ces écarts n'était difficile à trouver : tous étaient documentés publiquement avant l'écriture de la spec. Ils ont coûté des reprises en cours de route parce qu'on ne les a pas cherchés.

La spec du Socle portait en outre un différenciateur produit rendu faux treize jours avant sa rédaction par la sortie d'Omarchy 4 — voir [ADR 0001](0001-shell-du-bureau.md).

## 2. La règle

**Aucune spec n'est déclarée « validée » sans une passe de veille datée sur les technologies qu'elle engage.** La passe produit une trace dans la spec elle-même : une ligne de date sur la table des risques, et la date de vérification à côté de chaque affirmation périssable.

### Ce qu'on vérifie, par ordre de rendement

1. **Les versions et l'existence réelle des paquets, sur les deux architectures.** Pas « le paquet existe », mais `pacman -Si <pkg>` sur chaque cible. C'est ce qui a manqué pour `gradle` — présent, mais cassé.
2. **La documentation upstream des outils dont on dépend pour une garantie.** Le README de `limine-snapper-sync` donnait la taille d'ESP recommandée et le seuil de 85 % : deux valeurs qui contredisaient la spec, à une lecture de distance.
3. **La santé des projets amont, pas seulement leur existence.** Date du dernier commit, taille de l'équipe, dépôts actifs contre dépôts figés. C'est ce qui distingue « ALARM existe » de « ALARM est porté par une équipe très réduite et son keyring date de 2022 ».
4. **Les dépréciations annoncées.** Une technologie qui marche aujourd'hui mais dont le format de configuration est déprécié est une dette qu'on écrit volontairement (cas d'`hyprlang` face à Lua, sous-projet 2).
5. **Le paysage concurrent, pour toute affirmation de différenciation.** Un différenciateur est une affirmation sur le monde extérieur : il se périme sans prévenir et sans laisser de trace dans le code.

### Ce qu'on écrit

- Toute affirmation périssable porte **sa date de vérification**.
- Tout constat de terrain contredisant la spec **remonte dans la spec**, il ne reste pas dans un rapport de tâche. Une spec que l'implémentation a déjà démentie n'est plus l'autorité qu'elle prétend être.
- Un contournement est **tracé comme dette avec sa condition de sortie** (« à retirer quand X est réparé »), jamais comme une solution.

## 3. Conséquences

- Coût : quelques heures par spec, en amont.
- La passe se rejoue à l'ouverture de chaque sous-projet, pas une fois pour toutes — c'est ce qui rattrape les péremptions entre deux sous-projets.
- Une spec sans date de veille est un brouillon, quel que soit son niveau de détail par ailleurs.
