import QtQuick
import Quickshell

ShellRoot {
    id: root
    property string doneStatus: ""
    Component.onCompleted: Qt.callLater(function() {
        core._conversation = [{ role: "user", content: "Test sans fournisseur" }];
        core._pendingTools = ({ "call:a": { id: "a", name: "system_status" },
                                "call:b": { id: "b", name: "propose_rollback" } });
        core.pendingToolCount = 2;
        core.cancel();
        core.toolResult("a", '{"cancelled":true}');
        if (!core.busy || doneStatus !== "") {
            console.error("ASSISTANT_CANCEL_FAIL résultat prématuré");
            Qt.exit(1);
            return;
        }
        core.toolResult("b", '{"ok":true,"applied":true}');
        if (core.busy || doneStatus !== "cancelled" || core.stubTools
                || core._conversation.length !== 3 || core.messages.count !== 0) {
            console.error("ASSISTANT_CANCEL_FAIL status=" + doneStatus);
            Qt.exit(1);
            return;
        }
        console.log("ASSISTANT_CANCEL_OK two_results=true no_followup=true stubs=false");
        Qt.quit();
    })
    AssistantCore {
        id: core
        // Même un défaut ne doit jamais déclencher de requête réseau ici.
        baseUrl: "invalid://test"
        onDone: status => root.doneStatus = status
    }
    Timer {
        interval: 5000
        running: true
        onTriggered: Qt.exit(2)
    }
}
