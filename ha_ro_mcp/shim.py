"""Loopback proxy between the MCP server and the Supervisor.

- Passes GET, and POST only to /api/template: the read-only rule, enforced here
  as well as by upstream's code.
- The Supervisor refuses /api/hassio/... from add-ons on its Core API proxy, so
  the paths upstream uses for logs and versions go to the Supervisor's own API
  (which needs `hassio_api`); every other /api/ path goes to the Core proxy.
- Listens on 127.0.0.1 only and accepts only the per-start token run.sh hands
  the server, so the add-on's own Supervisor token never leaves this process.
"""

import os
import re
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

PORT = 8099
SUPERVISOR = "http://supervisor"
SUPERVISOR_TOKEN = os.environ["SUPERVISOR_TOKEN"]
LOCAL_TOKEN = os.environ["LOCAL_TOKEN"]
SUPERVISOR_PATHS = re.compile(r"^/api/hassio(/(?:core|supervisor)/info|/core/logs(?:/boots/-?\d+)?)$")


class Shim(BaseHTTPRequestHandler):
    def do_GET(self):
        self._forward(None)

    def do_POST(self):
        if urlsplit(self.path).path != "/api/template":
            self._reply(405, "text/plain", b"read-only: POST is allowed only to /api/template")
            return
        self._forward(self.rfile.read(int(self.headers.get("Content-Length", 0))))

    def _forward(self, body):
        if self.headers.get("Authorization") != f"Bearer {LOCAL_TOKEN}":
            self._reply(401, "text/plain", b"unauthorized")
            return
        parts = urlsplit(self.path)
        supervisor_path = SUPERVISOR_PATHS.match(parts.path)
        if supervisor_path:
            target = supervisor_path.group(1)
        elif parts.path.startswith("/api/hassio"):
            self._reply(403, "text/plain", b"not an allowed Supervisor path")
            return
        elif parts.path.startswith("/api/"):
            target = "/core" + parts.path
        else:
            self._reply(404, "text/plain", b"not found")
            return
        request = urllib.request.Request(
            SUPERVISOR + target + (f"?{parts.query}" if parts.query else ""),
            data=body,
            method=self.command,
            headers={
                "Authorization": f"Bearer {SUPERVISOR_TOKEN}",
                "Content-Type": self.headers.get("Content-Type", "application/json"),
                "Accept": self.headers.get("Accept", "*/*"),
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                self._reply(response.status, response.headers.get("Content-Type"), response.read())
        except urllib.error.HTTPError as err:
            self._reply(err.code, err.headers.get("Content-Type"), err.read())
        except OSError as err:
            self._reply(502, "text/plain", f"supervisor unreachable: {err}".encode())

    def _reply(self, status, content_type, data):
        self.send_response(status)
        self.send_header("Content-Type", content_type or "application/octet-stream")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_request(self, code="-", size="-"):
        # Only failures reach the add-on log; a healthy call is noise.
        if isinstance(code, int) and code >= 400:
            super().log_request(code, size)


ThreadingHTTPServer(("127.0.0.1", PORT), Shim).serve_forever()
