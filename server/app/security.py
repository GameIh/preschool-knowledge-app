from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pwdlib import PasswordHash
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import (
    ACCESS_TOKEN_MINUTES,
    JWT_ALGORITHM,
    JWT_SECRET,
    REFRESH_TOKEN_DAYS,
)
from .database import get_db
from .models import AuthSession, User


password_hash = PasswordHash.recommended()
bearer_scheme = HTTPBearer(auto_error=False)


def utc_now() -> datetime:
    # SQLite stores datetimes without timezone information.
    return datetime.now(timezone.utc).replace(tzinfo=None)


def normalize_email(email: str) -> str:
    return email.strip().lower()


def hash_password(password: str) -> str:
    return password_hash.hash(password)


def verify_password(password: str, encoded_hash: str) -> bool:
    return password_hash.verify(password, encoded_hash)


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_access_token(user_id: str, session_id: str) -> tuple[str, int]:
    expires_delta = timedelta(minutes=ACCESS_TOKEN_MINUTES)
    expires_at = utc_now() + expires_delta
    payload = {
        "sub": user_id,
        "sid": session_id,
        "type": "access",
        "iat": utc_now(),
        "exp": expires_at,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM), int(
        expires_delta.total_seconds()
    )


def create_session(
    db: Session,
    user: User,
    device_name: str | None,
) -> tuple[AuthSession, str]:
    raw_refresh_token = secrets.token_urlsafe(48)
    session = AuthSession(
        id=str(uuid.uuid4()),
        user_id=user.id,
        refresh_token_hash=hash_refresh_token(raw_refresh_token),
        device_name=device_name.strip() if device_name else None,
        expires_at=utc_now() + timedelta(days=REFRESH_TOKEN_DAYS),
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return session, raw_refresh_token


def issue_tokens(
    db: Session,
    user: User,
    device_name: str | None,
) -> tuple[str, str, int]:
    session, refresh_token = create_session(db, user, device_name)
    access_token, expires_in = create_access_token(user.id, session.id)
    return access_token, refresh_token, expires_in


def decode_access_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Срок действия access-токена истёк",
        ) from error
    except jwt.InvalidTokenError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Недействительный access-токен",
        ) from error

    if payload.get("type") != "access" or not payload.get("sub") or not payload.get("sid"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Недействительный access-токен",
        )
    return payload


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Требуется авторизация",
        )

    payload = decode_access_token(credentials.credentials)
    session = db.scalar(
        select(AuthSession).where(
            AuthSession.id == payload["sid"],
            AuthSession.user_id == payload["sub"],
        )
    )
    if session is None or session.revoked_at is not None or session.expires_at <= utc_now():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Сессия завершена",
        )

    user = db.get(User, payload["sub"])
    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Пользователь недоступен",
        )
    return user
