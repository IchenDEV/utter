#!/usr/bin/env python3
"""Temporary LAN fixture: only the fixed test HTML/video, with Safari byte ranges."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[3]
files = {
    "/": (Path(__file__).with_name("StandbySafari.html"), "text/html; charset=utf-8"),
    "/probe.mp4": (root / ".build-ios/standby-device-probe/StandbyHost.app/probe.mp4", "video/mp4"),
}

class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.serve(False)

    def do_GET(self):
        self.serve(True)

    def serve(self, body):
        if self.path not in files:
            self.send_error(404)
            return
        path, content_type = files[self.path]
        length = path.stat().st_size
        start, end = 0, length - 1
        requested = self.headers.get("Range")
        if requested:
            match = re.fullmatch(r"bytes=(\d+)-(\d*)", requested)
            if not match or int(match[1]) >= length or (match[2] and int(match[2]) < int(match[1])):
                self.send_error(416)
                return
            start = int(match[1])
            end = min(int(match[2]), end) if match[2] else end
        self.send_response(206 if requested else 200)
        self.send_header("Content-Type", content_type)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Cache-Control", "no-store")
        if requested:
            self.send_header("Content-Range", f"bytes {start}-{end}/{length}")
        self.end_headers()
        if body:
            with path.open("rb") as source:
                source.seek(start)
                remaining = end - start + 1
                try:
                    while remaining:
                        chunk = source.read(min(65536, remaining))
                        if not chunk: break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
                except (BrokenPipeError, ConnectionResetError): pass

if __name__ == "__main__":
    assert len(sys.argv) == 3, "Usage: serve-safari.py LAN_ADDRESS PORT"
    ThreadingHTTPServer((sys.argv[1], int(sys.argv[2])), Handler).serve_forever()
