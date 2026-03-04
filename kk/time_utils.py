from __future__ import annotations

from datetime import datetime, timezone


def utcnow() -> datetime:
    """
    Return a naive UTC datetime (UTC clock, tzinfo removed).

    We keep DB timestamps naive (UTC) for compatibility with existing models
    while avoiding deprecated `datetime.utcnow()` in Python 3.13+.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)

