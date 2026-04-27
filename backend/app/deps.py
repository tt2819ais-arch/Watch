from __future__ import annotations
from datetime import datetime
from typing import Optional

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from .db import SessionLocal, User
from .security import decode_token


_oauth2 = OAuth2PasswordBearer(tokenUrl="auth/login", auto_error=False)


def get_db():
    s = SessionLocal()
    try:
        yield s
    finally:
        s.close()


def get_optional_user(
    request: Request,
    token: Optional[str] = Depends(_oauth2),
    db: Session = Depends(get_db),
) -> Optional[User]:
    if not token:
        return None
    payload = decode_token(token)
    if not payload:
        return None
    user = db.get(User, int(payload.get("sub", 0)))
    if user is None:
        return None
    # Heartbeat: every authenticated request bumps last_seen so the
    # /stats/online endpoint can compute accurate active-user counts
    # without polling. We only update if the previous heartbeat was
    # more than 30s ago to keep write traffic low.
    now = datetime.utcnow()
    if (now - user.last_seen_at).total_seconds() > 30:
        user.last_seen_at = now
        db.commit()
    return user


def get_current_user(
    user: Optional[User] = Depends(get_optional_user),
) -> User:
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="admin only")
    return user
