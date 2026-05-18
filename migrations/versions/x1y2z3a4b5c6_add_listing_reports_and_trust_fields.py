"""add listing_report table and trust fields on user_report

Revision ID: x1y2z3a4b5c6
Revises: w1x2y3z4a5b6
Create Date: 2026-05-17

"""

from alembic import op
import sqlalchemy as sa


revision = "x1y2z3a4b5c6"
down_revision = "w1x2y3z4a5b6"
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table("user_report", schema=None) as batch_op:
        batch_op.add_column(sa.Column("admin_notes", sa.Text(), nullable=True))
        batch_op.add_column(sa.Column("resolved_at", sa.DateTime(), nullable=True))

    op.create_table(
        "listing_report",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("reporter_id", sa.Integer(), nullable=False),
        sa.Column("car_id", sa.Integer(), nullable=False),
        sa.Column("reason", sa.String(length=200), nullable=False),
        sa.Column("details", sa.Text(), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=True),
        sa.Column("admin_notes", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("resolved_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["car_id"], ["car.id"]),
        sa.ForeignKeyConstraint(["reporter_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_listing_report_reporter_id", "listing_report", ["reporter_id"])
    op.create_index("ix_listing_report_car_id", "listing_report", ["car_id"])
    op.create_index("ix_listing_report_status", "listing_report", ["status"])


def downgrade():
    op.drop_index("ix_listing_report_status", table_name="listing_report")
    op.drop_index("ix_listing_report_car_id", table_name="listing_report")
    op.drop_index("ix_listing_report_reporter_id", table_name="listing_report")
    op.drop_table("listing_report")

    with op.batch_alter_table("user_report", schema=None) as batch_op:
        batch_op.drop_column("resolved_at")
        batch_op.drop_column("admin_notes")
