"""drop unique constraint on car.vin

Revision ID: h4i5j6k7l8m9
Revises: x1y2z3a4b5c6
Create Date: 2026-06-04
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "h4i5j6k7l8m9"
down_revision = "x1y2z3a4b5c6"
branch_labels = None
depends_on = None


def _drop_vin_unique(conn) -> None:
    insp = sa.inspect(conn)
    if not insp.has_table("car"):
        return
    for uq in insp.get_unique_constraints("car"):
        cols = uq.get("column_names") or []
        if cols == ["vin"]:
            # SQLite commonly stores inline UNIQUE constraints without a name.
            # Give reflected constraints a deterministic name so Alembic's
            # batch table recreation can target the VIN constraint.
            naming_convention = {
                "uq": "uq_%(table_name)s_%(column_0_name)s",
            }
            constraint_name = uq.get("name") or "uq_car_vin"
            with op.batch_alter_table(
                "car",
                schema=None,
                naming_convention=naming_convention,
            ) as batch_op:
                batch_op.drop_constraint(constraint_name, type_="unique")
            return
    # PostgreSQL default name from initial migration.
    if conn.dialect.name == "postgresql":
        try:
            op.drop_constraint("car_vin_key", "car", type_="unique")
        except Exception:
            pass


def upgrade() -> None:
    _drop_vin_unique(op.get_bind())


def downgrade() -> None:
    with op.batch_alter_table("car", schema=None) as batch_op:
        batch_op.create_unique_constraint("car_vin_key", ["vin"])
