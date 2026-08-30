# Eschaton — Spec de conception : l'ISO et la première vraie machine (SP4b)

- **Date** : 2026-08-29
- **Statut** : rédigée sur deux passes de veille datées ([SP4 grand public](../../veille/2026-08-28-sp4-grand-public.md) §2 pour l'ISO, [Mac Intel T2](../../veille/2026-08-29-mac-intel-t2.md) pour le banc) — publiée pour relecture ; exécution Codex, gates Claude
- **Sous-projet** : 4b/5 — priorité **rehaussée** sur demande utilisateur (« j'attends qu'on arrive à l'ISO et j'installerai sur un Mac secondaire, et là on va ajuster »)
- **Amont** : [Spec du Socle](2026-08-27-socle-design.md) §9 (l'ISO était renvoyé au SP4), [ADR 0004](../../decisions/0004-perimetre-materiel-mac-t2.md) (périmètre T2, **proposé**)

---

## 1. Position

Eschaton s'installe aujourd'hui **uniquement depuis un environnement live tiers** : `archboot` sur aarch64, un ISO Arch standard sur le smoke x86_64. L'installation elle-même est prouvée (≈ 4 min, deux architectures, cassage et rollback vérifiés), mais **le véhicule manque** : il n'existe aucun média Eschaton. C'est le dernier verrou avant que l'auteur puisse quitter la VM et dogfooder sur du vrai matériel — ce qui est la raison d'être de la v1.

La veille SP4 §2.2 établit un fait libérateur : **personne, dans la famille Arch moderne, n'a d'installeur graphique maison.** Omarchy pilote `archinstall` depuis un script `gum` en terminal ; CachyOS emploie Calamares. L'ambition « installeur graphique » du Socle §9 n'est donc pas un retard concurrentiel : c'est un territoire vide. Ce constat autorise à **découper** plutôt qu'à tout tenir d'un coup.

## 2. Périmètre

**SP4b-1 (ce document) — l'ISO qui amorce le dogfooding.** Un média Eschaton amorçable qui installe le système sur la machine de l'auteur, et sur du matériel x86_64 ordinaire en VM. C'est un livrable d'ingénierie, pas encore un produit grand public.

**Non-buts explicites de 4b-1**, chacun avec sa destination :
- L'**installeur graphique** → SP4b-2. La v1 installe depuis l'environnement live avec notre `eschaton-install` existant, éprouvé.
- L'**ISO hors-ligne** → hors périmètre tant que l'hébergement n'est pas tranché (§3.4).
- Le **chiffrement LUKS** → SP4c (il touche la session et le déverrouillage).
- Le **Secure Boot** → §5, risque assumé et documenté, pas résolu.

## 3. Architecture

### 3.1 Deux ISO, pas un — la conséquence de l'ADR 0004

| | **ISO nominal** | **Variant T2** |
|---|---|---|
| Cible | matériel x86_64 ordinaire — **le produit** | le MacBook Pro 2019 de l'auteur — **le banc** |
| Noyau | `linux` (amont Arch) | `linux-t2` (dépôt tiers `arch-mact2`, non signé) |
| Raison d'être | ce qu'on livrera un jour | dogfooder maintenant |
| Statut | livrable | outil interne, jamais annoncé comme supporté |

Le variant T2 est **indispensable et non contournable** : la puce T2 *est* le contrôleur NVMe, un ISO à noyau standard **ne voit aucun disque** et échoue avant de partitionner. Les deux ISO partagent tout sauf le noyau et les paquets matériels ; la divergence doit rester une **liste de paquets**, jamais une fourche du profil.

### 3.2 `archiso`, et le renoncement assumé à Calamares

- **Outil** : `archiso` (`extra/archiso 89-1`, `any`) — on copie le profil `releng`, on édite `packages.x86_64`, on dépose dans `airootfs/`, on construit avec `mkarchiso`.
- **Calamares est écarté**, non par goût mais par **incompatibilité de modèle** : il installe en déballant un squashfs (« l'ISO *est* l'image système »), alors que notre principe directeur est l'inverse — *thin installer, fat packages*, on `pacstrap` des paquets et l'état initial reste tracé par pacman. L'adopter reviendrait soit à renoncer à cette traçabilité, soit à écrire un module de remplacement.
- **Un installeur maison en QML est écarté pour la v1** : aucun précédent, et surtout le coût réel n'est pas l'interface mais la mécanique (partitionnement, détection matérielle, bootloader, reprise d'erreur à mi-parcours) — exactement ce que nous n'avons pas. S'y ajoute un risque propre : Quickshell s'appuie sur des API privées de Qt et casse à chaque changement d'ABI, ce qui est délicat sur un média **figé**.

### 3.3 Ce que l'ISO embarque

L'environnement live porte : `eschaton-install` et ses dépendances, le dépôt `[eschaton]` préconfiguré, `iwd` (et **non** `wpa_supplicant`, régression 2.11 constatée par la veille T2), les outils de secours (`snapper`, `btrfs-progs`, `limine`), et — pour le variant T2 seulement — `linux-t2`, `apple-bce` et `apple-bcm-firmware`.

**Point juridique à ne pas contourner en silence** : `apple-bcm-firmware` contient du firmware Apple extrait de macOS. L'embarquer dans un ISO **publiquement téléchargeable** est une zone grise. Tant que le variant T2 reste un artefact interne non publié, la question ne se pose pas ; elle se poserait dès la première publication. À trancher avant toute mise en ligne du variant, jamais après.

### 3.4 Hébergement = la décision « en ligne ou hors ligne »

Les deux ne font qu'un. GitHub Releases plafonne à **2 Gio par fichier** ; l'ISO d'Omarchy pèse 6 à 7 Gio et vit sur une infrastructure dédiée avec miroirs et torrents. **Décision : un ISO *en ligne* de ≤ 2 Gio**, publié en GitHub Release, qui télécharge les paquets pendant l'installation. L'ISO hors-ligne engagerait une infrastructure hors GitHub — c'est un projet en soi, pas un paramètre.

### 3.5 L'amorçage de la confiance

L'ISO est aussi le véhicule du keyring (SP4a) : la clé publique versionnée dans le dépôt de construction, ajoutée et signée localement pendant le build, `eschaton-keyring` installé dans l'environnement live **et** dans le système cible. C'est la réponse au problème « comment faire confiance à la toute première installation ». **4b-1 n'attend pas 4a** (le dépôt reste `Optional` en attendant), mais la place est réservée dès maintenant pour ne pas avoir à retoucher le profil ensuite.

## 4. Vérification — définition de « 4b-1 terminé »

1. **L'ISO nominal démarre** en VM x86_64 (UEFI) et installe un Eschaton complet ; premier démarrage en session graphique, pastilles rendues.
2. **Le variant T2 démarre sur le MacBook Pro 2019 de l'auteur**, **voit le disque**, installe, et le système démarre — clavier et trackpad internes fonctionnels, réseau Wi-Fi opérationnel au premier démarrage sans passer par macOS.
3. **Le rollback fonctionne sur la vraie machine** : cassage volontaire, restauration depuis le shell, redémarrage vérifié. C'est le test de résistance nommé par l'ADR 0004 — le noyau tiers rend cette preuve plus précieuse ici qu'en VM.
4. **La taille de l'ISO nominal est ≤ 2 Gio** et il est publié en GitHub Release par la CI.
5. **La construction est reproductible en CI** (x86_64), avec la liste de paquets versionnée et l'immutabilité respectée.
6. **Les réserves sont écrites** : Secure Boot non supporté, défauts T2 connus (micro, veille, Touch Bar, GPU hybride sur 15″/16″), zone grise du firmware.

## 5. Risques (table datée 2026-08-29)

| # | Risque | Traitement |
|---|---|---|
| 1 | **`archiso` ne supporte pas le Secure Boot** — un ISO Eschaton ne démarre pas sur une machine grand public dont le Secure Boot est actif | Sur le Mac, il faut de toute façon le désactiver. Pour le produit, c'est une **limite réelle et documentée** ; `archboot` (déjà utilisé en aarch64) est le seul environnement Arch qui le supporte — piste pour 4b-2, pas pour maintenant. |
| 2 | Cadence de `linux-t2` : un `-Syu` casse l'installation | Épinglage + garde (ADR 0004 §4.3) ; le rollback est le filet, et sa preuve est au DoD §4.3. |
| 3 | ESP d'Apple à 300 Mio contre 4 Gio exigés | Effacement complet du disque — **point ouvert utilisateur** (ADR 0004 §6.2). |
| 4 | GPU AMD dédié sur 15″/16″ (écran noir sur Radeon Pro 5600M) | **Point ouvert utilisateur** : la taille d'écran conditionne l'ampleur du travail (ADR 0004 §6.1). |
| 5 | Firmware Apple redistribué | Variant T2 non publié tant que la question n'est pas tranchée (§3.3). |
| 6 | L'ISO diverge du dépôt (paquets embarqués périmés) | L'ISO est **en ligne** : il installe depuis le dépôt, donc il ne fige que l'environnement live. |
| 7 | Le banc T2 n'est pas représentatif du public cible | Assumé et écrit (ADR 0004 §5) ; un second banc ordinaire sera nécessaire avant toute distribution. |

## 6. Points ouverts

Les trois de l'[ADR 0004 §6](../../decisions/0004-perimetre-materiel-mac-t2.md) (taille d'écran, sort de macOS, ratification du périmètre) **bloquent le variant T2**, pas l'ISO nominal : l'exécution peut commencer par le second sans attendre.
