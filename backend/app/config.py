from __future__ import annotations
import os
import secrets
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration for the Watch backend.

    All values can be overridden via environment variables (see fly.toml /
    `flyctl secrets set`). The defaults are tuned for local development.
    """

    db_path: str = "/data/watch.db"
    jwt_secret: str = secrets.token_urlsafe(48)
    jwt_alg: str = "HS256"
    jwt_ttl_hours: int = 24 * 30  # 30 days

    # Bootstrap admin: created on first startup if it doesn't exist yet.
    admin_nickname: str = "Watch"
    admin_password: str = ""  # required at first boot to create the admin

    share_url_base: str = "watch://u"

    online_window_minutes: int = 5

    model_config = SettingsConfigDict(env_prefix="WATCH_", env_file=".env", extra="ignore")


settings = Settings()
Path(settings.db_path).parent.mkdir(parents=True, exist_ok=True)
