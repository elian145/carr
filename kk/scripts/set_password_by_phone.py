"""
Set a user's password by phone number (matches signup normalization quirks).

Run from the project root (folder that contains `kk/`).

PowerShell:

  $env:DATABASE_URL = "postgresql://..."
  python kk/scripts/set_password_by_phone.py 7505070706 --password "YourNewPassword"
  python kk/scripts/set_password_by_phone.py 7505070706 --password "YourNewPassword" --dry-run
"""
from __future__ import annotations

import argparse
import getpass
import os
import sys
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _normalize_phone(raw_phone: str) -> str:
    digits = "".join(ch for ch in (raw_phone or "") if ch.isdigit())
    if not digits:
        return ""
    if digits.startswith("964") and len(digits) >= 12:
        digits = digits[3:]
    if len(digits) > 11:
        digits = digits[-11:]
    return digits


def _phone_match_variants(raw: str) -> set[str]:
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
    p = argparse.ArgumentParser(description="Set password for user(s) with this phone.")
    p.add_argument("phone", help="Phone as you would type it (e.g. 7505070706)")
    p.add_argument("--password", help="New password (omit to prompt securely)")
    p.add_argument("--dry-run", action="store_true", help="Print matches but do not commit.")
    args = p.parse_args()

    password = args.password
    if not password:
        password = getpass.getpass("New password: ")
        confirm = getpass.getpass("Confirm password: ")
        if password != confirm:
            print("SET_PASSWORD_ERR passwords_do_not_match", file=sys.stderr)
            return 2
    if not password or len(password) < 6:
        print("SET_PASSWORD_ERR password_too_short (min 6)", file=sys.stderr)
        return 2

    root = _repo_root()
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))

    os.environ.setdefault("APP_ENV", "development")

    from sqlalchemy import or_
    from sqlalchemy.exc import OperationalError

    from kk import app_new as app_module
    from kk.models import User, db

    variants = _phone_match_variants(args.phone)
    if not variants:
        print("SET_PASSWORD_ERR no_digits_in_phone", file=sys.stderr)
        return 2

    app = app_module.app
    with app.app_context():
        q = User.query.filter(or_(*[User.phone_number == v for v in variants]))
        try:
            rows = q.all()
        except OperationalError as e:
            print("SET_PASSWORD_ERR could not connect to the database.", file=sys.stderr)
            print(f"  {e}", file=sys.stderr)
            return 3
        if not rows:
            print(
                "SET_PASSWORD_ERR no_user_found "
                f"variants={sorted(variants)}"
            )
            return 1
        for u in rows:
            print(
                "SET_PASSWORD_MATCH "
                f"id={u.id} public_id={u.public_id} username={u.username!r} "
                f"phone_number={u.phone_number!r}"
            )
            u.set_password(password)
            u.is_active = True
        if args.dry_run:
            db.session.rollback()
            print("SET_PASSWORD_DRY_RUN no_commit")
        else:
            db.session.commit()
            print(f"SET_PASSWORD_OK updated={len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
