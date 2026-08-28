import QtQuick
import Quickshell

ShellRoot {
    id: root
    property bool finished: false

    Component.onCompleted: {
        core.toolCatalog = core.loadToolCatalog();
        const known = core.validateToolCall("system_status", "{}");
        const unknown = core.validateToolCall("arbitrary_exec", "{}");
        const invalidRollback = core.validateToolCall(
            "propose_rollback", "{\"snapshot_id\":0}"
        );
        if (!known.ok || unknown.ok || invalidRollback.ok) {
            console.error("ASSISTANT_CORE_HARNESS_FAIL catalogue fermé invalide");
            Qt.callLater(function() { Qt.exit(1); });
            return;
        }
        if (!core.send("Réponds en une phrase courte sur Eschaton.")) {
            console.error("ASSISTANT_CORE_HARNESS_FAIL send a refusé la requête");
            Qt.callLater(function() { Qt.exit(1); });
        }
    }

    AssistantCore {
        id: core
        baseUrl: "http://127.0.0.1:8080/v1"
        model: "HuggingFaceTB/smollm-135M-instruct-v0.2-Q8_0-GGUF"
        maxTokens: 64
        timeoutSeconds: 15

        onDone: status => {
            root.finished = true;
            const last = messages.get(messages.count - 1);
            if ((status === "ok" || status === "truncated")
                    && messages.count >= 2 && last.content.length > 0) {
                console.log("ASSISTANT_CORE_HARNESS_OK status=" + status
                            + " chars=" + last.content.length);
            } else {
                console.error("ASSISTANT_CORE_HARNESS_FAIL status=" + status
                              + " count=" + messages.count
                              + " lastStatus=" + String(last.status || "")
                              + " chars=" + String(last.content || "").length
                              + " lines=" + streamLineCount
                              + " parseErrors=" + parseErrorCount
                              + " error=" + lastError);
                Qt.callLater(function() { Qt.exit(1); });
                return;
            }
            Qt.callLater(function() { Qt.quit(); });
        }
    }

    Timer {
        interval: 20000
        running: true
        repeat: false
        onTriggered: {
            if (!root.finished)
                console.error("ASSISTANT_CORE_HARNESS_FAIL timeout");
            core.cancel();
            Qt.callLater(function() { Qt.exit(1); });
        }
    }
}
