from __future__ import annotations
import logging
import os
from datetime import datetime
from typing import List, Optional

from fastapi import Body, Depends, FastAPI, HTTPException, Path, Query, status
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .config import settings
from .db import (
    Block,
    Favorite,
    Message,
    Reaction,
    StatPoint,
    User,
    init_db,
    session_scope,
)
from .deps import get_current_user, get_db, get_optional_user, require_admin
from .schemas import (
    ChangePasswordRequest,
    FavoriteIn,
    FavoriteOut,
    LoginRequest,
    MessageIn,
    MessageOut,
    OnlineStats,
    PublicProfile,
    PublicUser,
    ReactionIn,
    SignupRequest,
    StatPointIn,
    StatPointOut,
    TokenResponse,
    UpdateMeRequest,
    UsersCount,
)
from .security import hash_password, issue_token, verify_password
from .services import (
    conversation,
    is_blocked_either_way,
    lookup_user_by_nick,
    online_count,
    public_profile,
    to_message_out,
    to_public_user,
    total_users,
)


log = logging.getLogger("watch")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")


def _bootstrap_admin() -> None:
    """Ensure an admin account exists.

    1. If the bootstrap user already lives in the DB, just (re-)assert
       its admin/verified/is_official flags.
    2. Otherwise, create it. Password is taken from
       WATCH_ADMIN_PASSWORD if provided; if unset, a random password is
       generated and persisted to /data/admin_password.txt so the
       operator can recover it without redeploying. A clearly-marked
       "WATCH_BOOTSTRAP_ADMIN_PASSWORD=…" line is also emitted to the
       container's stdout so it shows up in `flyctl logs`.
    """
    import secrets as _secrets
    from pathlib import Path as _Path

    with session_scope() as s:
        existing = s.scalar(select(User).where(User.nickname_lower == settings.admin_nickname.lower()))
        if existing:
            existing.role = "admin"
            existing.verified = True
            existing.is_official = True
            # When WATCH_ADMIN_PASSWORD is set in the environment and
            # doesn't match the stored hash, overwrite — operators use
            # this to rotate the bootstrap password.
            if settings.admin_password and not verify_password(settings.admin_password, existing.password_hash):
                existing.password_hash = hash_password(settings.admin_password)
                log.info("Bootstrap admin '%s' password rotated.", settings.admin_nickname)
            return

        password = settings.admin_password
        generated = False
        if not password:
            password = _secrets.token_urlsafe(12)
            generated = True

        u = User(
            nickname=settings.admin_nickname,
            nickname_lower=settings.admin_nickname.lower(),
            password_hash=hash_password(password),
            role="admin",
            verified=True,
            is_official=True,
            bio="Официальный аккаунт Watch",
        )
        s.add(u)
        log.info("Bootstrap admin '%s' created.", settings.admin_nickname)

        if generated:
            try:
                p = _Path(settings.db_path).parent / "admin_password.txt"
                p.write_text(f"{settings.admin_nickname}:{password}\n", encoding="utf-8")
            except Exception as e:
                log.warning("Could not persist admin password file: %s", e)
            log.info(
                "WATCH_BOOTSTRAP_ADMIN_PASSWORD=%s nickname=%s",
                password,
                settings.admin_nickname,
            )


app = FastAPI(title="Watch backend", version="0.2.0")


@app.on_event("startup")
def _startup() -> None:
    init_db()
    _bootstrap_admin()


# ---- Health -----------------------------------------------------------

@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


# ---- Auth -------------------------------------------------------------

@app.post("/auth/signup", response_model=TokenResponse, tags=["auth"])
def signup(body: SignupRequest, db: Session = Depends(get_db)) -> TokenResponse:
    nick = body.nickname.strip()
    if not nick:
        raise HTTPException(status_code=400, detail="nickname required")
    existing = db.scalar(select(User).where(User.nickname_lower == nick.lower()))
    if existing:
        raise HTTPException(status_code=409, detail="Никнейм уже занят")
    u = User(
        nickname=nick,
        nickname_lower=nick.lower(),
        password_hash=hash_password(body.password),
    )
    db.add(u)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Никнейм уже занят")
    db.refresh(u)
    return TokenResponse(access_token=issue_token(user_id=u.id, nickname=u.nickname), user=to_public_user(u))


