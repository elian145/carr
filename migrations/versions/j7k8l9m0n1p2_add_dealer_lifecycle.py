"""add dealer application lifecycle

Revision ID: j7k8l9m0n1p2
Revises: q6r7s8t9u0v1
Create Date: 2026-07-18
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa


revision = "j7k8l9m0n1p2"
down_revision = "q6r7s8t9u0v1"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "dealer_application",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("public_id", sa.String(length=50), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("dealership_name", sa.String(length=120), nullable=False),
        sa.Column("dealership_phone", sa.String(length=20), nullable=False),
        sa.Column("dealership_phones", sa.JSON(), nullable=True),
        sa.Column("dealership_location", sa.String(length=200), nullable=False),
        sa.Column("dealership_description", sa.Text(), nullable=True),
        sa.Column("business_registration_number", sa.String(length=120), nullable=True),
        sa.Column("document_urls", sa.JSON(), nullable=True),
        sa.Column("review_reason", sa.Text(), nullable=True),
        sa.Column("submitted_at", sa.DateTime(), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("public_id"),
        sa.UniqueConstraint("user_id"),
    )
    op.create_index(
        "ix_dealer_application_status", "dealer_application", ["status"], unique=False
    )

    op.create_table(
        "dealer_profile",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("public_id", sa.String(length=50), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("dealership_name", sa.String(length=120), nullable=False),
        sa.Column("dealership_phone", sa.String(length=20), nullable=False),
        sa.Column("dealership_phones", sa.JSON(), nullable=True),
        sa.Column("dealership_location", sa.String(length=200), nullable=False),
        sa.Column("dealership_description", sa.Text(), nullable=True),
        sa.Column("dealership_cover_picture", sa.String(length=200), nullable=True),
        sa.Column("dealership_latitude", sa.Float(), nullable=True),
        sa.Column("dealership_longitude", sa.Float(), nullable=True),
        sa.Column("dealership_opening_hours", sa.JSON(), nullable=True),
        sa.Column(
            "is_featured", sa.Boolean(), nullable=False, server_default=sa.false()
        ),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("public_id"),
        sa.UniqueConstraint("user_id"),
    )

    op.create_table(
        "dealer_decision",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("public_id", sa.String(length=50), nullable=False),
        sa.Column("application_id", sa.Integer(), nullable=False),
        sa.Column("reviewer_id", sa.Integer(), nullable=True),
        sa.Column("decision", sa.String(length=20), nullable=False),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("application_snapshot", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["application_id"], ["dealer_application.id"]),
        sa.ForeignKeyConstraint(["reviewer_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("public_id"),
    )
    op.create_index(
        "ix_dealer_decision_application_id",
        "dealer_decision",
        ["application_id"],
        unique=False,
    )
    op.create_index(
        "ix_dealer_decision_created_at",
        "dealer_decision",
        ["created_at"],
        unique=False,
    )

    # Preserve every existing dealer application/account during rollout.
    conn = op.get_bind()
    user = sa.table(
        "user",
        sa.column("id", sa.Integer()),
        sa.column("public_id", sa.String()),
        sa.column("account_type", sa.String()),
        sa.column("dealer_status", sa.String()),
        sa.column("dealership_name", sa.String()),
        sa.column("dealership_phone", sa.String()),
        sa.column("dealership_phones", sa.JSON()),
        sa.column("dealership_location", sa.String()),
        sa.column("dealership_description", sa.Text()),
        sa.column("dealership_cover_picture", sa.String()),
        sa.column("dealership_latitude", sa.Float()),
        sa.column("dealership_longitude", sa.Float()),
        sa.column("dealership_opening_hours", sa.JSON()),
        sa.column("is_featured_dealer", sa.Boolean()),
        sa.column("created_at", sa.DateTime()),
        sa.column("updated_at", sa.DateTime()),
    )
    rows = conn.execute(
        sa.select(user).where(
            sa.or_(user.c.account_type == "dealer", user.c.dealer_status != "none")
        )
    ).mappings()
    application_table = sa.table(
        "dealer_application",
        sa.column("public_id"),
        sa.column("user_id"),
        sa.column("status"),
        sa.column("dealership_name"),
        sa.column("dealership_phone"),
        sa.column("dealership_phones"),
        sa.column("dealership_location"),
        sa.column("dealership_description"),
        sa.column("submitted_at"),
        sa.column("reviewed_at"),
        sa.column("created_at"),
        sa.column("updated_at"),
    )
    profile_table = sa.table(
        "dealer_profile",
        sa.column("public_id"),
        sa.column("user_id"),
        sa.column("dealership_name"),
        sa.column("dealership_phone"),
        sa.column("dealership_phones"),
        sa.column("dealership_location"),
        sa.column("dealership_description"),
        sa.column("dealership_cover_picture"),
        sa.column("dealership_latitude"),
        sa.column("dealership_longitude"),
        sa.column("dealership_opening_hours"),
        sa.column("is_featured"),
        sa.column("created_at"),
        sa.column("updated_at"),
    )
    import uuid
    from datetime import datetime

    now = datetime.utcnow()
    for row in rows:
        legacy_status = row["dealer_status"] or "none"
        if row["account_type"] == "dealer" or legacy_status == "approved":
            status = "approved"
        elif legacy_status == "rejected":
            status = "rejected"
        else:
            # Historical applications only had a generic pending state. Treat
            # any other inconsistent non-personal row as submitted for review.
            status = "submitted"
        created_at = row["created_at"] or now
        updated_at = row["updated_at"] or created_at
        conn.execute(
            application_table.insert().values(
                public_id=str(uuid.uuid4()),
                user_id=row["id"],
                status=status,
                dealership_name=row["dealership_name"] or "Dealership",
                dealership_phone=row["dealership_phone"] or "Not provided",
                dealership_phones=row["dealership_phones"],
                dealership_location=row["dealership_location"] or "Not provided",
                dealership_description=row["dealership_description"],
                submitted_at=created_at,
                reviewed_at=updated_at if status in ("approved", "rejected") else None,
                created_at=created_at,
                updated_at=updated_at,
            )
        )
        if status == "approved":
            conn.execute(
                profile_table.insert().values(
                    public_id=str(uuid.uuid4()),
                    user_id=row["id"],
                    dealership_name=row["dealership_name"] or "Dealership",
                    dealership_phone=row["dealership_phone"] or "Not provided",
                    dealership_phones=row["dealership_phones"],
                    dealership_location=row["dealership_location"] or "Not provided",
                    dealership_description=row["dealership_description"],
                    dealership_cover_picture=row["dealership_cover_picture"],
                    dealership_latitude=row["dealership_latitude"],
                    dealership_longitude=row["dealership_longitude"],
                    dealership_opening_hours=row["dealership_opening_hours"],
                    is_featured=bool(row["is_featured_dealer"]),
                    created_at=created_at,
                    updated_at=updated_at,
                )
            )


def downgrade():
    op.drop_index("ix_dealer_decision_created_at", table_name="dealer_decision")
    op.drop_index("ix_dealer_decision_application_id", table_name="dealer_decision")
    op.drop_table("dealer_decision")
    op.drop_table("dealer_profile")
    op.drop_index("ix_dealer_application_status", table_name="dealer_application")
    op.drop_table("dealer_application")
