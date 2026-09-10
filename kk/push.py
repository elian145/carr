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


def _fcm_permanent_token_error_types() -> tuple[type, ...]:
    """The real firebase-admin SDK exception classes that mean "this exact
    token is permanently, definitively invalid" (BE-05).

    Lazily imported and fail-closed: if firebase-admin can't be imported for
    any reason, this returns an empty tuple, so ``_is_permanent_token_error``
    below returns False and no token is ever cleared. Deliberately narrow --
    ``QuotaExceededError`` (transient/rate-limit), ``ThirdPartyAuthError``
    (server APNs/credential misconfiguration, not a token problem), network
    errors, and any unrecognized/future exception type are all excluded on
    purpose.
    """
    try:
        from firebase_admin import messaging  # type: ignore

        return (messaging.UnregisteredError, messaging.SenderIdMismatchError)
    except Exception:
        return ()


def _is_permanent_token_error(exc: BaseException) -> bool:
    """True only for FCM's own definitive permanent invalid-token errors."""
    types_ = _fcm_permanent_token_error_types()
    return bool(types_) and isinstance(exc, types_)


def _is_third_party_auth_error(exc: BaseException) -> bool:
    """True for the existing APNs/credential-misconfiguration error class
    (unrelated to any single token; every send may fail until the server's
    Firebase credentials/APNs key are fixed)."""
    try:
        from firebase_admin import messaging  # type: ignore

        return isinstance(exc, messaging.ThirdPartyAuthError)
    except Exception:
        return False


def _clear_invalidated_token(user_id: int, token: str) -> None:
    """BE-05: race-safe cleanup for a permanently invalid FCM token.

    Uses a single conditional ``UPDATE user SET firebase_token = NULL
    WHERE id = :user_id AND firebase_token = :token`` -- clearing the token
    ONLY if it still holds the exact value that FCM just rejected. If the
    user has since logged out, refreshed to a new token, or otherwise
    changed it, this affects 0 rows and is a safe no-op: the newer token is
    never touched.

    Runs on a short-lived, independent database connection/transaction of
    its own (``db.engine.begin()``), not the caller's ``db.session``. This
    is deliberate: callers like ``execute_broadcast()`` may have other,
    unrelated, not-yet-committed work pending on their own session (e.g.
    ``Notification`` rows queued earlier in a batched commit loop), and a
    failure/rollback here must never be able to touch that unrelated work.
    A cleanup failure is logged and swallowed -- it must never break the
    surrounding push/broadcast flow.
    """
    try:
        from sqlalchemy import update as sql_update

        from .models import User, db

        stmt = (
            sql_update(User)
            .where(User.id == user_id, User.firebase_token == token)
            .values(firebase_token=None)
        )
        engine = db.session.get_bind()
        with engine.begin() as connection:
            result = connection.execute(stmt)
        cleared = bool(result.rowcount)
    except Exception:
        logger.exception(
            "BE-05: failed to clear permanently invalidated FCM token for user_id=%s",
            user_id,
        )
        return

    if cleared:
        logger.info(
            "BE-05: permanently invalid FCM token cleared for user_id=%s (prefix %s…)",
            user_id,
            token[:12] if token else "?",
        )
    else:
        logger.info(
            "BE-05: permanently-invalid FCM token for user_id=%s already changed/cleared; no-op",
            user_id,
        )


def send_push(
    token: str,
    *,
    title: str,
    body: str,
    data: dict | None = None,
    user_id: int | None = None,
) -> bool:
    """Send an FCM push notification to a single device token.

    Returns True on success, False on failure or when FCM is not configured.

    BE-05: pass ``user_id`` (the owner of ``token``) so that, if and only if
    FCM returns a definitive, permanent invalid-token error (see
    ``_is_permanent_token_error``), the stored token is cleared via a
    race-safe conditional UPDATE (see ``_clear_invalidated_token``).
    Transient errors, server-credential errors, network/timeout errors, and
    any unrecognized exception type never clear the token (fail closed). If
    ``user_id`` is omitted, no cleanup is attempted -- this function's
    send/log/return-False behavior is otherwise unchanged for every caller.
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

        if user_id is not None and token and _is_permanent_token_error(exc):
            _clear_invalidated_token(user_id, token)

        if _is_third_party_auth_error(exc):
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
                type(exc).__name__,
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
