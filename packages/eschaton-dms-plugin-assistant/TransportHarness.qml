import QtQuick
import Quickshell

ShellRoot {
    id: root
    property bool finished: false
    readonly property int bodyCharacters: 140000

    function fail(message) {
        console.error("ASSISTANT_TRANSPORT_HARNESS_FAIL", message);
        finished = true;
        Qt.callLater(function() { Qt.exit(1); });
    }

    function proveMissingToolIndexHandling() {
        core._toolFragments = ({});
        core._toolPayloadChars = 0;
        core._fatalError = "";

        core.mergeToolDelta({
            index: null,
            id: "call_missing_index",
            name: "system_",
            arguments: ""
        });
        core.mergeToolDelta({
            index: null,
            id: "",
            name: "status",
            arguments: "{}"
        });

        const fragment = core._toolFragments["0"];
        if (!fragment || fragment.id !== "call_missing_index"
                || fragment.name !== "system_status"
                || fragment.arguments !== "{}") {
            fail("les fragments sans index ne sont pas fusionnés par call_id");
            return false;
        }

        core._toolFragments["1"] = {
            id: "call_other",
            name: "propose_rollback",
            arguments: "{}"
        };
        const ambiguous = core.resolveToolIndex({ index: null, id: "" });
        if (ambiguous.ok) {
            fail("un fragment sans index ni call_id ambigu a été accepté");
            return false;
        }

        core._toolFragments = ({});
        core._toolPayloadChars = 0;
        core._fatalError = "";
        return true;
    }

    Component.onCompleted: {
        core.toolCatalog = core.loadToolCatalog();
        if (!proveMissingToolIndexHandling())
            return;
        if (!core.send("x".repeat(bodyCharacters)))
            fail("send a refusé le body long");
    }

    AssistantCore {
        id: core
        baseUrl: "http://127.0.0.1:18080/v1"
        model: "transport-test"
        maxTokens: 4
        timeoutSeconds: 10

        onDone: status => {
            const last = messages.get(messages.count - 1);
            if (status !== "ok" || last.content !== "stdin-ok") {
                root.fail("status=" + status + " error=" + lastError);
                return;
            }
            root.finished = true;
            console.log("ASSISTANT_TRANSPORT_HARNESS_OK body_chars="
                        + root.bodyCharacters + " response=" + last.content);
            Qt.callLater(function() { Qt.quit(); });
        }
    }

    Timer {
        interval: 15000
        running: true
        repeat: false
        onTriggered: {
            if (!root.finished) {
                core.cancel();
                root.fail("timeout");
            }
        }
    }
}
