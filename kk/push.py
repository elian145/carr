"""
Push notification utilities (FCM via firebase-admin).

Supports two ways to provide the service account credentials:
    1. GOOGLE_APPLICATION_CREDENTIALS env var pointing to a JSON file path.
    2. FIREBASE_SERVICE_ACCOUNT env var containing the raw JSON string
       (useful on PaaS like Render where the filesystem is ephemeral).

Falls back to a no-op when firebase-admin is not installed or credentials are absent.
"""
from __future__ import annotations

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

_firebase_app = None
_init_attempted = False


def _ensure_firebase():
    """Lazy-init Firebase Admin SDK (once)."""
    global _firebase_app, _init_attempted
    if _init_attempted:
        return _firebase_app
    _init_attempted = True

    creds_path = (os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or "").strip()
    creds_json = (os.environ.get("FIREBASE_SERVICE_ACCOUNT") or "").strip()

    if not creds_path and not creds_json:
        logger.info("FCM disabled: neither GOOGLE_APPLICATION_CREDENTIALS nor FIREBASE_SERVICE_ACCOUNT is set.")
        return None

    try:
        import firebase_admin  # type: ignore
        from firebase_admin import credentials  # type: ignore

        if creds_json:
            cred = credentials.Certificate(json.loads(creds_json))
        else:
            cred = credentials.Certificate(creds_path)

        _firebase_app = firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin SDK initialised for push notifications.")
        return _firebase_app
    except Exception as exc:
        logger.warning("Firebase Admin SDK init failed: %s", exc)
        return None


def send_push(token: str, *, title: str, body: str, data: dict | None = None) -> bool:
    """Send an FCM push notification to a single device token.

    Returns True on success, False on failure or when FCM is not configured.
    """
    app = _ensure_firebase()
    if app is None:
        return False

    try:
        from firebase_admin import messaging  # type: ignore

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=token,
        )
        messaging.send(message, app=app)
        return True
    except Exception as exc:
        logger.warning("FCM send failed (token=%s…): %s", token[:12] if token else "?", exc)
        return False
