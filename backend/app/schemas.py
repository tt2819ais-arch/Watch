from __future__ import annotations
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


# ---- Auth -------------------------------------------------------------

class SignupRequest(BaseModel):
    nickname: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_]+$")
    password: str = Field(min_length=6, max_length=128)


class LoginRequest(BaseModel):
    nickname: str
    password: str


class PublicUser(BaseModel):
    id: int
    nickname: str
    bio: str
    role: str
    verified: bool
    is_official: bool
    created_at: datetime
    privacy_hide_stats: bool
    privacy_hide_favorites: bool
    privacy_hide_history: bool
    share_url: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: PublicUser


class UpdateMeRequest(BaseModel):
    bio: Optional[str] = None
    privacy_hide_stats: Optional[bool] = None
    privacy_hide_favorites: Optional[bool] = None
    privacy_hide_history: Optional[bool] = None


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=6, max_length=128)


# ---- Messages ----------------------------------------------------------

class ReactionIn(BaseModel):
    emoji: str = Field(min_length=1, max_length=16)


class ReactionOut(BaseModel):
    user_nickname: str
    emoji: str


class MessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=4000)
    item_id: Optional[str] = None
    item_title: Optional[str] = None
    item_poster_url: Optional[str] = None


class MessageOut(BaseModel):
    id: int
    sender_nickname: str
    recipient_nickname: str
    body: str
    item_id: Optional[str]
    item_title: Optional[str]
    item_poster_url: Optional[str]
    created_at: datetime
    read_at: Optional[datetime]
    deleted: bool
    reactions: List[ReactionOut] = []


# ---- Favorites & Stats -------------------------------------------------

class FavoriteIn(BaseModel):
    item_id: str
    title: str
    poster_url: Optional[str] = None
    kind: str


class FavoriteOut(FavoriteIn):
    id: int
    added_at: datetime


class StatPointIn(BaseModel):
    item_id: str
    title: str
    poster_url: Optional[str] = None
    kind: str
    episode_number: Optional[int] = None
    seconds_watched: int = 0


class StatPointOut(StatPointIn):
    id: int
    created_at: datetime


# ---- Profile ----------------------------------------------------------

class PublicProfile(BaseModel):
    user: PublicUser
    stats_minutes_total: Optional[int]
    stats_episodes_total: Optional[int]
    favorites: Optional[List[FavoriteOut]]
    recent_history: Optional[List[StatPointOut]]
    is_blocked_by_viewer: bool
    is_blocking_viewer: bool


# ---- Public stats -----------------------------------------------------

class UsersCount(BaseModel):
    total: int
    new_last_7d: int


class OnlineStats(BaseModel):
    online: int
    window_minutes: int
