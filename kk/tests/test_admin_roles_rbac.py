"""Unit tests for admin RBAC permission matrix (M-09)."""

from __future__ import annotations

from types import SimpleNamespace

from kk.admin_roles import (
    ROLE_MARKETING,
    ROLE_MODERATOR,
    ROLE_SUPER_ADMIN,
    ROLE_SUPPORT,
    normalize_admin_role,
    permissions_for_role,
    user_has_permission,
)


def _user(role: str | None, *, is_admin: bool = True):
    return SimpleNamespace(is_admin=is_admin, admin_role=role)


def test_support_cannot_read_user_pii_or_messages():
    support = _user(ROLE_SUPPORT)
    assert user_has_permission(support, "reports") is True
    assert user_has_permission(support, "users.write") is True
    assert user_has_permission(support, "dashboard") is True

    assert user_has_permission(support, "users.read") is False
    assert user_has_permission(support, "messages") is False
    assert user_has_permission(support, "search") is False
    assert user_has_permission(support, "saved_searches") is False
    assert user_has_permission(support, "dealers") is False
    assert user_has_permission(support, "audit") is False


def test_marketing_cannot_read_user_pii_or_messages():
    marketing = _user(ROLE_MARKETING)
    assert user_has_permission(marketing, "notifications.broadcast") is True
    assert user_has_permission(marketing, "users.read") is False
    assert user_has_permission(marketing, "messages") is False
    assert user_has_permission(marketing, "search") is False


def test_moderator_can_read_users_and_messages():
    moderator = _user(ROLE_MODERATOR)
    assert user_has_permission(moderator, "users.read") is True
    assert user_has_permission(moderator, "messages") is True
    assert user_has_permission(moderator, "search") is True
    assert user_has_permission(moderator, "users.role") is False
    assert user_has_permission(moderator, "settings") is False


def test_super_admin_has_all_permissions():
    admin = _user(ROLE_SUPER_ADMIN)
    for perm in permissions_for_role(ROLE_SUPER_ADMIN):
        assert user_has_permission(admin, perm) is True


def test_legacy_admin_without_role_is_super_admin():
    legacy = _user(None)
    assert normalize_admin_role(legacy) == ROLE_SUPER_ADMIN
    assert user_has_permission(legacy, "users.read") is True
    assert user_has_permission(legacy, "settings") is True


def test_non_admin_has_no_permissions():
    user = _user(ROLE_SUPPORT, is_admin=False)
    assert normalize_admin_role(user) is None
    assert user_has_permission(user, "dashboard") is False
