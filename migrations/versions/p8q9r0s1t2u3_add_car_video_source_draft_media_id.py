"""Phase 3A (server-side video transcode fallback -- promotion/attach):
add CarVideo.source_draft_media_id + a (car_id, source_draft_media_id)
unique constraint.

Revision ID: p8q9r0s1t2u3
Revises: h1i2j3k4l5m6
Create Date: 2026-09-25

Backing change for POST /api/media/r2/attach-transcoded-video's
idempotency requirement (see kk/routes/media.py::attach_transcoded_video's
docstring): a repeated attach call for the same (car_id, draft_media_id)
must never create a second CarVideo row. The unique constraint is the
DB-level protection a plain "check row exists, then insert" cannot provide
against two concurrent requests racing each other.

BACKWARDS-COMPATIBLE: the new column is nullable. Every existing row, and
every future row created by the unrelated, pre-existing multipart
upload_car_videos() endpoint (which has no draft_media_id concept and
never sets this column), leaves it NULL. Standard SQL unique-constraint
semantics never treat two NULLs as equal, so existing/NULL rows never
conflict with each other or with a new non-NULL value, on either SQLite
or PostgreSQL.

SQLITE MECHANICS: SQLite has no ALTER TABLE ... ADD CONSTRAINT, so adding
the unique constraint requires Alembic's batch (table-recreate) mode --
same precedent as ``7ae553c40b45_d_10_dedupe_historical_duplicate_and_.py``
(listing_report). ``car_video`` is a leaf table (nothing has a FOREIGN KEY
REFERENCES car_video(...)), so recreating it cannot cascade-delete any
other table's rows; its own outgoing FK (car_id -> car.id, ON DELETE
CASCADE) is preserved automatically by batch mode's reflect-then-recreate
behavior, so no PRAGMA foreign_keys guard is needed here. The plain
``add_column`` step does not need batch mode on either dialect and is done
separately, first.
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "p8q9r0s1t2u3"
down_revision = "h1i2j3k4l5m6"
branch_labels = None
depends_on = None

_UNIQUE_CONSTRAINT_NAME = "uq_car_video_car_id_source_draft_media_id"


def upgrade() -> None:
    op.add_column(
        "car_video",
        sa.Column("source_draft_media_id", sa.String(length=128), nullable=True),
    )

    conn = op.get_bind()
    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("car_video", schema=None) as batch_op:
            batch_op.create_unique_constraint(
                _UNIQUE_CONSTRAINT_NAME, ["car_id", "source_draft_media_id"]
            )
    else:
        op.create_unique_constraint(
            _UNIQUE_CONSTRAINT_NAME, "car_video", ["car_id", "source_draft_media_id"]
        )


def downgrade() -> None:
    conn = op.get_bind()
    if conn.dialect.name == "sqlite":
        with op.batch_alter_table("car_video", schema=None) as batch_op:
            batch_op.drop_constraint(_UNIQUE_CONSTRAINT_NAME, type_="unique")
            batch_op.drop_column("source_draft_media_id")
    else:
        op.drop_constraint(_UNIQUE_CONSTRAINT_NAME, "car_video", type_="unique")
        op.drop_column("car_video", "source_draft_media_id")
