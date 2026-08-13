#!/usr/bin/env python3
"""Tiny static file server for the local Godot web build.

Just http.server with caching turned off, so every browser reload serves the
freshest export during the dev loop instead of a cached one.

Usage: serve.py <directory> [port]

Note: the web export sets thread_support=false, so it does NOT need the
cross-origin isolation headers (COOP/COEP). If threads are ever enabled in the
export preset, add these in end_headers():
    self.send_header("Cross-Origin-Opener-Policy", "same-origin")
    self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
"""
import sys
from functools import partial
from http.server import HTTPServer, SimpleHTTPRequestHandler


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    directory = sys.argv[1] if len(sys.argv) > 1 else "."
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8000
    handler = partial(Handler, directory=directory)
    httpd = HTTPServer(("0.0.0.0", port), handler)
    print(f"Serving {directory} on 0.0.0.0:{port} (Ctrl+C to stop)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
