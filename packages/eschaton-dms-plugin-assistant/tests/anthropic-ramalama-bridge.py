#!/usr/bin/env python3
"""Pont de terrain Anthropic Messages SSE -> RamaLama OpenAI SSE.

Ce serveur n'est ni livré ni installé. Il permet de faire traverser au plugin
réel son adaptateur Anthropic, son transport curl et son KeyringBridge, tout en
gardant l'inférence dans la VM de validation.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


MAX_REQUEST_BYTES = 2 * 1024 * 1024


def anthropic_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""

    parts: list[str] = []
    for block in content:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text":
            parts.append(str(block.get("text", "")))
        elif block.get("type") == "tool_result":
            parts.append("Résultat d'outil : " + str(block.get("content", "")))
    return "\n".join(part for part in parts if part)


def openai_messages(payload: dict[str, Any]) -> list[dict[str, str]]:
    messages: list[dict[str, str]] = []
    system = payload.get("system")
    if isinstance(system, str) and system:
        messages.append({"role": "system", "content": system})

    source = payload.get("messages")
    if not isinstance(source, list):
        return messages
    for message in source:
        if not isinstance(message, dict):
            continue
        role = str(message.get("role", ""))
        if role not in ("user", "assistant"):
            continue
        text = anthropic_text(message.get("content"))
        if text:
            messages.append({"role": role, "content": text})
    return messages


class BridgeHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "EschatonAnthropicTestBridge/1"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def send_json_error(self, status: int, message: str) -> None:
        body = json.dumps(
            {"type": "error", "error": {"type": "bridge_error", "message": message}},
            ensure_ascii=False,
        ).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def emit(self, event: str, payload: dict[str, Any]) -> None:
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        self.wfile.write(f"event: {event}\ndata: {encoded}\n\n".encode())
        self.wfile.flush()

    def do_POST(self) -> None:  # noqa: N802 - API de BaseHTTPRequestHandler
        if self.path != "/v1/messages":
            self.send_json_error(404, "route inconnue")
            return
        if not self.headers.get("x-api-key", ""):
            self.send_json_error(401, "en-tête x-api-key absent")
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.send_json_error(400, "Content-Length invalide")
            return
        if length < 1 or length > MAX_REQUEST_BYTES:
            self.send_json_error(413, "corps absent ou trop volumineux")
            return

        try:
            payload = json.loads(self.rfile.read(length))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.send_json_error(400, "JSON invalide")
            return
        if not isinstance(payload, dict):
            self.send_json_error(400, "objet JSON attendu")
            return

        request_body = json.dumps(
            {
                "model": str(payload.get("model", "")),
                "messages": openai_messages(payload),
                "stream": True,
                "max_tokens": min(max(int(payload.get("max_tokens", 128)), 1), 256),
                "temperature": 0.2,
            },
            ensure_ascii=False,
        ).encode()
        upstream = urllib.request.Request(
            self.server.upstream_url,  # type: ignore[attr-defined]
            data=request_body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            response = urllib.request.urlopen(upstream, timeout=90)
        except (urllib.error.URLError, TimeoutError) as error:
            reason = getattr(error, "reason", error)
            self.send_json_error(502, "RamaLama indisponible : " + str(reason))
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

        self.emit(
            "message_start",
            {
                "type": "message_start",
                "message": {
                    "id": "msg_eschaton_task6",
                    "type": "message",
                    "role": "assistant",
                    "content": [],
                    "model": str(payload.get("model", "")),
                    "stop_reason": None,
                    "usage": {"input_tokens": 0, "output_tokens": 0},
                },
            },
        )
        self.emit(
            "content_block_start",
            {
                "type": "content_block_start",
                "index": 0,
                "content_block": {"type": "text", "text": ""},
            },
        )

        chars = 0
        stop_reason = "end_turn"
        try:
            for raw_line in response:
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if not data or data == "[DONE]":
                    continue
                chunk = json.loads(data)
                choices = chunk.get("choices", []) if isinstance(chunk, dict) else []
                if not choices:
                    continue
                choice = choices[0] if isinstance(choices[0], dict) else {}
                delta = choice.get("delta", {}) if isinstance(choice, dict) else {}
                text = delta.get("content", "") if isinstance(delta, dict) else ""
                if isinstance(text, str) and text:
                    chars += len(text)
                    self.emit(
                        "content_block_delta",
                        {
                            "type": "content_block_delta",
                            "index": 0,
                            "delta": {"type": "text_delta", "text": text},
                        },
                    )
                reason = choice.get("finish_reason") if isinstance(choice, dict) else None
                if reason == "length":
                    stop_reason = "max_tokens"
        except (BrokenPipeError, ConnectionResetError):
            return
        finally:
            response.close()

        self.emit("content_block_stop", {"type": "content_block_stop", "index": 0})
        self.emit(
            "message_delta",
            {
                "type": "message_delta",
                "delta": {"stop_reason": stop_reason, "stop_sequence": None},
                "usage": {"output_tokens": 0},
            },
        )
        self.emit("message_stop", {"type": "message_stop"})
        print(
            f"ASSISTANT_ANTHROPIC_BRIDGE_OK chars={chars} key_header=present",
            file=sys.stderr,
            flush=True,
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", default=18081, type=int)
    parser.add_argument(
        "--upstream",
        default="http://127.0.0.1:8080/v1/chat/completions",
    )
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.bind, args.port), BridgeHandler)
    server.upstream_url = args.upstream  # type: ignore[attr-defined]
    server.serve_forever()


if __name__ == "__main__":
    main()
