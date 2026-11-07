from __future__ import annotations

import logging
import os
import re
import json

from flask import Blueprint, Response, abort, current_app, jsonify, redirect, request, send_from_directory

from ..legal_pages import (
    default_privacy_url,
    default_terms_url,
    delete_account_response,
    privacy_response,
    terms_response,
)
from ..config import upload_persistence_mode
from ..listing_moderation import listing_require_approval
from urllib.parse import quote
from html import escape
from werkzeug.utils import safe_join

bp = Blueprint("misc", __name__)
logger = logging.getLogger(__name__)

# Public listing share URLs from the mobile app resolve here (same host as API_BASE).
_LISTING_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{1,128}$")


def _listing_browser_image_url(rel: str) -> str:
    """Turn stored relative / absolute media path into a browser-loadable URL on this host."""
    if not rel:
        return ""
    if rel.startswith("http://") or rel.startswith("https://"):
        return rel
    root = request.url_root.rstrip("/")
    r = rel.lstrip("/")
    if r.startswith("static/"):
        return f"{root}/{r}"
    return f"{root}/static/{r}"


def _trust_config_payload() -> dict:
    """Public trust/support URLs for mobile clients (env + admin DB overrides)."""
    try:
        from ..app_settings import get_platform_settings

        s = get_platform_settings()
        return {
            # No hardcoded fallback mailbox: SUPPORT_EMAIL is required in
            # production (validate_required_secrets() in kk/config.py fails
            # boot if it's missing), so this is never a fake/unreachable
            # placeholder address.
            "support_email": s.get("support_email") or "",
            "support_phone": s.get("support_phone") or "",
            "support_whatsapp": s.get("support_whatsapp") or "",
            "terms_url": s.get("terms_url") or "",
            "privacy_url": s.get("privacy_url") or "",
        }
    except Exception:
        def _env(key: str, default: str = "") -> str:
            return (os.environ.get(key) or default).strip()

        return {
            "support_email": _env("SUPPORT_EMAIL", ""),
            "support_phone": _env("SUPPORT_PHONE", ""),
            "support_whatsapp": _env("SUPPORT_WHATSAPP", ""),
            "terms_url": _env("TERMS_URL", "") or default_terms_url(),
            "privacy_url": _env("PRIVACY_URL", "") or default_privacy_url(),
        }


def _app_config_payload() -> dict:
    """Public client version gates + store URLs (no secrets).

    MI-03: works before authentication (no ``User.locale`` yet), so the
    force-update/soft-update message text is selected purely from the
    request's ``Accept-Language`` header.
    """
    try:
        from ..app_settings import get_platform_settings

        s = get_platform_settings()
    except Exception:
        s = {}

    from ..localization import get_request_locale

    locale = get_request_locale(request.headers.get("Accept-Language"))

    from ..app_settings import public_version_gate_settings

    # Force-update hardening: every version/build/store-URL field is sanitised
    # on READ, so a malformed value already stored in the DB (or env) is served
    # as "unset" and can never lock users out. Field names/types are unchanged.
    gate = public_version_gate_settings(s)

    # Keep in sync with kk.listing_moderation.listing_require_approval
    require_approval = listing_require_approval()

    try:
        from ..app_settings import get_feature_flags

        flags = get_feature_flags()
    except Exception:
        flags = {
            "sell": True,
            "chat": True,
            "dealers": True,
            "comparison": True,
            "saved_searches": True,
        }

    from ..app_settings import get_localized_platform_message

    return {
        "min_app_version": gate["min_app_version"],
        "min_android_build": gate["min_android_build"],
        "min_ios_build": gate["min_ios_build"],
        # MI-03: field names unchanged; value now localized by Accept-Language.
        "force_update_message": get_localized_platform_message(
            "force_update_message", locale, s
        ),
        "recommended_app_version": gate["recommended_app_version"],
        "recommended_android_build": gate["recommended_android_build"],
        "recommended_ios_build": gate["recommended_ios_build"],
        # Additive (old clients ignore unknown keys): latest published version.
        "latest_app_version": gate["latest_app_version"],
        "soft_update_message": get_localized_platform_message(
            "soft_update_message", locale, s
        ),
        "android_store_url": gate["android_store_url"],
        "ios_store_url": gate["ios_store_url"],
        "listing_require_approval": require_approval,
        "feature_flags": flags,
    }


_DIAG_HEADER_RE = re.compile(r"[^A-Za-z0-9._+\- ]")


