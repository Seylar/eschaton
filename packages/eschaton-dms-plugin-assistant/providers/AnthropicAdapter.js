// Adaptateur natif Anthropic Messages. Il traduit le format conversationnel
// interne OpenAI-like sans exposer cette différence à l'UI ou aux exécuteurs.

.pragma library

function normalizeBaseUrl(value) {
    const base = String(value || "").trim();
    if (!base)
        return "";
    return base.endsWith("/") ? base.slice(0, -1) : base;
}

function messagesUrl(baseUrl) {
    const base = normalizeBaseUrl(baseUrl);
    if (!base)
        return "";
    if (/\/v1\/messages$/.test(base))
        return base;
    if (/\/v1$/.test(base))
        return base + "/messages";
    return base + "/v1/messages";
}

function toolInput(value) {
    try {
        const parsed = JSON.parse(String(value || "{}"));
        return parsed && !Array.isArray(parsed) && typeof parsed === "object" ? parsed : {};
    } catch (error) {
        return {};
    }
}

function translateMessages(messages) {
    const source = Array.isArray(messages) ? messages : [];
    const result = [];
    let system = "";
    for (let i = 0; i < source.length; i++) {
        const message = source[i] || {};
        if (message.role === "system") {
            system += (system ? "\n\n" : "") + String(message.content || "");
            continue;
        }
        if (message.role === "tool") {
            const block = {
                type: "tool_result",
                tool_use_id: String(message.tool_call_id || ""),
                content: String(message.content || "")
            };
            const previous = result.length > 0 ? result[result.length - 1] : null;
            if (previous && previous.role === "user" && previous._toolResults) {
                previous.content.push(block);
            } else {
                result.push({ role: "user", content: [block], _toolResults: true });
            }
            continue;
        }
        if (message.role !== "user" && message.role !== "assistant")
            continue;

        let content = String(message.content || "");
        if (message.role === "assistant" && Array.isArray(message.tool_calls)) {
            const blocks = [];
            if (content)
                blocks.push({ type: "text", text: content });
            for (let j = 0; j < message.tool_calls.length; j++) {
                const call = message.tool_calls[j] || {};
                const fn = call.function || {};
                blocks.push({
                    type: "tool_use",
                    id: String(call.id || ""),
                    name: String(fn.name || ""),
                    input: toolInput(fn.arguments)
                });
            }
            content = blocks;
        }
        result.push({ role: message.role, content: content });
    }

    for (let k = 0; k < result.length; k++)
        delete result[k]._toolResults;
    return { system: system, messages: result };
}

function translateTools(tools) {
    const source = Array.isArray(tools) ? tools : [];
    const result = [];
    for (let i = 0; i < source.length; i++) {
        const fn = source[i] && source[i].function;
        if (!fn)
            continue;
        result.push({
            name: String(fn.name || ""),
            description: String(fn.description || ""),
            input_schema: fn.parameters || { type: "object", properties: {} }
        });
    }
    return result;
}

function buildRequest(settings, messages, tools) {
    const config = settings || {};
    const translated = translateMessages(messages);
    const body = {
        model: String(config.model || ""),
        messages: translated.messages,
        stream: true,
        max_tokens: Math.max(1, Number(config.maxTokens || 1024))
    };
    if (translated.system)
        body.system = translated.system;
    const translatedTools = translateTools(tools);
    if (translatedTools.length > 0)
        body.tools = translatedTools;

    // Les modèles Anthropic récents peuvent refuser une température non
    // défaut ; la v1 laisse donc le fournisseur appliquer son réglage natif.
    const curlArguments = [
        "--header", "Content-Type: application/json",
        "--header", "anthropic-version: 2023-06-01"
    ];
    if (config.hasApiKey) {
        curlArguments.push(
            "--variable", "%ESCHATON_ASSISTANT_API_KEY",
            "--expand-header", "x-api-key: {{ESCHATON_ASSISTANT_API_KEY}}"
        );
    }
    return {
        url: messagesUrl(config.baseUrl),
        body: JSON.stringify(body),
        curlArguments: curlArguments
    };
}

function buildCurlCommand(request, timeoutSeconds) {
    const requestData = request || {};
    const timeout = Math.max(1, Number(timeoutSeconds || 60));
    return [
        "/usr/bin/curl",
        "--disable",
        "--no-buffer",
        "--silent",
        "--show-error",
        "--connect-timeout", "5",
        "--max-time", String(timeout),
        "--write-out", "\nESCHATON_HTTP_STATUS:%{http_code}\n"
    ].concat(requestData.curlArguments || []).concat([
        "--data-binary", requestData.body || "{}",
        requestData.url || ""
    ]);
}

function parseEvent(payload) {
    const dataText = String(payload || "").trim();
    if (!dataText)
        return { ok: true, events: [] };

    let data;
    try {
        data = JSON.parse(dataText);
    } catch (error) {
        return { ok: false, error: "JSON SSE Anthropic invalide : " + error };
    }
    const type = String(data && data.type || "");
    if (type === "ping" || type === "message_start" || type === "content_block_stop")
        return { ok: true, events: [] };
    if (type === "error") {
        const details = data.error && (data.error.message || data.error.type);
        return { ok: true, events: [{ kind: "error", message: String(details || "erreur Anthropic") }] };
    }
    if (type === "message_stop")
        return { ok: true, events: [{ kind: "done" }] };
    if (type === "content_block_start") {
        const block = data.content_block || {};
        if (block.type === "text" && block.text)
            return { ok: true, events: [{ kind: "delta", text: String(block.text) }] };
        if (block.type === "tool_use") {
            return { ok: true, events: [{
                kind: "tool_delta",
                index: Number(data.index || 0),
                id: String(block.id || ""),
                name: String(block.name || ""),
                arguments: ""
            }] };
        }
        return { ok: true, events: [] };
    }
    if (type === "content_block_delta") {
        const delta = data.delta || {};
        if (delta.type === "text_delta")
            return { ok: true, events: [{ kind: "delta", text: String(delta.text || "") }] };
        if (delta.type === "input_json_delta") {
            return { ok: true, events: [{
                kind: "tool_delta",
                index: Number(data.index || 0),
                id: "",
                name: "",
                arguments: String(delta.partial_json || "")
            }] };
        }
        return { ok: true, events: [] };
    }
    if (type === "message_delta") {
        const reason = String(data.delta && data.delta.stop_reason || "");
        const mapped = reason === "tool_use" ? "tool_calls"
            : (reason === "max_tokens" ? "length"
               : (reason === "refusal" ? "content_filter" : "stop"));
        return { ok: true, events: reason ? [{ kind: "finish", reason: mapped }] : [] };
    }
    return { ok: true, events: [] };
}
