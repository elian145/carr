"""Strict Iraqi-mobile phone parsing for listing contact numbers.

The app is Iraq-only. An Iraqi mobile number has ONE canonical key: ``7`` plus
nine digits (``7XXXXXXXXX``) -- the same form ``kk.routes.auth._normalize_phone``
stores for account phones. Its international form is ``+964`` + the key; Iraq has
no trunk ``0`` after the country code, so ``+9640770...`` is a typing mistake
(``+964`` + a number written with its national leading ``0``) and is repaired,
not stored.

Evidence for the ``^7\\d{9}$`` rule (nothing stricter): the Flutter normaliser
(``lib/shared/phone/phone_normalizer.dart``) and ``kk/sms_service.py`` both treat
``7`` + 9 digits as the Iraqi mobile and give every other 10-digit number no
country prefix; no Flutter/backend validator knows individual operator prefixes
(75x/77x/78x/79x...), so none is enforced here either.

This module has no Flask / SQLAlchemy dependency so ``kk.models`` can import it.
"""

from __future__ import annotations

import re
import unicodedata

_CANONICAL_RE = re.compile(r"^7\d{9}$")

# Characters people type between digit groups (plus bidi marks that RTL
# keyboards / copy-paste insert). Anything else that is not a digit (letters,
# '#', '*', ...) makes the value invalid instead of being silently dropped.
_SEPARATORS = frozenset(
    " \t\r\n\u00a0-().\u200e\u200f\u061c\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069"
)


def _ascii_digits_or_none(value) -> tuple[str, bool] | None:
    """``(ascii digits, has_leading_plus)`` or None for non-phone-looking text."""
    if value is None or isinstance(value, bool):
        return None
    text = str(value).strip()
    if not text:
        return None
    digits: list[str] = []
    plus = False
    for ch in text:
        if ch == "+":
            # '+' is only meaningful as the very first (non-space) character.
            if digits or plus:
                return None
            plus = True
            continue
        if ch in _SEPARATORS:
            continue
        if ch.isdigit():
            # ``decimal`` (not ``digit``): superscripts / circled digits are not
            # something a person types into a phone field.
            d = unicodedata.decimal(ch, None)
            if d is None:
                return None
            digits.append(str(d))
            continue
        return None
    if not digits:
        return None
    return "".join(digits), plus


def normalize_iraqi_mobile(value) -> str | None:
    """Canonical key ``7XXXXXXXXX`` for any accepted spelling, else ``None``.

    Accepted: ``7XXXXXXXXX``, ``07XXXXXXXXX``, ``9647XXXXXXXXX``,
    ``+9647XXXXXXXXX``, ``009647XXXXXXXXX`` and the typo forms with a trunk zero
    after the country code (``+96407...``, ``96407...``, ``009640 7...``), with
    spaces / dashes / dots / parentheses and Arabic-Indic / Persian digits.

    Everything else (landlines, wrong lengths, 10-digit numbers that do not start
    with 7, foreign numbers, letters, empty) returns ``None``.
    """
    parsed = _ascii_digits_or_none(value)
    if parsed is None:
        return None
    digits, plus = parsed

    if digits.startswith("00"):
        # International dialling prefix: only ``00964`` can be an Iraqi number.
        if plus or not digits.startswith("00964"):
            return None
        digits = digits[2:]
        national = digits[3:]
    elif digits.startswith("964"):
        national = digits[3:]
    elif plus:
        return None  # explicit international number of another country
    elif len(digits) == 11 and digits.startswith("0"):
        national = digits[1:]
    else:
        national = digits

    if digits.startswith("964") and national.startswith("0"):
        national = national[1:]  # +9640770... typo: no trunk zero after +964

    return national if _CANONICAL_RE.match(national) else None


def normalize_stored_iraqi_mobile(value) -> str | None:
    """Like :func:`normalize_iraqi_mobile`, for values ALREADY stored in the DB.

    Additionally understands the ``0964...`` spelling that very old account rows
    may carry (see ``kk.routes.user._ACCOUNT_PHONE_LEGACY_PREFIXES``). Never used
    for fresh user input.
    """
    key = normalize_iraqi_mobile(value)
    if key is not None:
        return key
    parsed = _ascii_digits_or_none(value)
    if parsed is None:
        return None
    digits, plus = parsed
    if not plus and digits.startswith("0964"):
        return normalize_iraqi_mobile(digits[1:])
    return None


def to_e164_iraq(value) -> str | None:
    """``+9647XXXXXXXXX`` for a canonical key (or any accepted spelling)."""
    key = normalize_iraqi_mobile(value)
    return f"+964{key}" if key else None
