import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var snapshots: []
    property bool loading: false
    property bool restoreRunning: false
    property int selectedNumber: -1
    property bool confirmRestore: false
    property string errorText: ""

    function displayDate(value) {
        return String(value || "Date inconnue").replace("T", " ").slice(0, 19);
    }

    function refresh() {
        if (loading || restoreRunning)
            return;
        loading = true;
        errorText = "";
        listProcess.running = true;
    }

    function selectSnapshot(number) {
        selectedNumber = Number(number);
        confirmRestore = false;
    }

    function restoreSelected() {
        if (selectedNumber <= 0 || restoreRunning)
            return;
        if (!confirmRestore) {
            confirmRestore = true;
            return;
        }
        restoreRunning = true;
        restoreProcess.command = [
            "/usr/bin/pkexec", "/usr/bin/eschaton-rollback",
            "--yes", String(selectedNumber)
        ];
        restoreProcess.running = true;
    }

    Component.onCompleted: Qt.callLater(root.refresh)

    Process {
        id: listProcess
        // snapper utilise son service D-Bus par défaut ; ALLOW_GROUPS=wheel
        // dans la configuration root autorise cette lecture sans élévation.
        command: ["/usr/bin/snapper", "--jsonout", "--config", "root", "list"]
        running: false
        stdout: StdioCollector { id: listOutput }
        stderr: StdioCollector { id: listError }

        onExited: function(exitCode, exitStatus) {
            root.loading = false;
            if (exitCode !== 0) {
                root.errorText = listError.text.trim() || "Lecture des snapshots impossible";
                return;
            }
            try {
                const parsed = JSON.parse(listOutput.text);
                const rows = parsed.root || [];
                root.snapshots = rows.filter(function(row) {
                    return Number(row.number) > 0;
                }).sort(function(a, b) {
                    return Number(b.number) - Number(a.number);
                });
                root.errorText = "";
                if (root.selectedNumber > 0 && !root.snapshots.some(function(row) {
                    return Number(row.number) === root.selectedNumber;
                })) {
                    root.selectedNumber = -1;
                    root.confirmRestore = false;
                }
            } catch (error) {
                root.errorText = "Réponse Snapper invalide : " + error;
            }
        }
    }

    Process {
        id: restoreProcess
        running: false
        stdout: StdioCollector { id: restoreOutput }
        stderr: StdioCollector { id: restoreError }

        onExited: function(exitCode, exitStatus) {
            root.restoreRunning = false;
            root.confirmRestore = false;
            if (exitCode === 0) {
                ToastService.showInfo(
                    "Restauration prête",
                    "Redémarrez pour démarrer sur le snapshot " + root.selectedNumber + "."
                );
                root.closePopout();
            } else {
                const details = restoreError.text.trim() || restoreOutput.text.trim()
                    || "eschaton-rollback a quitté avec le code " + exitCode;
                ToastService.showError("Restauration impossible", details);
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: "history"
                size: root.iconSize
                color: root.errorText ? Theme.error : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "history"
            size: root.iconSize
            color: root.errorText ? Theme.error : Theme.surfaceText
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: rollbackPopout
            headerText: "Restauration Eschaton"
            detailsText: root.errorText || (root.loading ? "Lecture des snapshots…"
                : root.snapshots.length + " point(s) de restauration")
            showCloseButton: true

            Column {
                width: parent.width
                spacing: Theme.spacingM

                ListView {
                    id: snapshotList
                    width: parent.width
                    height: 285
                    clip: true
                    spacing: Theme.spacingXS
                    model: root.snapshots

                    delegate: StyledRect {
                        required property var modelData
                        width: snapshotList.width
                        height: 62
                        radius: Theme.cornerRadius
                        color: root.selectedNumber === Number(modelData.number)
                            ? Theme.primaryContainer : Theme.surfaceContainerHigh

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: 2
                            StyledText {
                                text: "Snapshot " + modelData.number + " · " + root.displayDate(modelData.date)
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            StyledText {
                                width: parent.width
                                text: modelData.description || "Sans description"
                                elide: Text.ElideRight
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectSnapshot(modelData.number)
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingM

                    DankButton {
                        text: "Actualiser"
                        iconName: "refresh"
                        enabled: !root.loading && !root.restoreRunning
                        onClicked: root.refresh()
                    }

                    DankButton {
                        text: root.restoreRunning ? "Restauration…"
                            : (root.confirmRestore ? "Confirmer le rollback " + root.selectedNumber
                                                   : "Restaurer " + (root.selectedNumber > 0 ? root.selectedNumber : ""))
                        iconName: root.confirmRestore ? "warning" : "restore"
                        enabled: root.selectedNumber > 0 && !root.loading && !root.restoreRunning
                        backgroundColor: root.confirmRestore ? Theme.error : Theme.primary
                        textColor: root.confirmRestore ? Theme.surface : Theme.onPrimary
                        onClicked: root.restoreSelected()
                    }
                }
            }
        }
    }

    popoutWidth: 520
    popoutHeight: 410
}
