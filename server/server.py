from __future__ import annotations

import argparse

import uvicorn


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Preschool knowledge API server.")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind.")
    parser.add_argument("--port", default=8000, type=int, help="Port to bind.")
    parser.add_argument(
        "--reload",
        action="store_true",
        help="Reload the server when Python files change.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    uvicorn.run(
        "app.main:app",
        host=args.host,
        port=args.port,
        reload=args.reload,
    )


if __name__ == "__main__":
    main()
