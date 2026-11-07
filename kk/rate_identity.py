"""Identity-aware rate limiting for the phone-OTP endpoints (audit F-12).

Problem (F-12)
--------------
``/api/auth/phone/start``, ``/api/auth/send-verification`` / ``send_otp`` and
``/api/auth/phone/verify`` were limited ONLY per source IP (3 sends per 10 min,
10 verifies per 15 min in production). In Iraq many subscribers sit behind the
same carrier-grade NAT address, so a handful of legitimate users exhausted the
budget for everybody behind that address (and the budget could be burnt on
purpose to lock a whole carrier out).

Design
------
The primary controls are now per *identity* and per *device*; the per-IP limit
stays only as a looser ceiling that still stops bulk abuse from one address.

* ``phone``  - canonical phone number (see ``_identity_keys``). Bounds SMS
  cost / SMS pumping and OTP guessing for ONE number regardless of how many IPs
  or devices the attacker rotates through.
* ``device`` - optional client-supplied ``X-Device-Id`` header (or JSON
  ``device_id``). Convenience limit for one install; it is client asserted and
  therefore NOT a security boundary (an attacker can rotate it), so the phone
  and IP dimensions are always applied as well.
* ``ip``     - ``kk.security._client_ip()`` (ProxyFix-adjusted ``remote_addr``).
  Ceiling, deliberately far higher than the phone limit.

Every dimension can have several windows (short + 24 h).

Order / accounting
------------------
Dimensions are evaluated phone -> device -> ip and evaluation stops at the first
exceeded limit. Each check is one atomic counter increment performed BEFORE the
request is served (never "read, then write"), so a request is only served when
every counter it touched was within its limit after its own increment. A request
that is rejected by the (more specific) phone limit does not consume the shared
IP budget, so one victim's phone being hammered cannot exhaust a whole carrier
IP. Rejected requests still count (fixed window, the window start is set by the
first hit and never extended), so hammering does not extend the block.

Store / atomicity
-----------------
* Production: Redis (``REDIS_URL``). ``INCR`` is atomic server side and shared
  by all gunicorn workers/replicas, so N simultaneous requests can never all
  slip past a limit. ``EXPIRE`` is set on the first hit; if a counter is ever
  found without a TTL while blocking (crash between INCR and EXPIRE) the TTL is
  repaired so a key can never block forever.
* If Redis is missing/failing the limiter FAILS CLOSED (503
  ``rate_limiter_unavailable``) unless the same dev/test escape hatch used by
  ``kk.security`` applies (``APP_ENV`` development/testing or
  ``ALLOW_INMEMORY_RATE_LIMITS``), in which case a lock-protected in-process
  fixed-window counter is used (single process only).
* Like ``kk.security.check_rate_limit`` the limiter is a no-op under
  ``APP_ENV=testing`` / ``app.config['TESTING']`` so the huge existing suite
  that logs in repeatedly with shared phones is unaffected; tests opt in by
  switching APP_ENV/TESTING exactly as the M-09/BE-19 tests do.

Keys never contain the raw phone/device/IP: phone and device identifiers are
HMAC-SHA256 hashed with ``SECRET_KEY`` (PII-free Redis keys).

Configuration (environment, all optional; production default / dev default)
---------------------------------------------------------------------------
send (phone/start, send-verification, send_otp share ONE budget per identity):
  OTP_SEND_PHONE_MAX         3 / 30     per OTP_SEND_WINDOW_MINUTES (10)
  OTP_SEND_PHONE_DAILY_MAX   10 / 100   per 24 h
  OTP_SEND_DEVICE_MAX        5 / 50     per OTP_SEND_WINDOW_MINUTES
  OTP_SEND_DEVICE_DAILY_MAX  30 / 300   per 24 h
  OTP_SEND_IP_MAX            100 / 1000 per OTP_SEND_WINDOW_MINUTES
  OTP_SEND_IP_DAILY_MAX      2000 / 20000 per 24 h
  Legacy ``RATE_LIMIT_SEND_OTP`` is honoured as the default of OTP_SEND_PHONE_MAX.
verify (phone/verify, verify-phone share ONE budget per identity):
  OTP_VERIFY_PHONE_MAX       10 / 100   per OTP_VERIFY_WINDOW_MINUTES (15)
  OTP_VERIFY_PHONE_DAILY_MAX 30 / 300   per 24 h
  OTP_VERIFY_DEVICE_MAX      20 / 200   per OTP_VERIFY_WINDOW_MINUTES
  OTP_VERIFY_IP_MAX          200 / 2000 per OTP_VERIFY_WINDOW_MINUTES

Part 2 - the remaining unauthenticated auth endpoints (same machinery)
---------------------------------------------------------------------
Threat model per endpoint (decision table: ``_agent_logs/batch5/f12``). The
per-IP limit alone punishes every subscriber behind one carrier NAT and is no
real control against a distributed attacker, so the primary control moves to
the identity being attacked and the IP becomes a higher ceiling:

* ``login``  (``/api/auth/login``)  identifier ``AUTH_LOGIN_IDENT_MAX`` 10 / 100
  per ``AUTH_LOGIN_WINDOW_MINUTES`` (15) - counts ALL attempts at the submitted
  username/phone whether or not it exists (no enumeration), and is >= the
  M-09 per-account failure throttle (5 failures -> 15 min) which is UNCHANGED
  and remains the stronger control; device ``AUTH_LOGIN_DEVICE_MAX`` 30 / 300;
  IP ceiling ``AUTH_LOGIN_IP_MAX`` 100 / 1000 (was 10 per IP): credential
  stuffing from one IP across many accounts is capped at 100 attempts / 15 min.
* ``forgot`` (``/api/auth/forgot-password``) phone ``AUTH_FORGOT_PHONE_MAX``
  3 / 30 per 15 min + ``AUTH_FORGOT_PHONE_DAILY_MAX`` 10 / 100 per 24 h (SMS-bomb
  guard; counted for unknown numbers too, response stays the generic 200);
  device 10 / 100; IP ``AUTH_FORGOT_IP_MAX`` 30 / 300 per 15 min and
  ``AUTH_FORGOT_IP_DAILY_MAX`` 300 / 3000 per 24 h (was 5 per 15 min per IP).
* ``signup`` (``/api/auth/signup``; needs a verified OTP, its own lockout stays)
  phone ``AUTH_SIGNUP_PHONE_MAX`` 10 / 100, device 10 / 100, IP
  ``AUTH_SIGNUP_IP_MAX`` 60 / 600 per ``AUTH_SIGNUP_WINDOW_MINUTES`` (60).
  Legacy ``RATE_LIMIT_SIGNUP`` is honoured as the default of the IP ceiling.
* ``email_send`` (``/api/auth/send-email-verification``, authenticated)
  per account ``AUTH_EMAIL_SEND_ACCOUNT_MAX`` 5 / 50 + daily 10 / 100, per
  destination e-mail ``AUTH_EMAIL_SEND_EMAIL_MAX`` 5 / 50 + daily 10 / 100 (an
  e-mail address is user supplied: many accounts must not bomb one inbox),
  IP ``AUTH_EMAIL_SEND_IP_MAX`` 60 / 600 per 15 min (was 5 per IP).
  Window env: ``AUTH_EMAIL_SEND_WINDOW_MINUTES``.
Kept as they are (legacy ``@rate_limit`` per IP): ``/api/auth/reset-password``
(the only secret is a guessable-in-theory 12-digit SMS code with NO identity in
the request, so any higher IP ceiling would weaken brute-force resistance),
``/api/auth/verify-email`` (256-bit token), retired ``register*`` stubs (410).

X-Device-Id is CLIENT ASSERTED. It is never an authentication factor and never
trusted to prove identity; because it can be rotated or omitted every scope
also applies the identity (phone / identifier / account / e-mail) and the IP
ceiling, so rotating device ids bypasses nothing that matters.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import os
import re
import threading
import time
import unicodedata
from functools import wraps

from flask import current_app, jsonify, request

from . import security as _security

_log = logging.getLogger(__name__)

_DAY_S = 24 * 60 * 60

# Format validation of the client-asserted ``X-Device-Id``. The Flutter app
# (``lib/services/device_id_service.dart``) sends a lower-case UUIDv4 (36 chars);
# the backend deliberately accepts a wider alphabet/length so other clients
# (web/admin, tests) can send their own opaque id. Anything that does not match
# is IGNORED (never a shared bucket, never an error): the request is then
# limited by the identity and IP dimensions only. KEEP IN SYNC with
# ``DeviceIdService.isValidDeviceId`` (a UUID satisfies this pattern).
_DEVICE_ID_RE = re.compile(r"^[A-Za-z0-9._:\-]{8,128}$")

# Production default / non-production default, per (scope, dimension, window).
# (name_suffix, prod_default, dev_default)
_SEND_DEFAULTS = {
    "PHONE_MAX": (3, 30),
    "PHONE_DAILY_MAX": (10, 100),
    "DEVICE_MAX": (5, 50),
    "DEVICE_DAILY_MAX": (30, 300),
    "IP_MAX": (100, 1000),
    "IP_DAILY_MAX": (2000, 20000),
}
_VERIFY_DEFAULTS = {
    "PHONE_MAX": (10, 100),
    "PHONE_DAILY_MAX": (30, 300),
    "DEVICE_MAX": (20, 200),
    "IP_MAX": (200, 2000),
}
# --- Part 2: remaining unauthenticated auth endpoints (see module docstring) ---
# login: identifier = the submitted username/phone (ALL attempts, known or
# unknown account, so it is not an account-existence oracle). Deliberately
# >= the M-09 per-account FAILURE throttle (5) so it never shadows it.
_LOGIN_DEFAULTS = {
    "IDENT_MAX": (10, 100),
    "DEVICE_MAX": (30, 300),
    "IP_MAX": (100, 1000),
}
# forgot-password (SMS reset code): the per-phone limit is the SMS-bomb guard.
_FORGOT_DEFAULTS = {
    "PHONE_MAX": (3, 30),
    "PHONE_DAILY_MAX": (10, 100),
    "DEVICE_MAX": (10, 100),
    "IP_MAX": (30, 300),
    "IP_DAILY_MAX": (300, 3000),
}
# signup (needs a previously verified phone OTP; the OTP lockout still applies)
_SIGNUP_DEFAULTS = {
    "PHONE_MAX": (10, 100),
    "DEVICE_MAX": (10, 100),
    "IP_MAX": (60, 600),
}
# send-email-verification (authenticated): per account + per destination email.
_EMAIL_SEND_DEFAULTS = {
    "ACCOUNT_MAX": (5, 50),
    "ACCOUNT_DAILY_MAX": (10, 100),
    "EMAIL_MAX": (5, 50),
    "EMAIL_DAILY_MAX": (10, 100),
    "IP_MAX": (60, 600),
}

# scope -> (env prefix, defaults, default window minutes)
_SCOPES = {
    "send": ("OTP_SEND", _SEND_DEFAULTS, 10),
    "verify": ("OTP_VERIFY", _VERIFY_DEFAULTS, 15),
    "login": ("AUTH_LOGIN", _LOGIN_DEFAULTS, 15),
    "forgot": ("AUTH_FORGOT", _FORGOT_DEFAULTS, 15),
    "signup": ("AUTH_SIGNUP", _SIGNUP_DEFAULTS, 60),
    "email_send": ("AUTH_EMAIL_SEND", _EMAIL_SEND_DEFAULTS, 15),
}

# Evaluation order of dimensions: most specific (cheapest to be hit by one
# victim) first, shared IP ceiling last.
_DIM_ORDER = ("IDENT", "PHONE", "ACCOUNT", "EMAIL", "DEVICE", "IP")

_OTP_SCOPES = frozenset({"send", "verify"})


class _LimiterUnavailable(Exception):
    pass


# ---------------------------------------------------------------------------
# configuration
# ---------------------------------------------------------------------------


def _env_int(name: str, default: int) -> int:
    raw = (os.environ.get(name) or "").strip()
    if raw:
        try:
            return max(1, int(raw))
        except ValueError:
            pass
    return default


def _is_production() -> bool:
    from .config import get_app_env

    return get_app_env() == "production"


def _limits_for(scope: str):
    """Return ``[(dimension, [(max_requests, window_s), ...]), ...]`` for scope."""
    prefix, defaults, window_min_default = _SCOPES[scope]
    prod = _is_production()

    def val(suffix: str) -> int:
        d_prod, d_dev = defaults[suffix]
        default = d_prod if prod else d_dev
        if scope == "send" and suffix == "PHONE_MAX":
            # Legacy knob (was the per-IP send limit) now seeds the per-phone limit.
            default = _env_int("RATE_LIMIT_SEND_OTP", default)
        if scope == "signup" and suffix == "IP_MAX":
            # Legacy knob: RATE_LIMIT_SIGNUP was (and stays) the per-IP signup limit.
            default = _env_int("RATE_LIMIT_SIGNUP", default)
        return _env_int(f"{prefix}_{suffix}", default)

    window_s = _env_int(f"{prefix}_WINDOW_MINUTES", window_min_default) * 60

    out = []
    for dim in _DIM_ORDER:
        windows = []
        if f"{dim}_MAX" in defaults:
            windows.append((val(f"{dim}_MAX"), window_s))
        if f"{dim}_DAILY_MAX" in defaults:
            windows.append((val(f"{dim}_DAILY_MAX"), _DAY_S))
        if windows:
            out.append((dim.lower(), windows))
    return out


# ---------------------------------------------------------------------------
# identity extraction
# ---------------------------------------------------------------------------


def _hash(label: str, value: str) -> str:
    secret = (current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    digest = hmac.new(secret, f"{label}:{value}".encode("utf-8"), hashlib.sha256)
    return digest.hexdigest()[:32]


def _canonical_phone(raw: str) -> str:
    """Iraq-aware canonical form used ONLY for limiter keys.

    ``0770...``, ``770...``, ``+964770...``, ``00964770...`` are the same
    subscriber. ``_normalize_phone`` (deliberately left untouched) does not
    unify all of them, so an attacker could multiply the per-phone budget by
    sending format variants of one number. We therefore ALSO count this
    canonical form (last 10 significant digits)."""
    # ``str.isdigit`` also accepts Arabic-Indic / fullwidth digits (the existing
    # normaliser keeps them verbatim); fold them to ASCII so they cannot be
    # used as a second "identity" for the same subscriber.
    digits = "".join(
        str(unicodedata.digit(ch)) for ch in raw if ch.isdigit() and unicodedata.digit(ch, None) is not None
    )
    if digits.startswith("00"):
        digits = digits[2:]
    if digits.startswith("964") and len(digits) >= 12:
        digits = digits[3:]
    digits = digits.lstrip("0")
    return digits[-10:]


def _request_payload() -> dict:
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return {}
    try:
        cleaned = _security.validate_input_sanitization(data)
        return cleaned if isinstance(cleaned, dict) else data
    except Exception:
        return data


_PHONE_FIELDS_DEFAULT = ("phone_number", "phone")


def _identity_keys(data: dict, fields: tuple[str, ...] = _PHONE_FIELDS_DEFAULT) -> list[str]:
    """Hashed phone identity keys for this request (0, 1 or 2 entries).

    The handlers read ``phone_number`` first, then ``phone``; mirror that and
    use the EXISTING ``kk.routes.auth._normalize_phone`` as-is. When the value is
    missing/unusable no phone key is produced and the request is limited by the
    device and IP dimensions only (the handler rejects it with 400 before any
    SMS is sent or any OTP state is touched, so there is no cost to protect)."""
    # ``fields`` is the handler's own precedence (``/auth/signup`` reads
    # ``phone`` before ``phone_number``): the key MUST be derived from the value
    # the handler will actually act on, otherwise a decoy value in the other
    # field would dodge the per-phone limit.
    raw = ""
    for name in fields:
        raw = data.get(name) or raw
        if raw:
            break
    if not isinstance(raw, str):
        return []
    raw = raw.strip()
    if not raw:
        return []
    from .routes.auth import _normalize_phone  # lazy: auth imports this module

    keys: list[str] = []
    normalised = _normalize_phone(raw)
    if normalised:
        keys.append(_hash("phone", normalised))
    canonical = _canonical_phone(raw)
    if canonical:
        canon_key = _hash("phone", canonical)
        if canon_key not in keys:
            keys.append(canon_key)
    return keys


def _device_key(data: dict) -> str | None:
    candidate = request.headers.get("X-Device-Id") or data.get("device_id")
    if not isinstance(candidate, str):
        return None
    candidate = candidate.strip()
    if not _DEVICE_ID_RE.match(candidate):
        return None
    return _hash("device", candidate)


_PHONE_LOOKING_RE = re.compile(r"^\+?[\d\s\-().]{7,24}$")
_IDENT_MAX_CHARS = 4096


def _login_identifier_keys(raw) -> list[str]:
    """Hashed keys for the login identifier (username or phone), 0, 1 or 2.

    Mirrors what ``login`` does with ``data["username"]`` but is deliberately
    COARSER than the account lookup so that no spelling the handler could map
    to one account escapes the bucket: NFKC, zero-width/control characters
    removed, case-folded, and phone-looking values additionally collapse to
    the Iraq-aware canonical number (``0770...``/``+964770...``/``00964770...``).

    Non-string garbage (lists, dicts, null, bool) yields NO key: the handler
    cannot authenticate such a value anyway, and the request is still bounded
    by the device and IP dimensions (an attacker gains nothing from it)."""
    if isinstance(raw, bool):
        return []
    if isinstance(raw, (int, float)):
        raw = str(raw)
    if not isinstance(raw, str):
        return []
    text = unicodedata.normalize("NFKC", raw[:_IDENT_MAX_CHARS])
    text = "".join(ch for ch in text if unicodedata.category(ch) not in ("Cc", "Cf"))
    text = text.strip().casefold()
    if not text:
        return []
    keys = [_hash("ident", text)]
    if _PHONE_LOOKING_RE.match(text):
        canonical = _canonical_phone(text)
        if canonical:
            canon_key = _hash("phone", canonical)
            if canon_key not in keys:
                keys.append(canon_key)
    return keys


def _jwt_account_key() -> str | None:
    """Account key from an ALREADY VERIFIED JWT (the route puts ``jwt_required``
    above this decorator). Never taken from the request body."""
    try:
        from flask_jwt_extended import get_jwt_identity

        ident = get_jwt_identity()
    except Exception:
        return None
    if not ident:
        return None
    return _hash("account", str(ident))


def _account_email_key() -> str | None:
    """Key of the destination e-mail of the authenticated account, if any.

    Bounds e-mail bombing of ONE address across many accounts/IPs (an account's
    e-mail is user-supplied, so several accounts can point at a victim)."""
    try:
        from .auth import get_current_user

        user = get_current_user()
        email = (getattr(user, "email", None) or "").strip().lower()
    except Exception:
        return None
    if not email or email.endswith("@phone.local"):
        return None
    return _hash("email", email)


# ---------------------------------------------------------------------------
# counters
# ---------------------------------------------------------------------------

# key -> [count, window_start]; dev/test fallback only (single process).
_mem: dict[str, list] = {}
_mem_lock = threading.Lock()
_MEM_MAX_KEYS = 50_000


def reset_in_memory_state() -> None:
    """Test helper: forget all in-process counters."""
    with _mem_lock:
        _mem.clear()


def _hit_memory(key: str, max_requests: int, window_s: int) -> int | None:
    now = time.time()
    with _mem_lock:
        if len(_mem) > _MEM_MAX_KEYS:
            for k in [k for k, (_, start, w) in _mem.items() if now - start >= w]:
                _mem.pop(k, None)
        entry = _mem.get(key)
        if entry is None or now - entry[1] >= window_s:
            entry = [0, now, window_s]
            _mem[key] = entry
        entry[0] += 1
        if entry[0] > max_requests:
            return max(1, int(window_s - (now - entry[1])) + 1)
    return None


def _hit(key: str, max_requests: int, window_s: int) -> int | None:
    """Count one hit. ``None`` => allowed, else the Retry-After seconds."""
    allow_memory = _security._allow_inmemory_rate_limits()
    r = _security._redis_client()
    if r is not None:
        try:
            n = r.incr(key)
            if n == 1:
                r.expire(key, window_s)
            if n > max_requests:
                ttl = r.ttl(key)
                if ttl is None or int(ttl) < 0:
                    # Counter without TTL (crash between INCR and EXPIRE):
                    # repair so it cannot block forever.
                    r.expire(key, window_s)
                    ttl = window_s
                return max(1, int(ttl))
            return None
        except Exception:
            if not allow_memory:
                raise _LimiterUnavailable()
    elif not allow_memory:
        raise _LimiterUnavailable()
    return _hit_memory(key, max_requests, window_s)


def _limited_response(retry_after: int, scope: str = "send"):
    if scope in _OTP_SCOPES:
        body = {
            "message": "Too many requests. Please try again later.",
            "code": "otp_rate_limited",
        }
    else:
        # Same status/headers/shape as the OTP limiter. The message keeps the
        # "Rate limit exceeded" wording of the legacy per-IP decorator these
        # scopes replace, and is IDENTICAL whichever dimension tripped and
        # whether or not the account exists (no enumeration signal).
        body = {
            "message": "Rate limit exceeded. Too many attempts, please try again later.",
            "code": "auth_rate_limited",
        }
    resp = jsonify({**body, "retry_after": int(retry_after)})
    resp.status_code = 429
    resp.headers["Retry-After"] = str(int(retry_after))
    return resp


def _disabled() -> bool:
    env = (os.environ.get("APP_ENV") or "").strip().lower()
    return env == "testing" or bool(current_app.config.get("TESTING"))


def _subjects_for(scope: str) -> dict[str, list[str]]:
    """``{dimension: [hashed subject, ...]}`` for the current request.

    IMPORTANT (client-asserted data): ``device`` comes from a header the client
    chooses, ``phone``/``ident`` from the body, so each of them can be rotated
    or omitted at will. They are therefore only EXTRA limits; the IP ceiling is
    always present (and, for per-account scopes, the account/phone/e-mail one).
    A client that rotates device ids still runs into the per-identity limit
    and into the per-IP ceiling. None of these values ever authenticates or
    authorises anything."""
    ip = _security._client_ip()
    if scope == "email_send":
        account = _jwt_account_key()
        email = _account_email_key()
        return {
            "account": [account] if account else [],
            "email": [email] if email else [],
            "ip": [ip],
        }
    if scope == "login":
        # The handler reads the RAW body (no sanitisation); mirror that.
        raw = request.get_json(silent=True)
        raw = raw if isinstance(raw, dict) else {}
        device = _device_key(raw)
        return {
            "ident": _login_identifier_keys(raw.get("username")),
            "device": [device] if device else [],
            "ip": [ip],
        }
    data = _request_payload()
    fields = ("phone", "phone_number") if scope == "signup" else _PHONE_FIELDS_DEFAULT
    device = _device_key(data)
    return {
        "phone": _identity_keys(data, fields),
        "device": [device] if device else [],
        "ip": [ip],
    }


def check_otp_rate_limit(scope: str):
    """Return a Flask response when the request must be rejected, else None.

    Despite the historical name this serves every scope in ``_SCOPES``
    (OTP send/verify and the Part-2 auth scopes)."""
    if _disabled():
        return None

    # ``send_otp_legacy`` calls the (also decorated) ``send_phone_verification``
    # in-process: count a single HTTP request only once per scope.
    # (per-request WSGI environ, NOT flask.g: g is shared across requests when
    # a caller holds an outer app context.)
    done = request.environ.setdefault("carnet.otp_rate_limit_done", set())
    if scope in done:
        return None
    done.add(scope)

    subjects = _subjects_for(scope)

    # OTP scopes keep their original key namespace (live counters survive a
    # deploy); the new auth scopes use their own.
    ns = "otp" if scope in _OTP_SCOPES else "authrl"
    try:
        for dim, windows in _limits_for(scope):
            for subject in subjects.get(dim, []):
                for max_requests, window_s in windows:
                    key = f"{ns}:{scope}:{dim}:{subject}:{window_s}"
                    retry_after = _hit(key, max_requests, window_s)
                    if retry_after is not None:
                        _log.warning(
                            "rate limit hit scope=%s dimension=%s window_s=%s",
                            scope,
                            dim,
                            window_s,
                        )
                        return _limited_response(retry_after, scope)
    except _LimiterUnavailable:
        return _security._rate_limit_unavailable_response()
    return None


check_identity_rate_limit = check_otp_rate_limit


def otp_rate_limit(scope: str):
    """Decorator: identity/device/IP-ceiling limiter (OTP and auth scopes)."""
    if scope not in _SCOPES:
        raise ValueError(f"unknown rate-limit scope {scope!r}")

    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            limited = check_otp_rate_limit(scope)
            if limited is not None:
                return limited
            return f(*args, **kwargs)

        return wrapper

    return decorator


# Readable alias for the Part-2 auth scopes (login/forgot/signup/email_send).
auth_rate_limit = otp_rate_limit
