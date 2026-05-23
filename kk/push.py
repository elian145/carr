"""
Push notification utilities (FCM via firebase-admin).

Supports service account credentials via:
    1. GOOGLE_APPLICATION_CREDENTIALS — path to JSON (Render Secret File works).
    2. FIREBASE_SERVICE_ACCOUNT — raw JSON string (one line).
    3. FIREBASE_SERVICE_ACCOUNT_BASE64 — base64(JSON) one line (best for Render UI paste).

Falls back to a no-op when firebase-admin is not installed or credentials are absent.
"""
from __future__ import annotations

import base64
import json
import logging
import os
import tempfile
from pathlib import Path

logger = logging.getLogger(__name__)

_firebase_app = None
_init_attempted = False
_last_send_error: BaseException | None = None
_oauth_checked = False
_oauth_ok = False


def _load_service_account_json() -> str | None:
    """Load Firebase service account JSON from env (raw, base64, or file path)."""
    b64 = (os.environ.get("FIREBASE_SERVICE_ACCOUNT_BASE64") or "").strip()
    if b64:
        try:
            return base64.b64decode(b64).decode("utf-8")
        except Exception as exc:
            logger.error("FIREBASE_SERVICE_ACCOUNT_BASE64 decode failed: %s", exc)
            return None

    raw = (os.environ.get("FIREBASE_SERVICE_ACCOUNT") or "").strip()
    if raw:
        return raw

    path = (os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or "").strip()
    if path and os.path.isfile(path):
        try:
            return Path(path).read_text(encoding="utf-8")
        except Exception as exc:
            logger.error("GOOGLE_APPLICATION_CREDENTIALS read failed (%s): %s", path, exc)
            return None

    return None


def _credentials_configured() -> bool:
    if (os.environ.get("FIREBASE_SERVICE_ACCOUNT_BASE64") or "").strip():
        return True
    if (os.environ.get("FIREBASE_SERVICE_ACCOUNT") or "").strip():
        return True
    path = (os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or "").strip()
    return bool(path and os.path.isfile(path))


def _service_account_oauth_ok() -> bool:
    """True when service account JSON can obtain a Google OAuth token."""
    global _oauth_checked, _oauth_ok
    if _oauth_checked:
        return _oauth_ok
    _oauth_checked = True

    creds_json = _load_service_account_json()
    if not creds_json:
        _oauth_ok = False
        return False

    try:
        info = json.loads(creds_json)
        pk = str(info.get("private_key") or "")
        if "BEGIN PRIVATE KEY" not in pk:
            logger.error(
                "FIREBASE_SERVICE_ACCOUNT: private_key missing PEM header — "
                "re-paste JSON using scripts/format_firebase_service_account_json.py"
            )
            _oauth_ok = False
            return False

        from google.oauth2 import service_account  # type: ignore
        from google.auth.transport.requests import Request  # type: ignore

        creds = service_account.Credentials.from_service_account_info(
            info,
            scopes=[
                "https://www.googleapis.com/auth/firebase.messaging",
                "https://www.googleapis.com/auth/cloud-platform",
            ],
        )
        creds.refresh(Request())
        _oauth_ok = bool(creds.token)
        if not _oauth_ok:
            logger.error("FIREBASE_SERVICE_ACCOUNT: OAuth refresh returned no access token")
        return _oauth_ok
    except json.JSONDecodeError as exc:
        logger.error("FIREBASE_SERVICE_ACCOUNT is not valid JSON: %s", exc)
        _oauth_ok = False
        return False
    except Exception as exc:
        logger.error(
            "FIREBASE_SERVICE_ACCOUNT OAuth failed (re-download key from Firebase, "
            "format with scripts/format_firebase_service_account_json.py): %s",
            exc,
        )
        _oauth_ok = False
        return False


def fcm_is_configured() -> bool:
    """True when Firebase Admin SDK is available and credentials can authenticate."""
    if _ensure_firebase() is None:
        return False
    return _service_account_oauth_ok()


def fcm_public_status() -> dict:
    """Safe status for /health/push (no secrets)."""
    creds_json = _load_service_account_json()
    project_id = None
    json_ok = False
    if creds_json:
        try:
            project_id = json.loads(creds_json).get("project_id")
            json_ok = True
        except json.JSONDecodeError:
            json_ok = False
    oauth_ok = _service_account_oauth_ok() if _credentials_configured() else None
    ready = fcm_is_configured()
    if ready and project_id is None:
        try:
            import firebase_admin  # type: ignore

            project_id = firebase_admin.get_app().project_id
        except Exception:
            pass
    return {
        "fcm_ready": ready,
        "credentials_oauth_ok": oauth_ok,
        "credentials_present": _credentials_configured(),
        "credentials_source": (
            "base64"
            if (os.environ.get("FIREBASE_SERVICE_ACCOUNT_BASE64") or "").strip()
            else "json"
            if (os.environ.get("FIREBASE_SERVICE_ACCOUNT") or "").strip()
            else "file"
            if (os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or "").strip()
            else None
        ),
        "credentials_json_valid": json_ok if creds_json else None,
        "firebase_project": project_id,
    }


