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
_last_send_error: BaseException | None = None
_oauth_checked = False
_oauth_ok = False


def _service_account_oauth_ok() -> bool:
    """True when FIREBASE_SERVICE_ACCOUNT can obtain a Google OAuth token."""
    global _oauth_checked, _oauth_ok
    if _oauth_checked:
        return _oauth_ok
    _oauth_checked = True

    creds_json = (os.environ.get("FIREBASE_SERVICE_ACCOUNT") or "").strip()
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
    creds_json = (os.environ.get("FIREBASE_SERVICE_ACCOUNT") or "").strip()
    creds_path = (os.environ.get("GOOGLE_APPLICATION_CREDENTIALS") or "").strip()
    project_id = None
    json_ok = False
    if creds_json:
        try:
            project_id = json.loads(creds_json).get("project_id")
            json_ok = True
        except json.JSONDecodeError:
            json_ok = False
    elif creds_path:
        json_ok = True
    oauth_ok = _service_account_oauth_ok() if creds_json else None
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
        "credentials_present": bool(creds_json or creds_path),
        "credentials_json_valid": json_ok if creds_json else None,
        "firebase_project": project_id,
    }


def log_fcm_startup_status() -> None:
    """Log push readiness once at app startup (Render logs)."""
    status = fcm_public_status()
    if not status["credentials_present"]:
        logger.warning(
            "Push disabled: set FIREBASE_SERVICE_ACCOUNT on Render (minified JSON, one line)."
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
                "new private key, then set FIREBASE_SERVICE_ACCOUNT using "
                "scripts/format_firebase_service_account_json.py (do not edit private_key by hand)."
            )
        return (
            "Firebase cannot reach Apple (APNs). In Firebase Console → carzo-prod → "
            "Cloud Messaging → com.carzo.app: delete and re-upload your APNs .p8 key "
            "(Team LN3R46L4H8). Also enable Firebase Cloud Messaging API in Google Cloud."
        )
    return (
        "FCM send failed. Check Render FIREBASE_SERVICE_ACCOUNT, Firebase APNs .p8, and re-login on device."
    )
