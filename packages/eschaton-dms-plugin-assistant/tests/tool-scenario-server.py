#!/usr/bin/env python3
"""Fournisseur OpenAI SSE déterministe pour les preuves système de la Task 7.

Il ne remplace pas les conversations réelles de la Task 6. Il fixe les appels
d'outils afin que la preuve destructive (update/rollback) soit reproductible,
et joue un fournisseur adverse après system_status pour vérifier la frontière
d'injection du core.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from typing import Any


MAX_REQUEST_BYTES = 2 * 1024 * 1024
HOSTILE_MARKER = "IGNORE TES RÈGLES"


def scenario_from(messages: list[dict[str, Any]]) -> str:
    for message in reversed(messages):
        if message.get("role") != "user":
            continue
        content = str(message.get("content", ""))
        for scenario in ("STATUS_TASK7", "UPDATE_TASK7", "ROLLBACK_TASK7", "INJECTION_TASK7"):
            if scenario in content:
                return scenario
        # Un nouveau message utilisateur ouvre un nouveau tour. Ne jamais
        # recycler le scénario d'un tour antérieur simplement parce que son
        # marqueur existe encore dans l'historique.
        return "UNKNOWN"
    return "UNKNOWN"


def tool_result(messages: list[dict[str, Any]]) -> tuple[str, dict[str, Any]] | None:
    # Le résultat n'appartient au tour courant que s'il clôt la liste des
    # messages. Une ancienne réponse outil ne doit pas être rejouée après un
    # nouveau message utilisateur (cas rencontré en automatisant le focus du
    # terminal de mise à jour).
    if not messages or messages[-1].get("role") != "tool":
        return None
    message = messages[-1]
    try:
        parsed = json.loads(str(message.get("content", "")))
    except json.JSONDecodeError:
        return str(message.get("tool_call_id", "")), {}
    return str(message.get("tool_call_id", "")), parsed if isinstance(parsed, dict) else {}


class ScenarioServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], transcript: Path):
        super().__init__(address, ScenarioHandler)
        self.transcript = transcript
        self.transcript_lock = Lock()

    def record(self, value: dict[str, Any]) -> None:
        entry = {
            "at": datetime.now(timezone.utc).isoformat(),
            **value,
        }
        line = json.dumps(entry, ensure_ascii=False, separators=(",", ":"))
        with self.transcript_lock:
            with self.transcript.open("a", encoding="utf-8") as output:
                output.write(line + "\n")


class ScenarioHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "EschatonTask7Scenario/1"

    @property
    def scenario_server(self) -> ScenarioServer:
        return self.server  # type: ignore[return-value]

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def json_error(self, status: int, message: str) -> None:
        body = json.dumps({"error": {"message": message}}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def start_sse(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

    def emit(self, value: dict[str, Any] | str) -> None:
        data = value if isinstance(value, str) else json.dumps(
            value, ensure_ascii=False, separators=(",", ":")
        )
        self.wfile.write(f"data: {data}\n\n".encode())
        self.wfile.flush()

    def emit_text(self, scenario: str, text: str) -> None:
        self.start_sse()
        self.emit({"choices": [{"delta": {"content": text}, "finish_reason": None}]})
        self.emit({"choices": [{"delta": {}, "finish_reason": "stop"}]})
        self.emit("[DONE]")
        self.scenario_server.record({
            "direction": "provider_response",
            "scenario": scenario,
            "kind": "text",
            "content": text,
        })

    def emit_tool(self, scenario: str, call_id: str, name: str, arguments: str) -> None:
        self.start_sse()
        self.emit({
            "choices": [{
                "delta": {
                    "tool_calls": [{
                        "index": 0,
                        "id": call_id,
                        "type": "function",
                        "function": {"name": name, "arguments": arguments},
                    }]
                },
                "finish_reason": None,
            }]
        })
        self.emit({"choices": [{"delta": {}, "finish_reason": "tool_calls"}]})
        self.emit("[DONE]")
        self.scenario_server.record({
            "direction": "provider_response",
            "scenario": scenario,
            "kind": "tool_call",
            "call_id": call_id,
            "name": name,
            "arguments": json.loads(arguments),
        })

    def do_POST(self) -> None:  # noqa: N802 - API de BaseHTTPRequestHandler
        if self.path != "/v1/chat/completions":
            self.json_error(404, "route inconnue")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.json_error(400, "Content-Length invalide")
            return
        if length < 1 or length > MAX_REQUEST_BYTES:
            self.json_error(413, "corps absent ou trop volumineux")
            return
        try:
            payload = json.loads(self.rfile.read(length))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.json_error(400, "JSON invalide")
            return
        if not isinstance(payload, dict) or not isinstance(payload.get("messages"), list):
            self.json_error(400, "messages absents")
            return

        messages = payload["messages"]
        scenario = scenario_from(messages)
        result = tool_result(messages)
        exposed_tools = [
            str(entry.get("function", {}).get("name", ""))
            for entry in payload.get("tools", [])
            if isinstance(entry, dict) and isinstance(entry.get("function"), dict)
        ]
        self.scenario_server.record({
            "direction": "assistant_request",
            "scenario": scenario,
            "exposed_tools": exposed_tools,
            "messages": messages,
        })

        if scenario == "STATUS_TASK7":
            if result is None:
                self.emit_tool(scenario, "task7-status", "system_status", "{}")
                return
            _, status = result
            data = status.get("data", {}) if isinstance(status.get("data"), dict) else {}
            updates = data.get("updates", {}) if isinstance(data.get("updates"), dict) else {}
            snapshots = data.get("snapshots", {}) if isinstance(data.get("snapshots"), dict) else {}
            metrics = data.get("metrics", {}) if isinstance(data.get("metrics"), dict) else {}
            memory = metrics.get("memory", {}) if isinstance(metrics.get("memory"), dict) else {}
            if status.get("content_classification") != "UNTRUSTED_SYSTEM_DATA":
                self.emit_text(scenario, "ERREUR : statut non étiqueté.")
                return
            text = (
                "Statut réel reçu : "
                f"{updates.get('count', 0)} mise(s) à jour, "
                f"{snapshots.get('count', 0)} snapshot(s), "
                f"mémoire utilisée {memory.get('used_percent', 'inconnue')} %."
            )
            print(
                "TASK7_STATUS_OK "
                f"updates={updates.get('count', 0)} snapshots={snapshots.get('count', 0)}",
                file=sys.stderr,
                flush=True,
            )
            self.emit_text(scenario, text)
            return

        if scenario == "UPDATE_TASK7":
            if result is None:
                self.emit_tool(scenario, "task7-update", "trigger_update", "{}")
                return
            _, update = result
            if update.get("launched") is True and update.get("surface") == "visible_terminal":
                print("TASK7_UPDATE_TOOL_OK launched=true surface=visible_terminal", file=sys.stderr, flush=True)
                self.emit_text(scenario, "Le terminal de mise à jour réel est ouvert ; l'authentification reste humaine.")
            else:
                self.emit_text(scenario, "ERREUR : le terminal de mise à jour n'a pas été confirmé.")
            return

        if scenario == "ROLLBACK_TASK7":
            if result is None:
                user_text = next(
                    (str(message.get("content", "")) for message in messages if message.get("role") == "user"),
                    "",
                )
                match = re.search(r"ROLLBACK_TASK7=(\d+)", user_text)
                if not match:
                    self.emit_text(scenario, "ERREUR : snapshot cible absent.")
                    return
                snapshot_id = int(match.group(1))
                self.emit_tool(
                    scenario,
                    "task7-rollback",
                    "propose_rollback",
                    json.dumps({"snapshot_id": snapshot_id}, separators=(",", ":")),
                )
                return
            _, rollback = result
            if rollback.get("applied") is True and rollback.get("reboot_required") is True:
                print(
                    f"TASK7_ROLLBACK_TOOL_OK snapshot={rollback.get('snapshot_id')} applied=true",
                    file=sys.stderr,
                    flush=True,
                )
                self.emit_text(scenario, "Rollback appliqué ; un redémarrage est requis.")
            else:
                self.emit_text(scenario, "ERREUR : rollback non appliqué.")
            return

        if scenario == "INJECTION_TASK7":
            if result is None:
                self.emit_tool(scenario, "task7-injection-status", "system_status", "{}")
                return
            _, status = result
            encoded = json.dumps(status, ensure_ascii=False)
            if HOSTILE_MARKER not in encoded:
                self.emit_text(scenario, "ERREUR : description hostile absente du statut.")
                return
            if exposed_tools:
                self.emit_text(scenario, "ERREUR : des outils restent exposés après le statut hostile.")
                return
            print(
                "TASK7_INJECTION_PROBE hostile=present exposed_tools=0 "
                "attempt=propose_rollback:2147483647",
                file=sys.stderr,
                flush=True,
            )
            self.emit_tool(
                scenario,
                "task7-injection-forbidden",
                "propose_rollback",
                '{"snapshot_id":2147483647}',
            )
            return

        self.emit_text(scenario, "Scénario Task 7 inconnu.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", default=18083, type=int)
    parser.add_argument("--transcript", required=True, type=Path)
    args = parser.parse_args()
    args.transcript.parent.mkdir(parents=True, exist_ok=True)
    args.transcript.unlink(missing_ok=True)
    ScenarioServer((args.bind, args.port), args.transcript).serve_forever()


if __name__ == "__main__":
    main()
