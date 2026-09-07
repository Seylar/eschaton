# Prise en main de la VM — 20 minutes pour juger toi-même

> Parcours actualisé le 2026-09-07 d'après le code. Les preuves d'exécution sont dans [`tools/vm-dev.md`](../tools/vm-dev.md). Ce guide sert à juger le produit et les choix du [registre des arbitrages](REGISTRE-ARBITRAGES.md).

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

Le flux actuel ouvre une **authentification graphique**, puis suit l'installation dans le panneau. Annuler exige une seconde authentification. Une mise à jour qui pose une question de résolution s'arrête pour demander une décision humaine.

> **Dis-moi** : ces deux compromis sont-ils acceptables ? L'ancien flux en terminal a été remplacé ; le veto **O1** reste à trancher sur ce nouveau comportement. Si un terminal s'ouvre encore, la VM n'a pas la version actuelle du plugin.

### Étape 3 — La pastille de rollback (5 min)

Clique dessus : tu vois la liste des snapshots avec leurs dates et descriptions, puis une restauration à confirmer.

> **Dis-moi** : est-ce lisible pour quelqu'un qui ne sait pas ce qu'est un snapshot ? Et surtout — la **modale de mot de passe** qui apparaît quand tu confirmes, tu la gardes ou tu la supprimes ? (arbitrage **R2**, trivial à défaire aujourd'hui)

### Étape 4 — L'assistant, `SUPER+A` (7 min)

Le panneau s'ouvre. Demande-lui l'état du système, puis essaie de lui demander autre chose : d'ouvrir une application, de changer un réglage, de te parler d'un fichier.

> **Dis-moi** : il peut converser, mais ses actions système se limitent à trois outils : état, mise à jour et proposition de restauration. Est-ce suffisant pour l'« assistant omniprésent » que tu attends ? (arbitrage **R1**)
>
> Essaie aussi : « regarde mon système et corrige ce qui ne va pas ». Il lira, puis s'arrêtera : il faut un second message pour qu'il agisse. C'est le rempart anti-injection (**R3**) — trop pénible, ou acceptable ?

### Étape 5 — Ta config à toi (3 min)

Ouvre un terminal dans la VM et regarde `~/.config/hypr/`. Essaie d'y modifier quelque chose.

Les fichiers générés par DMS peuvent être régénérés par `dms setup`. **`dms/binds-user.lua` est l'exception prévue pour les surcharges personnelles** : Eschaton y ajoute son accroche une seule fois et respecte son retrait. Une mise à jour du paquet ne réécrit pas tout le dossier personnel.

> **Dis-moi** : cette séparation est-elle compréhensible ? (arbitrage **J1**)

## 4. Ce que cette VM ne peut PAS te dire — ne t'y trompe pas

| | Pourquoi |
|---|---|
| **La fluidité** | Le banc ARM utilise la virtualisation sur Apple Silicon, pas l'émulation x86. Le rendu logiciel limite la comparaison avec un vrai GPU. Une lenteur doit néanmoins être diagnostiquée : le banc n'innocente pas automatiquement le produit. |
| **Le son** | La VM tourne sans audio (`-audio none`). Rien n'a jamais été testé. |
| **Le GPU, le jeu, le HDR** | Impossibles ici. C'est tout l'objet du SP4b (vraie machine) et du SP5. |
| **La vraie installation** | Ce que tu vois est une VM installée par notre installeur, mais sur du matériel virtuel simple. |

Juge donc **le design, la disposition, les mots, le parcours** — pas la vitesse.

## 5. Me renvoyer ton verdict

Le plus utile pour moi, dans l'ordre : ce qui t'a fait tiquer visuellement, puis ta réponse aux quatre questions d'arbitrage (**R1** catalogue, **R2** mot de passe du rollback, **R3** désarmement, **J1** propriété de la config). Tout ce que tu tranches, je le porte dans les specs et je relance l'exécution dessus.