def log_fcm_startup_status() -> None:
    """Log push readiness once at app startup (Render logs)."""
    status = fcm_public_status()
    if not status["credentials_present"]:
        logger.warning(
            "Push disabled: set FIREBASE_SERVICE_ACCOUNT_BASE64, FIREBASE_SERVICE_ACCOUNT, "
            "or GOOGLE_APPLICATION_CREDENTIALS on Render."
        )
        return
    if status.get("credentials_json_valid") is False:
        logger.error(
            "Push disabled: FIREBASE_SERVICE_ACCOUNT is not valid JSON — re-paste from Firebase."
        )
        return
    if status["fcm_ready"]:
        logger.info("Push ready: FCM configured for project %s", status.get("firebase_project"))
    elif status.get("credentials_oauth_ok") is False:
        logger.error(
            "Push disabled: FIREBASE_SERVICE_ACCOUNT cannot authenticate — "
            "re-paste JSON using scripts/format_firebase_service_account_json.py"
        )
    else:
        logger.warning(
            "Push disabled: credentials present but firebase-admin init failed (see warnings above)."
        )


def _ensure_firebase():
    """Lazy-init Firebase Admin SDK (once)."""
    global _firebase_app, _init_attempted
    if _init_attempted:
        return _firebase_app
    _init_attempted = True

    creds_json = _load_service_account_json()

    if not creds_json:
        logger.info(
            "FCM disabled: set FIREBASE_SERVICE_ACCOUNT_BASE64, FIREBASE_SERVICE_ACCOUNT, "
            "or GOOGLE_APPLICATION_CREDENTIALS."
        )
        return None

    try:
        import firebase_admin  # type: ignore
        from firebase_admin import credentials  # type: ignore

        cred = credentials.Certificate(json.loads(creds_json))

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
    global _last_send_error
    _last_send_error = None
    app = _ensure_firebase()
    if app is None:
        return False

    try:
        from firebase_admin import messaging  # type: ignore

        data_payload = {k: str(v) for k, v in (data or {}).items()}
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data=data_payload,
            token=token,
            android=messaging.AndroidConfig(priority="high"),
            apns=messaging.APNSConfig(
                headers={
                    "apns-priority": "10",
                    "apns-push-type": "alert",
                },
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        alert=messaging.ApsAlert(title=title, body=body),
                        sound="default",
                    ),
                ),
            ),
        )
        messaging.send(message, app=app)
        return True
    except Exception as exc:
        _last_send_error = exc
        exc_name = type(exc).__name__
        if exc_name == "ThirdPartyAuthError":
            logger.warning(
                "FCM/APNs auth failed (token=%s…): %s. "
                "Re-upload the APNs .p8 key in Firebase → Project settings → Cloud Messaging → "
                "iOS app com.carzo.app (Key ID + Team ID LN3R46L4H8 must match Apple Developer).",
                token[:12] if token else "?",
                exc,
            )
        else:
            logger.warning(
                "FCM send failed (token=%s…): %s: %s",
                token[:12] if token else "?",
                exc_name,
                exc,
            )
        return False


def last_fcm_send_error() -> BaseException | None:
    return _last_send_error


def fcm_send_error_hint(exc: BaseException | None = None) -> str:
    """User-facing hint when send_push fails."""
    name = type(exc).__name__ if exc else ""
    if name == "ThirdPartyAuthError":
        if not _service_account_oauth_ok():
            return (
                "Server Firebase credentials are invalid on Render. Download a new service "
                "account JSON from Firebase → Project settings → Service accounts → Generate "
                "new private key, then set FIREBASE_SERVICE_ACCOUNT_BASE64 on Render "
                "(see scripts/format_firebase_service_account_json.py)."
            )
        return (
            "Firebase cannot reach Apple (APNs). In Firebase Console → carzo-prod → "
            "Cloud Messaging → com.carzo.app: delete and re-upload your APNs .p8 key "
            "(Team LN3R46L4H8). Also enable Firebase Cloud Messaging API in Google Cloud."
        )
    return (
        "FCM send failed. Check Render FIREBASE_SERVICE_ACCOUNT, Firebase APNs .p8, and re-login on device."
    )
