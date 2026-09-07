import QtQuick
import Quickshell.Io

// Plugin utilisateur éphémère de validation VM. Il fait exécuter le runtime
// exact par le processus DMS actif, notamment pour prouver la porte polkit.
// Il n'entre jamais dans le paquet.
Item {
    id: root
    property var pluginService: null
    property string pluginId: "eschatonAssistantToolHarness"
    property string lastResult: ""

    QtObject {
        id: fakeCore
        signal toolCall(string callId, string name, string argsJson)

        function toolResult(callId, resultJson) {
            root.lastResult = JSON.stringify({
                call_id: String(callId || ""),
                result: JSON.parse(resultJson)
            });
            return true;
        }
    }

    ToolExecutor {
        id: executor
        assistantCore: fakeCore
    }

    IpcHandler {
        target: "eschatonAssistantToolHarness"

        function status(): string {
            root.lastResult = "";
            fakeCore.toolCall("dms-status", "system_status", "{}");
            return "STATUS_QUEUED";
        }

        function proposeRollback(snapshotId: int): string {
            root.lastResult = "";
            fakeCore.toolCall(
                "dms-rollback",
                "propose_rollback",
                JSON.stringify({ snapshot_id: snapshotId })
            );
            return "ROLLBACK_QUEUED";
        }

        function confirmRollback(): string {
            return executor.confirmRollback() ? "POLKIT_STARTED" : "CONFIRM_REFUSED";
        }

        function phase(): string {
            return JSON.stringify({
                phase: executor.rollbackPhase,
                snapshot_id: executor.rollbackSnapshotId,
                pkexec_running: executor.rollbackRunning
            });
        }

        function result(): string {
            return root.lastResult || "PENDING";
        }
    }
}
