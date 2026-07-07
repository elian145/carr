"""
Set a user's password by username or email.

Run from the project root (folder that contains `kk/`).

  $env:DATABASE_URL = "postgresql://..."
  python tools/set_password_by_username.py --user user_4f8b4ff1 --password "YourNewPassword"
"""
from __future__ import annotations

import argparse
import getpass
import os
import sys
from pathlib import Path


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--user", required=True, help="username or email")
    p.add_argument("--password", help="new password (omit to prompt securely)")
    p.add_argument("--dry-run", action="store_true")
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

    from sqlalchemy import func
    from sqlalchemy.exc import OperationalError

    from kk import app_new as app_module
    from kk.models import User, db

    user_key = args.user.strip()
    app = app_module.app
    with app.app_context():
        try:
            user = User.query.filter(
                (User.username == user_key)
                | (func.lower(User.email) == user_key.lower())
            ).first()
        except OperationalError as e:
            print("SET_PASSWORD_ERR could not connect to the database.", file=sys.stderr)
            print(f"  {e}", file=sys.stderr)
            return 3
        if not user:
            print("SET_PASSWORD_ERR no_user_found", file=sys.stderr)
            return 1
        print(
            "SET_PASSWORD_MATCH "
            f"id={user.id} public_id={user.public_id} username={user.username!r} "
            f"phone_number={user.phone_number!r}"
        )
        user.set_password(password)
        user.is_active = True
        if args.dry_run:
            db.session.rollback()
            print("SET_PASSWORD_DRY_RUN no_commit")
        else:
            db.session.commit()
            print("SET_PASSWORD_OK", user.username or user.email)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
