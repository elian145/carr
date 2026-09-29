"""Regression for the 2026-09-29 production incident: `POST /api/cars`
returned 500 on every call, immediately after
``migrations/versions/r5s6t7u8v9w0_media_readiness_manifest.py`` deployed,
with:

    psycopg.errors.StringDataRightTruncation:
    value too long for type character varying(12)

Root cause: `car_media_item.status` was declared `VARCHAR(12)` in that
migration (and mirrored as `db.String(12)` in `kk/models.py`), but the
very first value ever written to the column -- the row's own
`default='awaiting_upload'`, stamped atomically inside `create_car()`
(see kk/routes/cars.py) -- is 15 characters long. Fixed by
``migrations/versions/s7t8u9v0w1x2_widen_car_media_item_status.py``
(VARCHAR(12) -> VARCHAR(32)) plus the matching `kk/models.py` widen.

Why a NEW test file, and why it boots the app via a real `flask db
upgrade` (like `kk/tests/test_migration_schema_drift.py`) instead of
reusing `test_media_readiness_manifest.py`'s `app_ctx` fixture: that
fixture calls `db.create_all()` directly against the SQLAlchemy models,
which means it always uses whatever width `kk/models.py` *currently*
declares -- it can never catch a model/migration mismatch like this one,
because there is no migration involved at all. It also would not have
caught the original bug even with the mismatch present, because SQLite
(the test DB for that fixture) has no real `VARCHAR(n)` length
enforcement at the storage level regardless of the declared width (the
exact same asymmetry `test_migration_schema_drift.py` and
`o1p2q3r4s5t6`'s docstring already document for other columns). This
file instead:

  1. Boots the app the same way `test_migration_schema_drift.py` does
     (`AUTO_MIGRATE` default, fresh SQLite file) so the schema in play is
     whatever a real `flask db upgrade` deploy actually produces -- not
     what the ORM models declare.
  2. Asserts the *migrated* column's declared width (via
     `sqlalchemy.inspect(engine).get_columns(...)`, not
     `kk/models.py`) is >= the longest string in
     `CarMediaItem.ALL_STATUSES` -- this is a static check that would
     have failed loudly for the original VARCHAR(12) even on SQLite,
     without needing PostgreSQL's stricter enforcement to surface it.
  3. Additionally proves every defined status round-trips through that
     same migrated table via the real ORM (belt-and-suspenders: on a
     real PostgreSQL deploy this is exactly the check that would have
     caught the incident directly).
"""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
import uuid
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


class CarMediaItemStatusWidthTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(
            prefix="carlist_cmi_width_", ignore_cleanup_errors=True
        )
        os.environ["APP_ENV"] = "testing"
        os.environ["DB_PATH"] = os.path.join(self._tmp.name, "cmi_width.db")
        # Default AUTO_MIGRATE ("1"): create_app()'s bootstrap runs a real
        # `flask_migrate.upgrade()` against the fresh, empty SQLite file --
        # the same code path Render's start_render.sh drives -- never
        # db.create_all(). This is what proves the MIGRATED width, not
        # whatever kk/models.py happens to declare today.
        os.environ.pop("AUTO_MIGRATE", None)
        os.environ["SMS_PROVIDER"] = "console"

        from kk.app_factory import create_app

        self.app, *_ = create_app()

    def tearDown(self):
        with self.app.app_context():
            from kk.extensions import db

            try:
                db.session.remove()
            except Exception:
                pass
            try:
                db.engine.dispose()
            except Exception:
                pass
        self._tmp.cleanup()

    def test_migrated_column_width_covers_longest_defined_status(self):
        """Static check on the schema `flask db upgrade` actually
        produces -- catches a too-narrow column even on SQLite, which
        never enforces VARCHAR(n) at the storage level and so cannot
        catch this via insertion alone."""
        from sqlalchemy import inspect

        from kk.extensions import db
        from kk.models import CarMediaItem

        longest_status = max(CarMediaItem.ALL_STATUSES, key=len)
        longest_len = len(longest_status)

        with self.app.app_context():
            insp = inspect(db.engine)
            columns = {c["name"]: c for c in insp.get_columns("car_media_item")}

        self.assertIn(
            "status", columns, "car_media_item.status column is missing entirely"
        )
        declared_length = getattr(columns["status"]["type"], "length", None)
        self.assertIsNotNone(
            declared_length,
            "car_media_item.status has no inspectable VARCHAR length "
            f"(type={columns['status']['type']!r})",
        )
        self.assertGreaterEqual(
            declared_length,
            longest_len,
            "car_media_item.status is declared as VARCHAR("
            f"{declared_length}) in the migrated schema, which is narrower "
            f"than the longest CarMediaItem.ALL_STATUSES value "
            f"({longest_status!r}, {longest_len} chars). This is exactly "
            "the 2026-09-29 production StringDataRightTruncation incident "
            "-- see migrations/versions/"
            "s7t8u9v0w1x2_widen_car_media_item_status.py.",
        )

    def test_every_defined_status_round_trips_through_migrated_table(self):
        """Belt-and-suspenders: actually write and read back every status
        via the real ORM against the migrated table. On PostgreSQL this
        is precisely the check that would have caught the incident
        directly (StringDataRightTruncation raises on the INSERT)."""
        from kk.extensions import db
        from kk.models import Car, CarMediaItem, User

        with self.app.app_context():
            user = User(
                username=f"cmi_width_{uuid.uuid4().hex[:10]}",
                phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
                first_name="Width",
                last_name="Test",
                is_active=True,
                is_verified=True,
                phone_verified=True,
                public_id=f"cmi-width-{uuid.uuid4().hex[:12]}",
            )
            user.set_password("Aa123456!")
            db.session.add(user)
            db.session.flush()

            car = Car(
                seller_id=user.id,
                title="CMI width test car",
                brand="toyota",
                model="corolla",
                year=2021,
                mileage=10,
                engine_type="gas",
                transmission="auto",
                drive_type="fwd",
                condition="used",
                body_type="sedan",
                price=15.0,
                location="Erbil",
                is_active=True,
                status="pending",
            )
            db.session.add(car)
            db.session.flush()

            for status in CarMediaItem.ALL_STATUSES:
                item = CarMediaItem(
                    car_id=car.id,
                    kind="image",
                    client_media_id=f"width-{status}",
                    status=status,
                )
                db.session.add(item)
            # The write itself is the assertion on PostgreSQL (a too-narrow
            # column raises StringDataRightTruncation right here). On
            # SQLite this always succeeds regardless of width, which is
            # exactly why the previous test also checks the declared width
            # directly.
            db.session.commit()

            stored = {
                row.client_media_id: row.status
                for row in CarMediaItem.query.filter_by(car_id=car.id).all()
            }
            self.assertEqual(
                stored,
                {
                    f"width-{status}": status
                    for status in CarMediaItem.ALL_STATUSES
                },
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
