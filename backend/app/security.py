from __future__ import annotations
from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
import jwt

from .config import settings


def _to72(raw: str) -> bytes:
    """bcrypt only consumes the first 72 bytes — pre-truncate explicitly so
    longer passwords don't raise."""
    return raw.encode("utf-8")[:72]


def hash_password(raw: str) -> str:
    return bcrypt.hashpw(_to72(raw), bcrypt.gensalt(rounds=12)).decode("ascii")


def verify_password(raw: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(_to72(raw), hashed.encode("ascii"))
    except Exception:
        return False


def issue_token(*, user_id: int, nickname: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "nick": nickname,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(hours=settings.jwt_ttl_hours)).timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_alg)


def decode_token(token: str) -> Optional[dict]:
    try:
        return jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_alg])
    except jwt.PyJWTError:
        return None
