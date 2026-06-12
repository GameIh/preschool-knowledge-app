from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent
DEFAULT_CONTENT_PATH = ROOT / "content.json"


class ContentApiHandler(BaseHTTPRequestHandler):
    server_version = "PreschoolContentServer/1.0"

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self._send_cors_headers()
        self.end_headers()

    def do_GET(self) -> None:
        path = urlparse(self.path).path.rstrip("/") or "/"

        if path == "/":
            self._send_json(
                {
                    "name": "Preschool content update server",
                    "endpoints": ["/api/health", "/api/content", "/api/updates"],
                }
            )
            return

        if path == "/api/health":
            self._send_json(
                {
                    "status": "ok",
                    "time": datetime.now(timezone.utc).isoformat(),
                }
            )
            return

        if path in {"/api/content", "/api/updates"}:
            content = self._load_content()
            content["generated_at"] = datetime.now(timezone.utc).isoformat()
            self._send_json(content)
            return

        self._send_json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)

    def log_message(self, format: str, *args: object) -> None:
        print("%s - %s" % (self.address_string(), format % args))

    def _load_content(self) -> dict:
        content_path: Path = self.server.content_path  # type: ignore[attr-defined]
        with content_path.open("r", encoding="utf-8") as file:
            return json.load(file)

    def _send_json(self, payload: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self._send_cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Content update API for the Flutter app.")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind.")
    parser.add_argument("--port", default=8000, type=int, help="Port to bind.")
    parser.add_argument(
        "--content",
        default=DEFAULT_CONTENT_PATH,
        type=Path,
        help="Path to content JSON file.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    content_path = args.content.resolve()
    if not content_path.exists():
        raise FileNotFoundError(f"Content file was not found: {content_path}")

    server = ThreadingHTTPServer((args.host, args.port), ContentApiHandler)
    server.content_path = content_path  # type: ignore[attr-defined]
    print(f"Content API is running on http://{args.host}:{args.port}")
    print(f"Content file: {content_path}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
