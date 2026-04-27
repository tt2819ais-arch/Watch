from __future__ import annotations
import secrets
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


def _persistent_jwt_secret(db_path: str) -> str:
    """Return a JWT signing secret that survives across restarts.

    The secret lives next to the SQLite file (so it lands on the same
    Fly volume). Without this, every machine restart would generate a
    fresh secret and invalidate every issued client token.
    """
    p = Path(db_path).parent / "jwt_secret.txt"
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        if p.exists():
            value = p.read_text(encoding="utf-8").strip()
            if value:
                return value
        value = secrets.token_urlsafe(48)
        p.write_text(value + "\n", encoding="utf-8")
        return value
    except Exception:
        # Filesystem unavailable (e.g. tests) — fall back to ephemeral.
        return secrets.token_urlsafe(48)


class Settings(BaseSettings):
    """Runtime configuration for the Watch backend.

    All values can be overridden via environment variables (see
    `flyctl secrets set` or the `WATCH_*` env vars). The defaults are
    tuned for local development; production-only knobs (admin
    password, JWT secret) are derived from the persistent volume so a
    redeploy doesn't wipe sessions or admin credentials.
    """

    db_path: str = "/data/watch.db"
    jwt_secret: str = ""
    jwt_alg: str = "HS256"
    jwt_ttl_hours: int = 24 * 30  # 30 days

    # Bootstrap admin: created on first startup if it doesn't exist yet.
    # The default password ships with the build so a fresh deploy is
    # immediately usable; operators can rotate it via the admin
    # endpoints once logged in.
    admin_nickname: str = "Watch"
    admin_password: str = "WatchAdmin-K9Xq2026"

    share_url_base: str = "watch://u"

    online_window_minutes: int = 5

    model_config = SettingsConfigDict(env_prefix="WATCH_", env_file=".env", extra="ignore")


settings = Settings()
Path(settings.db_path).parent.mkdir(parents=True, exist_ok=True)
if not settings.jwt_secret:
    settings.jwt_secret = _persistent_jwt_secret(settings.db_path)
