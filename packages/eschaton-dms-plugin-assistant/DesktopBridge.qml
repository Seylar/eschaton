import QtQuick
import Quickshell.Io
import qs.Common

// An actuator owned by the desktop. The agent owns planning and the journal.
// Comparison and replacement are synchronous in the same QML event-loop turn.
Item {
    id: root
    function layout(bar) {
        return {leftWidgets: bar.leftWidgets, centerWidgets: bar.centerWidgets, rightWidgets: bar.rightWidgets};
    }
    function valid(value) {
        const keys = ["leftWidgets", "centerWidgets", "rightWidgets"];
        return value && Object.keys(value).length === 3 && keys.every(k =>
            Array.isArray(value[k]) && value[k].length <= 100 && value[k].every(w => typeof w === "string" && w.length <= 128));
    }
    IpcHandler {
        target: "eschatonDesktop"
        function inspect(): string {
            return JSON.stringify({ok: true, value: SettingsData.barConfigs.map(b =>
                ({id: b.id, leftWidgets: b.leftWidgets, centerWidgets: b.centerWidgets, rightWidgets: b.rightWidgets}))});
        }
        function apply(barId: string, expectedJson: string, desiredJson: string): string {
            try {
                if (expectedJson.length > 65536 || desiredJson.length > 65536) throw "Arguments trop longs";
                const expected = JSON.parse(expectedJson), desired = JSON.parse(desiredJson);
                if (!root.valid(expected) || !root.valid(desired)) throw "Disposition invalide";
                const keys = ["leftWidgets", "centerWidgets", "rightWidgets"];
                const oldWidgets = keys.reduce((a,k) => a.concat(expected[k]), []).sort();
                const newWidgets = keys.reduce((a,k) => a.concat(desired[k]), []).sort();
                if (JSON.stringify(oldWidgets) !== JSON.stringify(newWidgets)) throw "Seul le déplacement des widgets existants est permis";
                const bar = SettingsData.getBarConfig(barId);
                if (!bar || keys.some(k => JSON.stringify(bar[k]) !== JSON.stringify(expected[k])))
                    throw "Le bureau a changé depuis la lecture";
                SettingsData.updateBarConfig(barId, desired);
                const actual = root.layout(SettingsData.getBarConfig(barId));
                if (keys.some(k => JSON.stringify(actual[k]) !== JSON.stringify(desired[k]))) throw "Disposition refusée par le bureau";
                return JSON.stringify({ok: true, value: actual});
            } catch(e) { return JSON.stringify({ok: false, error: String(e)}); }
        }
    }
}
