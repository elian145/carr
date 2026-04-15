"""
Grant is_admin for a user by phone number (matches signup normalization quirks).

Run from the project root (folder that contains `kk/`):

  set DATABASE_URL=postgresql://...   # production / Render external URL
  python kk/scripts/set_admin_by_phone.py 7505070706

Or with a dry run:

  python kk/scripts/set_admin_by_phone.py 7505070706 --dry-run
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _normalize_phone(raw_phone: str) -> str:
    """Same rules as kk.routes.auth._normalize_phone."""
    digits = "".join(ch for ch in (raw_phone or "") if ch.isdigit())
    if not digits:
        return ""
    if digits.startswith("964") and len(digits) >= 12:
        digits = digits[3:]
    if len(digits) > 11:
        digits = digits[-11:]
    return digits


def _phone_match_variants(raw: str) -> set[str]:
    """Possible stored phone_number values for Iraqi-style numbers."""
    n = _normalize_phone(raw)
    if not n:
        return set()
    out = {n}
    if len(n) == 10 and n.isdigit():
        out.add("0" + n)
    if len(n) == 11 and n.startswith("0") and n.isdigit():
        out.add(n[1:])
    return out


def main() -> int:
    p = argparse.ArgumentParser(description="Set is_admin=true for user(s) with this phone.")
    p.add_argument("phone", help="Phone as you would type it (e.g. 7505070706 or +9647505070706)")
    p.add_argument("--dry-run", action="store_true", help="Print matches but do not commit.")
    args = p.parse_args()

    root = _repo_root()
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))

    os.environ.setdefault("APP_ENV", "development")

    from kk import app_new as app_module
    from kk.models import User, db
    from sqlalchemy import or_

    variants = _phone_match_variants(args.phone)
    if not variants:
        print("SET_ADMIN_BY_PHONE_ERR no_digits_in_phone", file=sys.stderr)
        return 2

    app = app_module.app
    with app.app_context():
        q = User.query.filter(or_(*[User.phone_number == v for v in variants]))
        rows = q.all()
        if not rows:
            print(
                "SET_ADMIN_BY_PHONE_ERR no_user_found "
                f"variants={sorted(variants)} "
                "tip: check exact phone_number in DB or pass full international"
            )
            return 1
        for u in rows:
            print(
                "SET_ADMIN_BY_PHONE_MATCH "
                f"id={u.id} public_id={u.public_id} username={u.username!r} "
                f"phone_number={u.phone_number!r} was_admin={u.is_admin}"
            )
            u.is_admin = True
        if args.dry_run:
            db.session.rollback()
            print("SET_ADMIN_BY_PHONE_DRY_RUN no_commit")
        else:
            db.session.commit()
            print(f"SET_ADMIN_BY_PHONE_OK updated={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
