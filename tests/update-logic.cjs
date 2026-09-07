// Tests des expressions/fonctions QML de production, sans moteur de rendu Qt.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const source = fs.readFileSync(path.join(__dirname,
    '../packages/eschaton-dms-plugin-update/EschatonUpdateWidget.qml'), 'utf8');
function expression(name) {
    const match = source.match(new RegExp(`readonly property (?:bool|var) ${name}:\\n([^]*?)\\n\\n`));
    assert.ok(match, `propriété absente : ${name}`);
    return match[1];
}
function widget(resultat, snapshotAvant) {
    const c = { resultat, snapshotAvant };
    vm.createContext(c);
    c.resultatsSansRetourArriere = vm.runInContext(expression('resultatsSansRetourArriere'), c);
    c.restaurationUtile = vm.runInContext(expression('restaurationUtile'), c);
    c.resultatEstUnEchec = vm.runInContext(expression('resultatEstUnEchec'), c);
    const detail = source.match(/^    function detailAnnulationTardive\([^]*?^    }/m);
    assert.ok(detail, 'fonction absente');
    vm.runInContext(detail[0], c);
    return c;
}

test('les résultats inconnus et dégradés conservent la présentation compacte', () => {
    for (const value of ['succes-degrade', 'annule-trop-tard', 'interrompu', 'echec', 'futur-verdict']) {
        const c = widget(value, 42);
        assert.equal(c.resultatEstUnEchec, true, value);
        assert.equal(c.restaurationUtile, true, value);
    }
    for (const value of ['', 'succes', 'annule', 'succes-non-verifie']) {
        assert.equal(widget(value, 42).resultatEstUnEchec, false, value);
    }
});

test('sans snapshot aucune restauration disponible dans ce panneau n’est promise', () => {
    const c = widget('annule-trop-tard', 0);
    assert.equal(c.restaurationUtile, false);
    assert.match(c.detailAnnulationTardive(), /Aucun point de retour/);
    assert.doesNotMatch(c.detailAnnulationTardive(), /retour arrière ci-dessous/);
    assert.match(c.detailAnnulationTardive(), /ont pu être installés/);
});

test('avec snapshot le message nomme le point de retour proposé', () => {
    const c = widget('annule-trop-tard', 42);
    assert.match(c.detailAnnulationTardive(), /snapshot 42/);
    assert.doesNotMatch(c.detailAnnulationTardive(), /Aucun point/);
});
