import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "eschatonAssistant"

    property string selectedProviderName: ""
    property string keyStatus: ""
    readonly property var selectedProvider: {
        for (let i = 0; i < providerCatalog.providers.length; i++) {
            if (providerCatalog.providers[i].name === selectedProviderName)
                return providerCatalog.providers[i];
        }
        return null;
    }

    function providerNames() {
        const names = [];
        for (let i = 0; i < providerCatalog.providers.length; i++) {
            if (providerCatalog.providers[i].requiresKey)
                names.push(providerCatalog.providers[i].name);
        }
        return names;
    }

    function chooseFirstKeyProvider() {
        const names = providerNames();
        if (names.length > 0 && names.indexOf(selectedProviderName) < 0)
            selectedProviderName = names[0];
    }

    function storeKey() {
        if (!selectedProvider || !apiKeyInput.text.trim())
            return;
        if (keyring.store(selectedProvider.id, apiKeyInput.text)) {
            apiKeyInput.text = "";
            keyStatus = "Enregistrement dans le trousseau…";
        } else {
            keyStatus = "Clé refusée ou opération déjà en cours.";
        }
    }

    StyledText {
        width: parent.width
        text: "Assistant Eschaton"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Choisis le fournisseur dans la sidebar. L'Assistant n'accède qu'aux trois outils Eschaton prévus et demande toujours ton authentification avant une action privilégiée."
        wrapMode: Text.WordWrap
        color: Theme.surfaceVariantText
    }

    ToggleSetting {
        settingKey: "localOnly"
        label: "Mode local uniquement"
        description: "Bloque tous les fournisseurs distants. Seuls les services lancés sur cet appareil restent disponibles. Activé par défaut."
        defaultValue: true
    }

    StyledRect {
        width: parent.width
        height: keyColumn.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: keyColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingM
            spacing: Theme.spacingS

            StyledText {
                width: parent.width
                text: "Clés API"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                text: "La clé reste dans le trousseau de la session. Elle n'est jamais enregistrée dans les réglages ni dans le catalogue de fournisseurs."
                wrapMode: Text.WordWrap
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DankIcon {
                    name: "warning"
                    size: Theme.iconSize
                    color: Theme.warning
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    width: parent.width - Theme.iconSize - parent.spacing
                    text: "Ne laisse pas le mot de passe du trousseau vide : les clés seraient stockées en clair sur le disque. Avec la connexion automatique actuelle, choisis un mot de passe et saisis-le de nouveau après chaque connexion."
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            DankDropdown {
                width: parent.width
                options: root.providerNames()
                currentValue: root.selectedProviderName
                emptyText: "Aucun fournisseur à clé"
                enabled: !keyring.busy && options.length > 0
                onValueChanged: value => {
                    root.selectedProviderName = value;
                    root.keyStatus = "";
                }
            }

            TextField {
                id: apiKeyInput
                width: parent.width
                enabled: !!root.selectedProvider && !keyring.busy
                echoMode: TextInput.Password
                passwordCharacter: "●"
                placeholderText: "Nouvelle clé, jamais affichée ensuite"
                color: Theme.surfaceText
                placeholderTextColor: Theme.surfaceVariantText
                selectionColor: Theme.primaryContainer
                selectedTextColor: Theme.primary
                background: Rectangle {
                    radius: Theme.cornerRadiusSmall
                    color: Theme.surfaceContainer
                    border.width: apiKeyInput.activeFocus ? 2 : 1
                    border.color: apiKeyInput.activeFocus ? Theme.primary : Theme.outlineMedium
                }
                Keys.onReturnPressed: root.storeKey()
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingS

                DankButton {
                    text: "Enregistrer"
                    iconName: "key"
                    enabled: !!root.selectedProvider
                        && apiKeyInput.text.trim().length > 0 && !keyring.busy
                    onClicked: root.storeKey()
                }

                DankButton {
                    text: "Vérifier"
                    iconName: "search"
                    enabled: !!root.selectedProvider && !keyring.busy
                    onClicked: {
                        root.keyStatus = "Lecture du trousseau…";
                        keyring.lookup(root.selectedProvider.id);
                    }
                }

                DankButton {
                    text: "Supprimer"
                    iconName: "delete"
                    enabled: !!root.selectedProvider && !keyring.busy
                    onClicked: {
                        root.keyStatus = "Suppression du trousseau…";
                        keyring.clear(root.selectedProvider.id);
                    }
                }
            }

            StyledText {
                width: parent.width
                text: providerCatalog.lastError || root.keyStatus
                visible: text !== ""
                color: providerCatalog.lastError ? Theme.error : Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    StyledText {
        width: parent.width
        text: "Catalogue système : /usr/share/eschaton/assistant/providers.json. Une surcharge complète peut être placée dans ~/.config/eschaton/assistant/providers.json ; Eschaton ne crée ni ne remplace ce fichier. Recharge le plugin après modification."
        wrapMode: Text.WordWrap
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
    }

    ProviderCatalog {
        id: providerCatalog
        onReloaded: root.chooseFirstKeyProvider()
    }

    KeyringBridge {
        id: keyring
        onLookupFinished: (providerId, secret, found) => {
            // La valeur est volontairement jetée : l'écran ne révèle jamais
            // une clé déjà stockée, il ne montre que sa présence.
            root.keyStatus = found ? "Une clé est présente dans le trousseau."
                : (keyring.lastError ? "Trousseau indisponible. Déverrouille-le puis réessaie."
                                     : "Aucune clé stockée pour ce fournisseur.");
        }
        onStoreFinished: (providerId, ok) => {
            root.keyStatus = ok ? "Clé enregistrée dans le trousseau."
                                : "Impossible d'enregistrer la clé. Déverrouille le trousseau puis réessaie.";
        }
        onClearFinished: (providerId, ok) => {
            root.keyStatus = ok ? "Clé supprimée du trousseau."
                : (keyring.lastError ? "Trousseau indisponible. Déverrouille-le puis réessaie."
                                     : "Aucune clé n'était stockée pour ce fournisseur.");
        }
    }
}
