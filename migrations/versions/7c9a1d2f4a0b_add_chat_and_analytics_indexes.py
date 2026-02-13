"""add chat and analytics indexes

Revision ID: 7c9a1d2f4a0b
Revises: 5f5f50c0c03d
Create Date: 2026-02-12

"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "7c9a1d2f4a0b"
down_revision = "5f5f50c0c03d"
branch_labels = None
depends_on = None


def upgrade():
    # --- listing_analytics: enforce 1 row per car_id (dedupe first) ---
    try:
        op.execute(
            """
            DELETE FROM listing_analytics
            WHERE id NOT IN (
                SELECT MIN(id) FROM listing_analytics GROUP BY car_id
            )
            """
        )
    except Exception:
        # Best-effort: if table is empty or backend doesn't support this exact SQL,
        # migration can still continue without enforcing uniqueness.
        pass

    with op.batch_alter_table("listing_analytics", schema=None) as batch_op:
        # Create a unique index (portable across SQLite/Postgres).
        batch_op.create_index(
            "uq_listing_analytics_car_id",
            ["car_id"],
            unique=True,
        )

    # --- message: add indexes used by unread_count and chat history ---
    with op.batch_alter_table("message", schema=None) as batch_op:
        batch_op.create_index(
            "ix_message_receiver_is_read_created_at",
            ["receiver_id", "is_read", "created_at"],
            unique=False,
        )
        batch_op.create_index(
            "ix_message_car_created_at",
            ["car_id", "created_at"],
            unique=False,
        )
        batch_op.create_index(
            "ix_message_sender_created_at",
            ["sender_id", "created_at"],
            unique=False,
        )


def downgrade():
    with op.batch_alter_table("message", schema=None) as batch_op:
        batch_op.drop_index("ix_message_sender_created_at")
        batch_op.drop_index("ix_message_car_created_at")
        batch_op.drop_index("ix_message_receiver_is_read_created_at")

    with op.batch_alter_table("listing_analytics", schema=None) as batch_op:
        batch_op.drop_index("uq_listing_analytics_car_id")

