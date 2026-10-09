"""Shared helpers for ADM-1 / AdminAccount-principal test setup."""

from __future__ import annotations


def attach_admin_account(db, user, *, password: str, username: str | None = None):
    """Link an active AdminAccount principal to ``user`` (must already be is_admin)."""
    from kk.models import AdminAccount

    acct = AdminAccount(
        principal_user_id=user.id,
        username=username or f"dash_{user.username}",
        is_active=True,
    )
    acct.set_password(password)
    db.session.add(acct)
    db.session.commit()
    return acct


def login_with_admin_scope(client, username: str, password: str) -> str:
    """Dashboard AdminAccount password login; returns access_token."""
    response = client.post(
        "/api/auth/login",
        json={
            "username": username,
            "password": password,
            "account_scope": "admin",
        },
    )
    assert response.status_code == 200, response.data
    return response.get_json()["access_token"]


def login_preferring_admin_scope(client, username: str, password: str) -> str:
    """Try AdminAccount login first; fall back to ordinary mobile password login."""
    response = client.post(
        "/api/auth/login",
        json={
            "username": username,
            "password": password,
            "account_scope": "admin",
        },
    )
    if response.status_code != 200:
        response = client.post(
            "/api/auth/login",
            json={"username": username, "password": password},
        )
    assert response.status_code == 200, response.data
    return response.get_json()["access_token"]
