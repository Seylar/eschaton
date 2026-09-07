import QtQuick
import Quickshell
import Quickshell.Io
import "./providers/OpenAIAdapter.js" as OpenAIAdapter
import "./providers/AnthropicAdapter.js" as AnthropicAdapter
import "./providers/ProviderPolicy.js" as ProviderPolicy

ShellRoot {
    id: root

    function replay(text, format) {
        const lines = String(text || "").split(/\r?\n/);
        let eventData = "";
        let output = "";
        let finishReason = "";
        let sawDone = false;
        const tools = ({});

        function consume(payload) {
            const parsed = format === "anthropic"
                ? AnthropicAdapter.parseEvent(payload)
                : OpenAIAdapter.parseEvent(payload);
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
            const content = replay(contentFixture.text(), "openai");
            check(content.output === "**Réponds", "texte reconstruit incorrect");
            check(content.finishReason === "length", "finish_reason length perdu");
            check(content.sawDone, "[DONE] perdu");

            const tool = replay(toolFixture.text(), "openai");
            check(tool.finishReason === "tool_calls", "finish_reason tool_calls perdu");
            check(tool.tools["0"].id === "call_status_1", "id d'outil incorrect");
            check(tool.tools["0"].name === "system_status", "nom fragmenté incorrect");
            check(tool.tools["0"].arguments === "{}", "arguments fragmentés incorrects");

            const anthropicContent = replay(anthropicContentFixture.text(), "anthropic");
            check(anthropicContent.output === "Bonjour Eschaton.", "texte Anthropic incorrect");
            check(anthropicContent.finishReason === "stop", "stop_reason Anthropic perdu");
            check(anthropicContent.sawDone, "message_stop Anthropic perdu");

            const anthropicTool = replay(anthropicToolFixture.text(), "anthropic");
            check(anthropicTool.finishReason === "tool_calls", "tool_use Anthropic perdu");
            check(anthropicTool.tools["0"].id === "toolu_status_1", "id Anthropic incorrect");
            check(anthropicTool.tools["0"].name === "system_status", "nom Anthropic incorrect");
            check(anthropicTool.tools["0"].arguments === "{}", "input Anthropic incorrect");

            const anthropicRequest = AnthropicAdapter.buildRequest({
                baseUrl: "https://api.anthropic.com",
                model: "claude-sonnet-5",
                maxTokens: 128,
                hasApiKey: true
            }, [
                { role: "system", content: "Système fermé." },
                { role: "user", content: "État ?" }
            ], [{
                type: "function",
                function: {
                    name: "system_status",
                    description: "État",
                    parameters: { type: "object", properties: {} }
                }
            }]);
            const anthropicBody = JSON.parse(anthropicRequest.body);
            check(anthropicRequest.url === "https://api.anthropic.com/v1/messages",
                  "URL Messages incorrecte");
            check(anthropicBody.system === "Système fermé.", "system Anthropic perdu");
            check(anthropicBody.tools[0].input_schema.type === "object",
                  "schéma outil Anthropic perdu");
            check(anthropicRequest.curlArguments.indexOf("x-api-key: {{ESCHATON_ASSISTANT_API_KEY}}") >= 0,
                  "clé Anthropic non développée depuis l'environnement");

            const anthropicToolRequest = AnthropicAdapter.buildRequest({
                baseUrl: "https://api.anthropic.com",
                model: "claude-sonnet-5",
                maxTokens: 128,
                hasApiKey: true
            }, [
                { role: "system", content: "Système fermé." },
                { role: "user", content: "Restaure le snapshot 42." },
                {
                    role: "assistant",
                    content: null,
                    tool_calls: [{
                        id: "toolu_rollback_42",
                        type: "function",
                        function: {
                            name: "propose_rollback",
                            arguments: "{\"snapshot_id\":42}"
                        }
                    }]
                },
                {
                    role: "tool",
                    tool_call_id: "toolu_rollback_42",
                    content: "{\"ok\":false,\"confirmation\":\"requise\"}"
                }
            ], []);
            const anthropicToolBody = JSON.parse(anthropicToolRequest.body);
            check(anthropicToolBody.messages[1].content[0].type === "tool_use"
                    && anthropicToolBody.messages[1].content[0].id === "toolu_rollback_42"
                    && anthropicToolBody.messages[1].content[0].input.snapshot_id === 42,
                  "historique tool_use Anthropic incorrect");
            check(anthropicToolBody.messages[2].role === "user"
                    && anthropicToolBody.messages[2].content[0].type === "tool_result"
                    && anthropicToolBody.messages[2].content[0].tool_use_id === "toolu_rollback_42",
                  "historique tool_result Anthropic incorrect");

            const largeRequest = OpenAIAdapter.buildRequest({
                baseUrl: "http://127.0.0.1:18080/v1",
                model: "transport-test",
                maxTokens: 4,
                hasApiKey: false
            }, [{ role: "user", content: "x".repeat(140000) }], []);
            const largeCommand = OpenAIAdapter.buildCurlCommand(largeRequest, 5);
            check(largeRequest.body.length > 131072, "fixture transport trop petite");
            check(largeCommand.indexOf(largeRequest.body) < 0,
                  "body OpenAI encore présent dans argv");
            check(largeCommand.indexOf("@-") >= 0,
                  "transport OpenAI stdin absent");

            const anthropicCommand = AnthropicAdapter.buildCurlCommand(anthropicRequest, 5);
            check(anthropicCommand.indexOf(anthropicRequest.body) < 0,
                  "body Anthropic encore présent dans argv");
            check(anthropicCommand.indexOf("@-") >= 0,
                  "transport Anthropic stdin absent");

            check(ProviderPolicy.isLocalEndpoint("http://localhost:8080/v1"),
                  "localhost refusé");
            check(ProviderPolicy.isLocalEndpoint("http://127.42.0.1:8080/v1"),
                  "loopback IPv4 refusée");
            check(ProviderPolicy.isLocalEndpoint("http://[::1]:8080/v1"),
                  "loopback IPv6 refusée");
            check(!ProviderPolicy.isLocalEndpoint("https://localhost.example/v1"),
                  "suffixe localhost distant accepté");
            check(!ProviderPolicy.isLocalEndpoint("https://localhost@evil.example/v1"),
                  "userinfo trompeur accepté");
            check(!ProviderPolicy.validateEndpoint("https://api.openai.com/v1", true).ok,
                  "local-only accepte un endpoint distant");
            const catalog = ProviderPolicy.validateCatalog(providerFixture.text());
            check(catalog.ok && catalog.providers.length === 3,
                  "catalogue fournisseurs invalide");
            check(catalog.providers[0].local && !catalog.providers[1].local,
                  "classification local/distant incorrecte");
            check(catalog.providers[2].format === "anthropic",
                  "format Anthropic absent du catalogue");
            console.log("ASSISTANT_PARSER_HARNESS_OK");
        } catch (error) {
            console.error("ASSISTANT_PARSER_HARNESS_FAIL", error);
            Qt.callLater(function() {
                Qt.exit(1);
            });
            return;
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

    FileView {
        id: anthropicContentFixture
        path: Qt.resolvedUrl("./tests/fixtures/anthropic-content.sse")
        blockLoading: true
    }

    FileView {
        id: anthropicToolFixture
        path: Qt.resolvedUrl("./tests/fixtures/anthropic-tool-call.sse")
        blockLoading: true
    }

    FileView {
        id: providerFixture
        path: Qt.resolvedUrl("./providers.json")
        blockLoading: true
    }
}
