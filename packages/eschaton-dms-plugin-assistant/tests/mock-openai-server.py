#!/usr/bin/env python3
"""Serveur loopback à une requête pour le harnais de transport stdin."""

from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        print(f"ASSISTANT_MOCK_BODY_BYTES={len(body)}", flush=True)

        if len(body) <= 131072:
            self.send_error(400, "body did not cross MAX_ARG_STRLEN")
        else:
            payload = (
                'data: {"choices":[{"delta":{"content":"stdin-ok"},'
                '"finish_reason":"stop"}]}\n\n'
                "data: [DONE]\n\n"
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, _format, *_args):
        return


HTTPServer(("127.0.0.1", 18080), Handler).serve_forever()
