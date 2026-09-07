'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const execute = promisify(execFile);
const sections = ['leftWidgets', 'centerWidgets', 'rightWidgets'];
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
function atomic(file, value) {
    fs.mkdirSync(path.dirname(file), {recursive:true, mode:0o700});
    const temp = file + '.' + randomUUID();
    const fd = fs.openSync(temp, 'wx', 0o600);
    try { fs.writeFileSync(fd, JSON.stringify(value)); fs.fsyncSync(fd); }
    finally { fs.closeSync(fd); }
    fs.renameSync(temp, file);
    const dir = fs.openSync(path.dirname(file), 'r');
    try { fs.fsyncSync(dir); } finally { fs.closeSync(dir); }
}
function read(file, fallback) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch(e) { if (e.code === 'ENOENT') return fallback; throw e; }
}
async function ipc(method, ...args) {
    const {stdout} = await execute('/usr/bin/qs', ['ipc', '-p', '/usr/share/quickshell/dms',
        '--any-display', 'call', 'eschatonDesktop', method, ...args], {timeout:5000, maxBuffer:262144});
    const result = JSON.parse(stdout);
    if (!result.ok) throw Error(result.error || 'Bureau indisponible.');
    return result.value;
}
class Desktop {
    constructor(directory, bridge = ipc) {
        this.file = path.join(directory, 'changes.json');
        this.changes = read(this.file, []); this.bridge = bridge; this.queue = Promise.resolve();
    }
    serial(fn) { const result = this.queue.then(fn); this.queue = result.catch(()=>{}); return result; }
    save() { atomic(this.file, this.changes); }
    async inspect() { return this.bridge('inspect'); }
    async layout(id) {
        const bar = (await this.inspect()).find(b=>b.id===id);
        if (!bar) throw Error('Barre introuvable.');
        return Object.fromEntries(sections.map(k=>[k,bar[k]]));
    }
    recover() { return this.serial(async()=>{
        for (const c of this.changes.filter(c=>['applying','undoing'].includes(c.status))) {
            const current = await this.layout(c.barId);
            c.status = equal(current,c.before) ? (c.status==='undoing'?'undone':'not_applied')
                : equal(current,c.after) ? 'verified' : 'conflict';
            this.save();
        }
    }); }
    move(args, requestId, permitted = () => true) { return this.serial(async()=>{
        if (typeof requestId !== 'string' || requestId.length > 160 || !requestId) throw Error('Identifiant requis.');
        const previous = this.changes.find(c=>c.id===requestId);
        if (previous) {
            if (!equal(previous.request,args)) throw Error('Identifiant déjà utilisé pour une autre action.');
            return previous;
        }
        if (!permitted()) throw Error("Action annulée.");
        const {barId, widget, section, index} = args;
        if (typeof barId !== 'string' || typeof widget !== 'string' || !['left','center','right'].includes(section)
            || !Number.isInteger(index) || index < 0) throw Error('Déplacement invalide.');
        if (this.changes.length >= 1000) throw Error('Journal plein : export et archivage nécessaires.');
        const before = await this.layout(barId);
        const widgets = sections.flatMap(k=>before[k]);
        if (!widgets.every(w=>typeof w==='string') || widgets.filter(w=>w===widget).length!==1)
            throw Error('Widget absent, ambigu ou format non pris en charge.');
        const after = Object.fromEntries(sections.map(k=>[k,before[k].filter(w=>w!==widget)]));
        const target = after[section+'Widgets'];
        if (index > target.length) throw Error('Position hors limites.');
        target.splice(index,0,widget);
        const change = {id:requestId, request:args, barId, before, after, at:new Date().toISOString(),
            label:(widget==='clock'?'Horloge':widget)+' · '+({left:'à gauche',center:'au centre',right:'à droite'}[section]), status:equal(before,after)?'unchanged':'applying'};
        this.changes.push(change); this.save();
        if (change.status==='unchanged') return change;
        await this.apply(change, false, permitted);
        return change;
    }); }
    undo(id) { return this.serial(async()=>{
        const change = this.changes.find(c=>c.id===id);
        if (!change) throw Error('Modification inconnue.');
        if (change.status==='undone') return change;
        if (change.status!=='verified') throw Error('Cette modification ne peut pas être annulée automatiquement.');
        if (!equal(await this.layout(change.barId),change.after)) throw Error('Le bureau a changé depuis : annulation refusée pour préserver tes réglages.');
        change.status='undoing'; this.save();
        await this.apply(change, true); return change;
    }); }
    async apply(change, undo, permitted = () => true) {
        const expected=undo?change.after:change.before, desired=undo?change.before:change.after;
        try {
            if (!permitted()) throw Error("Action annulée.");
            // Comparison and mutation occur together in the DMS event loop.
            await this.bridge('apply', change.barId, JSON.stringify(expected), JSON.stringify(desired));
            if (!equal(await this.layout(change.barId),desired)) throw Error('Vérification du bureau en échec.');
            change.status=undo?'undone':'verified'; delete change.error; this.save();
        } catch(e) {
            // An IPC timeout is not proof of failure. Reconcile without replaying.
            try {
                const current=await this.layout(change.barId);
                change.status=equal(current,desired)?(undo?'undone':'verified')
                    : equal(current,expected)?(undo?'verified':'not_applied'):'conflict';
            } catch (_) { /* Leave applying/undoing for restart reconciliation. */ }
            change.error=String(e.message).slice(0,1000); this.save();
            if (change.status!==(undo?'undone':'verified')) throw e;
        }
    }
}
module.exports={Desktop,atomic,read};
