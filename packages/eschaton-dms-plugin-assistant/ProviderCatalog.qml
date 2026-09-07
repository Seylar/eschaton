import QtQuick
import Quickshell
import Quickshell.Io
import "./providers/ProviderPolicy.js" as ProviderPolicy

Item {
    id: root
    visible: false
    width: 0
    height: 0

    property string systemConfigPath: "/usr/share/eschaton/assistant/providers.json"
    property string userConfigPath: {
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        const home = Quickshell.env("HOME");
        return (xdg ? xdg : home + "/.config") + "/eschaton/assistant/providers.json";
    }
    property var providers: []
    property string sourceName: ""
    property string updated: ""
    property string lastError: ""
    readonly property bool ready: providers.length > 0 && !lastError
    readonly property bool busy: existsProcess.running || readProcess.running
    property string _readingSource: ""

    signal reloaded

    function reload() {
        if (busy)
            return false;
        lastError = "";
        providers = [];
        existsProcess.command = ["/usr/bin/test", "-f", userConfigPath];
        existsProcess.running = true;
        return true;
    }

    function readConfig(path, source) {
        _readingSource = source;
        readProcess.command = ["/usr/bin/head", "--bytes=65537", path];
        readProcess.running = true;
    }

    function acceptConfig(text) {
        const result = ProviderPolicy.validateCatalog(text);
        if (!result.ok) {
            lastError = "Configuration " + _readingSource + " refusée : " + result.error;
            providers = [];
        } else {
            lastError = "";
            providers = result.providers;
            updated = result.updated;
            sourceName = _readingSource;
        }
        reloaded();
    }

    Component.onCompleted: reload()

    Process {
        id: existsProcess
        running: false
        onExited: exitCode => {
            if (exitCode === 0)
                root.readConfig(root.userConfigPath, "utilisateur");
            else
                root.readConfig(root.systemConfigPath, "système");
        }
    }

    Process {
        id: readProcess
        running: false
        stdout: StdioCollector { id: configOutput }
        stderr: StdioCollector { id: configError }

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.lastError = "Lecture de la configuration " + root._readingSource
                    + " impossible : " + (configError.text.trim() || "code " + exitCode);
                root.providers = [];
                root.reloaded();
                return;
            }
            root.acceptConfig(configOutput.text);
        }
    }
}