@app.post("/auth/login", response_model=TokenResponse, tags=["auth"])
def login(body: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    u = lookup_user_by_nick(db, body.nickname)
    if u is None or not verify_password(body.password, u.password_hash):
        raise HTTPException(status_code=401, detail="Неверный никнейм или пароль")
    u.last_seen_at = datetime.utcnow()
    db.commit()
    return TokenResponse(access_token=issue_token(user_id=u.id, nickname=u.nickname), user=to_public_user(u))


@app.get("/auth/me", response_model=PublicUser, tags=["auth"])
def me(user: User = Depends(get_current_user)) -> PublicUser:
    return to_public_user(user)


# ---- Users ------------------------------------------------------------

@app.get("/users", response_model=List[PublicUser], tags=["users"])
def search_users(
    query: str = Query(min_length=1, max_length=64),
    db: Session = Depends(get_db),
    _viewer: User = Depends(get_current_user),
) -> List[PublicUser]:
    """Type-ahead search over nicknames. Case-insensitive prefix match."""
    q = query.strip().lower()
    if not q:
        return []
    # Escape SQL LIKE wildcards (`%` and `_`) so that crafted queries like
    # "%" can't enumerate the entire user table — they must match the
    # literal characters instead.
    escaped = q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    rows = db.scalars(
        select(User)
        .where(User.nickname_lower.like(f"{escaped}%", escape="\\"))
        .order_by(User.nickname_lower)
        .limit(20)
    ).all()
    return [to_public_user(r) for r in rows]


# NOTE: keep /users/count and /users/me declared BEFORE /users/{nickname} so
# FastAPI's path matcher resolves them as static routes instead of treating
# "count" / "me" as a nickname.

@app.get("/users/count", response_model=UsersCount, tags=["stats"])
def users_count(db: Session = Depends(get_db)) -> UsersCount:
    total, new_7d = total_users(db)
    return UsersCount(total=total, new_last_7d=new_7d)


@app.patch("/users/me", response_model=PublicUser, tags=["users"])
def update_me(
    body: UpdateMeRequest,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> PublicUser:
    if body.bio is not None:
        viewer.bio = body.bio[:2000]
    if body.privacy_hide_stats is not None:
        viewer.privacy_hide_stats = body.privacy_hide_stats
    if body.privacy_hide_favorites is not None:
        viewer.privacy_hide_favorites = body.privacy_hide_favorites
    if body.privacy_hide_history is not None:
        viewer.privacy_hide_history = body.privacy_hide_history
    db.commit()
    db.refresh(viewer)
    return to_public_user(viewer)


@app.post("/auth/change_password", response_model=PublicUser, tags=["auth"])
def change_password(
    body: ChangePasswordRequest,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> PublicUser:
    if not verify_password(body.current_password, viewer.password_hash):
        raise HTTPException(status_code=401, detail="Неверный текущий пароль")
    if body.new_password == body.current_password:
        raise HTTPException(status_code=400, detail="Новый пароль совпадает со старым")
    viewer.password_hash = hash_password(body.new_password)
    db.commit()
    db.refresh(viewer)
    return to_public_user(viewer)


@app.get("/users/{nickname}", response_model=PublicProfile, tags=["users"])
def public_profile_endpoint(
    nickname: str = Path(..., min_length=1, max_length=64),
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> PublicProfile:
    target = lookup_user_by_nick(db, nickname)
    if target is None:
        raise HTTPException(status_code=404, detail="user not found")
    return public_profile(db, target, viewer)


# ---- Stats (public) ---------------------------------------------------

@app.get("/stats/online", response_model=OnlineStats, tags=["stats"])
def stats_online(db: Session = Depends(get_db)) -> OnlineStats:
    return OnlineStats(online=online_count(db), window_minutes=settings.online_window_minutes)


# ---- Messages ---------------------------------------------------------

@app.get("/messages/{nickname}", response_model=List[MessageOut], tags=["messages"])
def conversation_with(
    nickname: str,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> List[MessageOut]:
    other = lookup_user_by_nick(db, nickname)
    if other is None:
        raise HTTPException(status_code=404, detail="user not found")
    if is_blocked_either_way(db, viewer.id, other.id):
        return []
    msgs = conversation(db, viewer.id, other.id)
    # mark as read on fetch — only the messages we received.
    now = datetime.utcnow()
    for m in msgs:
        if m.recipient_id == viewer.id and m.read_at is None:
            m.read_at = now
    db.commit()
    return [to_message_out(db, m) for m in msgs]


@app.post("/messages/{nickname}", response_model=MessageOut, tags=["messages"])
def send_message(
    nickname: str,
    body: MessageIn,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> MessageOut:
    other = lookup_user_by_nick(db, nickname)
    if other is None:
        raise HTTPException(status_code=404, detail="user not found")
    if is_blocked_either_way(db, viewer.id, other.id):
        raise HTTPException(status_code=403, detail="blocked")
    m = Message(
        sender_id=viewer.id,
        recipient_id=other.id,
        body=body.body,
        item_id=body.item_id,
        item_title=body.item_title,
        item_poster_url=body.item_poster_url,
    )
    db.add(m)
    db.commit()
    db.refresh(m)
    return to_message_out(db, m)


@app.delete("/messages/{message_id}", tags=["messages"])
def delete_message(
    message_id: int,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> dict:
    m = db.get(Message, message_id)
    if m is None:
        raise HTTPException(status_code=404, detail="not found")
    if m.sender_id != viewer.id and viewer.role != "admin":
        raise HTTPException(status_code=403, detail="forbidden")
    m.deleted = True
    m.body = ""
    db.commit()
    return {"ok": True}


@app.post("/messages/{message_id}/react", response_model=MessageOut, tags=["messages"])
def react(
    message_id: int,
    body: ReactionIn,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> MessageOut:
    m = db.get(Message, message_id)
    if m is None:
        raise HTTPException(status_code=404, detail="not found")
    if viewer.id not in (m.sender_id, m.recipient_id):
        raise HTTPException(status_code=403, detail="forbidden")
    # Toggle: if user already reacted with this emoji, remove it.
    existing = db.scalar(
        select(Reaction).where(
            Reaction.message_id == m.id,
            Reaction.user_id == viewer.id,
            Reaction.emoji == body.emoji,
        )
    )
    if existing:
        db.delete(existing)
    else:
        db.add(Reaction(message_id=m.id, user_id=viewer.id, emoji=body.emoji))
    db.commit()
    db.refresh(m)
    return to_message_out(db, m)


@app.post("/messages/block/{nickname}", tags=["messages"])
def block_user(
    nickname: str,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> dict:
    other = lookup_user_by_nick(db, nickname)
    if other is None or other.id == viewer.id:
        raise HTTPException(status_code=404, detail="user not found")
    existing = db.scalar(
        select(Block).where(Block.blocker_id == viewer.id, Block.blocked_id == other.id)
    )
    if existing is None:
        db.add(Block(blocker_id=viewer.id, blocked_id=other.id))
        db.commit()
    return {"ok": True}


@app.delete("/messages/block/{nickname}", tags=["messages"])
def unblock_user(
    nickname: str,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> dict:
    other = lookup_user_by_nick(db, nickname)
    if other is None:
        raise HTTPException(status_code=404, detail="user not found")
    db.query(Block).filter(Block.blocker_id == viewer.id, Block.blocked_id == other.id).delete()
    db.commit()
    return {"ok": True}


# ---- Sync (favorites + stats) -----------------------------------------

@app.post("/sync/favorites", response_model=FavoriteOut, tags=["sync"])
def add_favorite(
    body: FavoriteIn,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> FavoriteOut:
    existing = db.scalar(
        select(Favorite).where(Favorite.user_id == viewer.id, Favorite.item_id == body.item_id)
    )
    if existing:
        existing.title = body.title
        existing.poster_url = body.poster_url
        existing.kind = body.kind
        db.commit()
        db.refresh(existing)
        f = existing
    else:
        f = Favorite(
            user_id=viewer.id,
            item_id=body.item_id,
            title=body.title,
            poster_url=body.poster_url,
            kind=body.kind,
        )
        db.add(f)
        db.commit()
        db.refresh(f)
    return FavoriteOut(
        item_id=f.item_id,
        title=f.title,
        poster_url=f.poster_url,
        kind=f.kind,
        id=f.id,
        added_at=f.added_at,
    )


@app.delete("/sync/favorites/{item_id}", tags=["sync"])
def remove_favorite(
    item_id: str,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> dict:
    db.query(Favorite).filter(Favorite.user_id == viewer.id, Favorite.item_id == item_id).delete()
    db.commit()
    return {"ok": True}


@app.post("/sync/stats", response_model=StatPointOut, tags=["sync"])
def push_stat(
    body: StatPointIn,
    db: Session = Depends(get_db),
    viewer: User = Depends(get_current_user),
) -> StatPointOut:
    p = StatPoint(
        user_id=viewer.id,
        item_id=body.item_id,
        title=body.title,
        poster_url=body.poster_url,
        kind=body.kind,
        episode_number=body.episode_number,
        seconds_watched=max(0, int(body.seconds_watched)),
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    return StatPointOut(
        item_id=p.item_id,
        title=p.title,
        poster_url=p.poster_url,
        kind=p.kind,
        episode_number=p.episode_number,
        seconds_watched=p.seconds_watched,
        id=p.id,
        created_at=p.created_at,
    )


# ---- Admin ------------------------------------------------------------

@app.post("/admin/promote/{nickname}", response_model=PublicUser, tags=["admin"])
def admin_promote(
    nickname: str,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
) -> PublicUser:
    target = lookup_user_by_nick(db, nickname)
    if target is None:
        raise HTTPException(status_code=404, detail="user not found")
    target.role = "admin"
    db.commit()
    return to_public_user(target)


@app.post("/admin/verify/{nickname}", response_model=PublicUser, tags=["admin"])
def admin_verify(
    nickname: str,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
) -> PublicUser:
    target = lookup_user_by_nick(db, nickname)
    if target is None:
        raise HTTPException(status_code=404, detail="user not found")
    target.verified = True
    db.commit()
    return to_public_user(target)


@app.delete("/admin/verify/{nickname}", response_model=PublicUser, tags=["admin"])
def admin_unverify(
    nickname: str,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
) -> PublicUser:
    target = lookup_user_by_nick(db, nickname)
    if target is None:
        raise HTTPException(status_code=404, detail="user not found")
    target.verified = False
    db.commit()
    return to_public_user(target)
