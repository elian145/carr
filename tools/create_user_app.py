"""Create or update a user via the canonical app factory (kk.app_new)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create or update a user (uses kk.app_new / app factory)"
    )
    parser.add_argument("--email", required=True)
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    args = parser.parse_args()

    from kk import app_new as app_module
    from kk.models import User

    app = app_module.app
    db = app_module.db

    with app.app_context():
        user = User.query.filter_by(email=args.email).first()
        if user is None:
            user = User(email=args.email, username=args.username)
            user.set_password(args.password)
            db.session.add(user)
            db.session.commit()
            print(f"USER_CREATED email={args.email} username={args.username}")
        else:
            user.username = args.username
            user.set_password(args.password)
            db.session.commit()
            print(f"USER_UPDATED email={args.email} username={args.username}")


if __name__ == "__main__":
    main()
