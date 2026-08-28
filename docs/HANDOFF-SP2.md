# Reprise SP2 (Bureau) — document de passage de relais

- **Date** : 2026-08-29. **Branche de travail : `bureau`** (issue de `main` post-fusion du Socle).
- **Contexte** : le développement est piloté par sessions Claude (méthode subagent + revues) ; ce document permet à un autre agent/dev (Codex…) de reprendre **sans le contexte de session**. Les conventions et l'autorité des documents restent inchangées.

## 1. Où on en est

- **Socle v0.1.0 : terminé, fusionné dans `main`, taggé.** Ne pas y toucher. Bilan : `docs/superpowers/bilans/2026-08-28-socle-execution.md`.
- **SP2 Bureau : Tasks 1–4 faites** (sur 9) :
  - T1 (spike rendu) : validé — Quickshell/DMS rendent sous virtio-gpu ; Hyprland exige `LIBGL_ALWAYS_SOFTWARE=1` (réglage **de la VM**, jamais des paquets).
  - T2 (`eschaton-desktop-config`) : livré et prouvé en session réelle (wrapper `eschaton-session`, greetd par drop-in, canal d'accroche via `dms/binds-user.lua`, target `hyprland-session.target` comblé).
  - T3 (meta `eschaton-desktop` + wallpaper + hook preset) : livré (14 depends dont `pipewire-pulse` — correction, pas précaution ; hook alpm `systemctl preset greetd.service` qui marche AUSSI en chroot/pacstrap).
  - T4 (`tools/check-desktop-deps`, garde CI bi-arch) : livré **et revu (Approved)** — le reviewer a reproduit chaque claim par exécution indépendante. 4 mineurs différés (commentaires inexacts : pipefail « premier étage », renvoi « Tasks 4 et 5 » au lieu de T5/T6 ; raffinements de contrat de sortie sur chemins d'erreur déjà bruyants) — corrigeables au fil de l'eau, rien de bloquant.
- **Restent : T5 à T9** (voir §4).
- **Rien de la vague SP2 n'est publié** : c'est voulu (le dépôt pacman publié ne doit pas référencer un meta dont les plugins n'existent pas). La publication est l'affaire de T6.

## 2. Les documents qui font foi (ordre d'autorité)

1. **Spec Bureau (amendée au fil des constats — c'est L'AUTORITÉ)** : `docs/superpowers/specs/2026-08-28-bureau-design.md`. Ses §4 (invariants Lua + propriété de `~/.config/hypr/`), §3 (table des paquets, mécanisme du plugin rollback = **méthode replace**, PAS `snapper rollback`), §7 (risques — 1 et 10 levés) sont à jour.
2. **Plan Bureau** : `docs/superpowers/plans/2026-08-28-bureau.md` — bonne structure des tâches, MAIS écrit avant les constats : là où il contredit la spec ou le §3 ci-dessous, **la spec et le §3 gagnent**.
3. **Guide opérationnel VM** : `tools/vm-dev.md` — §5+§9.2 (pilotage console série via `tools/vm-serial`), §8 (installation), §12 (spike bureau : inventaire, `dms setup` mesuré, §12.9 réserves), §13 (constats T2 : LIBGL dans le greetd.toml de la VM, pièges).
4. Veille : `docs/veille/2026-08-28-sp2-bureau.md` (anatomie plugin.json §3.1, sources API).

## 3. Rulings actifs que le plan NE contient PAS (à respecter)

- **Rollback (T6)** : le plan dit encore « rollback via l'API snapperd » — **FAUX** (réfuté : snapperd n'expose pas de rollback ; `snapper rollback` échoue sur notre layout). Le plugin **liste** via snapperd D-Bus (lecture seule) et **restaure** en orchestrant la logique replace d'`eschaton-rollback` (voir `packages/eschaton-base/eschaton-rollback`) derrière une surface privilégiée à choisir (pkexec autour d'un mode non interactif à ajouter à `eschaton-rollback` — probablement `--yes <num>` — est la voie pressentie ; règle polkit livrée par le paquet plugin).
- **Polkit** : AUCUN agent polkit externe à ajouter — le greffon du `qs` d'`extra` fonctionne (le « Not available » de `dms doctor` est un faux négatif, prouvé T2).
- **Publication (T6)** : la CI ne tourne que sur `main`. Pour publier la vague SP2 AVANT fusion : rouvrir temporairement `.github/workflows/ci.yml` à la branche `bureau` (trigger + condition deploy) + recréer une deployment branch policy `bureau` sur l'environnement `github-pages` (`gh api`) — et REFERMER tout ça à la fusion (même motif que le Socle).
- **Builds** : meta/configs/plugins = `tools/build-pkg <pkg> -d` (makepkg vérifie les depends même pour un meta). Conteneurs : tout pacman avec `--disable-sandbox` (Landlock cassé sous Docker).
- **VM** : jamais `ping` (ICMP bloqué par le NAT UTM) — `curl -fsI https://archlinux.org`. Pilotage : `tools/vm-serial` (le pty change à chaque boot). VM `eschaton-dev` : user `seylar`/`eschaton` (dev uniquement). Ne pas réinstaller la VM ; T7 installera les paquets par-dessus. La VM x86 `eschaton-x86-smoke` existe — ne pas y toucher pour SP2.
- **Conventions paquets** (motif Socle, copier un PKGBUILD existant) : `arch=(any)`, symlink `LICENSE -> ../../LICENSE` dans chaque dossier de paquet + `LICENSE` dans `source=()` + `install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"`, `sha256sums=(SKIP…)`, `backup=()` pour toute config éditable, pkgrel bump à tout changement d'un paquet déjà publié. `requires_dms: ">=1.5.0"` obligatoire dans chaque `plugin.json`.
- **Discipline** : tout correctif va dans le repo (jamais VM-seulement) ; toute affirmation de comportement se prouve par une exécution réelle dont la sortie est consignée ; ce qu'une investigation révèle de contraire aux docs REMONTE dans les docs (ADR 0002).

## 4. Les prochaines étapes (T5 → T9)

Suivre le plan (`docs/superpowers/plans/2026-08-28-bureau.md`) avec les corrections ci-dessus. Résumé opérationnel :

1. **T5 — `eschaton-dms-plugin-update`** : commencer par une étude dirigée d'un plugin `widget` first-party (`github.com/AvengeMedia/dms-plugins` + doc versionnée 1.5) pour copier les motifs réels (imports `qs.*`, héritage `PluginComponent`, exécution de process). Puis : `plugin.json` (anatomie : veille §3.1 ; id `eschatonUpdate`), widget badge de mises à jour (`checkupdates`, paquet `pacman-contrib` en depends) + déclenchement d'`eschaton-update`. Installe sous `/etc/xdg/quickshell/dms-plugins/eschatonUpdate/`. Validation : `jq` du manifest, `qmllint` (tolérer les imports qs.* non résolus hors DMS), build `-d`. Test réel de chargement : en VM, `dms ipc call plugins reload eschatonUpdate`.
2. **T6 — `eschaton-dms-plugin-rollback` + publication** : plugin (mécanisme du §3 ci-dessus — ruling rollback), règle polkit scopée `org.opensuse.Snapper.*` pour `wheel` (lecture) + la surface privilégiée pour la restauration ; mode non interactif d'`eschaton-rollback` ajouté à `eschaton-base` (avec bats, pkgrel bump). Puis : rouvrir la CI à `bureau` (ruling publication), pousser la vague, CI verte, vérifier `pacman -Si eschaton-desktop` depuis la sandbox sur `https://seylar.github.io/eschaton/$arch`.
3. **T7 — installation réelle du bureau en VM** : ajouter `env LIBGL_ALWAYS_SOFTWARE=1` au greetd.toml de la VM (procédure vm-dev §13.1), `sudo pacman -Syu && sudo pacman -S eschaton-desktop`, reboot → session graphique auto-login SANS autre étape. Vérifier : les 2 plugins visibles, btrfs-assistant se lance (polkit), invariant Lua (`hyprctl getoption input:kb_layout` → fr). **Arbitrages « écran en main » consignés à faire** : back-end FileChooser (`xdg-desktop-portal-gtk` ?), `noto-fonts-emoji`, banding du wallpaper, branchement du wallpaper dans DMS (mécanisme à constater).
4. **T8 — tests réels des plugins** : une mise à jour déclenchée DEPUIS le widget (paire snap-pac + entrées limine à l'appui) ; un rollback réel DEPUIS le widget (marqueur /home intact, paquet-témoin disparu au reboot). `dms ipc call plugins reload` prouvé.
5. **T9 — clôture** : dérouler la définition de terminé (spec §6, 6 points), statut spec → implémenté, tag `v0.2.0`, push. (La revue de branche complète et la fusion vers `main` se feront au retour de la session Claude — laisser la branche `bureau` en l'état, NE PAS fusionner.)

## 5. État git au moment du handoff

- `bureau` = `main` + travaux SP2. Les commits T3/T4 étaient volontairement locaux ; **ils sont poussés avec ce document** (sans risque : la CI ne se déclenche que sur `main`).
- Workspace `.superpowers/` : artefacts de session Claude, gitignorés — ignorer.
- `caffeinate` tourne sur le Mac (empêche la veille) ; VMs UTM : `eschaton-dev` démarrée, `eschaton-x86-smoke` arrêtée.
