# ADR 0001 — Shell du bureau : DankMaterialShell d'abord, shell maison ensuite

- **Date** : 2026-08-27
- **Statut** : acté
- **Portée** : sous-projet 2 (Bureau)
- **Contexte amont** : [Spec du Socle](../superpowers/specs/2026-08-27-socle-design.md) §1, §3

---

## 1. Contexte

Le différenciateur n°1 d'Eschaton est **le zéro-terminal** : un bureau moderne où les réglages, les paquets, les snapshots et le matériel s'administrent en interface graphique. Ce n'est ni le tactile (déclassé en nice-to-have), ni « Hyprland + Quickshell » (Omarchy 4 y est passé le 14 août 2026), ni l'IA intégrée (Omarchy 4 la livre déjà).

L'écosystème Quickshell propose plusieurs shells complets. Deux étaient candidats sérieux comme base :

| | **end-4 / dots-hyprland** (illogical-impulse) | **DankMaterialShell** (DMS) |
|---|---|---|
| Nature | Dotfiles + shell, installés par script dans `~/.config` | Shell packagé + daemon Go, config dans `~/.config/DankMaterialShell/` |
| Packaging Arch | Meta-paquets `illogical-impulse-*`, Quickshell épinglé à un commit | `dms-shell-git` (AUR) + profil officiel archinstall 4.4 |
| GUI de réglages | App Settings (`InterfaceConfig`) | Control Center : réseau, Bluetooth, audio, affichage, night mode |
| IA | Présente (Gemini, Ollama, OpenRouter en sidebar) | Absente |
| **Extensibilité** | **Aucun point d'extension → il faut forker** | **Plugin registry + `plugins.lock.json`** (commits épinglés) |
| Compositeurs | Hyprland seul | niri, Hyprland, sway, MangoWC, labwc, MiracleWM |
| Licence | GPL-3.0 | GPL-3.0 |

Options envisagées :

- **A** — DMS comme base, étendu par des plugins Eschaton.
- **B** — Fork d'end-4.
- **C** — Shell maison de zéro.

## 2. Décision

**A d'abord, C à terme.** Le bureau v1 est **DankMaterialShell étendu par des plugins Eschaton** ; un shell maison est construit ensuite, une fois le besoin réel connu, en reprenant ce qu'end-4 fait de mieux.

### Pourquoi A plutôt que B

Le critère décisif est **le modèle d'extension**, imposé par le principe *fat packages* (spec du Socle §3 : l'état vit dans des paquets pacman versionnés, jamais dans des scripts qui mutent la config).

- DMS a un registre de plugins avec lockfile : les panneaux Eschaton (gestion de paquets, snapshots Snapper, assistant IA) deviennent des paquets `eschaton-dms-plugin-*`. C'est exactement le §3.
- end-4 n'a aucun point d'extension : l'étendre impose de forker un projet à 15,8k étoiles qui bouge vite — coût de rebase permanent — et d'hériter de son calendrier, puisqu'il épingle Quickshell à un commit précis. Il verrouille en outre sur Hyprland seul.

L'avance d'end-4 sur l'IA ne compense pas : sa sidebar multi-provider n'est pas l'« assistant omniprésent avec outils système » du sous-projet 3, et l'upstream qualifie lui-même ces fonctions de perfectibles.

### Pourquoi pas C tout de suite

Le design d'un shell maison n'est pas encore assez informé pour justifier son coût. Trois mois de dogfooding sur DMS produiront une liste de griefs concrets ; un design théorique ne produirait qu'un pari.

## 3. Ce qu'on récolte chez end-4

À étudier et reprendre, indépendamment du fait qu'on n'en prend pas le code :

1. **Le découpage en meta-paquets** `illogical-impulse-*` — la seule preuve existante qu'un bureau Quickshell entier tient dans des PKGBUILDs modulaires. C'est le modèle direct de nos paquets `eschaton-desktop` / `eschaton-dms-plugin-*`.
2. **L'épinglage de Quickshell à un commit** — Quickshell est en 0.x (0.3.1 au 20 août 2026) ; ne pas suivre `HEAD` aveuglément.
3. **Le modèle d'invocation de l'assistant** — sidebar multi-provider sur une seule keybind, sans web app. Entrée directe pour le sous-projet 3.
4. **Les deux familles de layout** (Illogical Impulse / Waffle) — la démonstration qu'un shell peut porter plusieurs identités visuelles sans se dupliquer.
5. **Les QoL périphériques** — traduction d'écran, Google Lens, anti-flashbang.

