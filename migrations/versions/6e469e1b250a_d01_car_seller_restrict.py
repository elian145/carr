"""D-01: car.seller_id -> ON DELETE RESTRICT

Revision ID: 6e469e1b250a
Revises: acb26d5d1b40
Create Date: 2026-09-07

Product decision (D-01, approved): deleting a seller's account must never
destroy or orphan their car listings. `car.seller_id` therefore gets an
explicit `ON DELETE RESTRICT` (rather than the implicit `NO ACTION` default,
which is equivalent at the database level but was previously undocumented,
or `CASCADE`, which would silently delete the seller's listings).

This makes explicit, at the database layer, the invariant that
`kk/routes/auth.py::delete_account()` already relies on: an account that
still has cars cannot be hard-deleted and is anonymized instead (see
`User.cars`'s cascade note in `kk/models.py`). No column becomes nullable
and no data changes; this migration only adds the explicit `ondelete`
clause to the existing constraint.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "6e469e1b250a"
down_revision = "acb26d5d1b40"
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


def upgrade() -> None:
    conn = op.get_bind()
    if not sa.inspect(conn).has_table("car"):
        return

    fk = _find_fk(conn)

    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("car", schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
            if fk is not None:
                constraint_name = fk.get("name") or _FK_NAME
                batch_op.drop_constraint(constraint_name, type_="foreignkey")
            batch_op.create_foreign_key(_FK_NAME, "user", ["seller_id"], ["id"], ondelete="RESTRICT")
        return

    # PostgreSQL
    if fk is not None and fk.get("name"):
        op.drop_constraint(fk["name"], "car", type_="foreignkey")
    op.create_foreign_key(_FK_NAME, "car", "user", ["seller_id"], ["id"], ondelete="RESTRICT")


def downgrade() -> None:
    conn = op.get_bind()
    if not sa.inspect(conn).has_table("car"):
        return

    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("car", schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
            try:
                batch_op.drop_constraint(_FK_NAME, type_="foreignkey")
            except Exception:
                pass
            batch_op.create_foreign_key(None, "user", ["seller_id"], ["id"])
        return

    try:
        op.drop_constraint(_FK_NAME, "car", type_="foreignkey")
    except Exception:
        pass
    op.create_foreign_key(None, "car", "user", ["seller_id"], ["id"])
