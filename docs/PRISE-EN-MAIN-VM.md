# Prise en main de la VM — 20 minutes pour juger toi-même

> Ce document n'est pas un journal d'ingénierie (ça, c'est [`tools/vm-dev.md`](../tools/vm-dev.md), 3 000 lignes). C'est le parcours minimal pour que **tu** voies Eschaton de tes yeux et que tu me dises où le rendu s'écarte de ce que tu voulais. Il répond à la recommandation n°1 du [registre des arbitrages](REGISTRE-ARBITRAGES.md).

## 1. Démarrer (30 secondes)

```bash
/Applications/UTM.app/Contents/MacOS/utmctl start eschaton-dev
```

Puis ouvre la fenêtre **UTM** et double-clique sur `eschaton-dev` pour voir l'écran. Rien d'autre à faire : la session graphique s'ouvre toute seule (auto-login — c'est l'arbitrage O2 du registre, tu peux justement juger si ça te va).

Pour arrêter, quand tu auras fini :

```bash
/Applications/UTM.app/Contents/MacOS/utmctl stop eschaton-dev
```

Si tu as besoin du mot de passe : c'est `eschaton` (mot de passe de banc d'essai, à changer avant toute vraie machine).

## 2. Ce que tu dois voir

Un bureau Hyprland avec la barre DankMaterialShell en haut, et **deux pastilles Eschaton** dans cette barre : celle des mises à jour et celle du rollback. C'est notre travail à nous ; tout le reste de la barre est l'amont.

## 3. Le parcours — cinq étapes, et ce que je te demande de juger

### Étape 1 — Regarde, sans rien cliquer (2 min)

Ne teste rien. Regarde. **C'est le seul moment du projet où « joli » a un juge.**

> **Dis-moi** : est-ce que ça ressemble à quelque chose que tu installerais chez ta famille ? Qu'est-ce qui cloche en premier coup d'œil — densité, couleurs, typographie, la barre elle-même ?

### Étape 2 — La pastille de mise à jour (3 min)

Clique dessus. Elle liste les paquets en attente et propose de lancer la mise à jour.

> **Dis-moi** : le fait qu'un **terminal s'ouvre** et te demande un mot de passe sudo, c'est acceptable ou c'est la trahison du « zéro terminal » ? (arbitrage **O1** du registre)

### Étape 3 — La pastille de rollback (5 min)

Clique dessus : tu vois la liste des snapshots avec leurs dates et descriptions. C'est **le** différenciateur d'Eschaton — personne d'autre n'a un navigateur de snapshots dans sa barre.

> **Dis-moi** : est-ce lisible pour quelqu'un qui ne sait pas ce qu'est un snapshot ? Et surtout — la **modale de mot de passe** qui apparaît quand tu confirmes, tu la gardes ou tu la supprimes ? (arbitrage **R2**, trivial à défaire aujourd'hui)

### Étape 4 — L'assistant, `SUPER+A` (7 min)

Le panneau s'ouvre. Demande-lui l'état du système, puis essaie de lui demander autre chose : d'ouvrir une application, de changer un réglage, de te parler d'un fichier.

> **Dis-moi** : il refusera tout sauf ses trois outils. C'est ça, ton « assistant omniprésent » ? (arbitrage **R1** — c'est la question la plus importante du registre)
>
> Essaie aussi : « regarde mon système et corrige ce qui ne va pas ». Il lira, puis s'arrêtera : il faut un second message pour qu'il agisse. C'est le rempart anti-injection (**R3**) — trop pénible, ou acceptable ?

### Étape 5 — Ta config à toi (3 min)

Ouvre un terminal dans la VM et regarde `~/.config/hypr/`. Essaie d'y modifier quelque chose.

> **Dis-moi** : cet arbre appartient au shell, pas à toi ; tes modifications seront écrasées. Pour toi qui bricoles, c'est rédhibitoire ou tolérable ? (arbitrage **J1**, le plus coûteux à défaire)

## 4. Ce que cette VM ne peut PAS te dire — ne t'y trompe pas

| | Pourquoi |
|---|---|
| **La fluidité** | Tout est en **rendu logiciel** (`LIBGL_ALWAYS_SOFTWARE=1`), sur ARM émulé. Si c'est lent ou saccadé, **c'est le banc, pas le produit**. Ne juge pas la performance ici. |
| **Le son** | La VM tourne sans audio (`-audio none`). Rien n'a jamais été testé. |
| **Le GPU, le jeu, le HDR** | Impossibles ici. C'est tout l'objet du SP4b (vraie machine) et du SP5. |
| **La vraie installation** | Ce que tu vois est une VM installée par notre installeur, mais sur du matériel virtuel simple. |

Juge donc **le design, la disposition, les mots, le parcours** — pas la vitesse.

## 5. Me renvoyer ton verdict

Le plus utile pour moi, dans l'ordre : ce qui t'a fait tiquer visuellement, puis ta réponse aux quatre questions d'arbitrage (**R1** catalogue, **R2** mot de passe du rollback, **R3** désarmement, **J1** propriété de la config). Tout ce que tu tranches, je le porte dans les specs et je relance l'exécution dessus.
