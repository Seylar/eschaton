import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "eschatonRollback"

    StyledText {
        width: parent.width
        text: "Restauration Eschaton"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "La liste est lue via Snapper. Une restauration demande deux clics et une autorisation polkit, puis prend effet au redémarrage."
        wrapMode: Text.WordWrap
        color: Theme.surfaceVariantText
    }
}
