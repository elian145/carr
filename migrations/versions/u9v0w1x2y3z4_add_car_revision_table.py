"""Add car_revision (pending edits of published listings).

Revision ID: u9v0w1x2y3z4
Revises: t8u9v0w1x2y3
Create Date: 2026-10-16

Editing an already-approved listing must not change what the public sees
until an admin approves the edit. The owner's proposed values live in a
hidden *working copy* of the listing (a second ``car`` row with
``status='revision'`` and ``is_active=false``, created by the application
the first time the owner edits a published listing); ``car_revision`` is the
one-row-per-listing link between the approved listing and its working copy
and carries the review state (editing / pending / rejected, the rejection
reason, who reviewed it and when).

This migration is PURELY ADDITIVE:

- one new table (plus its indexes / unique constraints);
- both foreign keys point at ``car.id`` with ``ON DELETE CASCADE`` so a
  listing delete can never be blocked by, or leave behind, a revision row;
- no existing table, column, constraint or row is altered, so nothing needs
  a backfill and the application code currently in production (which never
  reads this table) keeps working unchanged against the upgraded schema.

Downgrade simply drops the table (any pending, not-yet-approved edit
becomes an orphaned, invisible, inactive working-copy ``car`` row -- it is
never public -- and approved data is unaffected).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "u9v0w1x2y3z4"
down_revision = "t8u9v0w1x2y3"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "car_revision",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("public_id", sa.String(length=50), nullable=False),
        sa.Column("car_id", sa.Integer(), nullable=False),
        sa.Column("shadow_car_id", sa.Integer(), nullable=False),
        sa.Column(
            "status",
            sa.String(length=20),
            nullable=False,
            server_default="editing",
        ),
        sa.Column("rejection_reason", sa.Text(), nullable=True),
        sa.Column("submitted_at", sa.DateTime(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(), nullable=True),
        sa.Column("reviewed_by", sa.String(length=100), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["car_id"], ["car.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["shadow_car_id"], ["car.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("car_id", name="uq_car_revision_car_id"),
        sa.UniqueConstraint("shadow_car_id", name="uq_car_revision_shadow_car_id"),
        sa.UniqueConstraint("public_id"),
    )
    op.create_index(
        "ix_car_revision_car_id", "car_revision", ["car_id"], unique=False
    )
    op.create_index(
        "ix_car_revision_status_submitted",
        "car_revision",
        ["status", "submitted_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_car_revision_status_submitted", table_name="car_revision")
    op.drop_index("ix_car_revision_car_id", table_name="car_revision")
    op.drop_table("car_revision")