def _log_client_version_headers() -> None:
    """Diagnostics only: log optional ``X-App-Version`` / ``X-App-Platform``.

    Deliberately NOT used for any decision (no server-side enforcement); the
    values are charset-filtered and truncated so they cannot inject log lines.
    """
    version = request.headers.get("X-App-Version")
    platform = request.headers.get("X-App-Platform")
    if not version and not platform:
        return
    logger.info(
        "config/app client version=%s platform=%s",
        _DIAG_HEADER_RE.sub("", (version or "")[:40]),
        _DIAG_HEADER_RE.sub("", (platform or "")[:20]),
    )


@bp.route("/api/config/trust", methods=["GET"])
def trust_config():
    """Support contact + legal URLs for Help, signup, and settings."""
    return jsonify(_trust_config_payload()), 200


@bp.route("/api/config/app", methods=["GET"])
def app_config():
    """Minimum + recommended client version gates and store URLs."""
    _log_client_version_headers()
    return jsonify(_app_config_payload()), 200


@bp.route("/terms", methods=["GET"])
def terms_of_service():
    """Public Terms of Service (store listing + in-app “Open in browser”)."""
    return terms_response()


@bp.route("/privacy", methods=["GET"])
def privacy_policy():
    """Public Privacy Policy (required for app stores)."""
    return privacy_response()


@bp.route("/delete-account", methods=["GET"])
def delete_account_page():
    """Web account-deletion instructions + request form (Play Console requirement)."""
    return delete_account_response()


@bp.route("/api/account-deletion-request", methods=["POST"])
def account_deletion_request():
    """Public web form: queue a deletion request for support to verify and process."""
    from ..security import check_rate_limit

    limited = check_rate_limit(max_requests=5, window_minutes=60, per_ip=True)
    if limited is not None:
        return limited

    data = request.get_json(silent=True) or {}
    if not data and request.form:
        data = request.form.to_dict()

    phone = str(data.get("phone") or data.get("phone_number") or "").strip()
    email = str(data.get("email") or "").strip()
    details = str(data.get("details") or data.get("message") or "").strip()[:1000]

    from ..account_deletion_requests import (
        RequestStorageError,
        phone_digits,
        submit_request,
    )

    digits = phone_digits(phone)
    if len(digits) < 8:
        return jsonify({"message": "A valid account phone number is required"}), 400

    trust = _trust_config_payload()
    # No hardcoded fallback mailbox: SUPPORT_EMAIL is required in production
    # (validate_required_secrets() in kk/config.py). The email is only a
    # best-effort NOTIFICATION; the request itself is stored durably first.
    support_email = trust.get("support_email") or ""
    logger.info("account_deletion_request phone_suffix=%s email=%s", digits[-4:], bool(email))

    try:
        submit_request(
            phone=phone,
            email=email,
            details=details,
            ip=request.remote_addr,
            support_email=support_email,
        )
    except RequestStorageError:
        # Never claim success for a request that was not durably stored.
        return jsonify(
            {
                "message": (
                    "We could not record your request right now. Please try again "
                    "in a few minutes or contact support."
                )
            }
        ), 503

    # Identical body for new and duplicate submissions, and independent of
    # whether any account exists for this phone (no account enumeration).
    return jsonify(
        {
            "message": (
                "Request received. We will verify ownership and delete the account. "
                "For faster deletion, use Profile → Delete account in the app."
            )
        }
    ), 200


@bp.route("/health", methods=["GET"])
def health():
    """Liveness + optional production readiness hints (no secrets)."""
    payload: dict = {"status": "ok"}
    env = (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "production").strip().lower()
    if env == "production":
        payload["redis_configured"] = bool((os.environ.get("REDIS_URL") or "").strip())
        payload["upload_persistence"] = upload_persistence_mode()
        payload["app_links_android"] = bool(
            (os.environ.get("ANDROID_SHA256_CERT_FINGERPRINTS") or "").strip()
        )
        payload["app_links_ios"] = bool((os.environ.get("APPLE_TEAM_ID") or "").strip())
    return jsonify(payload), 200


@bp.route("/health/push", methods=["GET"])
def health_push():
    """Whether the API can send FCM (no auth; safe for ops checks)."""
    try:
        from ..push import fcm_public_status

        return jsonify(fcm_public_status()), 200
    except Exception:
        return jsonify({"fcm_ready": False, "credentials_present": False}), 200


@bp.route("/", methods=["GET"])
def root():
    return jsonify({"status": "ok"}), 200


