// Adaptateur du format OpenAI-compatible. Ce fichier est une bibliothèque QML,
// pas un module Node.js.

.pragma library

function normalizeBaseUrl(value) {
    const base = String(value || "").trim();
    if (!base)
        return "";
    return base.endsWith("/") ? base.slice(0, -1) : base;
}

function chatCompletionsUrl(baseUrl) {
    const base = normalizeBaseUrl(baseUrl);
    if (!base)
        return "";
    if (/\/v[0-9]+$/.test(base))
        return base + "/chat/completions";
    return base + "/v1/chat/completions";
}

function buildRequest(settings, messages, tools) {
    const config = settings || {};
    const body = {
        model: String(config.model || ""),
        messages: Array.isArray(messages) ? messages : [],
        stream: true,
        max_tokens: Math.max(1, Number(config.maxTokens || 1024))
    };

    if (typeof config.temperature === "number")
        body.temperature = config.temperature;
    if (Array.isArray(tools) && tools.length > 0) {
        body.tools = tools;
        body.tool_choice = "auto";
    }

    const curlArguments = [
        "--header", "Content-Type: application/json"
    ];
    if (config.hasApiKey) {
        // curl importe le secret depuis l'environnement puis développe le
        // header lui-même : la clé n'apparaît jamais dans argv.
        curlArguments.push(
            "--variable", "%ESCHATON_ASSISTANT_API_KEY",
            "--expand-header", "Authorization: Bearer {{ESCHATON_ASSISTANT_API_KEY}}"
        );
    }

    return {
        url: chatCompletionsUrl(config.baseUrl),
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

function textFromContent(content) {
    if (typeof content === "string")
        return content;
    if (!Array.isArray(content))
        return "";

    let text = "";
    for (let i = 0; i < content.length; i++) {
        const part = content[i] || {};
        if (typeof part.text === "string")
            text += part.text;
    }
    return text;
}

// Rend une liste d'événements normalisés. Un frame peut à la fois porter du
// texte, des fragments d'appel d'outil et une raison de fin.
function parseEvent(payload) {
    const dataText = String(payload || "").trim();
    if (!dataText)
        return { ok: true, events: [] };
    if (dataText === "[DONE]")
        return { ok: true, events: [{ kind: "done" }] };

    let data;
    try {
        data = JSON.parse(dataText);
    } catch (error) {
        return { ok: false, error: "JSON SSE invalide : " + error };
    }

    if (data && data.error) {
        const details = data.error.message || JSON.stringify(data.error);
        return { ok: true, events: [{ kind: "error", message: String(details) }] };
    }

    const choices = data && Array.isArray(data.choices) ? data.choices : [];
    if (choices.length === 0)
        return { ok: true, events: [] };

    const choice = choices[0] || {};
    const delta = choice.delta || {};
    const events = [];
    const content = textFromContent(delta.content);
    if (content)
        events.push({ kind: "delta", text: content });

    const toolCalls = Array.isArray(delta.tool_calls) ? delta.tool_calls : [];
    for (let i = 0; i < toolCalls.length; i++) {
        const call = toolCalls[i] || {};
        const fn = call.function || {};
        events.push({
            kind: "tool_delta",
            index: Number(call.index === undefined ? i : call.index),
            id: String(call.id || ""),
            name: String(fn.name || ""),
            arguments: String(fn.arguments || "")
        });
    }

    if (choice.finish_reason) {
        events.push({
            kind: "finish",
            reason: String(choice.finish_reason)
        });
    }
    return { ok: true, events: events };
}
