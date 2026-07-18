"""Provision dashboard identities that survive deletion of mobile accounts."""

from __future__ import annotations

import secrets
import uuid

from sqlalchemy import or_

from .models import AdminAccount, User, db


def ensure_detached_admin_account(source_user: User) -> AdminAccount:
    """Create an independent dashboard login and its admin-only principal."""
    existing = AdminAccount.query.filter_by(
        origin_user_public_id=source_user.public_id,
    ).first()
    if not existing:
        identity_matches = [AdminAccount.username == source_user.username]
        if source_user.email:
            identity_matches.append(AdminAccount.email == source_user.email)
        if source_user.phone_number:
            identity_matches.append(AdminAccount.phone_number == source_user.phone_number)
        existing = AdminAccount.query.filter(or_(*identity_matches)).first()
    if existing:
        existing.origin_user_public_id = source_user.public_id
        existing.is_active = True
        existing.admin_role = source_user.admin_role or existing.admin_role or "super_admin"
        existing.principal.is_active = True
        existing.principal.is_admin = True
        existing.principal.admin_role = existing.admin_role
        return existing

    suffix = secrets.token_hex(4)
    principal = User(
        public_id=str(uuid.uuid4()),
        username=f"dashboard_admin_{source_user.id}_{suffix}",
        phone_number=f"adm_{source_user.id}_{suffix}"[:20],
        email=None,
        first_name=source_user.first_name or "Dashboard",
        last_name=source_user.last_name or "Admin",
        is_active=True,
        is_verified=True,
        is_admin=True,
        admin_role=source_user.admin_role or "super_admin",
        account_type="user",
        dealer_status="none",
    )
    copied_hash = source_user.password_hash or source_user.password
    if copied_hash:
        principal.password_hash = copied_hash
        principal.password = copied_hash
    else:
        principal.set_password(secrets.token_urlsafe(32))

    db.session.add(principal)
    db.session.flush()

    account = AdminAccount(
        principal_user_id=principal.id,
        origin_user_public_id=source_user.public_id,
        username=source_user.username,
        email=source_user.email,
        phone_number=source_user.phone_number,
        password_hash=copied_hash or principal.password_hash,
        is_active=True,
        admin_role=source_user.admin_role or "super_admin",
    )
    db.session.add(account)
    db.session.flush()
    return account
