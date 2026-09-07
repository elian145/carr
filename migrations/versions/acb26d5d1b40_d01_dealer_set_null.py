"""D-01: dealer-related foreign keys -> ON DELETE SET NULL

Revision ID: acb26d5d1b40
Revises: d6299b158303
Create Date: 2026-09-07

Product decision (D-01, approved): dealer application/profile/decision
records, and admin broadcast-notification audit records, are preserved even
after the referenced user account is deleted, so all four foreign keys use
`ON DELETE SET NULL` rather than the `NO ACTION` default:

- `dealer_application.user_id` — preserve the application/review history.
- `dealer_profile.user_id` — preserve the public dealer profile record.
- `dealer_decision.reviewer_id` — preserve the decision snapshot even if the
  reviewing admin identity is later removed.
- `scheduled_notification.created_by_user_id` — preserve the broadcast
  audit record even if the creating admin identity is later removed.

`SET NULL` requires the referencing column to be nullable.
`dealer_application.user_id` and `dealer_profile.user_id` are widened from
`NOT NULL` to `NULL` here; `dealer_decision.reviewer_id` and
`scheduled_notification.created_by_user_id` were already nullable.
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "acb26d5d1b40"
down_revision = "d6299b158303"
branch_labels = None
depends_on = None


# (table, column, referred_table, referred_column, was_nullable_before)
_DEALER_SET_NULL: list[tuple[str, str, str, str, bool]] = [
    ("dealer_application", "user_id", "user", "id", False),
    ("dealer_profile", "user_id", "user", "id", False),
    ("dealer_decision", "reviewer_id", "user", "id", True),
    ("scheduled_notification", "created_by_user_id", "user", "id", True),
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

    for table, column, referred_table, referred_column, _was_nullable in _DEALER_SET_NULL:
        if not insp.has_table(table):
            continue

        fk = _find_fk(conn, table, column, referred_table)

        if conn.dialect.name == "sqlite":
            with op.batch_alter_table(table, schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
                if fk is not None:
                    constraint_name = fk.get("name") or _fk_name(table, column, referred_table)
                    batch_op.drop_constraint(constraint_name, type_="foreignkey")
                batch_op.alter_column(column, existing_type=sa.Integer(), nullable=True)
                batch_op.create_foreign_key(
                    _fk_name(table, column, referred_table),
                    referred_table,
                    [column],
                    [referred_column],
                    ondelete="SET NULL",
                )
            continue

        # PostgreSQL
        op.execute(sa.text(f'ALTER TABLE {table} ALTER COLUMN {column} DROP NOT NULL'))
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

    for table, column, referred_table, referred_column, was_nullable in _DEALER_SET_NULL:
        if not insp.has_table(table):
            continue

        if conn.dialect.name == "sqlite":
            with op.batch_alter_table(table, schema=None, naming_convention=_NAMING_CONVENTION) as batch_op:
                try:
                    batch_op.drop_constraint(_fk_name(table, column, referred_table), type_="foreignkey")
                except Exception:
                    pass
                if not was_nullable:
                    batch_op.alter_column(column, existing_type=sa.Integer(), nullable=False)
                batch_op.create_foreign_key(None, referred_table, [column], [referred_column])
            continue

        # PostgreSQL: see note in 37060d159f6a downgrade() about NULL rows
        # for the two columns being restored to NOT NULL.
        try:
            op.drop_constraint(_fk_name(table, column, referred_table), table, type_="foreignkey")
        except Exception:
            pass
        op.create_foreign_key(None, table, referred_table, [column], [referred_column])
        if not was_nullable:
            op.execute(sa.text(f'ALTER TABLE {table} ALTER COLUMN {column} SET NOT NULL'))
