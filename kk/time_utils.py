from __future__ import annotations

import re
from datetime import datetime, timezone


def utcnow() -> datetime:
    """
    Return a naive UTC datetime (UTC clock, tzinfo removed).

    We keep DB timestamps naive (UTC) for compatibility with existing models
    while avoiding deprecated `datetime.utcnow()` in Python 3.13+.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)

def iso_utc(value):
    """
    Serialize a timestamp for API responses as ISO-8601 UTC with a ``Z`` suffix.

    The single serializer for every timestamp the API sends to clients (F-07).
    DB columns hold naive UTC datetimes; a bare ``isoformat()`` of those has no
    zone designator, which clients (Dart ``DateTime.parse``) read as *local*
    time (e.g. "3 hours old" in Iraq, UTC+3).

    * ``None`` -> ``None``
    * naive ``datetime`` -> treated as UTC
    * aware ``datetime`` -> converted to UTC
    * precision is preserved exactly (``isoformat()`` rules: microseconds are
      emitted only when non-zero) so equality/ordering/cursor round-trips hold.
    * non-datetime values (e.g. ``date``) fall back to ``isoformat()`` / ``str``.
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is not None and value.utcoffset() is not None:
            value = value.astimezone(timezone.utc)
        return value.replace(tzinfo=None).isoformat() + "Z"
    iso = getattr(value, "isoformat", None)
    if callable(iso):
        return iso()
    return str(value)


_FRACTION_RE = re.compile(r"\.(\d+)")
_SPACE_OFFSET_RE = re.compile(r"\s(\d{2}:?\d{2})$")


def parse_api_datetime(raw) -> datetime | None:
    """
    Parse a client-supplied ISO-8601 timestamp into a NAIVE UTC datetime.

    Accepts the new ``...Z`` form, explicit offsets (``+03:00``), and the legacy
    offset-less form (treated as UTC, like the DB). Works on every supported
    Python (``datetime.fromisoformat`` only learned ``Z`` in 3.11). Returns
    ``None`` for empty/unparseable input.
    """
    if raw is None:
        return None
    if isinstance(raw, datetime):
        dt = raw
    else:
        text = str(raw).strip()
        if not text:
            return None
        # An unencoded "+" in a query string arrives as a space.
        text = _SPACE_OFFSET_RE.sub(r"+\1", text)
        if text[-1] in ("Z", "z"):
            text = text[:-1] + "+00:00"
        # Python < 3.11 only accepts 3 or 6 fractional digits.
        text = _FRACTION_RE.sub(
            lambda m: "." + m.group(1)[:6].ljust(6, "0"), text, count=1
        )
        try:
            dt = datetime.fromisoformat(text)
        except ValueError:
            return None
    if dt.tzinfo is not None and dt.utcoffset() is not None:
        dt = dt.astimezone(timezone.utc)
    return dt.replace(tzinfo=None)