def _listing_share_path_globs() -> list[str]:
    """Path patterns for iOS Universal Links / documentation (must match app + LISTING_SHARE_URL_PATH)."""
    raw = (os.environ.get("LISTING_SHARE_URL_PATH") or "listing").strip().strip("/")
    if not raw:
        return ["/listing/*"]
    primary = f"/{raw}/*"
    out = [primary]
    if not raw.startswith("listing"):
        out.append("/listing/*")
    return out


# In-app WebViews that block Universal Links and ``carzo://`` (Snapchat, Instagram, etc.).
_IN_APP_BRIDGE_MARKERS = (
    "snapchat",
    "instagram",
    "tiktok",
    "musical_ly",
    "fban",
    "fbav",
    "fb_iab",
    "twitter",
)


def _is_ios_in_app_webkit(user_agent: str) -> bool:
    """Instagram/Snapchat on iOS often use a generic WebKit UA without 'Safari'."""
    ual = (user_agent or "").lower()
    if not any(x in ual for x in ("iphone", "ipad", "ipod")):
        return False
    if "applewebkit" not in ual:
        return False
    if any(x in ual for x in ("safari", "crios", "fxios", "edgios")):
        return False
    return True


def _needs_in_app_bridge(user_agent: str) -> bool:
    ua = (user_agent or "").lower()
    if any(m in ua for m in _IN_APP_BRIDGE_MARKERS):
        return True
    return _is_ios_in_app_webkit(user_agent)


def _listing_handoff_script(listing_id: str, is_android: bool, *, auto_attempt: bool = True) -> str:
    """JS to leave Snapchat/Instagram WebView and open CarNet (Safari or Android intent)."""
    qid = quote(listing_id, safe="")
    deep = f"carzo://listing?id={qid}"
    canonical = _listing_canonical_https_url(listing_id)
    id_js = json.dumps(listing_id)
    canonical_js = json.dumps(canonical)
    deep_js = json.dumps(deep)
    web_fallback = quote(f"{canonical}?web=1", safe="")
    auto_js = "true" if auto_attempt else "false"
    return f"""
(function () {{
  var listingId = {id_js};
  var universal = {canonical_js};
  var deep = {deep_js};
  var webFallback = {json.dumps(web_fallback)};
  var isAndroid = {json.dumps(is_android)};
  var autoAttempt = {auto_js};

  window.carzoIsInAppWebView = function () {{
    var ua = navigator.userAgent || "";
    if (/Snapchat|Instagram|FBAN|FBAV|FB_IAB|Twitter|TikTok|Musical_ly|Line\\//i.test(ua)) return true;
    if (!/iPhone|iPad|iPod/i.test(ua)) return false;
    if (/CriOS|FxiOS|EdgiOS|Safari/i.test(ua)) return false;
    return /AppleWebKit/i.test(ua);
  }};

  window.carzoOpenAndroidIntent = function () {{
    window.location.href =
      "intent://listing?id=" + encodeURIComponent(listingId) +
      "#Intent;scheme=carzo;package=com.carnetiq.app;S.browser_fallback_url=" + webFallback + ";end";
  }};

  window.carzoOpenInSafari = function () {{
    /* Never assign window.location = universal here: same URL in this WebView
       reloads the bridge page → infinite loop and endless "Opening…" spinner. */
    try {{
      var w = window.open(universal, "_blank", "noopener,noreferrer");
      if (w) return true;
    }} catch (e1) {{}}
    try {{
      var a = document.createElement("a");
      a.href = universal;
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      document.body.appendChild(a);
      a.click();
      a.remove();
      return true;
    }} catch (e2) {{}}
    if (universal.indexOf("https://") === 0) {{
      try {{
        window.location.href = "x-safari-" + universal;
        return true;
      }} catch (e3) {{}}
    }}
    return false;
  }};

  window.carzoHandoffContinue = function (ev) {{
    if (ev) ev.preventDefault();
    if (isAndroid) window.carzoOpenAndroidIntent();
    else window.carzoOpenInSafari();
  }};

  /** User-tap attempt to open the native app (custom scheme). May work outside strict WebViews; Instagram often blocks. */
  window.carzoTryDeepLink = function (ev) {{
    if (ev) ev.preventDefault();
    try {{
      window.location.href = deep;
    }} catch (e0) {{}}
  }};

  function wire(btnId) {{
    var btn = document.getElementById(btnId);
    if (btn) btn.addEventListener("click", window.carzoHandoffContinue);
  }}

  function wireTryApp(btnId) {{
    var btn = document.getElementById(btnId);
    if (btn) btn.addEventListener("click", window.carzoTryDeepLink);
  }}

  var soleOpenApp = document.getElementById("carzo-open-app");
  if (soleOpenApp) {{
    soleOpenApp.addEventListener("click", function (ev) {{
      ev.preventDefault();
      if (isAndroid) window.carzoOpenAndroidIntent();
      else window.carzoTryDeepLink(ev);
    }});
  }} else {{
    wire("carzo-open");
    wire("carzo-handoff-btn");
    if (!isAndroid) wireTryApp("carzo-try-app-ios");
  }}

  if (!autoAttempt) return;
  if (isAndroid) {{
    setTimeout(window.carzoOpenAndroidIntent, 80);
    return;
  }}
  /* iOS: auto-try custom scheme on load (same as tapping Open in CarNet app). May be blocked in some WebViews. */
  setTimeout(function () {{
    try {{ window.location.href = deep; }} catch (e4) {{}}
  }}, 120);
}})();
"""


