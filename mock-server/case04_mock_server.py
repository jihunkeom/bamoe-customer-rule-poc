#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse


SCENARIOS = {
    "PRIMARY_GRANTED": ("GRANTED", None),
    "PRIMARY_BODY_ERROR": ("ERROR", None),
    "FALLBACK_GRANTED": ("DENIED", "GRANTED"),
    "FALLBACK_DENIED": ("DENIED", "DENIED"),
    "FALLBACK_BODY_ERROR": ("DENIED", "ERROR"),
    "PRIMARY_HTTP_500": ("HTTP_500", None),
    "FALLBACK_HTTP_500": ("DENIED", "HTTP_500"),
}
PATHS = {
    "/mock/auth/csmaux004": ("CSMAUX004", 0),
    "/mock/auth/csmaux005": ("CSMAUX005", 1),
}
CALLS = {}


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

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            self.send_json(200, {"status": "UP"})
            return
        prefix = "/mock/auth/calls/"
        if path.startswith(prefix):
            request_id = unquote(path[len(prefix):])
            self.send_json(
                200,
                {"requestId": request_id, "calls": CALLS.get(request_id, [])},
            )
            return
        self.send_json(404, {"error": "NOT_FOUND", "path": path})

    def do_DELETE(self):
        path = urlparse(self.path).path
        prefix = "/mock/auth/calls/"
        if path.startswith(prefix):
            request_id = unquote(path[len(prefix):])
            CALLS.pop(request_id, None)
            self.send_json(200, {"requestId": request_id, "calls": []})
            return
        self.send_json(404, {"error": "NOT_FOUND", "path": path})

    def do_POST(self):
        path = urlparse(self.path).path
        target = PATHS.get(path)
        if target is None:
            self.send_json(404, {"error": "NOT_FOUND", "path": path})
            return
        try:
            request = self.read_json()
        except (ValueError, UnicodeDecodeError):
            self.send_json(400, {"error": "INVALID_JSON"})
            return

        request_id = request.get("requestId")
        scenario = request.get("mockScenario", "PRIMARY_GRANTED")
        if not request_id or scenario not in SCENARIOS:
            self.send_json(400, {"error": "INVALID_REQUEST"})
            return

        authority, index = target
        CALLS.setdefault(request_id, []).append(authority)
        result = SCENARIOS[scenario][index]

        if result is None:
            self.send_json(
                409,
                {"error": "UNEXPECTED_FALLBACK_CALL", "authority": authority},
            )
            return
        if result == "HTTP_500":
            self.send_json(
                500,
                {"error": "PROVIDER_UNAVAILABLE", "authority": authority},
            )
            return
        self.send_json(200, {"authority": authority, "result": result})

    def log_message(self, format_string, *args):
        print(
            "%s - %s"
            % (self.log_date_time_string(), format_string % args),
            flush=True,
        )


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 8094), Handler)
    print(
        "Case04 auth mock listening on http://0.0.0.0:8094",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
