import QtQuick
import Quickshell

ShellRoot {
    id: root
    property int stage: 0
    property bool finished: false

    function fail(message) {
        console.error("ASSISTANT_PROVIDER_HARNESS_FAIL", message);
        finished = true;
        Qt.callLater(function() { Qt.exit(1); });
    }

    ProviderCatalog {
        id: catalog
        systemConfigPath: Quickshell.shellDir + "/providers.json"
        userConfigPath: "/tmp/assistant-task4/providers.user.absent.json"

        onReloaded: {
            if (!ready || providers.length !== 3) {
                root.fail(lastError || "catalogue non chargé");
                return;
            }
            if (providers[0].id !== "ramalama-local"
                    || providers[2].format !== "anthropic") {
                root.fail("catalogue normalisé incorrect");
                return;
            }
            root.stage = 1;
            if (!keyring.store("task4-harness", "not-a-real-secret-task4"))
                root.fail("store n'a pas démarré");
        }
    }

    KeyringBridge {
        id: keyring

        onStoreFinished: (providerId, ok) => {
            if (!ok || providerId !== "task4-harness") {
                root.fail("store secret-tool : " + lastError);
                return;
            }
            root.stage = 2;
            if (!lookup(providerId))
                root.fail("lookup n'a pas démarré");
        }

        onLookupFinished: (providerId, secret, found) => {
            if (!found || secret !== "not-a-real-secret-task4") {
                root.fail("lookup secret-tool incorrect");
                return;
            }
            root.stage = 3;
            if (!clear(providerId))
                root.fail("clear n'a pas démarré");
        }

        onClearFinished: (providerId, ok) => {
            if (!ok) {
                root.fail("clear secret-tool : " + lastError);
                return;
            }
            root.stage = 4;
            root.finished = true;
            console.log("ASSISTANT_PROVIDER_HARNESS_OK providers="
                        + catalog.providers.length + " keyring=store,lookup,clear");
            Qt.callLater(function() { Qt.quit(); });
        }
    }

    Timer {
        // Laisse le temps de traiter le prompt graphique de création ou de
        // déverrouillage sur une session autologin de banc d'essai.
        interval: 60000
        running: true
        repeat: false
        onTriggered: {
            if (!root.finished)
                root.fail("timeout stage=" + root.stage);
        }
    }
}
