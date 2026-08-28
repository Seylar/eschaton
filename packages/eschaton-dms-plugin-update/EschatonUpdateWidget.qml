import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property int updateCount: 0
    property bool checking: false
    property bool updateRunning: false
    property string checkError: ""
    property int checkIntervalMinutes: {
        const parsed = parseInt(pluginData.checkIntervalMinutes || "30");
        return isNaN(parsed) ? 30 : Math.max(5, parsed);
    }

    function refresh() {
        if (checking || updateRunning)
            return;
        checking = true;
        checkError = "";
        checkProcess.running = true;
    }

    function startUpdate() {
        if (updateRunning)
            return;
        updateRunning = true;
        updateProcess.running = true;
        ToastService.showInfo("Mise à jour Eschaton", "La progression s'affiche dans le terminal.");
    }

    Component.onCompleted: Qt.callLater(root.refresh)

    Timer {
        interval: root.checkIntervalMinutes * 60 * 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

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

    Process {
        id: updateProcess
        command: [
            "/usr/bin/foot",
            "--hold",
            "--title=Eschaton · Mise à jour",
            "/usr/bin/eschaton-update",
            "--yes"
        ]
        running: false

        onExited: function(exitCode, exitStatus) {
            root.updateRunning = false;
            if (exitCode === 0) {
                ToastService.showInfo("Eschaton est à jour", "Redémarrez si le terminal l'a demandé.");
                Qt.callLater(root.refresh);
            } else {
                ToastService.showError("La mise à jour a échoué", "Le terminal s'est fermé avec le code " + exitCode + ".");
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: root.checking ? "sync" : "system_update_alt"
                size: root.iconSize
                color: root.checkError ? Theme.error : (root.updateCount > 0 ? Theme.primary : Theme.surfaceVariantText)
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.updateCount > 0 ? String(root.updateCount) : ""
                visible: root.updateCount > 0
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
                name: root.checking ? "sync" : "system_update_alt"
                size: root.iconSize
                color: root.checkError ? Theme.error : (root.updateCount > 0 ? Theme.primary : Theme.surfaceVariantText)
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.updateCount > 0 ? String(root.updateCount) : ""
                visible: root.updateCount > 0
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
            detailsText: root.checkError
                ? root.checkError
                : (root.checking ? "Vérification en cours…"
                   : (root.updateCount > 0 ? root.updateCount + " mise(s) à jour disponible(s)"
                                           : "Le système est à jour"))
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
                    text: "L'installation crée automatiquement les snapshots snap-pac avant et après la transaction."
                    wrapMode: Text.WordWrap
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingM

                    DankButton {
                        text: "Actualiser"
                        iconName: "refresh"
                        enabled: !root.checking && !root.updateRunning
                        onClicked: root.refresh()
                    }

                    DankButton {
                        text: root.updateRunning ? "Mise à jour en cours" : "Installer"
                        iconName: "system_update_alt"
                        enabled: !root.checking && !root.updateRunning && !root.checkError
                        onClicked: root.startUpdate()
                    }
                }
            }
        }
    }

    popoutWidth: 430
    popoutHeight: 230
}
