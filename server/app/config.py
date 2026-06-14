from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv


SERVER_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(SERVER_ROOT / ".env")

CONTENT_PATH = Path(os.getenv("CONTENT_PATH", SERVER_ROOT / "content.json"))
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    f"sqlite:///{(SERVER_ROOT / 'users.db').as_posix()}",
)

JWT_SECRET = os.getenv(
    "AUTH_SECRET",
    "development-secret-change-before-production",
)
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_MINUTES = int(os.getenv("ACCESS_TOKEN_MINUTES", "30"))
REFRESH_TOKEN_DAYS = int(os.getenv("REFRESH_TOKEN_DAYS", "30"))
