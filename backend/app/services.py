from __future__ import annotations
from datetime import datetime, timedelta
from typing import Iterable, List, Optional

from sqlalchemy import and_, func, or_, select
from sqlalchemy.orm import Session

from .config import settings
from .db import Block, Favorite, Message, Reaction, StatPoint, User
from .schemas import (
    FavoriteOut,
    MessageOut,
    PublicProfile,
    PublicUser,
    ReactionOut,
    StatPointOut,
)


def share_url_for(nickname: str) -> str:
    return f"{settings.share_url_base}/{nickname}"


def to_public_user(u: User) -> PublicUser:
    return PublicUser(
        id=u.id,
        nickname=u.nickname,
        bio=u.bio or "",
        role=u.role,
        verified=u.verified,
        is_official=u.is_official,
        created_at=u.created_at,
        privacy_hide_stats=u.privacy_hide_stats,
        privacy_hide_favorites=u.privacy_hide_favorites,
        privacy_hide_history=u.privacy_hide_history,
        share_url=share_url_for(u.nickname),
    )


def lookup_user_by_nick(db: Session, nickname: str) -> Optional[User]:
    nick = nickname.strip()
    if not nick:
        return None
    return db.scalar(select(User).where(User.nickname_lower == nick.lower()))


def block_pair_status(db: Session, viewer: Optional[User], target: User) -> tuple[bool, bool]:
    """Return (is_blocked_by_viewer, is_blocking_viewer)."""
    if viewer is None or viewer.id == target.id:
        return (False, False)
    rows = db.scalars(
        select(Block).where(
            or_(
                and_(Block.blocker_id == viewer.id, Block.blocked_id == target.id),
                and_(Block.blocker_id == target.id, Block.blocked_id == viewer.id),
            )
        )
    ).all()
    by_viewer = any(b.blocker_id == viewer.id for b in rows)
    blocking_viewer = any(b.blocker_id == target.id for b in rows)
    return (by_viewer, blocking_viewer)


def to_message_out(db: Session, m: Message) -> MessageOut:
    sender = db.get(User, m.sender_id)
    recipient = db.get(User, m.recipient_id)
    reactions: List[ReactionOut] = []
    for r in m.reactions:
        u = db.get(User, r.user_id)
        if u:
            reactions.append(ReactionOut(user_nickname=u.nickname, emoji=r.emoji))
    return MessageOut(
        id=m.id,
        sender_nickname=sender.nickname if sender else "?",
        recipient_nickname=recipient.nickname if recipient else "?",
        body="" if m.deleted else m.body,
        item_id=m.item_id,
        item_title=m.item_title,
        item_poster_url=m.item_poster_url,
        created_at=m.created_at,
        read_at=m.read_at,
        deleted=m.deleted,
        reactions=reactions,
    )


def public_profile(db: Session, target: User, viewer: Optional[User]) -> PublicProfile:
    by_viewer, blocking_viewer = block_pair_status(db, viewer, target)

    show_stats = not target.privacy_hide_stats or (viewer is not None and viewer.id == target.id)
    show_favs = not target.privacy_hide_favorites or (viewer is not None and viewer.id == target.id)
    show_hist = not target.privacy_hide_history or (viewer is not None and viewer.id == target.id)

    minutes_total: Optional[int] = None
    episodes_total: Optional[int] = None
    if show_stats:
        secs = db.scalar(
            select(func.coalesce(func.sum(StatPoint.seconds_watched), 0)).where(
                StatPoint.user_id == target.id
            )
        ) or 0
        minutes_total = int(secs // 60)
        # Count *distinct* (item_id, episode_number) tuples rather than
        # raw stat point rows: the player ticks a row every ~30s of
        # playback, so a single 24-minute episode produces ~48 rows
        # and counting them naïvely would inflate the public profile's
        # "episodes watched" badge by ~50x.
        distinct_subq = (
            select(StatPoint.item_id, StatPoint.episode_number)
            .where(
                StatPoint.user_id == target.id,
                StatPoint.episode_number.is_not(None),
            )
            .distinct()
            .subquery()
        )
        episodes_total = db.scalar(select(func.count()).select_from(distinct_subq)) or 0

    favorites: Optional[List[FavoriteOut]] = None
    if show_favs:
        rows = db.scalars(
            select(Favorite)
            .where(Favorite.user_id == target.id)
            .order_by(Favorite.added_at.desc())
            .limit(60)
        ).all()
        favorites = [
            FavoriteOut(
                item_id=f.item_id,
                title=f.title,
                poster_url=f.poster_url,
                kind=f.kind,
                id=f.id,
                added_at=f.added_at,
            )
            for f in rows
        ]

    recent: Optional[List[StatPointOut]] = None
    if show_hist:
        rows = db.scalars(
            select(StatPoint)
            .where(StatPoint.user_id == target.id)
            .order_by(StatPoint.created_at.desc())
            .limit(40)
        ).all()
        recent = [
            StatPointOut(
                item_id=p.item_id,
                title=p.title,
                poster_url=p.poster_url,
                kind=p.kind,
                episode_number=p.episode_number,
                seconds_watched=p.seconds_watched,
                id=p.id,
                created_at=p.created_at,
            )
            for p in rows
        ]

    return PublicProfile(
        user=to_public_user(target),
        stats_minutes_total=minutes_total,
        stats_episodes_total=episodes_total,
        favorites=favorites,
        recent_history=recent,
        is_blocked_by_viewer=by_viewer,
        is_blocking_viewer=blocking_viewer,
    )


def is_blocked_either_way(db: Session, a_id: int, b_id: int) -> bool:
    row = db.scalar(
        select(Block).where(
            or_(
                and_(Block.blocker_id == a_id, Block.blocked_id == b_id),
                and_(Block.blocker_id == b_id, Block.blocked_id == a_id),
            )
        )
    )
    return row is not None


def conversation(db: Session, a_id: int, b_id: int, *, limit: int = 200) -> List[Message]:
    return list(
        db.scalars(
            select(Message)
            .where(
                or_(
                    and_(Message.sender_id == a_id, Message.recipient_id == b_id),
                    and_(Message.sender_id == b_id, Message.recipient_id == a_id),
                )
            )
            .order_by(Message.created_at.asc())
            .limit(limit)
        )
    )


def online_count(db: Session) -> int:
    cutoff = datetime.utcnow() - timedelta(minutes=settings.online_window_minutes)
    return (
        db.scalar(select(func.count(User.id)).where(User.last_seen_at >= cutoff)) or 0
    )


def total_users(db: Session) -> tuple[int, int]:
    total = db.scalar(select(func.count(User.id))) or 0
    cutoff = datetime.utcnow() - timedelta(days=7)
    new_7d = db.scalar(select(func.count(User.id)).where(User.created_at >= cutoff)) or 0
    return total, new_7d
