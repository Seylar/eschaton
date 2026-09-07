// Exécute les fonctions de production ; ne simule ni Qt ni le transport curl.
// Les signaux/processus sont des doublures explicites. La validation QML/VM
// reste nécessaire pour les bindings et l'ordre réel des événements Qt.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const source = fs.readFileSync(path.join(__dirname,
    '../packages/eschaton-dms-plugin-assistant/AssistantCore.qml'), 'utf8');

function core() {
    const context = {
        console, _requestActive: false, isStreaming: false, _cancelled: false,
        _pendingTools: {}, pendingToolCount: 0, maxToolPayloadChars: 65536,
        _conversation: [{ role: 'user', content: 'État du système' }],
        maxHistoryMessages: 40, _followupAllowsTools: true,
        _requestAllowsTools: true, _assistantRow: -1, _assistantText: '',
        lastError: '', streamProcess: { running: false }, requests: 0,
        rows: 0, statuses: [], flushDelta() {},
        messageModel: { count: 0 },
        beginAssistantMessage() { context.rows++; },
        startRequest() { context.requests++; },
        done(status) { context.statuses.push(status); }
    };
    Object.defineProperty(context, 'busy', {
        get: () => context.isStreaming || context.pendingToolCount > 0
    });
    vm.createContext(context);
    for (const name of ['cancel', 'toolResult', 'pendingKey', 'appendConversation', 'finishReply']) {
        // Les fonctions racine finissent sur une accolade à quatre espaces.
        const match = source.match(new RegExp(`^    function ${name}\\([^]*?^    }`, 'm'));
        assert.ok(match, `fonction de production absente : ${name}`);
        vm.runInContext(match[0], context, { filename: `AssistantCore.qml:${name}` });
    }
    return context;
}

function pending(context, names) {
    for (const [id, name] of names) context._pendingTools['call:' + id] = { id, name };
    context.pendingToolCount = names.length;
}

test('Stop pendant un outil conserve le résultat et ne relance pas le fournisseur', () => {
    const c = core();
    pending(c, [['status-1', 'system_status']]);
    c.cancel();
    assert.equal(c.busy, true);
    assert.equal(c.toolResult('status-1', '{"ok":false,"cancelled":true}'), true);
    assert.equal(c.requests, 0);
    assert.equal(c.rows, 0);
    assert.equal(c.busy, false);
    assert.deepEqual(c.statuses, ['cancelled']);
    assert.equal(c._conversation[1].tool_call_id, 'status-1');
});

test('Stop attend tous les appels, y compris une action qui ne peut plus être annulée', () => {
    const c = core();
    pending(c, [['a', 'system_status'], ['b', 'propose_rollback']]);
    c.cancel();
    c.toolResult('a', '{"cancelled":true}');
    assert.equal(c.busy, true);
    assert.equal(c.statuses.length, 0);
    c.toolResult('b', '{"ok":true,"applied":true}');
    assert.equal(c.requests, 0);
    assert.equal(c._conversation.length, 3);
    assert.equal(JSON.parse(c._conversation[2].content).applied, true);
    assert.deepEqual(c.statuses, ['cancelled']);
    assert.equal(c.toolResult('b', '{}'), false);
    assert.equal(c.requests, 0);
});

test('sans Stop, le dernier résultat relance une seule restitution désarmée après lecture système', () => {
    const c = core();
    pending(c, [['a', 'system_status'], ['b', 'trigger_update']]);
    c.toolResult('a', '{"ok":true}');
    assert.equal(c.requests, 0);
    c.toolResult('b', '{"ok":true}');
    assert.equal(c.requests, 1);
    assert.equal(c._requestAllowsTools, false);
});

test('Stop pendant le streaming arrête le processus ; au repos il ne fait rien', () => {
    const c = core();
    c.cancel();
    assert.equal(c._cancelled, false);
    c._requestActive = true;
    c.isStreaming = true;
    c.streamProcess.running = true;
    c.cancel();
    assert.equal(c._cancelled, true);
    assert.equal(c.streamProcess.running, false);
    assert.equal(c.requests, 0);
});

test('les stubs exigent une activation explicite', () => {
    assert.match(source, /property bool stubTools: false/);
});