## 4. Critères de passage à C

Sans critères, « on fera notre shell un jour » ne se décide jamais, ou se décide mal. Le passage au shell maison se déclenche quand **au moins deux** des conditions suivantes sont réunies :

1. Le modèle de plugins DMS bloque une fonction centrale d'Eschaton (typiquement l'assistant IA omniprésent, qui déborde d'un widget de barre).
2. Le nombre de patchs portés sur DMS lui-même — au-delà des plugins — dépasse ce qu'un rebase raisonnable absorbe.
3. L'écart entre le design Material 3 de DMS et l'identité visuelle voulue devient le premier reproche des utilisateurs de test.
4. Le rythme ou la gouvernance de l'upstream deviennent un risque (abandon, changement de licence, réécriture).

Tant qu'aucune de ces conditions n'est réunie, rester sur A est la bonne décision, pas un renoncement.

## 5. Conséquences

- Le sous-projet 2 livre : `eschaton-desktop` (meta-paquet tirant Hyprland + DMS + dépendances) et un ou plusieurs `eschaton-dms-plugin-*`.
- Le multi-compositeur reste ouvert : DMS supporte niri, qui monte vite. Aucun verrouillage sur Hyprland n'est acté par cet ADR.
- **Config Hyprland en Lua** : depuis Hyprland 0.55, `hyprlang` est déprécié au profit de `hyprland.lua`. Les paquets de configuration partent directement en Lua. DMS 1.5 le supporte déjà.
- **Risque aarch64** : ni Quickshell ni DMS (Go) n'ont de binaires ALARM ; tout se compile sur le banc d'essai. À vérifier tôt dans le sous-projet 2 — c'est possiblement le vrai facteur limitant, avant toute considération de design.
- **Non vérifié à ce jour** : ni DMS ni end-4 n'ont été installés. Les jugements d'ergonomie et d'empreinte mémoire proviennent de tests tiers. Première tâche du sous-projet 2 : installer DMS dans la VM et confronter cet ADR au réel.

## Addendum du 2026-08-28 (passe de veille SP2 — ajout contrôleur)

Trois faits nouveaux ([rapport de veille](../veille/2026-08-28-sp2-bureau.md)) amendent cet ADR sans en changer la décision :

1. **§5 « Risque aarch64 » est levé, en mieux** : DMS (`extra/dms-shell` 1.5.3), Quickshell (0.3.1) et dgop sont entrés dans les dépôts **officiels** d'Arch ET d'ALARM, en binaires natifs des deux architectures — rien ne se compile sur le banc d'essai, le Bureau entier tient en meta-paquets `any`.
2. **Le mécanisme d'extension est meilleur qu'anticipé** : DMS scanne `/etc/xdg/quickshell/dms-plugins/` (plugins *système*, pacman-owned, lecture seule pour DMS) — le modèle *fat packages* exact ; `plugins.lock.json` ne concerne que les plugins git côté utilisateur et sort du périmètre Eschaton.
3. **Le critère n°1 de passage au shell maison (§4) est affaibli** : les cinq types de plugins (`widget`, `daemon`, `launcher`, `desktop`, `composite`) et la permission `process` couvrent a priori l'assistant IA omniprésent. Le critère reste valable, mais sa probabilité de déclenchement baisse nettement.

Le différenciateur formulé au §1 (« zéro-terminal ») est par ailleurs requalifié par la veille : voir la [spec du Bureau](../superpowers/specs/2026-08-28-bureau-design.md) §1 — le créneau réel est l'administration système **intégrée au shell**, rollback graphique en tête.

## 6. Sources

- [AvengeMedia/DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) · [Dank Linux](https://danklinux.com/) · [DankInstall](https://danklinux.com/docs/dankinstall)
- [Archinstall 4.4 ajoute le profil DMS + niri (Phoronix)](https://www.phoronix.com/news/Arch-Linux-Archinstall-4.4)
- [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) · [Paquets Arch (DeepWiki)](https://deepwiki.com/end-4/dots-hyprland/7.1-arch-linux-packages)
- [Lua-ification des configs Hyprland](https://hypr.land/news/26_lua/) · [Quickshell](https://quickshell.org/)
- [TUIs — The Omarchy Manual](https://omarchy.org/manual/tuis/)
