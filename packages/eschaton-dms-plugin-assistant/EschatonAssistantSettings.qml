import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "eschatonAssistant"

    StyledText {
        width: parent.width
        text: "Assistant Eschaton"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Le fournisseur, les clés du trousseau et le mode local uniquement arrivent dans la tranche fournisseurs. Les permissions du manifeste DMS sont informatives : la sécurité réelle vient du catalogue fermé et des confirmations humaines."
        wrapMode: Text.WordWrap
        color: Theme.surfaceVariantText
    }
}
