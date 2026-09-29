"""Media-readiness manifest: Car.media_status, car_media_item table,
CarImage.source_media_id + (car_id, source_media_id) unique constraint.

Revision ID: r5s6t7u8v9w0
Revises: p8q9r0s1t2u3
Create Date: 2026-09-28

Backs the media-readiness gate (kk/media_readiness.py): a listing that
declares expected media at create time must not become admin-approvable
until every declared item has finished server-side processing.

- ``car.media_status`` (NOT NULL, server_default 'ready'): every existing
  row -- and every future row for a listing that declares zero expected
  media -- reads 'ready' with no backfill needed.
- ``car_media_item``: brand-new table, starts empty. One row per media
  item a seller declared at submit time; unique on (car_id,
  client_media_id) so a retried/replayed create_car call (or a duplicated
  enqueue) can never insert a second row for the same item.
- ``car_image.source_media_id`` (nullable) + a NULL-safe unique constraint
  on (car_id, source_media_id) -- the image-side mirror of
  ``car_video.source_draft_media_id`` /
  ``uq_car_video_car_id_source_draft_media_id`` (see
  p8q9r0s1t2u3_add_car_video_source_draft_media_id.py), added for exactly
  the same reason: idempotent server-side attach must never create a
  second CarImage row for the same (car_id, client_media_id). Every
  existing row, and every row attached via the older client-driven
  `/images/attach` path, leaves this NULL -- standard SQL unique
  semantics never treat two NULLs as equal, so this is fully
  backwards-compatible on both SQLite and PostgreSQL.

SQLITE MECHANICS: SQLite has no ALTER TABLE ... ADD CONSTRAINT, so the new
unique constraint on `car_image` requires Alembic's batch (table-recreate)
mode -- same precedent as the CarVideo migration above. `car_image` is a
leaf table (nothing has a FOREIGN KEY REFERENCES car_image(...)), so
recreating it cannot cascade-delete any other table's rows.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "r5s6t7u8v9w0"
down_revision = "p8q9r0s1t2u3"
branch_labels = None
depends_on = None

_CAR_IMAGE_UNIQUE_CONSTRAINT_NAME = "uq_car_image_car_id_source_media_id"


def upgrade() -> None:
    # 1) Car.media_status
    op.add_column(
        "car",
        sa.Column(
            "media_status",
            sa.String(length=20),
            nullable=False,
            server_default=sa.text("'ready'"),
        ),
    )
    op.create_index("ix_car_media_status", "car", ["media_status"])

    # 2) car_media_item (brand-new table)
    op.create_table(
        "car_media_item",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column(
            "car_id",
            sa.Integer(),
            sa.ForeignKey("car.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("kind", sa.String(length=10), nullable=False),
        sa.Column("client_media_id", sa.String(length=128), nullable=False),
        sa.Column("job_task_id", sa.String(length=64), nullable=True),
        sa.Column(
            "status",
            sa.String(length=12),
            nullable=False,
            server_default=sa.text("'awaiting_upload'"),
        ),
        sa.Column("phase_a_completed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.UniqueConstraint(
            "car_id", "client_media_id", name="uq_car_media_item_car_client"
        ),
    )
    op.create_index(
        "ix_car_media_item_car_id", "car_media_item", ["car_id"]
    )
    op.create_index(
        "ix_car_media_item_car_status", "car_media_item", ["car_id", "status"]
    )

    # 3) car_image.source_media_id + unique constraint
    op.add_column(
        "car_image",
        sa.Column("source_media_id", sa.String(length=128), nullable=True),
    )

    conn = op.get_bind()
    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("car_image", schema=None) as batch_op:
            batch_op.create_unique_constraint(
                _CAR_IMAGE_UNIQUE_CONSTRAINT_NAME, ["car_id", "source_media_id"]
            )
    else:
        op.create_unique_constraint(
            _CAR_IMAGE_UNIQUE_CONSTRAINT_NAME,
            "car_image",
            ["car_id", "source_media_id"],
        )


def downgrade() -> None:
    conn = op.get_bind()
    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("car_image", schema=None) as batch_op:
            batch_op.drop_constraint(
                _CAR_IMAGE_UNIQUE_CONSTRAINT_NAME, type_="unique"
            )
            batch_op.drop_column("source_media_id")
    else:
        op.drop_constraint(
            _CAR_IMAGE_UNIQUE_CONSTRAINT_NAME, "car_image", type_="unique"
        )
        op.drop_column("car_image", "source_media_id")

    op.drop_index("ix_car_media_item_car_status", table_name="car_media_item")
    op.drop_index("ix_car_media_item_car_id", table_name="car_media_item")
    op.drop_table("car_media_item")

    op.drop_index("ix_car_media_status", table_name="car")
    op.drop_column("car", "media_status")
