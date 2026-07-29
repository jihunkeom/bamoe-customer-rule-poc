import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

JOURNAL = []


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, body):
        payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        return json.loads(self.rfile.read(length) or b"{}")

    def record(self, path, body):
        JOURNAL.append({
            "sequence": len(JOURNAL) + 1,
            "requestId": body.get("requestId"),
            "path": path,
            "scenario": body.get("scenario", "happy")
        })

    def do_POST(self):
        path = urlparse(self.path).path
        body = self.read_json()
        scenario = body.get("scenario", "happy")
        self.record(path, body)

        if path == "/case01/service-detail":
            if scenario == "service-http-500":
                return self.send_json(500, {"error": "SERVICE_LOOKUP_FAILED"})
            detail = "VOICE" if scenario == "not-target" else "CA"
            return self.send_json(200, {"serviceDetailClassCode": detail})

        if path == "/case01/ordaux227":
            if scenario == "auth-http-500":
                return self.send_json(500, {"error": "ORDAUX227_UNAVAILABLE"})
            result = {
                "auth-denied": "DENIED",
                "auth-body-error": "ERROR"
            }.get(scenario, "GRANTED")
            return self.send_json(200, {"result": result})

        if path == "/case01/promotion-count":
            if scenario == "promo-http-500":
                return self.send_json(500, {"error": "PROMOTION_LOOKUP_FAILED"})
            count = 2 if scenario == "promo-active" else 0
            return self.send_json(200, {"count": count})

        return self.send_json(404, {"error": "NOT_FOUND", "path": path})

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            return self.send_json(200, {"status": "UP"})
        if parsed.path != "/case01/_test/journal":
            return self.send_json(404, {"error": "NOT_FOUND"})
        request_id = parse_qs(parsed.query).get("requestId", [None])[0]
        calls = [
            call for call in JOURNAL
            if request_id is None or call["requestId"] == request_id
        ]
        self.send_json(200, {"calls": calls})

    def do_DELETE(self):
        if urlparse(self.path).path != "/case01/_test/journal":
            return self.send_json(404, {"error": "NOT_FOUND"})
        JOURNAL.clear()
        self.send_json(200, {"cleared": True})

    def log_message(self, fmt, *args):
        print("[case01-mock]", fmt % args)


print("Case01 mock listening on http://0.0.0.0:8091", flush=True)
ThreadingHTTPServer(("0.0.0.0", 8091), Handler).serve_forever()
