"""MI-03: minimal backend localization helpers.

PRODUCTION_AUDIT.md MI-03: ``User`` had no ``language``/``locale`` column and
there was no ``Accept-Language`` handling anywhere in the backend, so every
API error, push/alert/email/SMS template, and the force-update message were
English-only regardless of the account's actual language.

This module is intentionally NOT a general-purpose i18n framework (no Babel,
no gettext, no catalog loader). It is a small, narrowly scoped helper for the
specific strings MI-03/U-01 need localized:

  * ``normalize_locale`` / ``parse_accept_language`` -- turn a bare or
    regional locale code / an ``Accept-Language`` header into one of the
    supported base codes (or ``None``/``[]``).
  * ``get_request_locale`` -- REQUEST-TIME precedence:
        1. a valid ``Accept-Language`` header
        2. the authenticated ``User.locale``, when available
        3. English
    ``Accept-Language`` wins over the stored account preference because it
    reflects the language of the CURRENT device/session; a stored account
    preference must not override a user who switched the current device to
    another supported language (see PRODUCTION_AUDIT.md MI-03/U-01 design
    notes).
  * ``get_background_locale`` -- BACKGROUND/ASYNC precedence (Celery tasks,
    push/email/SMS senders): ``User.locale`` > English. Never touches Flask's
    request context (there isn't one).
  * ``current_request_locale`` -- convenience wrapper for route handlers:
    resolves the ``Accept-Language`` header from the active Flask request
    when one exists, otherwise degrades to the background precedence (so it
    is also safe to call from code paths that run both inside and outside a
    request, without raising).
  * ``translate`` -- looks up one of the small, fixed set of MI-03/U-01
    strings for a locale, formatting in any keyword arguments.

Keep the translation table LIMITED to strings this task actually needs.
Do NOT use this module as a place to accumulate every English string in the
codebase -- that is explicitly out of scope (see PRODUCTION_AUDIT.md U-01).
"""

from __future__ import annotations

import re

# Kept in sync with the Flutter app's `lib/app/production_app.dart`
# `supportedLocales`. `ckb` is tracked separately (U-07) and intentionally
# NOT included here.
SUPPORTED_LOCALES: tuple[str, ...] = ("en", "ar", "ku")

DEFAULT_LOCALE = "en"

_ACCEPT_LANGUAGE_ENTRY_RE = re.compile(
    r"^\s*([a-zA-Z]{1,8}(?:-[a-zA-Z0-9]{1,8})*)\s*(?:;\s*q\s*=\s*([01](?:\.[0-9]{1,3})?))?\s*$"
)


def normalize_locale(value) -> str | None:
    """Reduce a bare or regional locale tag to a supported base code.

    Examples: ``en`` -> ``en``, ``en-US`` -> ``en``, ``AR-iq`` -> ``ar``,
    ``ku-IQ`` -> ``ku``. Anything unsupported (including ``ckb``, empty, or
    ``None``) returns ``None``.
    """
    if not value:
        return None
    text = str(value).strip().lower()
    if not text:
        return None
    base = text.split("-")[0].split("_")[0]
    if base in SUPPORTED_LOCALES:
        return base
    return None


def parse_accept_language(header_value: str | None) -> list[str]:
    """Ordered, de-duplicated list of *supported* base locale codes from an
    ``Accept-Language`` header, most-preferred first (per RFC 7231 q-values,
    highest q wins; ties keep the header's original order). Unsupported or
    malformed tags are skipped rather than raising.
    """
    if not header_value:
        return []
    parsed: list[tuple[str, float, int]] = []
    for index, part in enumerate(header_value.split(",")):
        match = _ACCEPT_LANGUAGE_ENTRY_RE.match(part)
        if not match:
            continue
        tag, q_raw = match.group(1), match.group(2)
        normalized = normalize_locale(tag)
        if normalized is None:
            continue
        try:
            q = float(q_raw) if q_raw is not None else 1.0
        except ValueError:
            q = 1.0
        parsed.append((normalized, q, index))

    # Highest q-value first; stable on ties (original header order).
    parsed.sort(key=lambda entry: (-entry[1], entry[2]))

    ordered: list[str] = []
    for code, _q, _i in parsed:
        if code not in ordered:
            ordered.append(code)
    return ordered


