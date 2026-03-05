"""add engine_size and cylinder_count columns to car

Revision ID: 9b2d7f3c1e4a
Revises: 7c9a1d2f4a0b
Create Date: 2026-03-05 16:40:00.000000
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = "9b2d7f3c1e4a"
down_revision = "7c9a1d2f4a0b"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add engine_size and cylinder_count columns to car table."""
    with op.batch_alter_table("car") as batch_op:
        batch_op.add_column(sa.Column("engine_size", sa.Float(), nullable=True))
        batch_op.add_column(sa.Column("cylinder_count", sa.Integer(), nullable=True))


def downgrade() -> None:
    """Drop engine_size and cylinder_count columns from car table."""
    with op.batch_alter_table("car") as batch_op:
        batch_op.drop_column("cylinder_count")
        batch_op.drop_column("engine_size")

