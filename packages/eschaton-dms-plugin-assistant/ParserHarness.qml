import QtQuick
import Quickshell
import Quickshell.Io
import "./providers/OpenAIAdapter.js" as OpenAIAdapter

ShellRoot {
    id: root

    function replay(text) {
        const lines = String(text || "").split(/\r?\n/);
        let eventData = "";
        let output = "";
        let finishReason = "";
        let sawDone = false;
        const tools = ({});

        function consume(payload) {
            const parsed = OpenAIAdapter.parseEvent(payload);
            if (!parsed.ok)
                throw new Error(parsed.error);
            const events = parsed.events || [];
            for (let i = 0; i < events.length; i++) {
                const event = events[i];
                if (event.kind === "delta") {
                    output += event.text;
                } else if (event.kind === "finish") {
                    finishReason = event.reason;
                } else if (event.kind === "done") {
                    sawDone = true;
                } else if (event.kind === "tool_delta") {
                    const key = String(event.index);
                    const previous = tools[key] || { id: "", name: "", arguments: "" };
                    tools[key] = {
                        id: previous.id + event.id,
                        name: previous.name + event.name,
                        arguments: previous.arguments + event.arguments
                    };
                }
            }
        }

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (!line) {
                if (eventData) {
                    consume(eventData);
                    eventData = "";
                }
            } else if (line.startsWith("data:")) {
                const part = line.slice(5).replace(/^ /, "");
                eventData += (eventData ? "\n" : "") + part;
            }
        }
        if (eventData)
            consume(eventData);
        return {
            output: output,
            finishReason: finishReason,
            sawDone: sawDone,
            tools: tools
        };
    }

    function check(condition, message) {
        if (!condition)
            throw new Error(message);
    }

    Component.onCompleted: {
        try {
            const content = replay(contentFixture.text());
            check(content.output === "**Réponds", "texte reconstruit incorrect");
            check(content.finishReason === "length", "finish_reason length perdu");
            check(content.sawDone, "[DONE] perdu");

            const tool = replay(toolFixture.text());
            check(tool.finishReason === "tool_calls", "finish_reason tool_calls perdu");
            check(tool.tools["0"].id === "call_status_1", "id d'outil incorrect");
            check(tool.tools["0"].name === "system_status", "nom fragmenté incorrect");
            check(tool.tools["0"].arguments === "{}", "arguments fragmentés incorrects");
            console.log("ASSISTANT_PARSER_HARNESS_OK");
        } catch (error) {
            console.error("ASSISTANT_PARSER_HARNESS_FAIL", error);
        }
        Qt.callLater(function() {
            Qt.quit();
        });
    }

    FileView {
        id: contentFixture
        path: Qt.resolvedUrl("./tests/fixtures/openai-content.sse")
        blockLoading: true
    }

    FileView {
        id: toolFixture
        path: Qt.resolvedUrl("./tests/fixtures/openai-tool-call.sse")
        blockLoading: true
    }
}
