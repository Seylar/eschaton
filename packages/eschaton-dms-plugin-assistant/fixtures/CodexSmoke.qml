import QtQuick
import Quickshell
import ".." as Assistant

ShellRoot {
    Assistant.CodexCore { id: core; networkAllowed: true }
    Timer { interval: 50; running: true; onTriggered: core.active = true }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (core.lastError) {
                console.error("CODEX_SMOKE_FAIL", core.lastError);
                Qt.quit();
            } else if (core.ready && core.connectionMessage !== "Démarrage de Codex…") {
                console.log("CODEX_SMOKE_PASS", "ready=" + core.ready, "signedIn=" + core.signedIn);
                Qt.quit();
            }
        }
    }
    Timer { interval: 20000; running: true; onTriggered: { console.error("CODEX_SMOKE_FAIL timeout"); Qt.quit(); } }
}
