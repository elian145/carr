"""READ-ONLY inventory of legacy duplicate account phone numbers.

    python -m kk.phone_inventory_cli --db-path path/to/app.db
    python -m kk.phone_inventory_cli --database-url postgresql://...   (or $DATABASE_URL)
    python -m kk.phone_inventory_cli --json
    python -m kk.phone_inventory_cli --summary

Why: ``user.phone_number`` is UNIQUE only per exact string. Before the phone
canonicalisation work (SEC-003) the same SIM could be stored as ``07701234567``
by one code path and ``7701234567`` by another, i.e. two accounts for one
subscriber. This tool lists such colliding groups so an operator can decide what
to do. It never decides for them.

Guarantees (each one is pinned by ``kk/tests/test_phone_inventory_cli.py``):

* READ ONLY. It does not import the Flask app (``create_app`` runs migrations),
  opens its own engine, and refuses to execute anything but SELECT/SHOW:
  - SQLite: opened with ``mode=ro`` (a missing file is an error, never created)
    plus ``PRAGMA query_only=ON``;
  - PostgreSQL: every transaction is opened READ ONLY (driver ``read_only`` flag; no
    startup ``options``, so PgBouncer/Neon pooled endpoints keep working);
  - a SQLAlchemy ``before_cursor_execute`` guard raises ``ReadOnlyViolation``
    for any statement that is not a plain SELECT/SHOW (fail closed).
* PRIVACY. Output holds only masked phone numbers (``*******123``: last 3 digits),
  user ``public_id`` values, a spelling label (``canonical`` / ``leading_zero`` /
  ...) and counts. No full phone numbers, names, e-mails or database URL ever
  reach stdout/stderr.
* NEVER MERGES. There is no write path in this module. Merging or deleting
  duplicate accounts requires a MANUAL, SEPARATELY APPROVED procedure (decide
  which account survives, re-parent listings/chats/favourites/tokens, back up
  first); this tool only reports.
* Exit code is non-zero ONLY for errors (2 = bad usage/configuration,
  3 = database error). Finding duplicates is a normal result and exits 0.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Iterable
from urllib.parse import quote

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_DB = 3

MASK_VISIBLE_DIGITS = 3

# Statements the guard lets through. Anything else (INSERT/UPDATE/DELETE/DDL/
# PRAGMA writes/COPY/...) raises before reaching the driver.
_ALLOWED_LEADING = re.compile(r"^\s*\(?\s*(select|show|with)\b", re.IGNORECASE)
_FORBIDDEN_ANYWHERE = re.compile(
    r"\b(insert|update|delete|drop|alter|create|truncate|replace|merge|grant|revoke|"
    r"vacuum|reindex|attach|detach|copy|call|do|lock|into)\b",
    re.IGNORECASE,
)

_USER_QUERY = 'SELECT id, public_id, phone_number, is_active FROM "user"'

# A stored value counts as a phone number only if it is made of digits and the
# usual phone punctuation. Placeholders written by the app (``deleted_ab12cd34``,
# ``adm_5_x``) must not be fed to the canonicaliser (their digits would collide).
_PHONE_LIKE = re.compile(r"^\+?[\d\s\-().]+$")

_NOTE = (
    "Report only. This tool never merges, deletes or modifies accounts. Merging "
    "duplicate accounts requires a manual, separately approved procedure."
)


class ReadOnlyViolation(RuntimeError):
    """Raised when something other than a read statement is about to run."""


def is_read_only_statement(statement: str) -> bool:
    """True only for plain SELECT / SHOW statements (CTEs must not write)."""
    text = statement or ""
    if not _ALLOWED_LEADING.match(text):
        return False
    return _FORBIDDEN_ANYWHERE.search(text) is None


def mask_phone(raw: Any) -> str:
    """``*******123``-style mask: never more than the last 3 digits."""
    digits = "".join(ch for ch in str(raw or "") if ch.isdigit())
    if len(digits) <= MASK_VISIBLE_DIGITS:
        return "*" * 4
    return "*" * max(4, len(digits) - MASK_VISIBLE_DIGITS) + digits[-MASK_VISIBLE_DIGITS:]


def _fold_digits(raw: str) -> str:
    import unicodedata

    out = []
    for ch in raw:
        if ch.isdigit():
            d = unicodedata.digit(ch, None)
            if d is not None:
                out.append(str(d))
    return "".join(out)


def _canonical(raw: str) -> str:
    # Imported lazily and only for this one pure function: the canonical form
    # MUST be exactly what the auth routes store (no second implementation).
    from .routes.auth import _normalize_phone

    return _normalize_phone(raw)


def spelling_label(stored: str, canonical: str) -> str:
    """Label (no digits) describing how ``stored`` differs from ``canonical``."""
    s = (stored or "").strip()
    if s == canonical:
        return "canonical"
    folded = _fold_digits(s)
    if folded != s and folded == canonical:
        return "non_ascii_digits"
    if s.startswith("+"):
        return "plus_prefixed"
    if s.startswith("00"):
        return "international_00"
    if s.startswith("964"):
        return "country_code"
    if s.startswith("0") and folded == "0" + canonical:
        return "leading_zero"
    return "other_format"


def build_inventory(rows: Iterable[Any], *, group_limit: int = 1000) -> dict:
    """Pure function over ``(id, public_id, phone_number, is_active)`` rows."""
    total = 0
    non_phone = 0
    canonical_rows = 0
    legacy_rows = 0
    groups: dict[str, list[dict]] = {}
    for row in rows:
        total += 1
        _uid, public_id, phone, is_active = row[0], row[1], row[2], row[3]
        text = "" if phone is None else str(phone).strip()
        if not text or not _PHONE_LIKE.match(text):
            non_phone += 1
            continue
        canonical = _canonical(text)
        if not canonical:
            non_phone += 1
            continue
        if text == canonical:
            canonical_rows += 1
        else:
            legacy_rows += 1
        groups.setdefault(canonical, []).append(
            {
                "public_id": None if public_id is None else str(public_id),
                "spelling": spelling_label(text, canonical),
                "is_active": bool(is_active),
            }
        )

    collisions = {c: m for c, m in groups.items() if len(m) > 1}
    listed = []
    for canonical in sorted(collisions):
        members = sorted(collisions[canonical], key=lambda m: (m["public_id"] or ""))
        listed.append({"phone_masked": mask_phone(canonical), "members": members})
    users_in_collisions = sum(len(m) for m in collisions.values())
    return {
        "read_only": True,
        "total_users": total,
        "phone_like_users": total - non_phone,
        "non_phone_rows": non_phone,
        "canonical_rows": canonical_rows,
        "legacy_spelling_rows": legacy_rows,
        "collision_groups": len(collisions),
        "users_in_collision_groups": users_in_collisions,
        "groups_listed": min(len(listed), max(0, group_limit)),
        "groups": listed[: max(0, group_limit)],
        "manual_merge_required": bool(collisions),
        "note": _NOTE,
    }


def _normalise_database_url(url: str) -> str:
    url = url.strip()
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://") :]
    # Same driver choice as kk.app_factory (psycopg v3, not psycopg2).
    if url.startswith("postgresql://"):
        url = "postgresql+psycopg" + url[len("postgresql") :]
    return url


def sqlite_readonly_url(db_path: str) -> str:
    path = os.path.abspath(db_path)
    return "sqlite:///file:" + quote(path.replace("\\", "/"), safe="/:") + "?mode=ro&uri=true"


def open_readonly_engine(*, database_url: str | None = None, db_path: str | None = None):
    """Create an engine that cannot write. Raises ``ValueError`` on bad config."""
    from sqlalchemy import create_engine, event

    if db_path:
        if not os.path.isfile(db_path):
            raise ValueError("sqlite database file not found")
        url = sqlite_readonly_url(db_path)
        engine = create_engine(url)

        @event.listens_for(engine, "connect")
        def _sqlite_query_only(dbapi_connection, _record):  # pragma: no cover - trivial
            cur = dbapi_connection.cursor()
            cur.execute("PRAGMA query_only=ON")
            cur.close()

    elif database_url:
        url = _normalise_database_url(database_url)
        if url.startswith("sqlite"):
            raise ValueError("use --db-path for sqlite files")
        if not url.startswith("postgresql"):
            raise ValueError("unsupported database url scheme")
        engine = create_engine(
            url,
            execution_options={"postgresql_readonly": True},
        )
    else:
        raise ValueError("no database configured (use --db-path, --database-url or DATABASE_URL)")

    @event.listens_for(engine, "before_cursor_execute")
    def _read_only_guard(_conn, _cursor, statement, _params, _context, _executemany):
        if not is_read_only_statement(statement):
            raise ReadOnlyViolation("refusing to execute a non-read statement")

    return engine


def collect(engine, *, group_limit: int = 1000) -> dict:
    from sqlalchemy import text

    with engine.connect() as conn:
        result = conn.execution_options(stream_results=True).execute(text(_USER_QUERY))
        return build_inventory(result, group_limit=group_limit)


def format_text(report: dict, *, summary: bool) -> str:
    lines = [
        "PHONE INVENTORY (read-only)",
        f"users total:               {report['total_users']}",
        f"users with a phone number: {report['phone_like_users']}",
        f"placeholder/non-phone rows: {report['non_phone_rows']}",
        f"stored in canonical form:  {report['canonical_rows']}",
        f"stored in a legacy spelling: {report['legacy_spelling_rows']}",
        f"duplicate groups:          {report['collision_groups']}",
        f"users in duplicate groups: {report['users_in_collision_groups']}",
    ]
    if not summary:
        for i, group in enumerate(report["groups"], 1):
            lines.append(f"-- group {i}: phone {group['phone_masked']}")
            for m in group["members"]:
                lines.append(
                    f"   user {m['public_id']}  spelling={m['spelling']}  active={str(m['is_active']).lower()}"
                )
        if report["groups_listed"] < report["collision_groups"]:
            lines.append(
                f"... {report['collision_groups'] - report['groups_listed']} more group(s) not listed (see --limit)"
            )
    lines.append(report["note"])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m kk.phone_inventory_cli",
        description="READ-ONLY report of accounts whose phone numbers collide once canonicalised. "
        "Never merges, deletes or modifies anything.",
    )
    parser.add_argument("--db-path", help="SQLite database file (opened read-only)")
    parser.add_argument(
        "--database-url",
        help="PostgreSQL URL (default: $DATABASE_URL). Never printed.",
    )
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--summary", action="store_true", help="counts only, no per-group listing")
    parser.add_argument("--limit", type=int, default=1000, help="max duplicate groups listed")
    args = parser.parse_args(argv)

    url = args.database_url or os.environ.get("DATABASE_URL") or ""
    if args.db_path:
        url = ""
    try:
        engine = open_readonly_engine(database_url=url or None, db_path=args.db_path)
    except ValueError as exc:
        print(f"phone_inventory: error: {exc}", file=sys.stderr)
        return EXIT_USAGE
    except Exception as exc:  # driver missing etc.; never echo the URL
        print(f"phone_inventory: error: cannot open database ({type(exc).__name__})", file=sys.stderr)
        return EXIT_DB

    try:
        report = collect(engine, group_limit=args.limit)
    except Exception as exc:
        # Exception text can embed the DSN/statement; print the class only.
        print(f"phone_inventory: error: database read failed ({type(exc).__name__})", file=sys.stderr)
        return EXIT_DB
    finally:
        engine.dispose()

    if args.summary:
        report = {k: v for k, v in report.items() if k not in ("groups",)}
        report["groups_listed"] = 0
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(format_text(report, summary=args.summary))
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
