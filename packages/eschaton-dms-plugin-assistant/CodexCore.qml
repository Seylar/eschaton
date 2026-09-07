import QtQuick
import Quickshell.Io
import "./CodexProtocol.js" as CodexProtocol

Item {
    id: root
    visible: false
    property bool active: false
    property bool ready: false
    property bool signedIn: false
    property bool busy: false
    property bool loginPending: false
    property string loginCode: ""
    property string loginUrl: ""
    property string plan: ""
    property string model: ""
    property var models: []
    property string lastError: ""
    property string connectionMessage: "Connecte ton abonnement ChatGPT pour utiliser Codex."
    property alias messages: messageModel
    readonly property int messageCount: messageModel.count
    property var protocol: null
    property string buffer: ""
    property string pendingDelta: ""
    property int assistantRow: -1
    property string lastItemId: ""
    property bool connectWhenReady: false
    signal delta(string chunk)
    signal done(string status)
    signal toolCall(string callId, string name, string argsJson)

    function start() {
        if (!active || server.running) return;
        lastError = ""; ready = false; buffer = "";
        connectionMessage = "Démarrage de Codex…";
        let catalog;
        try { catalog = JSON.parse(catalogFile.text()).tools; }
        catch (_) { lastError = "Catalogue système indisponible."; return; }
        protocol = CodexProtocol.create(function(msg) { server.write(JSON.stringify(msg) + "\n"); },
            function(type, data) { root.handleEvent(type, data); }, catalog);
        server.running = true;
        startupTimeout.restart();
    }
    function connectAccount() {
        if (!active) return;
        lastError = "";
        if (ready) protocol.login();
        else { connectWhenReady = true; start(); }
    }
    function refresh() { if (ready) protocol.refresh(); else start(); }
    function cancelLogin() { if (protocol) protocol.cancelLogin(); }
    function logout() { if (ready && !busy && protocol.logout()) clear(); }
    function chooseModel(value) { if (ready) protocol.chooseModel(value); }
    function send(text) {
        if (!ready || busy || !signedIn) return false;
        // Append before sending: event handlers may run synchronously.
        if (!String(text).trim() || String(text).length > 32768 || !model) return false;
        lastError = "";
        if (messageModel.count >= 80) messageModel.remove(0, 2);
        messageModel.append({ role: "user", content: text, status: "ok", id: "user-" + Date.now() });
        assistantRow = -1; lastItemId = "";
        return protocol.send(text);
    }
    function cancel() { if (protocol && busy) { protocol.cancel(); cancelTimeout.restart(); } }
    function clear() {
        if (busy) return;
        if (protocol) protocol.clear();
        messageModel.clear(); assistantRow = -1; lastItemId = ""; pendingDelta = ""; lastError = "";
    }
    function toolResult(id, result) {
        const accepted = protocol ? protocol.toolResult(id, result) : false;
        if (accepted && busy) responseTimeout.restart();
        return accepted;
    }
    function flushDelta() {
        if (!pendingDelta || assistantRow < 0) return;
        const chunk = pendingDelta; pendingDelta = "";
        messageModel.setProperty(assistantRow, "content", messageModel.get(assistantRow).content + chunk);
        delta(chunk);
    }
    function stopWithError(message) {
        lastError = message;
        connectionMessage = message;
        ready = false; server.running = false;
    }
    function handleEvent(type, data) {
        if (type === "ready") {
            startupTimeout.stop(); ready = true;
            if (connectWhenReady) { connectWhenReady = false; protocol.login(); }
        } else if (type === "account") {
            signedIn = data.signedIn; plan = data.plan;
            connectionMessage = signedIn ? "" : "Connecte ton abonnement ChatGPT pour utiliser Codex.";
            if (!signedIn) { model = ""; models = []; }
        } else if (type === "models") {
            models = data.models; model = data.model;
            if (!model) connectionMessage = "Aucun modèle Codex disponible pour ce compte.";
        } else if (type === "loginPending") {
            loginPending = true; connectionMessage = "Préparation de la connexion sécurisée…";
        } else if (type === "login") {
            loginCode = data.code || ""; loginUrl = data.url || ""; loginPending = loginCode !== "";
            connectionMessage = loginPending ? "Ouvre la page de connexion, puis saisis ce code." : "";
        } else if (type === "busy") {
            busy = true; responseTimeout.restart();
        } else if (type === "delta") {
            responseTimeout.restart();
            if (assistantRow < 0 || lastItemId !== data.itemId) {
                flushDelta();
                if (assistantRow >= 0) messageModel.setProperty(assistantRow, "status", "ok");
                assistantRow = messageModel.count; lastItemId = data.itemId;
                messageModel.append({ role: "assistant", content: "", status: "streaming", id: String(data.itemId) });
            }
            pendingDelta += data.text;
            if (!deltaFlush.running) deltaFlush.start();
        } else if (type === "tool") {
            responseTimeout.stop();
            toolCall(data.id, data.name, data.args);
        } else if (type === "done") {
            flushDelta(); busy = false; cancelTimeout.stop(); responseTimeout.stop();
            lastError = data.error || "";
            if (assistantRow >= 0) messageModel.setProperty(assistantRow, "status", data.status);
            done(data.status);
        } else if (type === "fatal") stopWithError(data.error);
    }
    onActiveChanged: {
        if (active) start();
        else { connectWhenReady = false; server.running = false; }
    }
    Component.onCompleted: { if (active) start(); }
    FileView { id: catalogFile; path: Qt.resolvedUrl("tool-catalog.json"); blockLoading: true }
    ListModel { id: messageModel }
    Timer { id: deltaFlush; interval: 32; onTriggered: root.flushDelta() }
    Timer { interval: 1000; repeat: true; running: server.running; onTriggered: { if (root.protocol) root.protocol.tick(Date.now()); } }
    Timer { id: startupTimeout; interval: 15000; onTriggered: root.stopWithError("Codex n'a pas démarré. Vérifie le paquet eschaton-codex.") }
    Timer { id: cancelTimeout; interval: 5000; onTriggered: root.stopWithError("Réponse arrêtée. Relance Codex pour continuer.") }
    Timer { id: responseTimeout; interval: 120000; onTriggered: root.stopWithError("Codex ne répond plus depuis deux minutes. Réessaie.") }
    Process {
        id: server
        command: ["/usr/bin/eschaton-codex-session"]
        stdinEnabled: true
        onStarted: root.protocol.start()
        stdout: SplitParser {
            splitMarker: ""
            onRead: chunk => {
                root.buffer += chunk;
                let index;
                while ((index = root.buffer.indexOf("\n")) >= 0) {
                    const line = root.buffer.slice(0, index); root.buffer = root.buffer.slice(index + 1);
                    if (line.trim()) root.protocol.receive(line);
                }
                if (root.buffer.length > 1048576) root.stopWithError("Flux Codex trop volumineux.");
            }
        }
        // Les diagnostics du runtime peuvent contenir des données de compte.
        // Ils sont consommés sans les recopier dans le journal du bureau.
        stderr: SplitParser { splitMarker: ""; onRead: chunk => {} }
        onExited: exitCode => {
            startupTimeout.stop(); cancelTimeout.stop(); responseTimeout.stop();
            root.flushDelta(); root.ready = false; root.signedIn = false;
            root.loginPending = false; root.loginCode = ""; root.loginUrl = "";
            if (root.busy) { root.busy = false; root.done("cancelled"); }
            root.protocol = null;
            if (root.active && !root.lastError) {
                root.lastError = "Codex s'est arrêté. Réessaie la connexion.";
                root.connectionMessage = root.lastError;
            }
        }
    }
}
