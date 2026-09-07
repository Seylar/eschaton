import QtQuick
import Quickshell.Io

// Thin IPC client. Closing/reloading the panel never terminates the agent.
Item {
    id: root
    visible: false
    property bool active: false
    property bool networkAllowed: false
    property bool ready: false
    property bool signedIn: false
    property bool busy: false
    property bool loginPending: false
    property string loginCode: ""
    property string loginUrl: ""
    property string plan: ""
    property string model: ""
    property var models: []
    property var recentChange: null
    property string lastError: ""
    property string connectionMessage: "Connecte ton abonnement ChatGPT pour utiliser Codex."
    property alias messages: messageModel
    readonly property int messageCount: messageModel.count
    property bool connected: false
    property bool connectWhenReady: false
    property bool sending: false
    property string buffer: ""
    property int sequence: 0
    property string clientId: Date.now() + "-" + Math.random().toString(36).slice(2)
    signal delta(string chunk)
    signal done(string status)
    signal toolCall(string callId, string name, string argsJson)

    function request(method, params) {
        if (!connected) return false;
        transport.write(JSON.stringify({id: clientId + "-" + (++sequence), method: method, params: params || {}}) + "\n");
        return true;
    }
    function start() { if (active && !transport.running) { buffer = ""; transport.running = true; } }
    function refresh() { if (connected) request("refresh"); else start(); }
    function connectAccount() {
        if (!active) return;
        if (connected) { request("enable", {enabled: networkAllowed}); request("login"); }
        else { connectWhenReady = true; start(); }
    }
    function cancelLogin() { request("cancelLogin"); }
    function logout() { request("logout"); }
    function chooseModel(value) { request("model", {model: value}); }
    function send(text) {
        if (!ready || !signedIn || !model || busy || sending || !String(text).trim()) return false;
        sending = request("send", {text: text});
        return sending;
    }
    function cancel() { request("cancel"); }
    function clear() { if (!busy) request("clear"); }
    function undoLastChange() { if (recentChange) request("desktop.undo", {id: recentChange.id}); }
    function toolResult(id, result) { return false; }
    function receive(msg) {
        if (msg.type !== "snapshot") {
            sending = false;
            if (msg.ok === false) lastError = msg.error || "Demande refusée.";
            return;
        }
        const s = msg.state, wasBusy = busy;
        ready = s.ready; signedIn = s.signedIn; busy = s.busy;
        loginPending = s.loginPending; loginCode = s.loginCode; loginUrl = s.loginUrl;
        plan = s.plan; model = s.model; models = s.models;
        recentChange = s.recentChange; lastError = s.lastError; connectionMessage = s.connectionMessage;
        const rows = s.messages || [];
        // Update only changed rows; preserve the list and scroll position while streaming.
        if (messageModel.count > rows.length || (rows.length && messageModel.count && messageModel.get(0).id !== rows[0].id))
            messageModel.clear();
        let changed = false;
        for (let i = 0; i < rows.length; i++) {
            if (i >= messageModel.count) { messageModel.append(rows[i]); changed = true; }
            else if (messageModel.get(i).content !== rows[i].content || messageModel.get(i).status !== rows[i].status) {
                messageModel.set(i, rows[i]); changed = true;
            }
        }
        if (changed) delta("");
        if (wasBusy && !busy) done(lastError ? "error" : "ok");
    }
    onNetworkAllowedChanged: { if (connected) request("enable", {enabled: networkAllowed}); }
    onActiveChanged: { if (active) start(); else transport.running = false; }
    Component.onCompleted: { if (active) start(); }
    ListModel { id: messageModel }
    Timer { interval: 2000; repeat: true; running: root.active && !transport.running; onTriggered: root.start() }
    Process {
        id: transport
        command: ["/usr/bin/eschaton-agent", "attach"]
        stdinEnabled: true
        onStarted: {
            root.connected = true;
            root.request("enable", {enabled: root.networkAllowed});
            if (root.connectWhenReady) { root.connectWhenReady = false; root.request("login"); }
        }
        stdout: SplitParser {
            splitMarker: ""
            onRead: chunk => {
                root.buffer += chunk;
                let index;
                while ((index = root.buffer.indexOf("\n")) >= 0) {
                    const line = root.buffer.slice(0, index); root.buffer = root.buffer.slice(index + 1);
                    if (line.trim()) {
                        try { root.receive(JSON.parse(line)); }
                        catch (_) { root.lastError = "Réponse du service invalide."; transport.running = false; }
                    }
                }
                if (root.buffer.length > 1048576) transport.running = false;
            }
        }
        stderr: SplitParser { splitMarker: ""; onRead: chunk => {} }
        onExited: {
            root.connected = false; root.ready = false; root.sending = false;
            if (root.active) root.connectionMessage = "Reconnexion au service Eschaton…";
        }
    }
}
