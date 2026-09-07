import QtQuick
import Quickshell

ShellRoot {
    id: root
    property bool finished: false
    property int phase: 0
    property int selectedSnapshot: -1
    property bool secondPrivilegedRefused: false

    function fail(message) {
        if (finished)
            return;
        finished = true;
        console.error("ASSISTANT_TOOL_HARNESS_FAIL", message);
        Qt.callLater(function() { Qt.exit(1); });
    }

    QtObject {
        id: fakeCore
        signal toolCall(string callId, string name, string argsJson)

        function toolResult(callId, resultJson) {
            let result;
            try {
                result = JSON.parse(resultJson);
            } catch (error) {
                root.fail("résultat JSON invalide pour " + callId);
                return false;
            }

            if (root.phase === 0) {
                if (callId !== "harness-status" || !result.ok
                        || result.content_classification !== "UNTRUSTED_SYSTEM_DATA"
                        || !result.data || !result.data.snapshots
                        || !result.data.snapshots.ok
                        || result.data.snapshots.items.length === 0
                        || resultJson.length > executor.maxResultChars) {
                    root.fail("system_status incomplet ou non étiqueté");
                    return false;
                }
                root.selectedSnapshot = Number(result.data.snapshots.items[0].snapshot_id);
                root.phase = 1;
                Qt.callLater(function() {
                    fakeCore.toolCall(
                        "harness-rollback",
                        "propose_rollback",
                        JSON.stringify({ snapshot_id: root.selectedSnapshot })
                    );
                });
                return true;
            }

            if (root.phase === 1) {
                if (callId === "harness-second-privileged") {
                    if (result.ok
                            || result.error !== "une seule action privilégiée est autorisée par tour") {
                        root.fail("seconde action privilégiée non refusée");
                        return false;
                    }
                    root.secondPrivilegedRefused = true;
                    Qt.callLater(function() { executor.cancelRollback(); });
                    return true;
                }
                if (callId !== "harness-rollback" || !result.cancelled
                        || Number(result.snapshot_id) !== root.selectedSnapshot
                        || !root.secondPrivilegedRefused) {
                    root.fail("annulation rollback mal corrélée");
                    return false;
                }
                root.phase = 2;
                Qt.callLater(function() {
                    fakeCore.toolCall("harness-unknown", "run_shell", "{}");
                });
                return true;
            }

            if (root.phase === 2) {
                if (callId !== "harness-unknown" || result.ok
                        || result.error !== "outil hors catalogue fermé") {
                    root.fail("outil inconnu non refusé");
                    return false;
                }
                root.phase = 3;
                Qt.callLater(function() {
                    fakeCore.toolCall(
                        "harness-status-args",
                        "system_status",
                        JSON.stringify({ command: "touch /tmp/interdit" })
                    );
                });
                return true;
            }

            if (root.phase === 3) {
                if (callId !== "harness-status-args" || result.ok
                        || result.error !== "cet outil n'accepte aucun argument") {
                    root.fail("arguments inattendus de system_status non refusés");
                    return false;
                }
                root.phase = 4;
                Qt.callLater(function() {
                    fakeCore.toolCall(
                        "harness-rollback-string",
                        "propose_rollback",
                        JSON.stringify({ snapshot_id: String(root.selectedSnapshot) })
                    );
                });
                return true;
            }

            if (root.phase === 4) {
                if (callId !== "harness-rollback-string" || result.ok
                        || result.error.indexOf("entier positif") < 0) {
                    root.fail("snapshot_id non entier accepté");
                    return false;
                }
                root.finished = true;
                console.log("ASSISTANT_TOOL_HARNESS_OK status=labelled"
                            + " rollback=" + root.selectedSnapshot
                            + " pkexec_before_click=false unknown=refused"
                            + " privileged=single args=strict");
                Qt.callLater(function() { Qt.quit(); });
                return true;
            }

            root.fail("résultat inattendu");
            return false;
        }
    }

    ToolExecutor {
        id: executor
        assistantCore: fakeCore

        onRollbackPhaseChanged: {
            if (root.phase === 1 && rollbackPhase === "awaiting_confirmation") {
                if (rollbackRunning) {
                    root.fail("pkexec lancé avant le clic humain");
                    return;
                }
                Qt.callLater(function() {
                    fakeCore.toolCall("harness-second-privileged", "trigger_update", "{}");
                });
            }
        }
    }

    Component.onCompleted: {
        fakeCore.toolCall("harness-status", "system_status", "{}");
    }

    Timer {
        interval: 70000
        running: true
        repeat: false
        onTriggered: root.fail("timeout")
    }
}
