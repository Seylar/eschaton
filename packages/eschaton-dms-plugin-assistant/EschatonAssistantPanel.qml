pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Item {
    id: root

    required property var assistantCore
    property var providerNames: []
    property string currentProvider: ""
    property string activeToolName: ""
    property bool localOnly: true
    property bool providerReady: false
    property bool credentialsPending: false
    property string providerMessage: ""

    signal hideRequested
    signal providerSelected(string name)

    function focusComposer() {
        composer.forceActiveFocus();
    }

    function safeRichText(value) {
        // Sous-ensemble volontaire : gras et code en ligne, après échappement
        // HTML. Aucun lien, image ou balise du modèle ne charge de ressource.
        let text = String(value || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
        text = text.replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>");
        text = text.replace(/`([^`\n]+)`/g, "<tt>$1</tt>");
        return text.replace(/\n/g, "<br>");
    }

    function sendComposer() {
        const message = composer.text.trim();
        if (!message || !providerReady)
            return;
        if (assistantCore.send(message)) {
            composer.text = "";
            Qt.callLater(function() { messageList.positionViewAtEnd(); });
        }
    }

    function statusLabel(status) {
        switch (status) {
        case "streaming": return "Réponse en cours";
        case "tool": return "Outil demandé";
        case "truncated": return "Réponse tronquée";
        case "cancelled": return "Réponse annulée";
        case "error": return "Échec";
        default: return "";
        }
    }

    function toolLabel(name) {
        switch (name) {
        case "system_status": return "Lecture de l'état du système";
        case "trigger_update": return "Préparation d'une mise à jour";
        case "propose_rollback": return "Préparation d'une restauration";
        default: return "Outil refusé";
        }
    }

    Connections {
        target: root.assistantCore

        function onDelta() {
            Qt.callLater(function() { messageList.positionViewAtEnd(); });
        }

        function onToolCall(callId, name) {
            root.activeToolName = name;
        }

        function onDone() {
            root.activeToolName = "";
            Qt.callLater(function() { messageList.positionViewAtEnd(); });
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingM

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            DankDropdown {
                Layout.preferredWidth: 220
                options: root.providerNames
                currentValue: root.currentProvider
                emptyText: "Aucun fournisseur"
                enabled: !root.assistantCore.busy && !root.credentialsPending
                    && root.providerNames.length > 0
                onValueChanged: value => root.providerSelected(value)
            }

            StyledRect {
                Layout.preferredWidth: localStatusRow.implicitWidth + Theme.spacingM * 2
                Layout.preferredHeight: 32
                radius: 16
                color: Theme.surfaceContainerHigh

                Row {
                    id: localStatusRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: root.localOnly ? Theme.success : Theme.warning
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: root.localOnly ? "Local uniquement" : "Distant autorisé"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            Item { Layout.fillWidth: true }

            DankActionButton {
                iconName: "delete_sweep"
                tooltipText: "Effacer la conversation"
                enabled: root.assistantCore.messageCount > 0 && !root.assistantCore.busy
                onClicked: root.assistantCore.clear()
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: providerRow.implicitHeight + Theme.spacingM * 2
            visible: root.providerMessage !== ""
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.warning, 0.14)
            border.width: 1
            border.color: Theme.withAlpha(Theme.warning, 0.45)

            Row {
                id: providerRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingS

                DankIcon {
                    name: root.credentialsPending ? "sync" : "key"
                    size: Theme.iconSize
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    width: parent.width - Theme.iconSize - parent.spacing
                    text: root.providerMessage
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: toolRow.implicitHeight + Theme.spacingS * 2
            visible: root.activeToolName !== "" && root.assistantCore.busy
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.primary, 0.12)

            Row {
                id: toolRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingS

                DankIcon {
                    name: "shield"
                    size: Theme.iconSizeSmall
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    width: parent.width - Theme.iconSizeSmall - parent.spacing
                    text: root.toolLabel(root.activeToolName)
                        + " · catalogue fermé, aucune approbation automatique"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: errorRow.implicitHeight + Theme.spacingM * 2
            visible: root.assistantCore.lastError !== ""
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.error, 0.14)
            border.width: 1
            border.color: Theme.withAlpha(Theme.error, 0.45)

            Row {
                id: errorRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingM
                spacing: Theme.spacingS

                DankIcon {
                    name: "error"
                    size: Theme.iconSize
                    color: Theme.error
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    width: parent.width - Theme.iconSize - parent.spacing
                    text: root.assistantCore.lastError
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: messageList
                anchors.fill: parent
                clip: true
                spacing: Theme.spacingM
                model: root.assistantCore.messages
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: DankScrollbar { }

                onCountChanged: Qt.callLater(function() { positionViewAtEnd(); })

                delegate: Item {
                    id: messageDelegate
                    required property string role
                    required property string content
                    required property string status

                    width: messageList.width
                    height: messageBubble.height

                    StyledRect {
                        id: messageBubble
                        width: Math.min(Math.max(messageText.implicitWidth + Theme.spacingM * 2, 120),
                                        messageDelegate.width * 0.82)
                        height: messageColumn.implicitHeight + Theme.spacingM * 2
                        anchors.right: messageDelegate.role === "user" ? parent.right : undefined
                        anchors.left: messageDelegate.role === "user" ? undefined : parent.left
                        radius: Theme.cornerRadius
                        color: messageDelegate.role === "user"
                            ? Theme.primaryContainer : Theme.surfaceContainerHigh

                        Column {
                            id: messageColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            spacing: Theme.spacingXS

                            StyledText {
                                id: messageText
                                width: parent.width
                                text: messageDelegate.role === "assistant"
                                    ? root.safeRichText(messageDelegate.content)
                                    : messageDelegate.content
                                textFormat: messageDelegate.role === "assistant"
                                    ? Text.RichText : Text.PlainText
                                color: Theme.surfaceText
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                                visible: messageDelegate.content !== ""
                            }

                            Row {
                                spacing: Theme.spacingXS
                                visible: root.statusLabel(messageDelegate.status) !== ""

                                DankIcon {
                                    name: messageDelegate.status === "streaming" ? "more_horiz"
                                        : (messageDelegate.status === "error" ? "error" : "info")
                                    size: 14
                                    color: messageDelegate.status === "error"
                                        ? Theme.error : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    text: root.statusLabel(messageDelegate.status)
                                    color: messageDelegate.status === "error"
                                        ? Theme.error : Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                }
                            }
                        }
                    }
                }
            }

            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.82, 480)
                spacing: Theme.spacingM
                visible: root.assistantCore.messageCount === 0

                DankIcon {
                    name: "auto_awesome"
                    size: 40
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    width: parent.width
                    text: "Que veux-tu vérifier sur cette machine ?"
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }

                StyledText {
                    width: parent.width
                    text: "L'assistant répond en direct. Ses trois outils système sont déclarés, bornés et jamais auto-approuvés."
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }
        }

        StyledRect {
            id: composerContainer
            Layout.fillWidth: true
            Layout.preferredHeight: 112
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.width: composer.activeFocus ? 2 : 1
            border.color: composer.activeFocus ? Theme.primary : Theme.outlineMedium

            TextArea {
                id: composer
                anchors.left: parent.left
                anchors.right: actionButton.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacingS
                anchors.rightMargin: Theme.spacingXS
                activeFocusOnTab: true
                enabled: root.providerReady && !root.assistantCore.busy
                placeholderText: root.assistantCore.busy ? "Réponse en cours…"
                    : (root.providerReady ? "Écris une demande système…"
                                          : "Configure un fournisseur disponible…")
                wrapMode: TextArea.Wrap
                color: Theme.surfaceText
                placeholderTextColor: Theme.surfaceVariantText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                selectionColor: Theme.primaryContainer
                selectedTextColor: Theme.primary
                background: Rectangle { color: "transparent" }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.hideRequested();
                        event.accepted = true;
                    } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                               && !(event.modifiers & Qt.ShiftModifier)) {
                        root.sendComposer();
                        event.accepted = true;
                    }
                }
            }

            DankActionButton {
                id: actionButton
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacingS
                iconName: root.assistantCore.busy ? "stop" : "send"
                tooltipText: root.assistantCore.busy ? "Annuler" : "Envoyer"
                iconColor: root.assistantCore.busy ? Theme.error : Theme.primary
                enabled: root.assistantCore.busy
                    || (root.providerReady && composer.text.trim().length > 0)
                onClicked: {
                    if (root.assistantCore.busy)
                        root.assistantCore.cancel();
                    else
                        root.sendComposer();
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: "Entrée pour envoyer · Maj+Entrée pour une nouvelle ligne · Échap pour fermer"
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideNone
        }
    }
}
