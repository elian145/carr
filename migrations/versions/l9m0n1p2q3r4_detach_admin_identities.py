"""detach dashboard identities from mobile accounts

Revision ID: l9m0n1p2q3r4
Revises: k8l9m0n1p2q3
Create Date: 2026-07-19
"""

from __future__ import annotations

from datetime import datetime, timezone
import uuid

from alembic import op
import sqlalchemy as sa


revision = "l9m0n1p2q3r4"
down_revision = "k8l9m0n1p2q3"
branch_labels = None
depends_on = None


def _has_table(conn, name: str) -> bool:
    try:
        return bool(sa.inspect(conn).has_table(name))
    except Exception:
        return False


def upgrade() -> None:
    conn = op.get_bind()
    if not _has_table(conn, "admin_account"):
        op.create_table(
            "admin_account",
            sa.Column("id", sa.Integer(), nullable=False),
            sa.Column("public_id", sa.String(length=50), nullable=False),
            sa.Column("principal_user_id", sa.Integer(), nullable=False),
            sa.Column("origin_user_public_id", sa.String(length=50), nullable=True),
            sa.Column("username", sa.String(length=80), nullable=False),
            sa.Column("email", sa.String(length=120), nullable=True),
            sa.Column("phone_number", sa.String(length=20), nullable=True),
            sa.Column("password_hash", sa.String(length=128), nullable=False),
            sa.Column("is_active", sa.Boolean(), nullable=False),
            sa.Column("admin_role", sa.String(length=32), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=False),
            sa.Column("updated_at", sa.DateTime(), nullable=False),
            sa.Column("last_login", sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(
                ["principal_user_id"],
                ["user.id"],
                ondelete="RESTRICT",
            ),
            sa.PrimaryKeyConstraint("id"),
            sa.UniqueConstraint("principal_user_id"),
            sa.UniqueConstraint("public_id"),
        )
        op.create_index("ix_admin_account_email", "admin_account", ["email"], unique=True)
        op.create_index(
            "ix_admin_account_origin_user_public_id",
            "admin_account",
            ["origin_user_public_id"],
            unique=False,
        )
        op.create_index(
            "ix_admin_account_phone_number",
            "admin_account",
            ["phone_number"],
            unique=True,
        )
        op.create_index("ix_admin_account_username", "admin_account", ["username"], unique=True)

    metadata = sa.MetaData()
    user_table = sa.Table("user", metadata, autoload_with=conn)
    admin_table = sa.Table("admin_account", metadata, autoload_with=conn)
    now = datetime.now(timezone.utc).replace(tzinfo=None)

    legacy_admins = conn.execute(
        sa.select(user_table).where(user_table.c.is_admin.is_(True))
    ).mappings()
    for source in legacy_admins:
        already_migrated = conn.execute(
            sa.select(admin_table.c.id).where(
                admin_table.c.origin_user_public_id == source["public_id"]
            )
        ).first()
        if already_migrated:
            continue

        suffix = uuid.uuid4().hex[:8]
        copied_hash = source.get("password_hash") or source.get("password")
        if not copied_hash:
            continue

        principal_values = {
            "public_id": str(uuid.uuid4()),
            "username": f"dashboard_admin_{source['id']}_{suffix}",
            "email": None,
            "password": copied_hash,
            "password_hash": copied_hash,
            "phone_number": f"adm_{source['id']}_{suffix}"[:20],
            "first_name": source.get("first_name") or "Dashboard",
            "last_name": source.get("last_name") or "Admin",
            "is_verified": True,
            "is_active": True,
            "is_admin": True,
            "admin_role": source.get("admin_role") or "super_admin",
            "account_type": "user",
            "dealer_status": "none",
            "is_featured_dealer": False,
            "created_at": now,
            "updated_at": now,
        }
        principal_values = {
            key: value
            for key, value in principal_values.items()
            if key in user_table.c
        }
        result = conn.execute(user_table.insert().values(**principal_values))
        principal_id = result.inserted_primary_key[0]

        conn.execute(
            admin_table.insert().values(
                public_id=str(uuid.uuid4()),
                principal_user_id=principal_id,
                origin_user_public_id=source["public_id"],
                username=source["username"],
                email=source.get("email"),
                phone_number=source.get("phone_number"),
                password_hash=copied_hash,
                is_active=True,
                admin_role=source.get("admin_role") or "super_admin",
                created_at=now,
                updated_at=now,
            )
        )


def downgrade() -> None:
    conn = op.get_bind()
    if not _has_table(conn, "admin_account"):
        return

    principal_ids = [
        row[0]
        for row in conn.execute(sa.text("SELECT principal_user_id FROM admin_account"))
    ]
    op.drop_table("admin_account")
    if principal_ids:
        user_table = sa.Table("user", sa.MetaData(), autoload_with=conn)
        conn.execute(user_table.delete().where(user_table.c.id.in_(principal_ids)))
