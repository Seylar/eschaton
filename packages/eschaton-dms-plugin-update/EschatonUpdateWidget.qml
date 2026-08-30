import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Le panneau de mise à jour.
//
// Il ne PORTE pas la transaction : il ouvre la porte privilégiée
// (`pkexec eschaton-update-helper --apply`), qui confie la transaction à une
// unité systemd, puis il se contente de REGARDER — le journal de l'unité et
// son fichier d'état. C'est ce qui permet de fermer le panneau, de recharger
// la configuration du shell ou de perdre un fil sans toucher à `pacman`.
//
// Aucun shell n'est lancé ici : chaque Process a un argv constant.
PluginComponent {
    id: root

    // ————————————————————————— état observé —————————————————————————
    property int updateCount: 0
    property bool checking: false
    property string checkError: ""

    // "" (rien en cours) · "authentification" · "en-cours" · "termine"
    property string phase: ""
    // "" · succes · succes-degrade · succes-non-verifie · echec · echec-prevol
    // · decision-humaine · annule · interrompu · verdict-inconnu
    property string resultat: ""
    property int codeResultat: 0
    property bool noyauARecharger: false
    property bool annulationEnCours: false
    property string erreurPorte: ""
    property bool _uniteActive: false
    // Vrai le temps de la toute première sonde, celle qui cherche une
    // transaction que le panneau n'a PAS lancée (voir reconcilier()).
    property bool _reconciliation: false
    // Combien de sondes consécutives ont vu l'unité éteinte SANS verdict écrit.
    // Conclure sur une seule lecture confondait un repli en cours avec une
    // disparition — voir la sonde.
    property int _lecturesTerminales: 0

    // Les états que `systemctl is-active` rend pour une unité qui n'a pas fini.
    // `deactivating` en fait partie, et son absence était un défaut : une
    // annulation y passe forcément, pendant tout le repli de pacman. Le panneau
    // la lisait comme une unité éteinte, concluait « interrompu » — toast rouge
    // « La mise à jour a échoué » — et ARRÊTAIT la sonde, si bien que le
    // `resultat=annule` réellement écrit ensuite n'était jamais lu. Corrigé le
    // 2026-08-30 (revue de sécurité I4).
    readonly property var etatsUniteVivante:
        ["active", "activating", "deactivating", "reloading", "refreshing"]
    // Le point de retour calculé par la transaction avant d'agir. C'est lui
    // qui rend l'échec réversible sans ligne de commande.
    property int snapshotAvant: 0
    property string unitesEnEchec: ""
    property bool confirmRestauration: false
    property bool restaurationEnCours: false
    // Instant du clic, en secondes. Il borne à la fois le suivi en direct et
    // la relecture finale : on ne rejoue jamais le journal d'une transaction
    // précédente.
    property int _debutEpoch: 0

    property int maxLignes: 600

    property int checkIntervalMinutes: {
        const parsed = parseInt(pluginData.checkIntervalMinutes || "30");
        return isNaN(parsed) ? 30 : Math.max(5, parsed);
    }

    readonly property bool transactionActive: phase === "authentification" || phase === "en-cours"

    readonly property string resumeResultat: {
        switch (resultat) {
        case "succes":
            return noyauARecharger
                ? "Mise à jour installée. Redémarrez pour utiliser le nouveau noyau."
                : "Mise à jour installée.";
        case "succes-degrade":
            // Archétype dovecot 2.4 : pacman réussit, le service ne repart pas.
            // Le code de retour dirait « succès » ; nous, non.
            return "Paquets installés, mais des services ne démarrent plus : " + unitesEnEchec;
        case "succes-non-verifie":
            // Interrompue APRÈS l'installation, pendant le contrôle des
            // services. On ne cache pas que le système est à jour, et on ne
            // prétend pas avoir vérifié ce qu'on n'a pas vérifié.
            return "Mise à jour installée, mais le contrôle des services n'a pas pu être fait.";
        case "annule":
            return "Mise à jour annulée. Rien n'a été installé.";
        case "decision-humaine":
            return "Cette mise à jour demande une décision humaine. Rien n'a été modifié.";
        case "echec-prevol":
            return "La transaction ne se résout pas (code " + codeResultat + "). Rien n'a été modifié.";
        case "echec":
            return "La mise à jour a échoué (code " + codeResultat + ").";
        case "interrompu":
            return "La mise à jour s'est interrompue sans rendre de résultat.";
        case "verdict-inconnu":
            // Le pré-vol a rendu un mot que la transaction ne sait pas
            // interpréter : elle s'arrête sans rien modifier plutôt que de
            // continuer sur un état inconnu (fail-closed, cf. eschaton-update).
            return "Le pré-vol a rendu un verdict inattendu. Rien n'a été modifié.";
        default:
            return "";
        }
    }

    readonly property bool resultatEstUnEchec:
        resultat === "echec" || resultat === "echec-prevol"
        || resultat === "decision-humaine" || resultat === "interrompu"
        || resultat === "succes-degrade" || resultat === "verdict-inconnu"

    // La restauration n'est proposée que lorsqu'elle a un sens : quelque chose
    // a été modifié, et un point de retour existe. Après un échec de pré-vol,
    // rien n'a bougé — proposer un rollback y serait du bruit alarmiste.
    //
    // `succes-non-verifie` y a été ajouté le 2026-08-30 (revue de sécurité M4).
    // C'est l'état « installé mais NON vérifié » : les paquets sont en place et
    // le contrôle des services n'a pas pu être fait. C'est exactement la
    // situation où l'utilisateur peut avoir besoin de revenir en arrière —
    // l'omettre lui retirait la porte de sortie au moment où l'incertitude est
    // la plus grande.
    readonly property bool restaurationUtile:
        (resultat === "echec" || resultat === "succes-degrade"
         || resultat === "interrompu" || resultat === "succes-non-verifie")
        && snapshotAvant > 0

    // ————————————————————————— actions —————————————————————————
    function refresh() {
        if (checking || transactionActive)
            return;
        checking = true;
        checkError = "";
        checkProcess.running = true;
    }

    // Le suivi en direct, borné au début de LA transaction observée. Partagé
    // par le lancement depuis le panneau et par l'adoption d'une transaction
    // lancée ailleurs : les deux regardent la même unité, de la même façon.
    function suivreJournal() {
        journalProcess.command = [
            "/usr/bin/journalctl",
            "--no-pager",
            "-q",
            "-f",
            "-o", "cat",
            "-u", "eschaton-update.service",
            "--since", "@" + _debutEpoch
        ];
        journalProcess.running = true;
    }

    // Relecture COMPLÈTE du journal de cette transaction, sans `-f`.
    //
    // Mesuré le 2026-08-30 : le suiveur était arrêté à l'instant même où la
    // sonde voyait l'unité s'éteindre, et la fin du journal n'arrivait jamais.
    // Sur le cas « décision humaine », le panneau affichait donc tout sauf LA
    // question — précisément ce que l'utilisateur doit lire. Une relecture
    // bornée supprime la course au lieu de la temporiser.
    function relireJournal() {
        journalProcess.running = false;
        journalFinalProcess.command = [
            "/usr/bin/journalctl",
            "--no-pager",
            "-q",
            "-o", "cat",
            "-u", "eschaton-update.service",
            "--since", "@" + _debutEpoch
        ];
        journalFinalProcess.running = true;
    }

    function startUpdate() {
        if (transactionActive)
            return;
        journalModel.clear();
        resultat = "";
        codeResultat = 0;
        noyauARecharger = false;
        erreurPorte = "";
        annulationEnCours = false;
        snapshotAvant = 0;
        unitesEnEchec = "";
        confirmRestauration = false;
        _lecturesTerminales = 0;
        phase = "authentification";
        // `--since` sur l'instant du clic : on ne rejoue pas le journal des
        // transactions précédentes, et on ne rate pas les premières lignes de
        // celle-ci si l'unité démarre avant que le suiveur soit prêt.
        _debutEpoch = Math.floor(Date.now() / 1000);
        suivreJournal();
        applyProcess.running = true;
    }

    // ————————————————— adoption d'une transaction tierce —————————————————
    //
    // LE PANNEAU NE PORTE PAS LA TRANSACTION, donc il ne doit pas supposer
    // l'avoir lancée. Jusqu'au 2026-08-30 la sonde n'était armée que par
    // `phase === "en-cours"`, c'est-à-dire uniquement après un clic sur
    // « Installer ». Deux conséquences, toutes deux corrigées ici (revue de
    // sécurité I3) :
    //
    //   - une mise à jour déclenchée par l'ASSISTANT (`trigger_update`)
    //     n'affichait rien, alors que `tool-catalog.json` promet au modèle que
    //     « sa progression s'affiche dans le panneau « Mises à jour » ».
    //     L'artefact mentait au modèle qui le lit ;
    //   - après un rechargement du shell — qui arrive, et que la spec §5.3
    //     revendique comme sans effet sur la transaction — le verdict n'était
    //     jamais rendu à personne.
    //
    // La réconciliation lit les deux mêmes sources que la sonde : l'état de
    // l'unité, et le fichier d'état de la transaction.
    function reconcilier(champs) {
        const resultatLu = champs.resultat || "";
        if (!resultatLu)
            return;   // rien ne s'est passé depuis le démarrage : /run est vide

        // L'instant de début est publié par la transaction elle-même. C'est lui
        // qui borne le journal, exactement comme l'instant du clic le fait pour
        // une transaction que nous avons lancée — sans quoi nous rejouerions le
        // journal de toutes les transactions du boot.
        const debut = Date.parse(champs.debut || "");
        _debutEpoch = isNaN(debut) ? 0 : Math.floor(debut / 1000);

        if (_uniteActive) {
            // Une transaction est EN VOL, et ce n'est pas nous qui l'avons
            // lancée. On l'adopte : même journal, même sonde, même verdict à
            // l'arrivée. Le bouton « Annuler » redevient disponible avec elle.
            journalModel.clear();
            resultat = "";
            codeResultat = 0;
            erreurPorte = "";
            annulationEnCours = false;
            confirmRestauration = false;
            _lecturesTerminales = 0;
            phase = "en-cours";
            suivreJournal();
            return;
        }

        if (resultatLu === "en-cours")
            return;   // unité éteinte sans verdict : rien d'honnête à afficher

        // Transaction déjà terminée. On rend le verdict et son journal, mais
        // SANS notification : un toast annoncerait comme un événement ce qui
        // n'est qu'un constat, et se répéterait à chaque rechargement du shell.
        phase = "termine";
        resultat = resultatLu;
        codeResultat = parseInt(champs.code || "0") || 0;
        relireJournal();
    }

    function cancelUpdate() {
        if (phase !== "en-cours" || annulationEnCours)
            return;
        annulationEnCours = true;
        cancelProcess.running = true;
    }

    // La porte de sortie de la spec §4 : l'échec reste réversible sans ligne de
    // commande. On emprunte EXACTEMENT la commande du panneau de restauration —
    // même binaire, même action polkit `org.eschaton.rollback`. Aucun second
    // chemin privilégié n'est ouvert ici ; seule la cible est déjà connue,
    // puisque la transaction l'a calculée avant d'agir.
    function restaurerAvantMiseAJour() {
        if (!restaurationUtile || restaurationEnCours)
            return;
        if (!confirmRestauration) {
            confirmRestauration = true;
            return;
        }
        restaurationEnCours = true;
        restoreProcess.command = [
            "/usr/bin/pkexec", "/usr/bin/eschaton-rollback",
            "--yes", String(snapshotAvant)
        ];
        restoreProcess.running = true;
    }

    // Le journal est la seule source de progression : il n'est jamais résumé
    // ni réécrit. On coupe seulement les barres de progression de pacman, qui
    // réécrivent la même ligne à coups de retour chariot — on garde leur
    // dernier état, ce qui est ce que le terminal aurait montré.
    function ajouterLigne(brute) {
        const segments = String(brute).split("\r");
        const ligne = segments[segments.length - 1];
        if (!ligne.trim())
            return;
        journalModel.append({ texte: ligne });
        while (journalModel.count > maxLignes)
            journalModel.remove(0);
    }

    function lireEtat(texte) {
        const champs = {};
        const lignes = String(texte).split("\n");
        for (let i = 0; i < lignes.length; i++) {
            const separateur = lignes[i].indexOf("=");
            if (separateur > 0)
                champs[lignes[i].slice(0, separateur)] = lignes[i].slice(separateur + 1).trim();
        }
        return champs;
    }

    function terminer(nouveauResultat, code) {
        relireJournal();
        annulationEnCours = false;
        confirmRestauration = false;
        phase = "termine";
        resultat = nouveauResultat;
        codeResultat = code;
        Qt.callLater(root.refresh);
        if (nouveauResultat === "succes") {
            ToastService.showInfo("Eschaton est à jour", root.resumeResultat);
        } else if (nouveauResultat === "annule") {
            ToastService.showInfo("Mise à jour annulée", "Rien n'a été installé.");
        } else if (nouveauResultat === "succes-degrade") {
            // Le code de retour disait « succès ». On ne le répète pas.
            ToastService.showError("Mise à jour installée, système dégradé", root.resumeResultat);
        } else if (nouveauResultat === "succes-non-verifie") {
            ToastService.showInfo("Mise à jour installée", root.resumeResultat);
        } else {
            ToastService.showError("La mise à jour a échoué", root.resumeResultat);
        }
    }

    Component.onCompleted: {
        // Première chose : chercher une transaction qui tournerait déjà, ou un
        // verdict que personne n'a encore lu (voir reconcilier()).
        _reconciliation = true;
        uniteProcess.running = true;
        Qt.callLater(root.refresh);
    }

    Timer {
        interval: root.checkIntervalMinutes * 60 * 1000
        repeat: true
        running: !root.transactionActive
        onTriggered: root.refresh()
    }

    // Sonde d'état. Le journal dit ce qui se passe ; l'unité et le fichier
    // d'état disent si c'est fini, et comment.
    Timer {
        id: sonde
        interval: 1000
        repeat: true
        running: root.phase === "en-cours"
        onTriggered: {
            if (!uniteProcess.running && !etatProcess.running)
                uniteProcess.running = true;
        }
    }

    ListModel { id: journalModel }

    Process {
        id: checkProcess
        command: ["/usr/bin/checkupdates"]
        running: false

        stdout: StdioCollector { id: checkOutput }
        stderr: StdioCollector { id: checkErrorOutput }

        onExited: function(exitCode, exitStatus) {
            root.checking = false;
            if (exitCode === 0) {
                const lines = checkOutput.text.trim();
                root.updateCount = lines ? lines.split("\n").length : 0;
                root.checkError = "";
            } else if (exitCode === 2) {
                // checkupdates documente rc=2 pour « aucune mise à jour ».
                root.updateCount = 0;
                root.checkError = "";
            } else {
                root.checkError = checkErrorOutput.text.trim() || "Vérification impossible";
            }
        }
    }

    // La porte. Argv constant, aucune option d'auto-approbation : c'est
    // `eschaton-update-helper` qui décide, et lui seul.
    Process {
        id: applyProcess
        command: ["/usr/bin/pkexec", "/usr/bin/eschaton-update-helper", "--apply"]
        running: false
        stderr: StdioCollector { id: applyError }

        onExited: function(exitCode, exitStatus) {
            if (exitCode === 0) {
                root.phase = "en-cours";
                uniteProcess.running = true;
                return;
            }
            // 126/127 : pkexec, autorisation refusée ou modale annulée.
            root.erreurPorte = applyError.text.trim();
            journalProcess.running = false;
            root.phase = "";
            if (exitCode === 126 || exitCode === 127) {
                ToastService.showInfo("Mise à jour non lancée",
                                      "L'authentification a été refusée ou annulée.");
            } else {
                ToastService.showError("Mise à jour impossible",
                                       root.erreurPorte || ("La porte a rendu le code " + exitCode + "."));
            }
        }
    }

    // L'annulation passe par LA MÊME porte : il n'existe pas de second chemin
    // privilégié. Elle coûte donc, elle aussi, une authentification.
    Process {
        id: cancelProcess
        command: ["/usr/bin/pkexec", "/usr/bin/eschaton-update-helper", "--cancel"]
        running: false
        stderr: StdioCollector { id: cancelError }

        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) {
                root.annulationEnCours = false;
                ToastService.showError("Annulation impossible",
                                       cancelError.text.trim()
                                       || ("La porte a rendu le code " + exitCode + "."));
            }
            // En cas de succès, c'est la sonde qui constatera l'arrêt et lira
            // le résultat : l'interface ne décide jamais du verdict elle-même.
        }
    }

    // La porte de sortie. Même binaire et même action polkit que le panneau de
    // restauration : `org.eschaton.rollback`, `auth_admin` sans `_keep`.
    Process {
        id: restoreProcess
        running: false
        stdout: StdioCollector { id: restoreOutput }
        stderr: StdioCollector { id: restoreError }

        onExited: function(exitCode, exitStatus) {
            root.restaurationEnCours = false;
            root.confirmRestauration = false;
            if (exitCode === 0) {
                ToastService.showInfo(
                    "Restauration prête",
                    "Redémarrez pour démarrer sur le snapshot " + root.snapshotAvant + "."
                );
            } else if (exitCode === 126 || exitCode === 127) {
                ToastService.showInfo("Restauration non lancée",
                                      "L'authentification a été refusée ou annulée.");
            } else {
                ToastService.showError("Restauration impossible",
                                       restoreError.text.trim() || restoreOutput.text.trim()
                                       || ("eschaton-rollback a quitté avec le code " + exitCode + "."));
            }
        }
    }

    // Le suiveur de journal appartient à l'interface, pas à la transaction :
    // le tuer, ou perdre le panneau, n'a aucun effet sur `pacman`.
    Process {
        id: journalProcess
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: ligne => root.ajouterLigne(ligne)
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: ligne => root.ajouterLigne(ligne)
        }
    }

    Process {
        id: journalFinalProcess
        running: false
        stdout: StdioCollector { id: journalFinalOutput }

        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0)
                return;   // on garde alors ce que le suivi en direct a capté
            const lignes = journalFinalOutput.text.split("\n");
            journalModel.clear();
            for (let i = 0; i < lignes.length; i++)
                root.ajouterLigne(lignes[i]);
        }
    }

    Process {
        id: uniteProcess
        command: ["/usr/bin/systemctl", "is-active", "eschaton-update.service"]
        running: false
        stdout: StdioCollector { id: uniteOutput }

        onExited: function(exitCode, exitStatus) {
            // `is-active` rend un code non nul dès que l'unité n'est plus
            // active : c'est la SORTIE qui porte l'information.
            //
            // On teste l'appartenance aux états VIVANTS, jamais l'égalité à
            // « active » seul : `deactivating` est l'état de tout le repli de
            // pacman après un `systemctl stop`, et le prendre pour une unité
            // éteinte transformait chaque annulation un peu lente en échec
            // (revue de sécurité I4).
            root._uniteActive =
                root.etatsUniteVivante.indexOf(uniteOutput.text.trim()) !== -1;
            etatProcess.running = true;
        }
    }

    Process {
        id: etatProcess
        command: ["/usr/bin/cat", "/run/eschaton-update/etat"]
        running: false
        stdout: StdioCollector { id: etatOutput }

        onExited: function(exitCode, exitStatus) {
            const champs = exitCode === 0 ? root.lireEtat(etatOutput.text) : ({});
            root.noyauARecharger = champs.noyau_a_recharger === "oui";
            root.snapshotAvant = parseInt(champs.snapshot_avant || "0") || 0;
            root.unitesEnEchec = champs.unites_en_echec || "";

            // La toute première sonde ne conclut pas : elle adopte, ou rend un
            // verdict que personne n'avait lu.
            if (root._reconciliation) {
                root._reconciliation = false;
                root.reconcilier(champs);
                return;
            }

            if (root._uniteActive) {
                root._lecturesTerminales = 0;
                return;
            }
            if (root.phase !== "en-cours")
                return;
            const resultatLu = champs.resultat || "";
            if (!resultatLu || resultatLu === "en-cours") {
                // L'unité paraît éteinte sans que la transaction ait écrit son
                // verdict. Avant de le croire, on le CONFIRME : le filet de
                // sortie de la transaction écrit toujours un verdict, donc
                // cette combinaison désigne presque toujours l'instant précis
                // du repli, pas une disparition. Conclure sur une seule lecture
                // rendait « interrompu » — toast rouge — pour une annulation
                // parfaitement propre, et arrêtait la sonde avant que le
                // `resultat=annule` réel ne soit lisible (revue I4).
                root._lecturesTerminales += 1;
                if (root._lecturesTerminales < 3)
                    return;
                // Trois secondes d'unité éteinte sans un mot : là, on ne
                // prétend pas savoir — et surtout on n'appelle pas ça un succès.
                root.terminer("interrompu", 0);
                return;
            }
            root.terminer(resultatLu, parseInt(champs.code || "0") || 0);
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.transactionActive || root.checking ? "sync" : "system_update_alt"
                size: root.iconSize
                color: root.checkError || root.resultatEstUnEchec
                    ? Theme.error
                    : (root.transactionActive || root.updateCount > 0 ? Theme.primary : Theme.surfaceVariantText)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.updateCount > 0 ? String(root.updateCount) : ""
                visible: root.updateCount > 0 && !root.transactionActive
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Bold
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 0
            DankIcon {
                name: root.transactionActive || root.checking ? "sync" : "system_update_alt"
                size: root.iconSize
                color: root.checkError || root.resultatEstUnEchec
                    ? Theme.error
                    : (root.transactionActive || root.updateCount > 0 ? Theme.primary : Theme.surfaceVariantText)
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.updateCount > 0 ? String(root.updateCount) : ""
                visible: root.updateCount > 0 && !root.transactionActive
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Bold
                color: Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: updatePopout
            headerText: "Mises à jour Eschaton"
            detailsText: {
                if (root.phase === "authentification")
                    return "Authentification requise…";
                if (root.phase === "en-cours")
                    return root.annulationEnCours ? "Annulation en cours…" : "Mise à jour en cours…";
                if (root.phase === "termine")
                    return root.resumeResultat;
                if (root.checkError)
                    return root.checkError;
                if (root.checking)
                    return "Vérification en cours…";
                return root.updateCount > 0
                    ? root.updateCount + " mise(s) à jour disponible(s)"
                    : "Le système est à jour";
            }
            showCloseButton: true

            // Le badge est périodique, mais ouvrir le popout exprime une demande
            // immédiate. Sans cette relecture, il peut encore annoncer une
            // mise à jour déjà installée pendant tout l'intervalle du Timer.
            Connections {
                target: updatePopout.parentPopout
                function onShouldBeVisibleChanged() {
                    if (updatePopout.parentPopout?.shouldBeVisible)
                        Qt.callLater(root.refresh);
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM
                topPadding: Theme.spacingM

                StyledText {
                    width: parent.width
                    visible: root.phase === ""
                    text: "L'installation crée automatiquement les snapshots snap-pac avant et après la transaction. Une authentification est demandée à chaque mise à jour."
                    wrapMode: Text.WordWrap
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                }

                // La sortie de pacman, telle quelle. Jamais résumée, jamais
                // avalée : c'est elle qui remplace le terminal.
                StyledRect {
                    width: parent.width
                    // DMS plafonne la hauteur d'un popout de greffon (mesuré :
                    // 479 px, quelle que soit `popoutHeight`). Quand l'échec
                    // ajoute son explication et l'offre de retour arrière, le
                    // journal doit donc céder de la place — sans quoi c'est la
                    // rangée de boutons qui sort du cadre, et la porte de
                    // sortie devient inatteignable au moment où elle sert.
                    height: root.phase === "termine" && root.resultatEstUnEchec ? 150 : 250
                    visible: root.phase !== ""
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    ListView {
                        id: journalView
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        clip: true
                        model: journalModel
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: DankScrollbar { }

                        onCountChanged: Qt.callLater(function() { journalView.positionViewAtEnd(); })

                        delegate: StyledText {
                            required property string texte
                            width: journalView.width
                            text: texte
                            // Donnée machine affichée telle quelle : jamais
                            // interprétée comme du balisage.
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: journalModel.count === 0
                        text: root.phase === "authentification"
                            ? "En attente de l'authentification…"
                            : "En attente de la première ligne du journal…"
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                StyledText {
                    width: parent.width
                    visible: root.phase === "termine" && root.resultatEstUnEchec
                    text: {
                        if (root.resultat === "succes-degrade")
                            return "Les paquets sont installés, mais " + root.unitesEnEchec
                                + " ne démarre(nt) plus. Le code de retour de pacman disait « succès » — pas nous.";
                        if (root.resultat === "decision-humaine")
                            return "pacman a posé une question à laquelle Eschaton refuse de répondre à votre place. La question exacte est dans le journal ci-dessus, ainsi que, le cas échéant, la nouvelle Arch qui la documente. Rien n'a été modifié.";
                        return "Rien n'a été approuvé à votre place. La sortie exacte de pacman est ci-dessus, telle quelle.";
                    }
                    // `unitesEnEchec` vient de `systemctl list-units` : une
                    // donnée machine interpolée dans du texte affiché. Comme le
                    // délégué du journal, on interdit toute interprétation en
                    // balisage plutôt que de parier sur le jeu de caractères
                    // des noms d'unités (revue de sécurité M5).
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.error
                    font.pixelSize: Theme.fontSizeSmall
                }

                // L'échec reste réversible SANS ligne de commande : c'est ce que
                // personne d'autre n'offre, et c'est ce qui rend tenable de
                // refuser de répondre à la place de l'utilisateur.
                StyledText {
                    width: parent.width
                    visible: root.restaurationUtile
                    text: root.confirmRestauration
                        ? "Le système redémarrera sur l'état d'avant la mise à jour (snapshot "
                          + root.snapshotAvant + "). L'état actuel n'est pas détruit : il est mis de côté."
                        : "Un point de retour existe : l'état d'avant cette mise à jour (snapshot "
                          + root.snapshotAvant + ")."
                    // Même règle que ci-dessus : rien de ce qui vient du
                    // fichier d'état n'est interprété comme du balisage.
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingM

                    DankButton {
                        text: "Actualiser"
                        iconName: "refresh"
                        enabled: !root.checking && !root.transactionActive
                        onClicked: root.refresh()
                    }

                    DankButton {
                        text: root.phase === "authentification" ? "Authentification…"
                            : (root.phase === "en-cours" ? "Mise à jour en cours" : "Installer")
                        iconName: "system_update_alt"
                        enabled: !root.checking && !root.transactionActive && !root.checkError
                        onClicked: root.startUpdate()
                    }

                    DankButton {
                        text: root.annulationEnCours ? "Annulation…" : "Annuler"
                        iconName: "cancel"
                        visible: root.phase === "en-cours"
                        enabled: !root.annulationEnCours
                        backgroundColor: Theme.error
                        textColor: Theme.surface
                        onClicked: root.cancelUpdate()
                    }

                    DankButton {
                        text: root.restaurationEnCours ? "Restauration…"
                            : (root.confirmRestauration
                               ? "Confirmer le retour au snapshot " + root.snapshotAvant
                               : "Revenir à l'état d'avant")
                        iconName: root.confirmRestauration ? "warning" : "restore"
                        visible: root.restaurationUtile
                        enabled: !root.restaurationEnCours
                        backgroundColor: root.confirmRestauration ? Theme.error : Theme.primary
                        textColor: root.confirmRestauration ? Theme.surface : Theme.onPrimary
                        onClicked: root.restaurerAvantMiseAJour()
                    }
                }
            }
        }
    }

    popoutWidth: 560
    // Valeur demandée ; DMS la plafonne (mesuré : 479 px de haut effectifs).
    // C'est pourquoi la boîte du journal se rétracte dans les cas d'échec —
    // voir son commentaire.
    popoutHeight: 500
}
