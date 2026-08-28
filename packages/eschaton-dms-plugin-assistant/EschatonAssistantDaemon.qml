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

    function toggle() {
        if (variants.instances.length > 0)
            variants.instances[0].toggle();
    }

    AssistantCore {
        id: assistantCore
        baseUrl: "http://127.0.0.1:8080/v1"
        model: "HuggingFaceTB/smollm-135M-instruct-v0.2-Q8_0-GGUF"
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
                if (slideout.loadedItem)
                    slideout.loadedItem.focusComposer();
            }

            content: EschatonAssistantPanel {
                assistantCore: assistantCore
                providerNames: ["RamaLama local"]
                currentProvider: "RamaLama local"
                onHideRequested: slideout.hide()
            }
        }
    }
}
