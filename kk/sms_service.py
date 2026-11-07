"""
SMS Service for sending password reset and verification codes.
Supports: Twilio, OTPIQ (Iraq SMS/WhatsApp), console (dev only).
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
import unicodedata
from typing import Any, Optional

import requests

from .config import get_app_env

logger = logging.getLogger(__name__)

OTPIQ_API_URL = "https://api.otpiq.com/api/sms"
_otpiq_script_path: Optional[str] = None


def _app_env() -> str:
    """
    M-01: delegate to the single shared environment resolver instead of an
    independently-defaulted copy. ``get_app_env()`` defaults unset
    APP_ENV/FLASK_ENV to ``"production"`` (fail-safe) — this helper
    previously defaulted to ``"development"`` (fail-open), which meant the
    "console SMS is not allowed in production" guard below could silently
    fail to fire on a deploy that simply forgot to set APP_ENV.
    """
    return get_app_env()


def _get_otpiq_script_path() -> Optional[str]:
    global _otpiq_script_path
    if _otpiq_script_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        path = os.path.join(here, "..", "tools", "otpiq_http.py")
        if os.path.isfile(path):
            _otpiq_script_path = os.path.normpath(os.path.abspath(path))
        else:
            _otpiq_script_path = ""
    return _otpiq_script_path or None


def _otpiq_via_subprocess(
    *,
    url: str,
    headers: dict[str, str],
    body: dict[str, Any],
    timeout: float = 15,
) -> tuple[int, Any]:
    """
    Call OTPIQ in a clean interpreter (avoids eventlet recursion on requests).

    Returns (status_code, body). Raises RuntimeError on transport failure.
    """
    script_path = _get_otpiq_script_path()
    if not script_path:
        raise RuntimeError("otpiq_http.py missing")

    payload = {
        "url": url,
        "headers": headers,
        "json": body,
        "timeout": timeout,
    }
    proc = subprocess.run(
        [sys.executable, script_path],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        timeout=timeout + 10,
        env=os.environ,
    )
    out = (proc.stdout or "").strip()
    if not out:
        err = (proc.stderr or "").strip() or f"exit {proc.returncode}"
        raise RuntimeError(err)
    result = json.loads(out)
    if isinstance(result, dict) and result.get("error"):
        raise RuntimeError(str(result["error"]))
    if not isinstance(result, dict) or "status" not in result:
        raise RuntimeError("invalid otpiq subprocess response")
    return int(result["status"]), result.get("body")


def _normalize_phone_otpiq(phone: str) -> str:
    """Normalize for OTPIQ (Iraq): full E.164 without +, 964 + 10-digit national = 13 digits (e.g. 9647505070706)."""
    digits = "".join(c for c in (phone or "") if c.isdigit())
    if len(digits) == 13 and digits.startswith("964"):
        return digits
    if len(digits) == 12 and digits.startswith("964"):
        return digits
    if len(digits) == 11 and digits.startswith("0"):
        digits = digits[1:]
    if len(digits) == 11 and digits.startswith("64"):
        return "9" + digits
    if len(digits) == 11 and digits.startswith("4"):
        return "96" + digits
    if len(digits) == 10:
        return "964" + digits
    if len(digits) == 11:
        return "964" + digits
    if len(digits) >= 10 and len(digits) <= 15:
        return digits
    return digits


def _ascii_digits(value: str) -> str:
    """Digits of ``value`` folded to ASCII (Arabic-Indic / Persian / fullwidth)."""
    out = []
    for ch in value or "":
        if not ch.isdigit():
            continue
        d = unicodedata.digit(ch, None)
        if d is not None:
            out.append(str(d))
    return "".join(out)


def _normalize_phone_twilio(phone: str) -> str:
    """Normalize to E.164 for Twilio (best-effort, never guesses a country).

    The app is Iraq-only: the login/profile screens send ``+964`` + the typed
    digits and the backend stores ONE canonical form, the 10-digit national
    significant number ``7XXXXXXXXX`` (see ``kk.routes.auth._normalize_phone``).
    Accepted inputs and results:

    * canonical Iraqi mobile ``7XXXXXXXXX`` (10 digits)        -> ``+9647XXXXXXXXX``
    * national ``07XXXXXXXXX`` (11 digits)                     -> ``+9647XXXXXXXXX``
    * ``964...`` / ``00964...`` / ``+964...`` (also with a stray
      trunk ``0`` after the code, as ``+9640770...``)          -> ``+964...``
    * explicit E.164 ``+<digits>`` of any other country        -> unchanged
    * ``00<country><number>``                                  -> ``+<country><number>``
    * 11..15 digits without ``+``/``00`` (e.g. ``447911123456``)-> ``+<digits>``
    * anything else (10 digits that are not an Iraqi mobile, too short/long,
      no digits)                                               -> returned as typed

    The last rule is deliberate: prefixing a bare 10-digit number with ``+``
    turns it into a *different country's* number (``+7...`` is Russia/Kazakhstan,
    ``+20...`` Egypt) and would deliver the OTP to a stranger; handing Twilio the
    unprefixed value makes it reject the request instead (fails closed).
    """
    raw = (phone or "").strip()
    if not raw:
        return ""
    digits = _ascii_digits(raw)
    if not digits:
        return raw

    def _iraq(national: str) -> str:
        # Iraq has no trunk "0" after the country code: +9640770... is a typo
        # produced by "+964" + a number typed with its national leading 0.
        if national.startswith("0"):
            national = national[1:]
        return f"+964{national}"

    if raw.startswith("+"):
        if digits.startswith("964"):
            return _iraq(digits[3:])
        # Explicit E.164 of another country: keep (formatting characters such
        # as spaces/dashes are not part of E.164 and are dropped).
        return f"+{digits}"
    if digits.startswith("00") and len(digits) > 2:
        digits = digits[2:]
        if digits.startswith("964"):
            return _iraq(digits[3:])
        if 8 <= len(digits) <= 15:
            return f"+{digits}"
        return raw
    # Iraq national mobile: 07XXXXXXXXX
    if len(digits) == 11 and digits.startswith("07"):
        return f"+964{digits[1:]}"
    # Canonical stored Iraqi mobile: 7XXXXXXXXX
    if len(digits) == 10 and digits.startswith("7"):
        return f"+964{digits}"
    # Iraq intl without plus
    if digits.startswith("964") and 11 <= len(digits) <= 14:
        return _iraq(digits[3:])
    # Generic fallback for international-looking numbers (country code present).
    if 11 <= len(digits) <= 15 and not digits.startswith("0"):
        return f"+{digits}"
    return raw


def _safe_provider_error(detail: str, *, limit: int = 180) -> str:
    text = " ".join(str(detail or "").split())
    if len(text) > limit:
        text = text[: limit - 1] + "…"
    return text


class SMSService:
    """SMS service for sending messages"""

    def __init__(self):
        self.reload_config()

    def reload_config(self) -> None:
        """Re-read SMS env vars (safe after Render env updates / worker boot)."""
        self.provider = (os.environ.get("SMS_PROVIDER") or "console").strip().lower()
        self.twilio_account_sid = os.environ.get("TWILIO_ACCOUNT_SID")
        self.twilio_auth_token = os.environ.get("TWILIO_AUTH_TOKEN")
        self.twilio_phone_number = os.environ.get("TWILIO_PHONE_NUMBER")
        self.otpiq_api_key = (os.environ.get("OTPIQ_API_KEY") or "").strip()
        self.otpiq_provider = (os.environ.get("OTPIQ_PROVIDER") or "sms").strip().lower()

    def send_password_reset_code(
        self, phone_number: str, reset_code: str, locale: str | None = None
    ) -> tuple[bool, str]:
        """
        Send password reset code via SMS.

        ``locale`` (MI-03) localizes the message body for the Twilio and
        console providers only -- OTPIQ templates its own SMS text
        server-side ("smsType": "verification") and does not accept a
        freeform body from this codebase, so it is unaffected.

        Returns:
            (ok, detail) where detail is empty on success.
        """
        self.reload_config()
        try:
            if self.provider == "twilio":
                return self._send_via_twilio(phone_number, reset_code, locale=locale)
            if self.provider == "otpiq":
                return self._send_via_otpiq(phone_number, reset_code, purpose="password_reset")
            if self.provider == "console":
                return self._send_via_console(phone_number, reset_code, locale=locale)
            detail = f"Unsupported SMS provider: {self.provider}"
            logger.error("%s (supported: twilio, otpiq, console)", detail)
            return False, detail
        except Exception as e:
            detail = f"Failed to send SMS: {e}"
            logger.error(detail)
            return False, _safe_provider_error(detail)

    def _send_via_twilio(
        self, phone_number: str, reset_code: str, locale: str | None = None
    ) -> tuple[bool, str]:
        """Send SMS via Twilio"""
        try:
            from twilio.rest import Client

            from .localization import get_background_locale, translate

            if not all([self.twilio_account_sid, self.twilio_auth_token, self.twilio_phone_number]):
                detail = "Twilio credentials not configured"
                logger.error(detail)
                return False, detail

            client = Client(self.twilio_account_sid, self.twilio_auth_token)

            normalized_to = _normalize_phone_twilio(phone_number)
            body_text = translate(
                "password_reset_sms_body", get_background_locale(locale), code=reset_code
            )
            message = client.messages.create(
                body=body_text,
                from_=self.twilio_phone_number,
                to=normalized_to,
            )

            logger.info(
                "SMS sent successfully to %s (normalized=%s), SID: %s",
                phone_number,
                normalized_to,
                message.sid,
            )
            return True, ""

        except ImportError:
            detail = "Twilio library not installed"
            logger.error("%s. Install with: pip install twilio", detail)
            return False, detail
        except Exception as e:
            detail = f"Twilio SMS failed: {e}"
            logger.error(detail)
            return False, _safe_provider_error(detail)

    def _send_via_console(
        self, phone_number: str, reset_code: str, locale: str | None = None
    ) -> tuple[bool, str]:
        """Send SMS via console (for development)"""
        if _app_env() == "production":
            detail = "SMS_PROVIDER=console is not allowed in production"
            logger.error(detail)
            return False, detail

        from .localization import get_background_locale, translate

        body_text = translate(
            "password_reset_sms_body", get_background_locale(locale), code=reset_code
        )
        print(f"\n{'=' * 50}")
        print(f"SMS TO: {phone_number}")
        print(f"MESSAGE: {body_text}")
        print(f"EXPIRES: 1 hour")
        print(f"{'=' * 50}\n")

        # M-03: do not route the plaintext OTP through the `logging` module —
        # the print() above already gives local developers full visibility
        # without exposing the code to log aggregation/CI logs/Sentry
        # breadcrumbs. Intentionally no logger.info() call here.
        return True, ""

    def _send_via_otpiq(
        self, phone_number: str, code: str, purpose: str = "verification"
    ) -> tuple[bool, str]:
        """Send OTP via OTPIQ (Iraq SMS/WhatsApp). See https://docs.otpiq.com"""
        if not self.otpiq_api_key:
            detail = "OTPIQ_API_KEY not set"
            logger.error(detail)
            return False, detail
        normalized = _normalize_phone_otpiq(phone_number)
        if len(normalized) < 10 or len(normalized) > 15:
            detail = f"OTPIQ phone number must be 10–15 digits, got len={len(normalized)}"
            logger.error(detail)
            return False, detail
        logger.info(
            "OTPIQ phone: input=%r normalized=%s (len=%s)",
            phone_number,
            normalized,
            len(normalized),
        )
        payload = {
            "smsType": "verification",
            "phoneNumber": normalized,
            "verificationCode": str(code)[:20],
        }
        if self.otpiq_provider and self.otpiq_provider != "sms":
            payload["provider"] = self.otpiq_provider

        headers = {
            "Authorization": f"Bearer {self.otpiq_api_key}",
            "Content-Type": "application/json",
        }
        try:
            # Always prefer subprocess under eventlet/gunicorn — in-process
            # requests hits "maximum recursion depth exceeded" on Render.
            if _get_otpiq_script_path():
                status, data = _otpiq_via_subprocess(
                    url=OTPIQ_API_URL,
                    headers=headers,
                    body=payload,
                    timeout=15,
                )
            else:
                logger.warning(
                    "OTPIQ subprocess script missing; using in-process requests"
                )
                response = requests.post(
                    OTPIQ_API_URL,
                    json=payload,
                    headers=headers,
                    timeout=15,
                )
                status = response.status_code
                try:
                    data = response.json() if response.text else {}
                except Exception:
                    data = response.text

            if 200 <= status < 300:
                logger.info("OTPIQ %s sent to %s***", purpose, normalized[:4])
                return True, ""

            if isinstance(data, dict):
                err = data.get("error", data.get("message", data))
            else:
                err = data or str(status)
            detail = f"OTPIQ returned {status}: {err}"
            logger.warning(detail)
            return False, _safe_provider_error(detail)
        except Exception as e:
            detail = f"OTPIQ request failed: {e}"
            logger.exception(detail)
            return False, _safe_provider_error(detail)

    def send_verification_code(
        self, phone_number: str, verification_code: str
    ) -> tuple[bool, str]:
        """
        Send phone verification code via SMS.

        Returns:
            (ok, detail) where detail is empty on success.
        """
        self.reload_config()
        try:
            if self.provider == "twilio":
                return self._send_verification_via_twilio(phone_number, verification_code)
            if self.provider == "otpiq":
                return self._send_via_otpiq(
                    phone_number, verification_code, purpose="verification"
                )
            if self.provider == "console":
                return self._send_verification_via_console(phone_number, verification_code)
            detail = f"Unsupported SMS provider: {self.provider}"
            logger.error("%s (supported: twilio, otpiq, console)", detail)
            return False, detail
        except Exception as e:
            detail = f"Failed to send verification SMS: {e}"
            logger.error(detail)
            return False, _safe_provider_error(detail)

    def _send_verification_via_twilio(
        self, phone_number: str, verification_code: str
    ) -> tuple[bool, str]:
        """Send verification SMS via Twilio"""
        try:
            from twilio.rest import Client

            if not all([self.twilio_account_sid, self.twilio_auth_token, self.twilio_phone_number]):
                detail = "Twilio credentials not configured"
                logger.error(detail)
                return False, detail

            client = Client(self.twilio_account_sid, self.twilio_auth_token)

            normalized_to = _normalize_phone_twilio(phone_number)
            message = client.messages.create(
                body=f"Your verification code is: {verification_code}. This code expires in 10 minutes.",
                from_=self.twilio_phone_number,
                to=normalized_to,
            )

            logger.info(
                "Verification SMS sent successfully to %s (normalized=%s), SID: %s",
                phone_number,
                normalized_to,
                message.sid,
            )
            return True, ""

        except ImportError:
            detail = "Twilio library not installed"
            logger.error("%s. Install with: pip install twilio", detail)
            return False, detail
        except Exception as e:
            detail = f"Twilio verification SMS failed: {e}"
            logger.error(detail)
            return False, _safe_provider_error(detail)

    def _send_verification_via_console(
        self, phone_number: str, verification_code: str
    ) -> tuple[bool, str]:
        """Send verification SMS via console (for development)"""
        if _app_env() == "production":
            detail = "SMS_PROVIDER=console is not allowed in production"
            logger.error(detail)
            return False, detail
        print(f"\n{'=' * 50}")
        print(f"VERIFICATION SMS TO: {phone_number}")
        print(f"MESSAGE: Your verification code is: {verification_code}")
        print(f"EXPIRES: 10 minutes")
        print(f"{'=' * 50}\n")

        # M-03: do not route the plaintext OTP through the `logging` module —
        # the print() above already gives local developers full visibility
        # without exposing the code to log aggregation/CI logs/Sentry
        # breadcrumbs. Intentionally no logger.info() call here.
        return True, ""


# Global SMS service instance
sms_service = SMSService()


def send_password_reset_sms(
    phone_number: str, reset_code: str, locale: str | None = None
) -> bool:
    """Convenience function to send password reset SMS"""
    ok, _ = sms_service.send_password_reset_code(phone_number, reset_code, locale=locale)
    return ok


def send_verification_sms(phone_number: str, verification_code: str) -> bool:
    """Convenience function to send verification SMS"""
    ok, _ = sms_service.send_verification_code(phone_number, verification_code)
    return ok


def send_verification_sms_result(
    phone_number: str, verification_code: str
) -> tuple[bool, str]:
    """Send verification SMS and return (ok, failure_detail)."""
    return sms_service.send_verification_code(phone_number, verification_code)
