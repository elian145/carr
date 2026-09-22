"""D-01 revisit: car.seller_id RESTRICT -> ON DELETE SET NULL

Revision ID: h1i2j3k4l5m6
Revises: d5e6f7a8b9c0
Create Date: 2026-09-22

Product decision update (self-service account deletion must satisfy the
Google Play / App Store account-deletion requirement -- see
``kk/routes/auth.py::delete_account()``): the original D-01 choice of
``ON DELETE RESTRICT`` on ``car.seller_id`` (migration
``6e469e1b250a_d01_car_seller_restrict.py``) meant a seller who still had
any listing could never actually be hard-deleted -- ``delete_account()``
silently fell back to anonymizing the ``User`` row (rename to
``deleted_xxxx``, clear PII fields) while leaving it ``is_active`` in the
database indefinitely. That is no longer acceptable: the *normal* result
of a successful account deletion must be that the ``user`` row is gone,
never merely deactivated because the account happened to have listings.

Switching to ``ON DELETE SET NULL`` (mirroring the exact pattern already
used for ``dealer_application.user_id`` / ``dealer_profile.user_id`` /
``dealer_decision.reviewer_id`` / ``scheduled_notification.created_by_user_id``
in ``acb26d5d1b40_d01_dealer_set_null.py``) lets ``delete_account()``
explicitly scrub each listing's personal data (description, VIN, contact
phones, exact map coordinates, photos/videos -- DB rows *and* the
underlying object-storage files) and deactivate it *before* deleting the
``User`` row, in one transaction. The DB then nulls ``car.seller_id``
itself the instant the user row disappears -- no remaining RESTRICT to
work around, and no need to delete the listing row itself (which would
have orphaned the surviving buyer's chat history for that listing --
``message.car_id`` is looked up directly by chat/messages endpoints).

``SET NULL`` requires ``car.seller_id`` to become nullable. No data is
changed by this migration; existing rows keep their current seller_id.

Unlike ``6e469e1b250a`` (the original RESTRICT migration, which only
tightened metadata and never recreated the table's rows), ``car`` now has
several years' worth of ``ON DELETE CASCADE``/``SET NULL`` children
(``car_image``, ``car_video``, ``listing_analytics``, ``saved_search_alert``,
``listing_view_claim``, ``message.car_id``, ``listing_report.car_id``).
SQLite's batch mode recreates the *entire* ``car`` table (rename -> create
-> copy -> drop old) to change the FK, and dropping that renamed old table
with ``PRAGMA foreign_keys=ON`` would cascade/null every one of those
children for every row, for real data as much as for any other migration
replayed after this one in a from-scratch ``flask db upgrade`` -- exactly
the hazard already solved once for the ``user`` table in
``3f945e50c327_d05_nullability_hardening.py``. This migration disables FK
enforcement for its own ``car`` batch-alter and restores it immediately
after, the same way.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "h1i2j3k4l5m6"
down_revision = "d5e6f7a8b9c0"
branch_labels = None
depends_on = None

_NAMING_CONVENTION = {
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
}

_FK_NAME = "fk_car_seller_id_user"


def _find_fk(conn) -> dict | None:
    for fk in sa.inspect(conn).get_foreign_keys("car"):
        if fk.get("constrained_columns") == ["seller_id"] and fk.get("referred_table") == "user":
            return fk
    return None


def _set_sqlite_fk_enforcement(conn, enabled: bool) -> None:
    """Toggle SQLite's `PRAGMA foreign_keys` so it actually takes effect
    mid-migration. See the identical helper/rationale in
    ``3f945e50c327_d05_nullability_hardening.py``: a plain
    ``PRAGMA foreign_keys=...`` is a no-op while a transaction is open
    (which Alembic always has one), so this uses
    ``op.get_context().autocommit_block()`` to apply it outside that
    transaction. SQLite only; no effect on PostgreSQL.
    """
    with op.get_context().autocommit_block():
        conn.execute(sa.text(f"PRAGMA foreign_keys={'ON' if enabled else 'OFF'}"))


def upgrade() -> None:
    conn = op.get_bind()
    if not sa.inspect(conn).has_table("car"):
        return

    fk = _find_fk(conn)

    if conn.dialect.name == "sqlite":
        _set_sqlite_fk_enforcement(conn, enabled=False)
        try:
            with op.batch_alter_table("car", schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
                if fk is not None:
                    constraint_name = fk.get("name") or _FK_NAME
                    batch_op.drop_constraint(constraint_name, type_="foreignkey")
                batch_op.alter_column("seller_id", existing_type=sa.Integer(), nullable=True)
                batch_op.create_foreign_key(_FK_NAME, "user", ["seller_id"], ["id"], ondelete="SET NULL")
        finally:
            _set_sqlite_fk_enforcement(conn, enabled=True)
        return

    # PostgreSQL
    op.execute(sa.text("ALTER TABLE car ALTER COLUMN seller_id DROP NOT NULL"))
    if fk is not None and fk.get("name"):
        op.drop_constraint(fk["name"], "car", type_="foreignkey")
    op.create_foreign_key(_FK_NAME, "car", "user", ["seller_id"], ["id"], ondelete="SET NULL")


def downgrade() -> None:
    conn = op.get_bind()
    if not sa.inspect(conn).has_table("car"):
        return

    if conn.dialect.name == "sqlite":
        _set_sqlite_fk_enforcement(conn, enabled=False)
        try:
            with op.batch_alter_table("car", schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
                try:
                    batch_op.drop_constraint(_FK_NAME, type_="foreignkey")
                except Exception:
                    pass
                # NOTE: does not restore nullable=False -- any row already
                # scrubbed to seller_id=NULL by the new code path would
                # violate NOT NULL. Downgrading past this revision on a
                # database with such rows requires a manual data fix first.
                batch_op.create_foreign_key(_FK_NAME, "user", ["seller_id"], ["id"], ondelete="RESTRICT")
        finally:
            _set_sqlite_fk_enforcement(conn, enabled=True)
        return

    try:
        op.drop_constraint(_FK_NAME, "car", type_="foreignkey")
    except Exception:
        pass
    op.create_foreign_key(_FK_NAME, "car", "user", ["seller_id"], ["id"], ondelete="RESTRICT")
