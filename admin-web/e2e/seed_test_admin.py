"""L-02 CSP e2e helper: seed a real admin login into a local test database.

NOT backend production code and does not modify anything under kk/ — this is
a standalone script (mirrors the sys.path bootstrap already used by
kk/tests/*.py) that uses the real, unmodified `kk.app_factory.create_app()`
and `kk.admin_identity.ensure_detached_admin_account()` to create a genuine
User + AdminAccount pair in a throwaway SQLite database, so admin-web's e2e
CSP tests can authenticate through the REAL login flow
(POST /api/admin-session -> POST /api/auth/login -> AdminAccount.check_password)
instead of any fake/bypass token.

Usage (run once before starting the real backend on the same DB_PATH):
    APP_ENV=testing SMS_PROVIDER=console DB_PATH=/tmp/l02_e2e.db \
    E2E_ADMIN_USERNAME=e2e_admin E2E_ADMIN_PASSWORD=... \
    python admin-web/e2e/seed_test_admin.py
"""

from __future__ import annotations

import os
import secrets
import sys
import uuid
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SMS_PROVIDER", "console")

USERNAME = os.environ.get("E2E_ADMIN_USERNAME", "e2e_admin")
PASSWORD = os.environ.get("E2E_ADMIN_PASSWORD", "")
if not PASSWORD:
    raise SystemExit("E2E_ADMIN_PASSWORD must be set (test-only credential, not committed).")

from kk.admin_identity import ensure_detached_admin_account  # noqa: E402
from kk.app_factory import create_app  # noqa: E402
from kk.models import User, db  # noqa: E402

app, *_ = create_app()
with app.app_context():
    db.create_all()

    user = User.query.filter_by(username=USERNAME).first()
    if not user:
        user = User(
            public_id=str(uuid.uuid4()),
            username=USERNAME,
            phone_number=f"e2e{secrets.token_hex(4)}"[:20],
            first_name="E2E",
            last_name="Admin",
        )
        db.session.add(user)

    user.is_admin = True
    user.admin_role = "super_admin"
    user.is_active = True
    user.is_verified = True
    user.phone_verified = True
    user.set_password(PASSWORD)
    db.session.flush()

    admin_account = ensure_detached_admin_account(user)
    # ensure_detached_admin_account() copies the ORIGINAL password hash at
    # creation time only; re-sync it explicitly so reruns with a changed
    # E2E_ADMIN_PASSWORD always take effect for the login the tests use.
    admin_account.password_hash = user.password_hash
    admin_account.is_active = True

    db.session.commit()
    print(
        "SEEDED_ADMIN "
        f"username={user.username!r} user_id={user.id} admin_account_id={admin_account.id}"
    )
