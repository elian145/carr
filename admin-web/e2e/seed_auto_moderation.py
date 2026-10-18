"""Auto-moderation e2e seed (test-only; run against a THROWAWAY database).

Creates, through the real, unmodified application code:

* three admin accounts (super_admin / moderator / support) that sign in via the
  real login flow;
* three pending listings whose automatic decisions are recorded by the real
  engine in SHADOW mode (the default): one it would auto-approve, one with
  scam language, one from a seller with no approved history;
* nothing is ever published, no setting is changed, and live mode is never
  enabled.

Usage (same DATABASE_URL / DB_PATH as the backend under test):

    APP_ENV=testing SMS_PROVIDER=console DATABASE_URL=... \
    AUTO_MODERATION_AI_PROVIDER=stub E2E_SEED_OUT=seed.json \
    python admin-web/e2e/seed_auto_moderation.py

Writes the usernames / ids the Playwright spec needs to E2E_SEED_OUT. The
password is the fixed throwaway test credential of the unit-test helpers.
"""

from __future__ import annotations

import json
import os
import sys
import uuid
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SMS_PROVIDER", "console")
os.environ.setdefault("AUTO_MODERATION_AI_PROVIDER", "stub")
for k in ("AUTO_MODERATION_ALLOW_LIVE", "AUTO_MODERATION_KILL_SWITCH", "AUTO_MODERATION_DISABLED"):
    os.environ.pop(k, None)

OUT = os.environ.get("E2E_SEED_OUT", "")
if not OUT:
    raise SystemExit("E2E_SEED_OUT must be set")

from kk.app_factory import create_app  # noqa: E402
from kk.tests.test_auto_moderation_engine import (  # noqa: E402
    _PASSWORD,
    _car,
    _moderate,
    _trusted_seller,
    _user,
)

app, *_ = create_app()

seed: dict = {"password": _PASSWORD, "admins": {}, "listings": {}}
for role in ("super_admin", "moderator", "support"):
    _uid, username = _user(app, admin=True, role=role)
    seed["admins"][role] = username

tag = uuid.uuid4().hex[:6]
good_uid, _ = _trusted_seller(app)
good = _car(app, good_uid, title=f"E2E Clean Camry {tag}", description=f"One owner, full service history {tag}.")
scam_uid, _ = _trusted_seller(app)
scam = _car(
    app, scam_uid, title=f"E2E Scam Camry {tag}", price=16100, mileage=52000,
    description=f"Pay by western union only, guaranteed profit {tag}.",
)
new_uid, _ = _user(app)
fresh = _car(app, new_uid, title=f"E2E New Seller Camry {tag}", price=17100, mileage=61000,
             description=f"Garage kept {tag}.")

for key, c in (("clean", good), ("scam", scam), ("new_seller", fresh)):
    result = _moderate(app, "listing", c["car_id"])
    seed["listings"][key] = {
        "car_id": c["car_id"],
        "public_id": c["public_id"],
        "title": {"clean": f"E2E Clean Camry {tag}", "scam": f"E2E Scam Camry {tag}",
                  "new_seller": f"E2E New Seller Camry {tag}"}[key],
        "outcome": result.get("outcome"),
        "decision": result.get("decision"),
    }

Path(OUT).write_text(json.dumps(seed, indent=2), encoding="utf-8")
print("SEEDED_AUTO_MODERATION", json.dumps({k: v["outcome"] for k, v in seed["listings"].items()}))
