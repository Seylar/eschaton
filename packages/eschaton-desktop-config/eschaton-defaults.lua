-- Défauts Hyprland d'Eschaton — /usr/share/eschaton/hypr/eschaton-defaults.lua
--
-- Ce fichier appartient à pacman. Il n'est JAMAIS copié dans ~/.config/hypr/ :
-- l'arbre ~/.config/hypr/ tout entier appartient à DMS (spec Bureau §4.2, règle
-- amendée le 2026-08-28). Il est chargé par un `dofile()` d'une seule ligne posé
-- dans ~/.config/hypr/dms/binds-user.lua — le seul fichier de l'arbre que
-- `dms setup` préserve ET que le hyprland.lua généré par DMS charge toujours
-- (avant-dernier `require`, donc APRÈS toute la configuration DMS : ce qui est
-- réglé ici gagne).
--
-- S'en passer : retirer la ligne `dofile(...)` de ~/.config/hypr/dms/binds-user.lua.
-- eschaton-session ne la repose pas — il ne l'écrit qu'une fois, et retient
-- l'avoir fait dans ~/.config/hypr/.eschaton-hook.

hl.config({
	input = {
		-- Volontairement vide : libxkbcommon hérite alors de XKB_DEFAULT_LAYOUT,
		-- que /usr/bin/eschaton-session pose à « fr » quand la variable n'est pas
		-- déjà définie. Sans cette ligne, Hyprland impose son défaut « us » et la
		-- variable d'environnement est ignorée. C'est exactement la convention du
		-- hyprland.lua généré par DMS, qui commente sa propre ligne ainsi :
		-- « empty inherits XKB_DEFAULT_LAYOUT (libxkbcommon), falls back to "us" ».
		kb_layout = "",
	},
	misc = {
		-- DMS peint son propre fond d'écran ; le logo et le splash d'Hyprland
		-- n'apparaissent qu'au démarrage, avant que la barre ne prenne la main.
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
	},
})

-- Surface système omniprésente : le daemon DMS expose toggle() et reste le
-- seul point d'entrée. Aucun terminal ni agent CLI intermédiaire.
hl.bind("SUPER + A", hl.dsp.exec_cmd("dms ipc call plugins toggle eschatonAssistant"), {
	description = "Assistant Eschaton",
})

-- Les surfaces layer-shell de DMS (fond d'écran, barre, popouts) ne doivent pas
-- être animées : elles ne sont pas des fenêtres, et l'animation d'entrée les
-- fait clignoter à chaque rechargement de configuration.
hl.layer_rule({ match = { namespace = "^(quickshell)$" }, no_anim = true })
hl.layer_rule({ match = { namespace = "^dms:.*" }, no_anim = true })