def get_request_locale(header_value: str | None, user_locale: str | None = None) -> str:
    """REQUEST-TIME precedence: Accept-Language header > authenticated
    User.locale > English. See module docstring for the reasoning."""
    candidates = parse_accept_language(header_value)
    if candidates:
        return candidates[0]
    normalized_user = normalize_locale(user_locale)
    if normalized_user:
        return normalized_user
    return DEFAULT_LOCALE


def get_background_locale(user_locale: str | None) -> str:
    """BACKGROUND/ASYNC precedence (no request context): User.locale >
    English. Safe to call from Celery tasks / senders."""
    return normalize_locale(user_locale) or DEFAULT_LOCALE


def current_request_locale(user_locale: str | None = None) -> str:
    """Convenience wrapper for route handlers: reads the current Flask
    request's Accept-Language header when a request context is active,
    applying the request-time precedence; otherwise falls back to the
    background precedence (User.locale > English). Never raises just
    because no request is active.
    """
    try:
        from flask import has_request_context, request

        if has_request_context():
            return get_request_locale(request.headers.get("Accept-Language"), user_locale)
    except RuntimeError:
        pass
    return get_background_locale(user_locale)


# ---------------------------------------------------------------------------
# Translation table -- LIMITED to the strings MI-03/U-01 need. Do not grow
# this into a general-purpose string catalog.
# ---------------------------------------------------------------------------

