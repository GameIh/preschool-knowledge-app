from __future__ import annotations

import json
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import CONTENT_PATH
from .database import Base, engine, get_db
from .models import AuthSession, User
from .schemas import (
    LoginRequest,
    LogoutRequest,
    MessageResponse,
    RefreshRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)
from .security import (
    create_access_token,
    get_current_user,
    hash_password,
    hash_refresh_token,
    issue_tokens,
    normalize_email,
    utc_now,
    verify_password,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(
    title="Preschool Knowledge API",
    version="2.0.0",
    lifespan=lifespan,
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


def token_response(
    user: User,
    access_token: str,
    refresh_token: str,
    expires_in: int,
) -> TokenResponse:
    return TokenResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=expires_in,
        user=UserResponse.model_validate(user),
    )


@app.get("/")
def root() -> dict:
    return {
        "name": "Preschool Knowledge API",
        "version": "2.0.0",
        "docs": "/docs",
    }


@app.get("/api/health")
def health() -> dict:
    return {
        "status": "ok",
        "time": datetime.now(timezone.utc).isoformat(),
    }


@app.post(
    "/api/auth/register",
    response_model=TokenResponse,
    status_code=status.HTTP_201_CREATED,
)
def register(payload: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    email = normalize_email(str(payload.email))
    if db.scalar(select(User).where(User.email == email)) is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Пользователь с такой почтой уже существует",
        )

    user = User(
        id=str(uuid.uuid4()),
        email=email,
        name=payload.name.strip(),
        password_hash=hash_password(payload.password),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    access_token, refresh_token, expires_in = issue_tokens(
        db, user, payload.device_name
    )
    return token_response(user, access_token, refresh_token, expires_in)


@app.post("/api/auth/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    email = normalize_email(str(payload.email))
    user = db.scalar(select(User).where(User.email == email))
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Неверная почта или пароль",
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Учётная запись отключена",
        )

    access_token, refresh_token, expires_in = issue_tokens(
        db, user, payload.device_name
    )
    return token_response(user, access_token, refresh_token, expires_in)


@app.post("/api/auth/refresh", response_model=TokenResponse)
def refresh(payload: RefreshRequest, db: Session = Depends(get_db)) -> TokenResponse:
    session = db.scalar(
        select(AuthSession).where(
            AuthSession.refresh_token_hash == hash_refresh_token(payload.refresh_token)
        )
    )
    if session is None or session.revoked_at is not None or session.expires_at <= utc_now():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh-токен недействителен или истёк",
        )

    user = db.get(User, session.user_id)
    if user is None or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Пользователь недоступен",
        )

    session.revoked_at = utc_now()
    db.commit()
    access_token, refresh_token, expires_in = issue_tokens(
        db, user, session.device_name
    )
    return token_response(user, access_token, refresh_token, expires_in)


@app.post("/api/auth/logout", response_model=MessageResponse)
def logout(payload: LogoutRequest, db: Session = Depends(get_db)) -> MessageResponse:
    session = db.scalar(
        select(AuthSession).where(
            AuthSession.refresh_token_hash == hash_refresh_token(payload.refresh_token)
        )
    )
    if session is not None and session.revoked_at is None:
        session.revoked_at = utc_now()
        db.commit()
    return MessageResponse(message="Сессия завершена")


@app.get("/api/auth/me", response_model=UserResponse)
def me(user: User = Depends(get_current_user)) -> UserResponse:
    return UserResponse.model_validate(user)


@app.get("/api/content")
def content(_: User = Depends(get_current_user)) -> dict:
    if not CONTENT_PATH.exists():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Файл контента не найден",
        )
    with CONTENT_PATH.open("r", encoding="utf-8") as file:
        payload = json.load(file)
    payload["generated_at"] = datetime.now(timezone.utc).isoformat()
    return payload
