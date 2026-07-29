#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse


SCENARIOS = {
    "GRANTED": {"auth": "GRANTED", "alternative": None},
    "DENIED_NORMAL": {"auth": "DENIED", "alternative": None},
    "DENIED_ALT_SUCCESS": {"auth": "DENIED", "alternative": "PROCESSED"},
    "AUTH_BODY_ERROR": {"auth": "ERROR", "alternative": None},
    "AUTH_HTTP_500": {"auth": "HTTP_500", "alternative": None},
    "ALT_HTTP_500": {"auth": "DENIED", "alternative": "HTTP_500"},
}

CALLS = {}
EXECUTIONS = {}


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def append_call(self, request_id, operation, **values):
        event = {"operation": operation, **values}
        CALLS.setdefault(request_id, []).append(event)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            self.send_json(200, {"status": "UP"})
            return

        prefix = "/mock/calls/"
        if path.startswith(prefix):
            request_id = unquote(path[len(prefix):])
            self.send_json(
                200,
                {"requestId": request_id, "calls": CALLS.get(request_id, [])},
            )
            return

        self.send_json(404, {"error": "NOT_FOUND", "path": path})

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            request = self.read_json()
        except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
            self.send_json(400, {"error": "INVALID_JSON"})
            return

        request_id = request.get("requestId")
        scenario_name = request.get("mockScenario")
        if not request_id or scenario_name not in SCENARIOS:
            self.send_json(
                400,
                {
                    "error": "INVALID_REQUEST",
                    "allowedScenarios": sorted(SCENARIOS),
                },
            )
            return

        scenario = SCENARIOS[scenario_name]

        if path == "/mock/auth/csmaux004":
            self.append_call(request_id, "CSMAUX004")
            if scenario["auth"] == "HTTP_500":
                self.send_json(500, {"error": "AUTH_PROVIDER_FAILURE"})
                return
            self.send_json(
                200,
                {"authority": "CSMAUX004", "result": scenario["auth"]},
            )
            return

        if path == "/mock/alternative-processing":
            key = self.headers.get("IdempotencyKey")
            self.append_call(
                request_id,
                "ALTERNATIVE_PROCESSING",
                idempotencyKey=key,
            )
            if scenario["alternative"] is None:
                self.send_json(
                    409,
                    {"error": "UNEXPECTED_ALTERNATIVE_CALL"},
                )
                return
            if scenario["alternative"] == "HTTP_500":
                self.send_json(500, {"error": "ALTERNATIVE_PROVIDER_FAILURE"})
                return
            if not key:
                self.send_json(400, {"error": "IDEMPOTENCY_KEY_REQUIRED"})
                return

            existing = EXECUTIONS.get(key)
            duplicate = existing is not None
            if existing is None:
                existing = {
                    "operationId": "ALT-" + request_id,
                    "result": "PROCESSED",
                }
                EXECUTIONS[key] = existing
                self.append_call(
                    request_id,
                    "ALTERNATIVE_EFFECT_APPLIED",
                    idempotencyKey=key,
                )

            self.send_json(
                200,
                {
                    **existing,
                    "duplicate": duplicate,
                    "idempotencyKey": key,
                },
            )
            return

        self.send_json(404, {"error": "NOT_FOUND", "path": path})

    def do_DELETE(self):
        path = urlparse(self.path).path
        prefix = "/mock/calls/"
        if path.startswith(prefix):
            request_id = unquote(path[len(prefix):])
            CALLS.pop(request_id, None)
            keys = [
                key for key in EXECUTIONS
                if key == "case03-alt:" + request_id
            ]
            for key in keys:
                EXECUTIONS.pop(key, None)
            self.send_json(200, {"requestId": request_id, "calls": []})
            return
        self.send_json(404, {"error": "NOT_FOUND", "path": path})

    def log_message(self, format_string, *args):
        print(
            "%s - %s" %
            (self.log_date_time_string(), format_string % args),
            flush=True,
        )


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8093), Handler)
    print("Case03 mock listening on http://0.0.0.0:8093", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
