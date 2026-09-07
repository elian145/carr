"""D-01: explicit ON DELETE CASCADE on Group-A foreign keys

Revision ID: c05b6c97708d
Revises: 29381c94a7a4
Create Date: 2026-09-07

Production audit item D-01 (see PRODUCTION_AUDIT.md): every foreign key must
carry an explicit `ON DELETE` policy instead of relying on the database
default (`NO ACTION` on PostgreSQL). This is the first of five append-only
D-01 migrations.

This migration covers the "Group A" foreign keys: rows that are strictly
child/dependent data of their parent and have no independent product value
once the parent is gone (favorites, viewed-listings, dealer decisions on a
dealer application, car media/analytics, notifications, audit/session
records, saved searches + their alerts, user blocks, token blacklist
entries, and vehicle catalog trims/models). All of these already behave as
"delete-with-parent" in application code today (either via ORM
`cascade='all, delete-orphan'` or because the parent's own delete path
already removes them); this migration only makes that behavior an explicit,
enforced `ON DELETE CASCADE` at the database level so it holds even for
direct SQL/ad-hoc deletes.

No column becomes nullable in this migration and no columns are added or
removed — only the foreign key constraints are dropped and recreated with an
explicit `ondelete` clause. Constraint names are discovered dynamically
(existing deployments were created via unnamed `sa.ForeignKeyConstraint(...)`
in earlier migrations, e.g. `5f5f50c0c03d_initial.py`) rather than assumed
literally, exactly as `h4i5j6k7l8m9_drop_car_vin_unique.py` does for the
`car.vin` unique constraint.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "c05b6c97708d"
down_revision = "29381c94a7a4"
branch_labels = None
depends_on = None


# (table, [(column, referred_table, referred_column), ...])
_GROUP_A_CASCADE: list[tuple[str, list[tuple[str, str, str]]]] = [
    ("user_favorites", [("user_id", "user", "id"), ("car_id", "car", "id")]),
    ("user_viewed_listings", [("user_id", "user", "id"), ("car_id", "car", "id")]),
    ("dealer_decision", [("application_id", "dealer_application", "id")]),
    ("car_image", [("car_id", "car", "id")]),
    ("car_video", [("car_id", "car", "id")]),
    ("listing_analytics", [("car_id", "car", "id")]),
    ("notification", [("user_id", "user", "id")]),
    ("user_action", [("user_id", "user", "id")]),
    ("password_reset", [("user_id", "user", "id")]),
    ("email_verification", [("user_id", "user", "id")]),
    ("saved_search", [("user_id", "user", "id")]),
    ("saved_search_alert", [("saved_search_id", "saved_search", "id"), ("car_id", "car", "id")]),
    ("blocked_user", [("blocker_id", "user", "id"), ("blocked_id", "user", "id")]),
    ("token_blacklist", [("user_id", "user", "id")]),
    ("catalog_vehicle_model", [("brand_id", "catalog_brand", "id")]),
    ("catalog_trim", [("model_id", "catalog_vehicle_model", "id")]),
]

_NAMING_CONVENTION = {
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
}


def _fk_name(table: str, column: str, referred_table: str) -> str:
    return f"fk_{table}_{column}_{referred_table}"


def _find_fk(conn, table: str, column: str, referred_table: str) -> dict | None:
    for fk in sa.inspect(conn).get_foreign_keys(table):
        if fk.get("constrained_columns") == [column] and fk.get("referred_table") == referred_table:
            return fk
    return None


def _apply_ondelete(conn, table: str, specs: list[tuple[str, str, str]], ondelete: str) -> None:
    insp = sa.inspect(conn)
    if not insp.has_table(table):
        return

    # `fk` is None only if no such constraint exists at the DB level at all
    # (not expected for any Group-A FK — all were created inline via
    # `op.create_table(...)` — but checked defensively rather than assumed;
    # a batch `drop_constraint` for a name that doesn't exist raises at
    # `batch_alter_table.__exit__()`/flush time, which a `try/except` around
    # the queuing call does NOT catch).
    existing = [
        (column, referred_table, referred_column, _find_fk(conn, table, column, referred_table))
        for column, referred_table, referred_column in specs
    ]

    if conn.dialect.name == "sqlite":
        with op.batch_alter_table(table, schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
            for column, referred_table, _referred_column, fk in existing:
                if fk is None:
                    continue
                constraint_name = fk.get("name") or _fk_name(table, column, referred_table)
                batch_op.drop_constraint(constraint_name, type_="foreignkey")
            for column, referred_table, referred_column, _fk in existing:
                batch_op.create_foreign_key(
                    _fk_name(table, column, referred_table),
                    referred_table,
                    [column],
                    [referred_column],
                    ondelete=ondelete,
                )
        return

    for column, referred_table, referred_column, fk in existing:
        if fk is not None and fk.get("name"):
            op.drop_constraint(fk["name"], table, type_="foreignkey")
        op.create_foreign_key(
            _fk_name(table, column, referred_table),
            table,
            referred_table,
            [column],
            [referred_column],
            ondelete=ondelete,
        )


def upgrade() -> None:
    conn = op.get_bind()
    for table, specs in _GROUP_A_CASCADE:
        _apply_ondelete(conn, table, specs, "CASCADE")


def downgrade() -> None:
    conn = op.get_bind()
    # Restore the original unnamed/no-ondelete foreign keys (equivalent to
    # NO ACTION on PostgreSQL, the pre-D-01 behavior).
    for table, specs in _GROUP_A_CASCADE:
        insp = sa.inspect(conn)
        if not insp.has_table(table):
            continue
        if conn.dialect.name == "sqlite":
            with op.batch_alter_table(table, schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
                for column, referred_table, referred_column in specs:
                    try:
                        batch_op.drop_constraint(_fk_name(table, column, referred_table), type_="foreignkey")
                    except Exception:
                        pass
                for column, referred_table, referred_column in specs:
                    batch_op.create_foreign_key(None, referred_table, [column], [referred_column])
        else:
            for column, referred_table, referred_column in specs:
                try:
                    op.drop_constraint(_fk_name(table, column, referred_table), table, type_="foreignkey")
                except Exception:
                    pass
                op.create_foreign_key(None, table, referred_table, [column], [referred_column])
