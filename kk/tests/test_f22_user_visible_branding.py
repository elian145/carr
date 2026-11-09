"""F-22: user-visible backend copy must use the CarNet brand, not legacy "Carzo".

Scope: verification/confirmation emails, the localized email templates in
``kk/localization.py`` and the verify-email handoff page in ``kk/routes/misc.py``.
Internal identifiers (``carzo://`` scheme, ``com.carzo.app`` bundle id, JS helper
names, ``carzo_*`` channel ids) are an owner decision (docs/OWNER_ACTIONS.md
F-11) and are intentionally NOT asserted here -- the pattern only matches the
capitalised brand word.
"""

from __future__ import annotations

import re
from pathlib import Path

_KK = Path(__file__).resolve().parents[1]
_LEGACY_BRAND = re.compile(r"\bCarzo\b")


def test_user_visible_backend_copy_has_no_legacy_brand() -> None:
    offenders = []
    for rel in ("email_service.py", "localization.py", "routes/misc.py"):
        text = (_KK / rel).read_text(encoding="utf-8")
        for n, line in enumerate(text.splitlines(), 1):
            if _LEGACY_BRAND.search(line):
                offenders.append(f"{rel}:{n}: {line.strip()}")
    assert not offenders, "legacy 'Carzo' brand in user-visible copy:\n" + "\n".join(offenders)


def test_dealer_verification_email_templates_render_carnet_in_every_locale() -> None:
    import sys

    sys.path.insert(0, str(_KK.parent))
    from kk.localization import translate

    for locale in ("en", "ar", "ku"):
        for key in (
            "dealer_email_verification_subject",
            "dealer_email_verification_text",
            "dealer_email_verification_html",
        ):
            rendered = translate(key, locale, code="123456")
            assert "CarNet" in rendered, (key, locale)
            assert "Carzo" not in rendered, (key, locale)

