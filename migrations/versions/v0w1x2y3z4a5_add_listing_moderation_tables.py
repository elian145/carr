"""Add listing_moderation_run / listing_moderation_event (automated moderation).

Revision ID: v0w1x2y3z4a5
Revises: u9v0w1x2y3z4
Create Date: 2026-10-18

Backs the automated listing-moderation engine (``kk/auto_moderation``):

* ``listing_moderation_run``   -- one row per evaluated version of a listing /
  pending edit: the decision (AUTO_APPROVE / NEEDS_REVIEW / HOLD), the reasons,
  whether it was applied, and what an administrator later did with the same
  subject (shadow-mode comparison). ``(subject_key, content_token, mode)`` is
  unique -- that is the idempotency key of the Celery job.
* ``listing_moderation_event`` -- append-only decision log.

PURELY ADDITIVE: two new tables and their indexes. No existing table, column,
constraint or row is touched, nothing needs a backfill, and the application
code currently in production (which never reads these tables) keeps working
against the upgraded schema. Every foreign key to ``car`` / ``car_revision`` /
``user`` is ``ON DELETE SET NULL`` so this table can never block (or be the
reason for blocking) a listing / revision / account delete, and the decision
history survives a purge.

Platform settings (mode, kill switch, thresholds) reuse the existing
``app_setting`` table -- no schema change for them.

Downgrade drops both tables (decision history is lost; listings, revisions
and everything else are unaffected).
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "v0w1x2y3z4a5"
down_revision = "u9v0w1x2y3z4"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "listing_moderation_run",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("public_id", sa.String(length=50), nullable=False),
        sa.Column("subject_key", sa.String(length=64), nullable=False),
        sa.Column("subject_type", sa.String(length=12), nullable=False),
        sa.Column("car_id", sa.Integer(), nullable=True),
        sa.Column("car_public_id", sa.String(length=50), nullable=True),
        sa.Column("revision_id", sa.Integer(), nullable=True),
        sa.Column("revision_public_id", sa.String(length=50), nullable=True),
        sa.Column("seller_id", sa.Integer(), nullable=True),
        sa.Column("content_token", sa.String(length=64), nullable=False),
        sa.Column("mode", sa.String(length=10), nullable=False),
        sa.Column(
            "status", sa.String(length=16), nullable=False, server_default="evaluating"
        ),
        sa.Column("decision", sa.String(length=16), nullable=True),
        sa.Column("reasons", sa.JSON(), nullable=True),
        sa.Column("checks", sa.JSON(), nullable=True),
        sa.Column("ai", sa.JSON(), nullable=True),
        sa.Column("engine_version", sa.String(length=20), nullable=True),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("claimed_at", sa.DateTime(), nullable=True),
        sa.Column("decided_at", sa.DateTime(), nullable=True),
        sa.Column("next_retry_at", sa.DateTime(), nullable=True),
        sa.Column("outcome", sa.String(length=32), nullable=True),
        sa.Column("applied_at", sa.DateTime(), nullable=True),
        sa.Column("admin_outcome", sa.String(length=20), nullable=True),
        sa.Column("admin_outcome_at", sa.DateTime(), nullable=True),
        sa.Column("admin_outcome_by", sa.String(length=100), nullable=True),
        sa.Column("override_action", sa.String(length=20), nullable=True),
        sa.Column("override_by", sa.String(length=100), nullable=True),
        sa.Column("override_at", sa.DateTime(), nullable=True),
        sa.Column("override_note", sa.Text(), nullable=True),
        sa.Column("alerted_at", sa.DateTime(), nullable=True),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("updated_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["car_id"], ["car.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(
            ["revision_id"], ["car_revision.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(["seller_id"], ["user.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("public_id"),
        sa.UniqueConstraint(
            "subject_key", "content_token", "mode", name="uq_lmr_subject_token_mode"
        ),
    )
    op.create_index("ix_lmr_car_id", "listing_moderation_run", ["car_id"])
    op.create_index(
        "ix_lmr_decision_created",
        "listing_moderation_run",
        ["decision", "created_at"],
    )
    op.create_index(
        "ix_lmr_status_retry", "listing_moderation_run", ["status", "next_retry_at"]
    )
    op.create_index("ix_lmr_subject_key", "listing_moderation_run", ["subject_key"])

    op.create_table(
        "listing_moderation_event",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("run_id", sa.Integer(), nullable=True),
        sa.Column("car_id", sa.Integer(), nullable=True),
        sa.Column("car_public_id", sa.String(length=50), nullable=True),
        sa.Column("event_type", sa.String(length=40), nullable=False),
        sa.Column(
            "actor", sa.String(length=100), nullable=False, server_default="system"
        ),
        sa.Column("data", sa.JSON(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(
            ["run_id"], ["listing_moderation_run.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["car_id"], ["car.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_lme_run_id", "listing_moderation_event", ["run_id"])
    op.create_index(
        "ix_lme_car_created", "listing_moderation_event", ["car_id", "created_at"]
    )


def downgrade() -> None:
    op.drop_index("ix_lme_car_created", table_name="listing_moderation_event")
    op.drop_index("ix_lme_run_id", table_name="listing_moderation_event")
    op.drop_table("listing_moderation_event")
    op.drop_index("ix_lmr_subject_key", table_name="listing_moderation_run")
    op.drop_index("ix_lmr_status_retry", table_name="listing_moderation_run")
    op.drop_index("ix_lmr_decision_created", table_name="listing_moderation_run")
    op.drop_index("ix_lmr_car_id", table_name="listing_moderation_run")
    op.drop_table("listing_moderation_run")
