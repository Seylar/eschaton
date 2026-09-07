pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Common
import qs.Widgets

Item {
    id: root

    // Injectés par PluginService pour les surfaces daemon.
    property var pluginService: null
    property string pluginId: "eschatonAssistant"
    property var providers: providerCatalog.providers
    property var selectedProvider: null
    property bool localOnly: true
    property bool credentialsPending: false
    property string providerMessage: providerCatalog.lastError
    readonly property string selectedProviderName: selectedProvider
        ? selectedProvider.name : "Aucun fournisseur"
    readonly property bool providerReady: !!selectedProvider
        && !providerCatalog.lastError
        && !credentialsPending
        && !(localOnly && !selectedProvider.local)
        && (!selectedProvider.requiresKey || assistantCore.apiKey !== "")

    function toggle() {
        if (variants.instances.length > 0)
            variants.instances[0].toggle();
    }

    function providerById(providerId) {
        for (let i = 0; i < providers.length; i++) {
            if (providers[i].id === providerId)
                return providers[i];
        }
        return null;
    }

    function providerByName(name) {
        for (let i = 0; i < providers.length; i++) {
            if (providers[i].name === name)
                return providers[i];
        }
        return null;
    }

    function providerNames() {
        const names = [];
        for (let i = 0; i < providers.length; i++)
            names.push(providers[i].name);
        return names;
    }

    function settingBoolean(value, fallback) {
        if (value === true || value === "true")
            return true;
        if (value === false || value === "false")
            return false;
        return fallback;
    }

    function syncPluginSettings() {
        if (!pluginService || providers.length === 0)
            return;
        localOnly = settingBoolean(
            pluginService.loadPluginData(pluginId, "localOnly", true), true
        );
        const wanted = String(pluginService.loadPluginData(
            pluginId, "selectedProvider", "ramalama-local"
        ));
        applyProvider(providerById(wanted) || providers[0], false);
    }

    function selectProviderName(name) {
        if (assistantCore.busy)
            return false;
        const provider = providerByName(name);
        if (!provider)
            return false;
        applyProvider(provider, true);
        return true;
    }

    function applyProvider(provider, persist) {
        if (!provider)
            return;
        selectedProvider = provider;
        assistantCore.providerId = provider.id;
        assistantCore.providerFormat = provider.format;
        assistantCore.baseUrl = provider.baseUrl;
        assistantCore.model = provider.model;
        assistantCore.requiresApiKey = provider.requiresKey;
        assistantCore.localOnly = localOnly;
        assistantCore.apiKey = "";
        credentialsPending = false;
        updateProviderMessage();
        if (persist && pluginService)
            pluginService.savePluginData(pluginId, "selectedProvider", provider.id);
        refreshCredentials();
    }

    function refreshCredentials() {
        if (!selectedProvider || !selectedProvider.requiresKey) {
            credentialsPending = false;
            updateProviderMessage();
            return;
        }
        if (keyring.busy)
            return;
        assistantCore.apiKey = "";
        credentialsPending = true;
        providerMessage = "Lecture de la clé dans le trousseau…";
        if (!keyring.lookup(selectedProvider.id)) {
            credentialsPending = false;
            providerMessage = "Lecture du trousseau impossible.";
        }
    }

    function updateProviderMessage() {
        if (providerCatalog.lastError) {
            providerMessage = providerCatalog.lastError;
        } else if (!selectedProvider) {
            providerMessage = "Aucun fournisseur n'est configuré.";
        } else if (localOnly && !selectedProvider.local) {
            providerMessage = "Mode local uniquement actif : l'endpoint distant est refusé.";
        } else if (selectedProvider.requiresKey && !assistantCore.apiKey) {
            providerMessage = "Aucune clé dans le trousseau. Ajoute-la dans les réglages du plugin.";
        } else {
            providerMessage = "";
        }
    }

    onLocalOnlyChanged: {
        assistantCore.localOnly = localOnly;
        updateProviderMessage();
    }

    onPluginServiceChanged: Qt.callLater(root.syncPluginSettings)

    Connections {
        target: root.pluginService
        function onPluginDataChanged(changedId) {
            if (changedId === root.pluginId)
                Qt.callLater(root.syncPluginSettings);
        }
    }

    ProviderCatalog {
        id: providerCatalog
        onReloaded: {
            if (ready)
                root.syncPluginSettings();
            else
                root.updateProviderMessage();
        }
    }

    KeyringBridge {
        id: keyring
        onLookupFinished: (providerId, secret, found) => {
            if (!root.selectedProvider || root.selectedProvider.id !== providerId) {
                Qt.callLater(root.refreshCredentials);
                return;
            }
            root.credentialsPending = false;
            assistantCore.apiKey = found ? secret : "";
            if (!found && keyring.lastError)
                root.providerMessage = "Trousseau indisponible. Déverrouille-le dans les réglages du plugin.";
            else
                root.updateProviderMessage();
        }
    }

    AssistantCore {
        id: assistantCore
        stubTools: false
    }

    ToolExecutor {
        id: toolExecutor
        assistantCore: assistantCore
    }

    Variants {
        id: variants
        model: Quickshell.screens

        delegate: DankSlideout {
            id: slideout
            required property var modelData

            layerNamespace: "dms:eschaton-assistant"
            title: "Assistant Eschaton"
            slideoutWidth: Math.min(520, modelData.width)
            expandable: true
            expandedWidthValue: Math.min(960, modelData.width)

            onRevealed: {
                root.refreshCredentials();
                if (slideout.loadedItem)
                    slideout.loadedItem.focusComposer();
            }

            content: EschatonAssistantPanel {
                assistantCore: assistantCore
                toolExecutor: toolExecutor
                providerNames: root.providerNames()
                currentProvider: root.selectedProviderName
                localOnly: root.localOnly
                providerReady: root.providerReady
                providerMessage: root.providerMessage
                credentialsPending: root.credentialsPending
                onProviderSelected: name => root.selectProviderName(name)
                onHideRequested: slideout.hide()
            }
        }
    }
}
