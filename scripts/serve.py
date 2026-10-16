#!/usr/bin/env python3
"""Serve the Pages artifact locally with the same required MIME types and isolation headers."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import json

ROOT = Path(__file__).resolve().parent.parent

class Handler(SimpleHTTPRequestHandler):
    extensions_map = dict(SimpleHTTPRequestHandler.extensions_map, **{".wasm": "application/wasm", ".dll": "application/octet-stream", ".js": "text/javascript"})
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()
    def log_message(self, fmt, *args):
        if args and str(args[0]).startswith('"GET /_framework/'):
            return
        super().log_message(fmt, *args)
    def do_POST(self):
        if self.path != "/__report":
            self.send_error(404)
            return
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        report = ROOT / ".artifacts/browser-test.json"
        report.parent.mkdir(exist_ok=True)
        report.write_text(json.dumps(data, indent=2))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
    def translate_path(self, path):
        if path.split("?")[0] == "/__tests":
            return str(ROOT / "tests/browser.html")
        return super().translate_path(path)

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=4173)
args = parser.parse_args()
server = ThreadingHTTPServer(("127.0.0.1", args.port), partial(Handler, directory=str(ROOT / "dist")))
print(f"Alice Playground: http://localhost:{args.port}", flush=True)
server.serve_forever()
