import QtQuick
import Quickshell

ShellRoot {
    id: root
    property bool launched: false

    QtObject {
        id: fakeCore
        signal toolCall(string callId, string name, string argsJson)

        function toolResult(callId, resultJson) {
            const result = JSON.parse(resultJson);
            if (callId !== "harness-update" || !result.ok || !result.launched) {
                console.error("ASSISTANT_UPDATE_HARNESS_FAIL", resultJson);
                Qt.callLater(function() { Qt.exit(1); });
                return false;
            }
            root.launched = true;
            console.log("ASSISTANT_UPDATE_HARNESS_READY terminal=visible sudo=human");
            return true;
        }
    }

    ToolExecutor {
        id: executor
        assistantCore: fakeCore

        onUpdateRunningChanged: {
            if (root.launched && !updateRunning) {
                console.log("ASSISTANT_UPDATE_HARNESS_OK terminal_closed=true");
                Qt.callLater(function() { Qt.quit(); });
            }
        }
    }

    Component.onCompleted: {
        fakeCore.toolCall("harness-update", "trigger_update", "{}");
    }

    Timer {
        interval: 120000
        running: true
        repeat: false
        onTriggered: {
            console.error("ASSISTANT_UPDATE_HARNESS_FAIL timeout");
            Qt.exit(1);
        }
    }
}
