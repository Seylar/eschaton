import QtQuick
import Quickshell.Io

// Les attributs stables sont : application=org.eschaton.Assistant et
// provider=<id>. La valeur secrète entre uniquement par stdin de secret-tool.
Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property bool busy: secretProcess.running
    property string lastError: ""
    property string _action: ""
    property string _providerId: ""
    property string _pendingSecret: ""
    property bool _timedOut: false

    signal lookupFinished(string providerId, string secret, bool found)
    signal storeFinished(string providerId, bool ok)
    signal clearFinished(string providerId, bool ok)

    function validProviderId(providerId) {
        return /^[a-z0-9][a-z0-9-]{0,63}$/.test(String(providerId || ""));
    }

    function begin(action, providerId, command) {
        if (busy || !validProviderId(providerId))
            return false;
        _action = action;
        _providerId = String(providerId);
        _timedOut = false;
        lastError = "";
        secretProcess.stdinEnabled = action === "store";
        secretProcess.command = command;
        secretProcess.running = true;
        operationTimeout.restart();
        return true;
    }

    function lookup(providerId) {
        return begin("lookup", providerId, [
            "/usr/bin/secret-tool", "lookup",
            "application", "org.eschaton.Assistant",
            "provider", String(providerId)
        ]);
    }

    function store(providerId, secret) {
        const value = String(secret || "").trim();
        if (busy || !validProviderId(providerId)
                || !value || value.length > 8192 || /[\r\n]/.test(value))
            return false;
        _pendingSecret = value;
        return begin("store", providerId, [
            "/usr/bin/secret-tool", "store",
            "--label=Eschaton Assistant — " + String(providerId),
            "application", "org.eschaton.Assistant",
            "provider", String(providerId)
        ]);
    }

    function clear(providerId) {
        return begin("clear", providerId, [
            "/usr/bin/secret-tool", "clear",
            "application", "org.eschaton.Assistant",
            "provider", String(providerId)
        ]);
    }

    Process {
        id: secretProcess
        running: false
        stdinEnabled: false
        stdout: StdioCollector { id: secretOutput }
        stderr: StdioCollector { id: secretError }

        onStarted: {
            if (root._action === "store") {
                write(root._pendingSecret + "\n");
                root._pendingSecret = "";
                // Fermer le canal est indispensable : secret-tool lit stdin
                // jusqu'à EOF. Il sera rouvert avant le prochain store.
                stdinEnabled = false;
            }
        }

        onExited: exitCode => {
            operationTimeout.stop();
            const action = root._action;
            const providerId = root._providerId;
            const stderrText = secretError.text.trim();
            root._action = "";
            root._providerId = "";
            root._pendingSecret = "";
            if (root._timedOut)
                root.lastError = "Le trousseau n'a pas répondu sous 60 secondes.";
            else if (stderrText)
                root.lastError = stderrText;

            if (action === "lookup") {
                const found = exitCode === 0;
                let secret = found ? secretOutput.text : "";
                secret = secret.replace(/[\r\n]+$/, "");
                // Process.running ne bascule à false qu'après le retour de
                // onExited. Différer le signal permet à son consommateur
                // d'enchaîner store → lookup → clear sans faux « busy ».
                Qt.callLater(function() {
                    root.lookupFinished(providerId, secret, found);
                });
            } else if (action === "store") {
                const ok = exitCode === 0;
                Qt.callLater(function() {
                    root.storeFinished(providerId, ok);
                });
            } else if (action === "clear") {
                const ok = exitCode === 0;
                Qt.callLater(function() {
                    root.clearFinished(providerId, ok);
                });
            }
        }
    }

    // Un prompt Secret Service inaccessible ou ignoré ne doit jamais figer
    // l'Assistant. Couper le Process déclenche onExited et le signal d'échec de
    // l'opération en cours ; aucune valeur secrète n'est conservée ensuite.
    Timer {
        id: operationTimeout
        interval: 60000
        repeat: false
        onTriggered: {
            if (!secretProcess.running)
                return;
            root._timedOut = true;
            root._pendingSecret = "";
            secretProcess.running = false;
        }
    }
}
