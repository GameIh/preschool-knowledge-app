from __future__ import annotations

import os
from pathlib import Path

from fastapi.testclient import TestClient


TEST_DB = Path(__file__).with_name("test_auth.db")
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB.as_posix()}"
os.environ["AUTH_SECRET"] = "test-secret"

from app import database as database_module  # noqa: E402
from app import main as main_module  # noqa: E402


def setup_function() -> None:
    database_module.Base.metadata.drop_all(bind=database_module.engine)
    database_module.Base.metadata.create_all(bind=database_module.engine)


def teardown_module() -> None:
    database_module.engine.dispose()
    if TEST_DB.exists():
        TEST_DB.unlink()


def test_registration_refresh_logout_and_protected_content() -> None:
    with TestClient(main_module.app) as client:
        register = client.post(
            "/api/auth/register",
            json={
                "email": "Parent@Mail.com",
                "password": "strong-password",
                "name": "Родитель",
                "device_name": "test-device",
            },
        )
        assert register.status_code == 201
        tokens = register.json()
        assert tokens["user"]["email"] == "parent@mail.com"

        unauthorized = client.get("/api/content")
        assert unauthorized.status_code == 401

        content = client.get(
            "/api/content",
            headers={"Authorization": f"Bearer {tokens['access_token']}"},
        )
        assert content.status_code == 200
        assert content.json()["activities"]

        refreshed = client.post(
            "/api/auth/refresh",
            json={"refresh_token": tokens["refresh_token"]},
        )
        assert refreshed.status_code == 200
        new_tokens = refreshed.json()
        assert new_tokens["refresh_token"] != tokens["refresh_token"]

        reused = client.post(
            "/api/auth/refresh",
            json={"refresh_token": tokens["refresh_token"]},
        )
        assert reused.status_code == 401

        logout = client.post(
            "/api/auth/logout",
            json={"refresh_token": new_tokens["refresh_token"]},
        )
        assert logout.status_code == 200

        after_logout = client.post(
            "/api/auth/refresh",
            json={"refresh_token": new_tokens["refresh_token"]},
        )
        assert after_logout.status_code == 401


def test_duplicate_registration_and_invalid_login() -> None:
    with TestClient(main_module.app) as client:
        payload = {
            "email": "user@example.com",
            "password": "password-123",
            "name": "Пользователь",
        }
        assert client.post("/api/auth/register", json=payload).status_code == 201
        assert client.post("/api/auth/register", json=payload).status_code == 409

        invalid = client.post(
            "/api/auth/login",
            json={"email": payload["email"], "password": "wrong"},
        )
        assert invalid.status_code == 401
