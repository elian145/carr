"""Listing-edits e2e helper: seed an ACTIVE listing with a PENDING owner edit.

Test-only tooling (does not modify anything under kk/). Runs against the same
throwaway SQLite database as ``seed_test_admin.py`` (``DB_PATH``) and drives
the REAL application: it creates an owner + an approved listing with three
photos directly in the DB, then submits the owner's edit through the real
``PUT /api/cars/<id>`` endpoint, so the revision/working copy are created
exactly as in production.

    APP_ENV=testing SMS_PROVIDER=console DB_PATH=/tmp/l02_e2e.db \
    E2E_SEED_OUT=/tmp/listing_edit_seed.json \
    python admin-web/e2e/seed_listing_edit.py

Writes ``{"public_id", "title", "old_price", "new_price", "new_description"}``
to ``E2E_SEED_OUT`` for the spec to read.
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

OUT = os.environ.get("E2E_SEED_OUT", "")
if not OUT:
    raise SystemExit("E2E_SEED_OUT must be set (path of the JSON the spec reads).")

from kk.app_factory import create_app  # noqa: E402
from kk.models import Car, CarImage, User, db  # noqa: E402

PASSWORD = "E2e-Owner-Pass-1!"
OLD_PRICE = 15000
NEW_PRICE = 12345
NEW_DESCRIPTION = "E2E edited description"

app, *_ = create_app()
with app.app_context():
    db.create_all()
    suffix = uuid.uuid4().hex[:8]
    owner = User(
        public_id=f"e2e-owner-{suffix}",
        username=f"e2e_owner_{suffix}",
        phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
        first_name="E2E",
        last_name="Owner",
        is_active=True,
        is_verified=True,
        phone_verified=True,
    )
    owner.set_password(PASSWORD)
    db.session.add(owner)
    db.session.flush()
    car = Car(
        seller_id=owner.id,
        public_id=f"e2e-car-{suffix}",
        title="E2E Toyota Camry 2021",
        brand="toyota",
        model="camry",
        trim="base",
        year=2021,
        mileage=1000,
        engine_type="gasoline",
        fuel_type="gasoline",
        transmission="automatic",
        drive_type="fwd",
        condition="used",
        body_type="sedan",
        price=OLD_PRICE,
        currency="USD",
        location="Erbil",
        description="Original description",
        is_active=True,
        status="active",
    )
    db.session.add(car)
    db.session.flush()
    for i in range(3):
        db.session.add(
            CarImage(
                car_id=car.id,
                image_url=f"https://cdn.example.com/car_photos/e2e_{car.id}_{i}.jpg",
                is_primary=(i == 0),
                order=i,
                kind="listing",
            )
        )
    db.session.commit()
    public_id = car.public_id
    title = car.title
    owner_username = owner.username

client = app.test_client()
login = client.post(
    "/api/auth/login", json={"username": owner_username, "password": PASSWORD}
)
assert login.status_code == 200, login.data
token = login.get_json()["access_token"]
put = client.put(
    f"/api/cars/{public_id}",
    json={"price": NEW_PRICE, "description": NEW_DESCRIPTION},
    headers={"Authorization": f"Bearer {token}"},
)
assert put.status_code == 200, put.data
assert put.get_json().get("submitted_for_review") is True, put.data

with open(OUT, "w", encoding="utf-8") as fh:
    json.dump(
        {
            "public_id": public_id,
            "title": title,
            "old_price": OLD_PRICE,
            "new_price": NEW_PRICE,
            "new_description": NEW_DESCRIPTION,
        },
        fh,
    )
print(f"SEEDED_LISTING_EDIT public_id={public_id!r}")
