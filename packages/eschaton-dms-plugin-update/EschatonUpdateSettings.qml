import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "eschatonUpdate"

    StyledText {
        width: parent.width
        text: "Mises à jour Eschaton"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StringSetting {
        settingKey: "checkIntervalMinutes"
        label: "Intervalle de vérification (minutes)"
        description: "Minimum 5 minutes. La valeur par défaut est 30."
        placeholder: "30"
        defaultValue: "30"
    }
}