_TRANSLATIONS: dict[str, dict[str, str]] = {
    # kk/routes/auth.py -- login failure (MI-03 cited path).
    "invalid_credentials": {
        "en": "Invalid credentials",
        "ar": "بيانات الاعتماد غير صحيحة",
        "ku": "زانیاری چوونەژوورەوە هەڵەیە",
    },
    # kk/socketio_handlers.py + kk/chat_realtime.py -- chat message
    # notification title (in-app Notification row).
    "new_message_title": {
        "en": "New message",
        "ar": "رسالة جديدة",
        "ku": "پەیامی نوێ",
    },
    # kk/socketio_handlers.py + kk/chat_realtime.py -- chat message FCM push
    # title (includes the sender's display name).
    "new_message_push_title": {
        "en": "New message from {name}",
        "ar": "رسالة جديدة من {name}",
        "ku": "پەیامی نوێ لە {name}",
    },
    # kk/routes/user.py -- Notification sent to a user when their dealer
    # application is submitted for review.
    "dealer_application_submitted_title": {
        "en": "Dealer application submitted",
        "ar": "تم إرسال طلب المعرض",
        "ku": "داواکاری شوکە نێردرا",
    },
    "dealer_application_submitted_body": {
        "en": "Your dealership details were received and are ready for review.",
        "ar": "تم استلام بيانات معرضك وهي جاهزة للمراجعة.",
        "ku": "زانیارییەکانی شوکەکەت وەرگیران و ئامادەن بۆ پێداچوونەوە.",
    },
    # kk/routes/admin.py -- _review_dealer_application() decision notification
    # sent to the applicant. Titles are always shown; bodies are only used
    # when the admin did not supply a free-text `reason` (needs_changes /
    # rejected always require one, so those body strings are unreachable in
    # practice but kept as a safe fallback if that ever changes).
    "dealer_decision_under_review_title": {
        "en": "Dealer application under review",
        "ar": "طلب المعرض قيد المراجعة",
        "ku": "داواکاری شوکە لە ژێر پێداچوونەوەدایە",
    },
    "dealer_decision_under_review_body": {
        "en": "An administrator has started reviewing your dealer application.",
        "ar": "بدأ أحد المسؤولين بمراجعة طلب معرضك.",
        "ku": "بەڕێوەبەرێک دەستی کرد بە پێداچوونەوە بە داواکاری شوکەکەت.",
    },
    "dealer_decision_needs_changes_title": {
        "en": "Dealer application needs changes",
        "ar": "طلب المعرض يحتاج إلى تعديلات",
        "ku": "داواکاری شوکە پێویستی بە گۆڕانکاری هەیە",
    },
    "dealer_decision_needs_changes_default_body": {
        "en": "Please update your dealer application.",
        "ar": "يرجى تحديث طلب معرضك.",
        "ku": "تکایە داواکاری شوکەکەت نوێ بکەرەوە.",
    },
    "dealer_decision_approved_title": {
        "en": "Dealer application approved",
        "ar": "تمت الموافقة على طلب المعرض",
        "ku": "داواکاری شوکە پەسەند کرا",
    },
    "dealer_decision_approved_body": {
        "en": (
            "Your dealership is verified and active. Complete your public "
            "profile with a logo, cover image, opening hours, and contact "
            "details."
        ),
        "ar": (
            "تم التحقق من معرضك وهو نشط الآن. أكمل ملفك العام بشعار وصورة "
            "غلاف وساعات عمل وبيانات تواصل."
        ),
        "ku": (
            "شوکەکەت پشتڕاست کرایەوە و چالاکە. پرۆفایلی گشتیت تەواو بکە "
            "بە لۆگۆ، وێنەی بەرگ، کاتەکانی کارکردن، و زانیاری پەیوەندی."
        ),
    },
    "dealer_decision_rejected_title": {
        "en": "Dealer application declined",
        "ar": "تم رفض طلب المعرض",
        "ku": "داواکاری شوکە ڕەتکرایەوە",
    },
    "dealer_decision_rejected_default_body": {
        "en": "Your dealer application was not approved.",
        "ar": "لم تتم الموافقة على طلب معرضك.",
        "ku": "داواکاری شوکەکەت پەسەند نەکرا.",
    },
    # kk/tasks/alert_tasks.py -- saved-search push, fallback title when the
    # search has no user-given name.
    "saved_search_default_title": {
        "en": "Saved search",
        "ar": "بحث محفوظ",
        "ku": "گەڕانی هەڵگیراو",
    },
    # kk/tasks/alert_tasks.py -- price-drop push title.
    "price_drop_title": {
        "en": "Price drop",
        "ar": "انخفاض السعر",
        "ku": "کەمبووەوەی نرخ",
    },
    # kk/sms_service.py -- password-reset SMS body (Twilio / console
    # providers only; OTPIQ templates its own SMS text and is not
    # controllable from this codebase).
    "password_reset_sms_body": {
        "en": "Your password reset code is: {code}. This code expires in 1 hour.",
        "ar": "رمز إعادة تعيين كلمة المرور هو: {code}. تنتهي صلاحية هذا الرمز خلال ساعة واحدة.",
        "ku": "کۆدی گەڕاندنەوەی وشەی نهێنیت ئەمەیە: {code}. ئەم کۆدە لە ماوەی یەک کاتژمێردا بەسەردەچێت.",
    },
    # kk/email_service.py -- send_dealer_email_verification_code (MI-03
    # cited path).
    "dealer_email_verification_subject": {
        "en": "Your Carzo verification code",
        "ar": "رمز التحقق الخاص بك في Carzo",
        "ku": "کۆدی پشتڕاستکردنەوەی تۆ لە Carzo",
    },
    "dealer_email_verification_text": {
        "en": (
            "Your Carzo verification code is: {code}\n\n"
            "Enter this code in the app to verify your dealership contact "
            "email. It expires in 10 minutes."
        ),
        "ar": (
            "رمز التحقق الخاص بك في Carzo هو: {code}\n\n"
            "أدخل هذا الرمز في التطبيق لتأكيد البريد الإلكتروني الخاص "
            "بمعرض السيارات. تنتهي صلاحيته خلال 10 دقائق."
        ),
        "ku": (
            "کۆدی پشتڕاستکردنەوەی تۆ لە Carzo ئەمەیە: {code}\n\n"
            "ئەم کۆدە لە ئەپەکەدا بنووسە بۆ پشتڕاستکردنەوەی ئیمەیلی پەیوەندی "
            "شوکەکەت. ئەم کۆدە لە ماوەی 10 خولەکدا بەسەردەچێت."
        ),
    },
    "dealer_email_verification_html": {
        "en": (
            "<p>Your Carzo verification code is:</p>"
            "<p style='font-size:24px;font-weight:700;letter-spacing:2px'>{code}</p>"
            "<p>Enter this code in the app to verify your dealership contact "
            "email. It expires in 10 minutes.</p>"
        ),
        "ar": (
            "<p>رمز التحقق الخاص بك في Carzo هو:</p>"
            "<p style='font-size:24px;font-weight:700;letter-spacing:2px'>{code}</p>"
            "<p>أدخل هذا الرمز في التطبيق لتأكيد البريد الإلكتروني الخاص "
            "بمعرض السيارات. تنتهي صلاحيته خلال 10 دقائق.</p>"
        ),
        "ku": (
            "<p>کۆدی پشتڕاستکردنەوەی تۆ لە Carzo ئەمەیە:</p>"
            "<p style='font-size:24px;font-weight:700;letter-spacing:2px'>{code}</p>"
            "<p>ئەم کۆدە لە ئەپەکەدا بنووسە بۆ پشتڕاستکردنەوەی ئیمەیلی "
            "پەیوەندی شوکەکەت. ئەم کۆدە لە ماوەی 10 خولەکدا بەسەردەچێت.</p>"
        ),
    },
    # kk/routes/admin.py -- seller-facing listing-moderation notifications
    # (update_car_status / bulk_update_car_status / delete_car). Titles are
    # always localized; the "hidden" default body is only used when the
    # admin supplied no free-text `reason` (a supplied reason is the
    # admin's own words and is passed through verbatim, never translated).
    "listing_moderation_active_title": {
        "en": "Listing approved",
        "ar": "تمت الموافقة على الإعلان",
        "ku": "ڕێکلامەکە پەسەند کرا",
    },
    "listing_moderation_active_body": {
        "en": "Your listing is now live and visible to buyers.",
        "ar": "إعلانك أصبح الآن مباشرًا ومرئيًا للمشترين.",
        "ku": "ڕێکلامەکەت ئێستا چالاکە و بۆ کڕیاران دیارە.",
    },
    "listing_moderation_hidden_title": {
        "en": "Listing hidden",
        "ar": "تم إخفاء الإعلان",
        "ku": "ڕێکلامەکە شاردرایەوە",
    },
    "listing_moderation_hidden_default_body": {
        "en": "Your listing was hidden by our moderation team.",
        "ar": "تم إخفاء إعلانك من قبل فريق المراجعة لدينا.",
        "ku": "ڕێکلامەکەت لەلایەن تیمی پێداچوونەوەمانەوە شاردرایەوە.",
    },
    "listing_moderation_removed_title": {
        "en": "Listing removed",
        "ar": "تمت إزالة الإعلان",
        "ku": "ڕێکلامەکە لابرا",
    },
    "listing_moderation_removed_body": {
        "en": "Your listing was removed by our moderation team.",
        "ar": "تمت إزالة إعلانك من قبل فريق المراجعة لدينا.",
        "ku": "ڕێکلامەکەت لەلایەن تیمی پێداچوونەوەمانەوە لابرا.",
    },
    # kk/app_settings.py + kk/routes/misc.py -- force-update gate
    # (GET /api/config/app), built-in fallback text when no admin-configured
    # override exists for the resolved locale.
    "force_update_message": {
        "en": "Please update CarNet to continue.",
        "ar": "يرجى تحديث CarNet للمتابعة.",
        "ku": "تکایە CarNet نوێ بکەرەوە بۆ بەردەوامبوون.",
    },
    "soft_update_message": {
        "en": "A newer version of CarNet is available.",
        "ar": "يتوفر إصدار أحدث من CarNet.",
        "ku": "وەشانێکی نوێتری CarNet بەردەستە.",
    },
}


def translate(key: str, locale: str | None, **kwargs) -> str:
    """Look up the MI-03/U-01-scoped string ``key`` for ``locale``.

    Falls back to English if the locale isn't in the table (or is
    unsupported), and to the key itself if the key is unknown (fail-loud in
    development without ever raising in production). Any ``kwargs`` are
    applied via ``str.format``; a missing placeholder degrades to the
    unformatted text rather than raising.
    """
    table = _TRANSLATIONS.get(key)
    if not table:
        return key
    normalized = normalize_locale(locale) or DEFAULT_LOCALE
    text = table.get(normalized) or table.get(DEFAULT_LOCALE)
    if text is None:
        text = next(iter(table.values()))
    if kwargs:
        try:
            return text.format(**kwargs)
        except (KeyError, IndexError):
            return text
    return text
