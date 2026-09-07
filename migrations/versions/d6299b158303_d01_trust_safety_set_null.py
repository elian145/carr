"""D-01: user_report / listing_report foreign keys -> ON DELETE SET NULL

Revision ID: d6299b158303
Revises: 37060d159f6a
Create Date: 2026-09-07

Product decision (D-01, approved): trust & safety report records
(`user_report`, `listing_report`) must be preserved for moderation history
even after the reporter's account, the reported user's account, or the
reported listing is deleted. All four columns therefore use
`ON DELETE SET NULL` instead of the `NO ACTION` default (which would block
account deletion for anyone who ever filed or was the subject of a report)
or `CASCADE` (which would destroy moderation history).

`SET NULL` requires the referencing columns to be nullable, so
`user_report.reporter_id`, `user_report.reported_id`,
`listing_report.reporter_id`, and `listing_report.car_id` are widened from
`NOT NULL` to `NULL` here. Admin read paths (`to_admin_dict()` on both
models) already tolerate a missing related user/car. `delete_account()` no
longer bulk-deletes `UserReport`/`ListingReport` rows for the same reason;
`admin.purge_car()` no longer hard-deletes `ListingReport` rows for a purged
car.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "d6299b158303"
down_revision = "37060d159f6a"
branch_labels = None
depends_on = None


# (table, [(column, referred_table, referred_column), ...])
_TRUST_SAFETY_SET_NULL: list[tuple[str, list[tuple[str, str, str]]]] = [
    ("user_report", [("reporter_id", "user", "id"), ("reported_id", "user", "id")]),
    ("listing_report", [("reporter_id", "user", "id"), ("car_id", "car", "id")]),
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


def upgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)

    for table, specs in _TRUST_SAFETY_SET_NULL:
        if not insp.has_table(table):
            continue

        existing = [
            (column, referred_table, referred_column, _find_fk(conn, table, column, referred_table))
            for column, referred_table, referred_column in specs
        ]

        if conn.dialect.name == "sqlite":
            with op.batch_alter_table(table, schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
                for column, referred_table, _rc, fk in existing:
                    if fk is None:
                        continue
                    constraint_name = fk.get("name") or _fk_name(table, column, referred_table)
                    batch_op.drop_constraint(constraint_name, type_="foreignkey")
                for column, _rt, _rc, _fk in existing:
                    batch_op.alter_column(column, existing_type=sa.Integer(), nullable=True)
                for column, referred_table, referred_column, _fk in existing:
                    batch_op.create_foreign_key(
                        _fk_name(table, column, referred_table),
                        referred_table,
                        [column],
                        [referred_column],
                        ondelete="SET NULL",
                    )
            continue

        # PostgreSQL
        for column, _rt, _rc, _fk in existing:
            op.execute(sa.text(f'ALTER TABLE {table} ALTER COLUMN {column} DROP NOT NULL'))
        for column, referred_table, referred_column, fk in existing:
            if fk is not None and fk.get("name"):
                op.drop_constraint(fk["name"], table, type_="foreignkey")
            op.create_foreign_key(
                _fk_name(table, column, referred_table),
                table,
                referred_table,
                [column],
                [referred_column],
                ondelete="SET NULL",
            )


def downgrade() -> None:
    conn = op.get_bind()
    insp = sa.inspect(conn)

    for table, specs in _TRUST_SAFETY_SET_NULL:
        if not insp.has_table(table):
            continue

        if conn.dialect.name == "sqlite":
            with op.batch_alter_table(table, schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
                for column, referred_table, _rc in specs:
                    try:
                        batch_op.drop_constraint(_fk_name(table, column, referred_table), type_="foreignkey")
                    except Exception:
                        pass
                for column, _rt, _rc in specs:
                    batch_op.alter_column(column, existing_type=sa.Integer(), nullable=False)
                for column, referred_table, referred_column in specs:
                    batch_op.create_foreign_key(None, referred_table, [column], [referred_column])
            continue

        # PostgreSQL: see note in 37060d159f6a downgrade() about NULL rows.
        for column, referred_table, referred_column in specs:
            try:
                op.drop_constraint(_fk_name(table, column, referred_table), table, type_="foreignkey")
            except Exception:
                pass
            op.create_foreign_key(None, table, referred_table, [column], [referred_column])
        for column, _rt, _rc in specs:
            op.execute(sa.text(f'ALTER TABLE {table} ALTER COLUMN {column} SET NOT NULL'))
