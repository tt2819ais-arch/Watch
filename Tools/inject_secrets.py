#!/usr/bin/env python3
"""Inject build-time secrets into Watch/Services/Secrets.swift.

Reads tokens from environment (POISKKINO_API_TOKEN, KODIK_API_TOKEN)
and rewrites the BakedSecrets defaults so the produced .ipa carries
them. Source-tree defaults remain empty/public so the repo stays
clean.
"""
from __future__ import annotations

import os
import pathlib
import re
import sys


SECRETS_PATH = pathlib.Path("Watch/Services/Secrets.swift")


def _swift_escape(value: str) -> str:
    """Escape a string so it lives inside a Swift "..." literal safely.

    Swift treats `\\` as a literal backslash, `"` ends the string,
    `\\(expr)` is interpolation that would *execute* expr at runtime,
    and a raw newline byte breaks the single-line `"..."` literal —
    which would silently produce invalid Swift if a CI secret was
    misconfigured to include trailing whitespace. We escape to the
    Swift forms (`\\\\`, `\\"`, `\\n`, `\\r`, `\\0`) so any token can
    be safely embedded.
    """
    return (
        value.replace("\\", "\\\\")
             .replace('"', '\\"')
             .replace("\n", "\\n")
             .replace("\r", "\\r")
             .replace("\0", "\\0")
    )


def replace(text: str, name: str, value: str) -> str:
    pattern = rf'static let {name}: String = ".*?"'
    escaped = _swift_escape(value)
    swift_literal = f'static let {name}: String = "{escaped}"'
    # Pass the replacement as a callable so `re.sub` does not interpret
    # backslash-digit sequences (e.g. "\\1") in the secret as group
    # back-references.
    new_text, n = re.subn(pattern, lambda _m: swift_literal, text, count=1)
    if n != 1:
        raise SystemExit(f"failed to substitute {name}: pattern not found")
    return new_text


def main() -> int:
    if not SECRETS_PATH.exists():
        print(f"missing {SECRETS_PATH}", file=sys.stderr)
        return 1
    content = SECRETS_PATH.read_text()

    poisk = os.environ.get("POISKKINO_API_TOKEN", "").strip()
    kodik = os.environ.get("KODIK_API_TOKEN", "").strip()

    if poisk:
        content = replace(content, "poiskkinoToken", poisk)
        print(f"Injected PoiskKino token (length: {len(poisk)})")
    else:
        print(
            "::warning::POISKKINO_API_TOKEN not set — "
            "PoiskKino features will be disabled in this build"
        )

    if kodik:
        content = replace(content, "kodikToken", kodik)
        print(f"Injected Kodik token (length: {len(kodik)})")
    # else: keep public fallback baked.

    SECRETS_PATH.write_text(content)
    print(f"Secrets file size: {SECRETS_PATH.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
