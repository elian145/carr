"""D-10: dedupe historical duplicate and add unique constraint on listing_report(reporter_id, car_id)

Revision ID: 7ae553c40b45
Revises: o1p2q3r4s5t6
Create Date: 2026-09-08 02:38:31.963207

PRODUCTION_AUDIT.md D-10: "Duplicate reports allowed — no unique on
(reporter_id, car_id)". `listing_report` had three separate non-unique
indexes (`reporter_id`, `car_id`, `status`) but nothing prevented the same
reporter from filing more than one report against the same listing, at
either the database or application layer.

Real production PostgreSQL (Neon) evidence (verified 2026-09-08):
  listing_report total rows: 3
  duplicate groups: 1
  reporter_id=26, car_id=162:
    id=1  reason="yuhh"  status="resolved"   created_at=2026-07-07 22:05:34.790014
    id=2  reason="bugs"  status="dismissed"  created_at=2026-07-07 22:06:30.345002

FAIL-CLOSED DESIGN (deliberately NOT a generic "keep earliest, delete the
rest" rule): this migration is authorized to delete exactly one row --
listing_report.id=2 -- and only after verifying, at migration time, that
id=1 and id=2 both still have reporter_id=26 and car_id=162. This check
verifies row identity (id) and duplicate-key identity (reporter_id,
car_id) ONLY -- it does not compare reason/details/status/timestamps or
any other column. If that verification fails (id=2 exists but the
observed state doesn't match), or if id=2 is simply absent (fresh
database, or already cleaned up), no arbitrary deletion occurs.

After that single, pre-verified deletion (or its no-op), the migration
scans the ENTIRE table for any remaining duplicate (reporter_id, car_id)
group. If any exist -- including a hypothetical further duplicate within
the (26, 162) pair itself, or any entirely unrelated pair -- the migration
raises and the whole transaction (including the id=2 delete, if it ran)
rolls back via migrations/env.py's `context.begin_transaction()`. This
migration is not authorized to delete any row other than the one, single,
pre-verified id=2; unexpected duplicates require manual/data-owner review,
not automatic resolution.

Only once zero duplicate groups are proven does the migration add
UniqueConstraint("reporter_id", "car_id", name="uq_listing_report_reporter_car").

NULL SEMANTICS: reporter_id/car_id can be NULL (D-01 ON DELETE SET NULL,
after the reporter's account or the listing is later deleted). Both the
duplicate-group scan and the unique constraint itself explicitly/implicitly
ignore NULL pairs -- standard SQL never treats two NULLs as equal for
uniqueness purposes on either SQLite or PostgreSQL, so historical
SET-NULL'd rows can never collide with each other or with anything else.
D-01's ON DELETE SET NULL FK behavior is completely untouched by this
migration.

SQLITE MECHANICS: SQLite has no ALTER TABLE ... ADD CONSTRAINT, so adding
the unique constraint requires Alembic's batch (table-recreate) mode.
Unlike the D-05/D-08 batch_alter_table("user") migrations, no
PRAGMA foreign_keys guard is needed here: listing_report is a leaf table
(nothing has a FOREIGN KEY REFERENCES listing_report(...)), so recreating
it cannot cascade-delete any other table's rows. Its own two outgoing FKs
(reporter_id -> user.id, car_id -> car.id, both ON DELETE SET NULL) are
preserved automatically by batch mode's reflect-then-recreate behavior
(verified empirically by
kk/tests/test_d10_listing_report_duplicates.py::...test_fks_survive_sqlite_batch_recreation).

ROLLBACK / DOWNGRADE: downgrade() only drops the unique constraint. It
contains no data statement of any kind and cannot attempt to recreate the
deleted id=2 row -- removing a unique constraint can never fail against
existing data, so downgrade() is unconditionally safe on both dialects.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '7ae553c40b45'
down_revision = 'o1p2q3r4s5t6'
branch_labels = None
depends_on = None


# The single, specific historical production duplicate this migration is
# authorized to resolve. See docstring above for the verified evidence.
_KNOWN_DUP_REPORTER_ID = 26
_KNOWN_DUP_CAR_ID = 162
_KNOWN_DUP_KEEP_ID = 1
_KNOWN_DUP_REMOVE_ID = 2

_UNIQUE_CONSTRAINT_NAME = "uq_listing_report_reporter_car"


def upgrade():
    conn = op.get_bind()

    # ---- Step 1: known historical duplicate, verified before any DELETE ----
    keep_row = conn.execute(
        sa.text("SELECT id, reporter_id, car_id FROM listing_report WHERE id = :id"),
        {"id": _KNOWN_DUP_KEEP_ID},
    ).mappings().first()
    remove_row = conn.execute(
        sa.text("SELECT id, reporter_id, car_id FROM listing_report WHERE id = :id"),
        {"id": _KNOWN_DUP_REMOVE_ID},
    ).mappings().first()

    if remove_row is not None:
        keep_matches = (
            keep_row is not None
            and keep_row["reporter_id"] == _KNOWN_DUP_REPORTER_ID
            and keep_row["car_id"] == _KNOWN_DUP_CAR_ID
        )
        remove_matches = (
            remove_row["reporter_id"] == _KNOWN_DUP_REPORTER_ID
            and remove_row["car_id"] == _KNOWN_DUP_CAR_ID
        )
        if not (keep_matches and remove_matches):
            raise RuntimeError(
                "D-10 migration: row listing_report.id=2 exists but does not "
                f"exactly match the known production duplicate identity "
                f"(observed keep_row={dict(keep_row) if keep_row else None}, "
                f"remove_row={dict(remove_row)}; expected both id=1 and id=2 "
                f"to have reporter_id={_KNOWN_DUP_REPORTER_ID}, "
                f"car_id={_KNOWN_DUP_CAR_ID}). Refusing to delete anything "
                "automatically. This migration is only authorized to remove "
                "that one specific, pre-verified row. Manual/data-owner "
                "review is required before this migration can proceed."
            )
        conn.execute(
            sa.text("DELETE FROM listing_report WHERE id = :id"),
            {"id": _KNOWN_DUP_REMOVE_ID},
        )
        print(
            f"D-10: verified listing_report id={_KNOWN_DUP_KEEP_ID} and "
            f"id={_KNOWN_DUP_REMOVE_ID} both have "
            f"reporter_id={_KNOWN_DUP_REPORTER_ID}/car_id={_KNOWN_DUP_CAR_ID}; "
            f"removed id={_KNOWN_DUP_REMOVE_ID}, kept id={_KNOWN_DUP_KEEP_ID}.",
            flush=True,
        )
    else:
        print(
            f"D-10: no row with listing_report.id={_KNOWN_DUP_REMOVE_ID} found "
            "-- known-duplicate cleanup is a no-op (fresh database, or "
            "already clean).",
            flush=True,
        )

    # ---- Step 2: fail loudly on ANY other remaining duplicate group ----
    remaining = conn.execute(
        sa.text(
            """
            SELECT reporter_id, car_id, COUNT(*) AS n
            FROM listing_report
            WHERE reporter_id IS NOT NULL AND car_id IS NOT NULL
            GROUP BY reporter_id, car_id
            HAVING COUNT(*) > 1
            """
        )
    ).mappings().all()
    if remaining:
        detail = ", ".join(
            f"(reporter_id={r['reporter_id']}, car_id={r['car_id']}, count={r['n']})"
            for r in remaining
        )
        raise RuntimeError(
            "D-10 migration: unexpected duplicate listing_report "
            f"(reporter_id, car_id) group(s) remain: {detail}. This "
            "migration is only authorized to remove the single known "
            f"historical duplicate (id={_KNOWN_DUP_REMOVE_ID}, handled above "
            "if present); it will not delete any other duplicate "
            "automatically. Manual/data-owner review is required to resolve "
            "these group(s) before the unique constraint can be installed. "
            "No further changes have been made."
        )

    # ---- Step 3: only now, with zero remaining duplicates proven ----
    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("listing_report", schema=None) as batch_op:
            batch_op.create_unique_constraint(
                _UNIQUE_CONSTRAINT_NAME, ["reporter_id", "car_id"]
            )
    else:
        op.create_unique_constraint(
            _UNIQUE_CONSTRAINT_NAME, "listing_report", ["reporter_id", "car_id"]
        )


def downgrade():
    conn = op.get_bind()
    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("listing_report", schema=None) as batch_op:
            batch_op.drop_constraint(_UNIQUE_CONSTRAINT_NAME, type_="unique")
    else:
        op.drop_constraint(_UNIQUE_CONSTRAINT_NAME, "listing_report", type_="unique")