def _listing_canonical_https_url(listing_id: str) -> str:
    qid = quote(listing_id, safe="")
    return request.url_root.rstrip("/") + f"/listing/{qid}"


def _listing_in_app_bridge_html(listing_id: str) -> Response:
    """Snapchat / Instagram in-app browsers: minimal page that opens CarNet (intent / ``carzo://``)."""
    ua = (request.headers.get("User-Agent") or "").lower()
    is_android = "android" in ua
    qid = quote(listing_id, safe="")
    deep = f"carzo://listing?id={qid}"
    canonical = _listing_canonical_https_url(listing_id)
    esc_href = escape(canonical, quote=True)
    esc_deep = escape(deep, quote=True)
    open_script = _listing_handoff_script(listing_id, is_android, auto_attempt=True)

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Open in CarNet</title>
  <meta property="og:url" content="{esc_href}"/>
  <meta property="al:ios:url" content="{esc_deep}"/>
  <meta property="al:ios:app_name" content="CarNet"/>
  <meta property="al:android:url" content="{esc_deep}"/>
  <meta property="al:android:package" content="com.carnetiq.app"/>
  <meta property="al:android:app_name" content="CarNet"/>
  <style>
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 1.5rem;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      background: #111;
      color: #fff;
      text-align: center;
    }}
    .btn {{
      display: block;
      width: 100%;
      max-width: 20rem;
      padding: 1.1rem 1.25rem;
      background: linear-gradient(180deg, #ff7a1a, #e85f00);
      color: #fff !important;
      font-weight: 700;
      font-size: 1.1rem;
      border-radius: 14px;
      text-decoration: none;
      font-family: inherit;
      border: none;
      cursor: pointer;
      -webkit-appearance: none;
    }}
  </style>
</head>
<body>
  <button type="button" class="btn" id="carzo-open-app">Open in CarNet app</button>
  <script>{open_script}</script>
</body>
</html>"""
    return Response(
        html,
        200,
        headers={
            "Content-Type": "text/html; charset=utf-8",
            "Cache-Control": "no-store",
        },
    )


def _listing_mobile_app_redirect(listing_id: str):
    """Open the native app from a shared listing URL.

    - **Android** (including Snapchat / Instagram WebViews): ``intent://`` 302.
    - **iOS**: never 302 to ``carzo://`` (Snapchat hangs on Loading). Chat taps must
      use Universal Links; in-app WebViews get the HTTPS bridge page instead.
    """
    ua = (request.headers.get("User-Agent") or "").lower()
    qid = quote(listing_id, safe="")
    canonical = _listing_canonical_https_url(listing_id)
    web_fallback = quote(f"{canonical}?web=1", safe="")

    if "android" in ua:
        intent = (
            f"intent://listing?id={qid}"
            f"#Intent;scheme=carzo;package=com.carnetiq.app;"
            f"S.browser_fallback_url={web_fallback};end"
        )
        return redirect(intent, code=302)

    if _needs_in_app_bridge(ua):
        return None

    # iOS Safari / Chrome: Universal Links on tap — no server redirect.
    return None


def _apple_app_site_association_payload() -> dict:
    """AASA for iOS Universal Links.

    Keep this minimal (``appID`` + ``paths`` only). Mixing ``components`` with invalid
    ``NOT`` path rules caused iOS to reject the whole file and stop opening the app.
    """
    team = (os.environ.get("APPLE_TEAM_ID") or "").strip()
    if not team:
        raise ValueError("APPLE_TEAM_ID not set")
    app_id = f"{team}.com.carzo.app"
    path_patterns = _listing_share_path_globs()
    return {
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appID": app_id,
                    "paths": path_patterns,
                }
            ],
        }
    }


def _apple_app_site_association_response() -> Response:
    try:
        data = _apple_app_site_association_payload()
    except ValueError:
        abort(404)
    return Response(
        json.dumps(data, separators=(",", ":")),
        200,
        mimetype="application/json",
        headers={
            "Cache-Control": "public, max-age=300",
            "Content-Type": "application/json",
        },
    )


@bp.route("/.well-known/apple-app-site-association", methods=["GET"])
def apple_app_site_association_well_known():
    """iOS Universal Links (``/.well-known/`` path)."""
    return _apple_app_site_association_response()


@bp.route("/apple-app-site-association", methods=["GET"])
def apple_app_site_association_root():
    """iOS Universal Links (root path — some crawlers use this)."""
    return _apple_app_site_association_response()


@bp.route("/.well-known/assetlinks.json", methods=["GET"])
def android_assetlinks():
    """Android App Links — comma-separated SHA-256 cert fingerprints in ``ANDROID_SHA256_CERT_FINGERPRINTS``."""
    raw = (os.environ.get("ANDROID_SHA256_CERT_FINGERPRINTS") or "").strip()
    if not raw:
        abort(404)
    # Normalize: trim, uppercase hex, drop empties. Accept space-separated typos by
    # also splitting on whitespace after commas.
    fps: list[str] = []
    for part in raw.replace(";", ",").split(","):
        fp = " ".join(part.split()).upper()
        if fp:
            fps.append(fp)
    if not fps:
        abort(404)
    body = [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "com.carnetiq.app",
                "sha256_cert_fingerprints": fps,
            },
        }
    ]
    return Response(
        json.dumps(body),
        200,
        mimetype="application/json",
        headers={"Cache-Control": "public, max-age=300"},
    )


@bp.route("/verify-email", methods=["GET"])
def verify_email_landing():
    """Browser landing page for the account-email verification link.

    The token is applied by the app calling ``POST /api/auth/verify-email``
    (see ``verify_email_page.dart``), not by this page — it only hands the
    token to the app or lets the user paste it in manually.
    """
    token = (request.args.get("token") or "").strip()
    if not token:
        abort(404)

    deep = f"carzo://auth/verify-email?token={quote(token, safe='')}"
    esc_deep = escape(deep, quote=True)
    esc_token = escape(token, quote=True)

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Verify your Carzo email</title>
  <style>
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 1.5rem;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      background: #111;
      color: #fff;
      text-align: center;
    }}
    .btn {{
      display: block;
      width: 100%;
      max-width: 20rem;
      padding: 1.1rem 1.25rem;
      margin-bottom: 1rem;
      background: linear-gradient(180deg, #ff7a1a, #e85f00);
      color: #fff !important;
      font-weight: 700;
      font-size: 1.1rem;
      border-radius: 14px;
      text-decoration: none;
      font-family: inherit;
    }}
    .token {{
      max-width: 20rem;
      word-break: break-all;
      font-size: 0.85rem;
      color: #bbb;
      margin-top: 0.5rem;
    }}
  </style>
</head>
<body>
  <p>Tap below to verify your email in the Carzo app.</p>
  <a class="btn" id="carzo-open" href="{esc_deep}">Open in Carzo app</a>
  <p class="token">App not opening? Paste this code in Carzo &rarr; Verify email:<br/>{esc_token}</p>
  <script>
    setTimeout(function () {{ window.location.href = {json.dumps(deep)}; }}, 120);
  </script>
</body>
</html>"""
    return Response(
        html,
        200,
        headers={
            "Content-Type": "text/html; charset=utf-8",
            "Cache-Control": "no-store",
        },
    )


@bp.route("/listing/<listing_id>", methods=["GET"])
def listing_share_landing(listing_id: str):
    """Public listing page for shared URLs: ``https://<host>/listing/<id>`` *is* the listing."""
    from sqlalchemy.orm import joinedload, selectinload

    from ..listing_visibility import listing_is_public
    from ..models import Car
    from ..routes.cars import _with_media_compat

    raw = (listing_id or "").strip()
    if not raw or not _LISTING_ID_RE.match(raw):
        abort(404)

    ua = request.headers.get("User-Agent") or ""
    if request.args.get("web") != "1":
        app_redirect = _listing_mobile_app_redirect(raw)
        if app_redirect is not None:
            return app_redirect
        if _needs_in_app_bridge(ua):
            return _listing_in_app_bridge_html(raw)

    car = (
        Car.query.options(
            selectinload(Car.images),
            selectinload(Car.videos),
            joinedload(Car.seller),
        )
        .filter_by(public_id=raw, is_active=True)
        .first()
    )
    if not car and raw.isdigit():
        car = (
            Car.query.options(
                selectinload(Car.images),
                selectinload(Car.videos),
                joinedload(Car.seller),
            )
            .filter_by(id=int(raw), is_active=True)
            .first()
        )
    if not car or not listing_is_public(car):
        nf = "<!DOCTYPE html><html><head><meta charset='utf-8'/><title>Not found</title></head><body><p>Listing not found.</p></body></html>"
        return Response(nf, 404, {"Content-Type": "text/html; charset=utf-8"})

    d = _with_media_compat(car)
    title_raw = (d.get("title") or "").strip() or "Listing"
    title = escape(title_raw)
    brand_raw = str(d.get("brand") or "").strip()
    model_raw = str(d.get("model") or "").strip()
    trim_raw = str(d.get("trim") or "").strip()
    sub_parts_raw = [p for p in (brand_raw, model_raw, trim_raw) if p]
    subline = escape(" · ".join(sub_parts_raw)) if sub_parts_raw else ""
    price = d.get("price")
    currency = escape(str(d.get("currency") or "").strip())
    try:
        price_s = escape(f"{float(price):,.0f}") if price is not None else ""
    except (TypeError, ValueError):
        price_s = escape(str(price)) if price is not None else ""
    year = escape(str(d.get("year") or ""))
    mileage = d.get("mileage")
    try:
        mile_s = escape(f"{int(mileage):,}") if mileage is not None else ""
    except (TypeError, ValueError):
        mile_s = escape(str(mileage)) if mileage is not None else ""
    loc = escape(str(d.get("location") or d.get("city") or "").strip())
    desc = (d.get("description") or "").strip()
    if len(desc) > 900:
        desc = desc[:900] + "…"
    desc_html = escape(desc).replace("\n", "<br/>\n") if desc else ""

    img_rel = (d.get("image_url") or "").strip()
    img_url = _listing_browser_image_url(img_rel)
    img_block = ""
    if img_url:
        esc_img = escape(img_url, quote=True)
        img_block = f'<div class="hero"><img src="{esc_img}" alt="" loading="lazy"/></div>'

    deep = f"carzo://listing?id={quote(raw, safe='')}"
    esc_deep = escape(deep, quote=True)
    canonical = request.url_root.rstrip("/") + f"/listing/{quote(raw, safe='')}"
    page_url_esc = escape(canonical, quote=True)
    og_desc = escape(
        (desc[:200] + "…") if len(desc) > 200 else desc,
        quote=True,
    ) if desc else escape(f"{currency} {price_s}".strip(), quote=True)

    app_store_id = (os.environ.get("IOS_APP_STORE_ID") or "").strip()
    itunes_meta = ""
    if app_store_id.isdigit():
        arg = escape(deep, quote=True)
        itunes_meta = (
            f'<meta name="apple-itunes-app" '
            f'content="app-id={escape(app_store_id, quote=True)}, app-argument={arg}"/>\n'
        )

    og_image_meta = ""
    if img_url:
        og_image_meta = (
            f'  <meta property="og:image" content="{escape(img_url, quote=True)}"/>\n'
        )

    subline_html = f'<p class="subline">{subline}</p>' if subline else ""

    ua_lower = (request.headers.get("User-Agent") or "").lower()
    page_is_android = "android" in ua_lower
    handoff_js = _listing_handoff_script(raw, page_is_android, auto_attempt=False)
    deep_js = json.dumps(deep)

    cta_script = f"""  <script>
{handoff_js}
(function () {{
  var deep = {deep_js};
  var ua = navigator.userAgent || "";

  function tryAutoOpen() {{
    if (window.carzoIsInAppWebView && window.carzoIsInAppWebView()) {{
      var overlay = document.getElementById("carzo-handoff-overlay");
      if (overlay) overlay.style.display = "flex";
      var ab = document.getElementById("carzo-handoff-btn");
      if (ab && /Android/i.test(ua)) ab.style.display = "block";
      var sl = document.getElementById("carzo-handoff-link");
      if (sl && /Android/i.test(ua)) sl.style.display = "none";
      return;
    }}
    if (/Android/i.test(ua)) {{
      window.carzoOpenAndroidIntent();
      return;
    }}
    if (/iPhone|iPad|iPod/i.test(ua)) {{
      try {{ window.top.location.href = deep; }} catch (e) {{ window.location.href = deep; }}
    }}
  }}

  var mainBtn = document.getElementById("carzo-open-btn");
  if (mainBtn) {{
    mainBtn.addEventListener("click", function (ev) {{
      if (window.carzoIsInAppWebView && window.carzoIsInAppWebView()) {{
        ev.preventDefault();
        window.carzoHandoffContinue(ev);
      }}
    }});
  }}

  tryAutoOpen();
}})();
</script>
"""

    handoff_overlay = f"""
  <div id="carzo-handoff-overlay" style="display:none;position:fixed;inset:0;z-index:99999;background:#111;color:#fff;flex-direction:column;align-items:center;justify-content:center;padding:1.5rem;text-align:center;font-family:-apple-system,BlinkMacSystemFont,sans-serif;">
    <p style="font-size:1rem;margin:0 0 0.75rem;max-width:22rem;line-height:1.5">Instagram / Snapchat cannot open CarNet from here.</p>
    <p style="font-size:0.88rem;margin:0 0 1rem;max-width:22rem;line-height:1.5;color:#bbb">Tap the <strong>compass</strong> at the bottom (Open in Safari), or <strong>⋯</strong> → Open in Safari.</p>
    <a href="{page_url_esc}" target="_blank" rel="noopener noreferrer" id="carzo-handoff-link" style="display:block;width:100%;max-width:20rem;padding:1.1rem 1.25rem;background:linear-gradient(180deg,#ff7a1a,#e85f00);color:#fff;font-weight:700;font-size:1.1rem;border-radius:14px;text-decoration:none;-webkit-appearance:none;">Open in Safari</a>
    <button type="button" id="carzo-handoff-btn" style="display:none;margin-top:0.75rem;width:100%;max-width:20rem;padding:1rem;background:#333;color:#fff;font-weight:600;font-size:1rem;border-radius:12px;border:1px solid #555">Open in app (Android)</button>
  </div>"""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>{title} · CarNet</title>
  <link rel="canonical" href="{page_url_esc}"/>
  <meta property="og:type" content="website"/>
  <meta property="og:title" content="{title} · CarNet"/>
  <meta property="og:description" content="{og_desc}"/>
  <meta property="og:url" content="{page_url_esc}"/>
{og_image_meta}  <meta name="twitter:card" content="summary_large_image"/>
{itunes_meta}  <style>
    body {{
      margin: 0;
      font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
      background: #ececf0;
      color: #111;
    }}
    .topbar {{
      background: #111;
      color: #fff;
      padding: 0.65rem 1rem;
      font-weight: 700;
      font-size: 0.95rem;
      letter-spacing: 0.02em;
    }}
    .wrap {{
      max-width: 28rem;
      margin: 0 auto;
      padding: 1rem 1rem 2.5rem;
    }}
    .card {{
      background: #fff;
      border-radius: 18px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.08);
      overflow: hidden;
    }}
    .hero img {{
      width: 100%;
      display: block;
      background: #ddd;
      aspect-ratio: 16/10;
      object-fit: cover;
    }}
    .inner {{ padding: 1.1rem 1.15rem 1.25rem; }}
    h1 {{
      font-size: 1.25rem;
      font-weight: 700;
      margin: 0 0 0.35rem;
      line-height: 1.25;
    }}
    .subline {{
      margin: 0 0 0.5rem;
      color: #555;
      font-size: 0.9rem;
      line-height: 1.35;
    }}
    .meta {{ color: #666; font-size: 0.88rem; margin: 0 0 0.75rem; }}
    .price {{
      font-size: 1.45rem;
      font-weight: 800;
      color: #e85f00;
      margin: 0 0 0.85rem;
    }}
    .desc {{
      line-height: 1.55;
      font-size: 0.92rem;
      color: #333;
      margin-bottom: 1rem;
    }}
    .cta {{
      display: block;
      width: 100%;
      box-sizing: border-box;
      text-align: center;
      padding: 0.95rem 1rem;
      background: linear-gradient(180deg, #ff7a1a 0%, #e85f00 100%);
      color: #fff !important;
      font-weight: 700;
      font-size: 1rem;
      border-radius: 12px;
      text-decoration: none;
      margin: 0.25rem 0 0.5rem;
      border: none;
      cursor: pointer;
      font-family: inherit;
      -webkit-appearance: none;
      appearance: none;
    }}
  </style>
</head>
<body>
{handoff_overlay}
  <div id="web-shell">
  <div class="topbar">CarNet</div>
  <div class="wrap">
    <div class="card">
      {img_block}
      <div class="inner">
        <h1>{title}</h1>
        {subline_html}
        <p class="meta">{year} · {mile_s} · {loc}</p>
        <p class="price">{currency} {price_s}</p>
        <div class="desc">{desc_html}</div>
        <a href="{esc_deep}" class="cta" id="carzo-open-btn" rel="noopener noreferrer">Open in CarNet app</a>
      </div>
    </div>
  </div>
  </div>
{cta_script}
</body>
</html>"""
    return Response(html, 200, {"Content-Type": "text/html; charset=utf-8"})


# F-27: extensions that browsers treat as active content. Nothing legitimate is ever
# stored under ``uploads/`` with these (photos are re-encoded to JPEG, videos to MP4), so
# refuse to serve them from the user-upload tree even if one is dropped on the disk.
_UPLOAD_ACTIVE_CONTENT_EXTS = frozenset(
    {
        ".html", ".htm", ".xhtml", ".shtml", ".svg", ".svgz", ".xml", ".xsl", ".xslt",
        ".js", ".mjs", ".css", ".json", ".swf", ".php", ".py", ".pl", ".cgi",
    }
)


def _static_path_is_refused(filename: str) -> bool:
    """True for paths that must never be served by ``/static/<path>`` (404).

    * hidden segments (``.env``, ``.git/...``) anywhere in the path;
    * active-content file types under the user-upload tree (``uploads/``).

    Path traversal (``..``) is handled separately by ``safe_join`` /
    ``send_from_directory``.
    """
    parts = [p for p in filename.replace("\\", "/").split("/") if p]
    if any(p.startswith(".") for p in parts):
        return True
    if parts and parts[0] == "uploads":
        ext = os.path.splitext(parts[-1])[1].lower()
        if ext in _UPLOAD_ACTIVE_CONTENT_EXTS:
            return True
    return False


def _harden_static_response(filename: str, resp):
    """Defence-in-depth headers for files served from the user-upload tree."""
    if filename.startswith("uploads/"):
        resp.headers["X-Content-Type-Options"] = "nosniff"
        # Only relevant if the file is opened as a document; <img>/<video> loads ignore it.
        resp.headers.setdefault("Content-Security-Policy", "default-src 'none'; sandbox")
    return resp


@bp.route("/static/<path:filename>")
def static_files(filename: str):
    """Serve static files from kk/static, then repo root static/ as fallback.

    User-generated uploads (photos/videos) are stored under UPLOAD_FOLDER (see app_factory).
    When UPLOAD_FOLDER points to a persistent volume, serve those files here so URLs like
    /static/uploads/car_videos/... keep working after redeploys.

    Listing media is public by design (the R2 bucket is public-read too). There is no
    directory listing (``os.path.isfile`` gate) and traversal is rejected by ``safe_join``.
    """
    if filename.startswith("uploads/uploads/"):
        filename = filename[len("uploads/") :]

    if _static_path_is_refused(filename):
        abort(404)

    # 1) Configured upload root (may be outside kk/static for persistent storage)
    upload_root = (current_app.config.get("UPLOAD_FOLDER") or "").strip()
    if upload_root and filename.startswith("uploads/"):
        rel_under_uploads = filename[len("uploads/") :]
        try:
            safe_path = safe_join(upload_root, rel_under_uploads)
            if safe_path and os.path.isfile(safe_path):
                return _harden_static_response(
                    filename, send_from_directory(upload_root, rel_under_uploads)
                )
        except Exception as e:
            logger.warning(
                "static_files UPLOAD_FOLDER failed for %s: %s",
                filename,
                e,
                exc_info=True,
            )

    static_dir = os.path.join(current_app.root_path, "static")
    try:
        safe_path = safe_join(static_dir, filename)
        if safe_path and os.path.isfile(safe_path):
            return _harden_static_response(filename, send_from_directory(static_dir, filename))
    except Exception as e:
        logger.warning("static_files kk/static failed for %s: %s", filename, e, exc_info=True)

    repo_static = os.path.abspath(os.path.join(current_app.root_path, "..", "static"))
    try:
        safe_path = safe_join(repo_static, filename)
        if safe_path and os.path.isfile(safe_path):
            return _harden_static_response(filename, send_from_directory(repo_static, filename))
    except Exception as e:
        logger.warning("static_files repo static failed for %s: %s", filename, e, exc_info=True)

    abort(404)

