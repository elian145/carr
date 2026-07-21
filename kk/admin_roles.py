"""Admin role helpers and permission checks."""

from __future__ import annotations

from functools import wraps

from flask import jsonify

from .auth import get_current_user

ROLE_SUPER_ADMIN = "super_admin"
ROLE_MODERATOR = "moderator"
ROLE_SUPPORT = "support"
ROLE_MARKETING = "marketing"

VALID_ROLES = (
    ROLE_SUPER_ADMIN,
    ROLE_MODERATOR,
    ROLE_SUPPORT,
    ROLE_MARKETING,
)

# permission -> roles allowed (super_admin always implied via user_has_permission)
# PII-heavy reads (users, messages, search, saved searches) are limited to
# super_admin + moderator — support/marketing must not browse phone/email/chat.
_PERMISSIONS: dict[str, frozenset[str]] = {
    "dashboard": frozenset(VALID_ROLES),
    "search": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR}),
    "insights": frozenset(VALID_ROLES),
    "analytics": frozenset(VALID_ROLES),
    "users.read": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR}),
    "users.write": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR, ROLE_SUPPORT}),
    "users.role": frozenset({ROLE_SUPER_ADMIN}),
    "listings.read": frozenset(VALID_ROLES),
    "listings.write": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR}),
    "listings.delete": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR}),
    "reports": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR, ROLE_SUPPORT}),
    "dealers": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR}),
    "messages": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR}),
    "notifications.read": frozenset(VALID_ROLES),
    "notifications.broadcast": frozenset({ROLE_SUPER_ADMIN, ROLE_MARKETING}),
    "saved_searches": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR}),
    "audit": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR}),
    "system": frozenset({ROLE_SUPER_ADMIN}),
    "settings": frozenset({ROLE_SUPER_ADMIN}),
    "catalog.read": frozenset(VALID_ROLES),
    "catalog.write": frozenset({ROLE_SUPER_ADMIN, ROLE_MODERATOR}),
    "purge": frozenset({ROLE_SUPER_ADMIN}),
}


def normalize_admin_role(user) -> str | None:
    """Return effective role for an admin user (legacy admins → super_admin)."""
    if not user or not getattr(user, "is_admin", False):
        return None
    raw = (getattr(user, "admin_role", None) or "").strip().lower()
    if raw in VALID_ROLES:
        return raw
    return ROLE_SUPER_ADMIN


def user_has_permission(user, permission: str) -> bool:
    role = normalize_admin_role(user)
    if not role:
        return False
    if role == ROLE_SUPER_ADMIN:
        return True
    allowed = _PERMISSIONS.get(permission)
    if not allowed:
        return False
    return role in allowed


def permissions_for_role(role: str | None) -> list[str]:
    effective = role if role in VALID_ROLES else ROLE_SUPER_ADMIN
    if effective == ROLE_SUPER_ADMIN:
        return sorted(_PERMISSIONS.keys())
    return sorted(p for p, roles in _PERMISSIONS.items() if effective in roles)


def require_admin_permission(permission: str):
    """Decorator: require is_admin + specific permission."""

    def decorator(f):
        @wraps(f)
        def wrapped(*args, **kwargs):
            user = get_current_user()
            if not user or not user.is_admin:
                return jsonify({"message": "Admin privileges required"}), 403
            if not user_has_permission(user, permission):
                return jsonify({"message": f"Missing permission: {permission}"}), 403
            return f(*args, **kwargs)

        # Preserve jwt from admin_required by composing: routes use @admin_required then this,
        # OR we stack jwt here. Callers should use @admin_required @require_admin_permission.
        return wrapped

    return decorator


def assert_permission(permission: str):
    """Return (None, response_tuple) if denied, else (user, None)."""
    user = get_current_user()
    if not user or not user.is_admin:
        return None, (jsonify({"message": "Admin privileges required"}), 403)
    if not user_has_permission(user, permission):
        return None, (jsonify({"message": f"Missing permission: {permission}"}), 403)
    return user, None
