from __future__ import annotations

import logging
import os
import re
import json

from flask import Blueprint, Response, abort, current_app, jsonify, redirect, request, send_from_directory
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


@bp.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


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
    """JS to leave Snapchat/Instagram WebView and open CARZO (Safari or Android intent)."""
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
      "#Intent;scheme=carzo;package=com.carzo.app;S.browser_fallback_url=" + webFallback + ";end";
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

  wire("carzo-open");
  wire("carzo-handoff-btn");
  if (!isAndroid) wireTryApp("carzo-try-app-ios");

  if (!autoAttempt) return;
  if (isAndroid) {{
    setTimeout(window.carzoOpenAndroidIntent, 80);
    return;
  }}
  /* iOS in-app: do not auto-open — it often fails and same-URL navigation loops. */
}})();
"""


def _listing_canonical_https_url(listing_id: str) -> str:
    qid = quote(listing_id, safe="")
    return request.url_root.rstrip("/") + f"/listing/{qid}"


def _listing_in_app_bridge_html(listing_id: str) -> Response:
    """Snapchat / Instagram in-app browsers cannot use Universal Links or ``carzo://``.

    Hand off to Safari (iOS) or fire an Android intent so CARZO can open outside the WebView.
    """
    ua = (request.headers.get("User-Agent") or "").lower()
    is_android = "android" in ua
    qid = quote(listing_id, safe="")
    deep = f"carzo://listing?id={qid}"
    canonical = _listing_canonical_https_url(listing_id)
    esc_href = escape(canonical, quote=True)
    esc_deep = escape(deep, quote=True)
    open_script = _listing_handoff_script(listing_id, is_android, auto_attempt=is_android)

    if is_android:
        steps_html = (
            "<ol class=\"steps\">"
            "<li>Tap <strong>Open in CARZO app</strong> below (or wait a moment — we try automatically).</li>"
            "<li>If nothing happens, use <strong>Open in Chrome</strong> or your browser’s menu to open this page outside Instagram.</li>"
            "</ol>"
        )
        buttons_html = f"""
  <button type="button" class="btn" id="carzo-open" style="margin-top:0">Open in CARZO app</button>
  <a class="btn btn-secondary" href="{esc_href}" target="_blank" rel="noopener noreferrer" id="carzo-open-safari" style="margin-top:0.75rem">Continue in browser</a>
"""
    else:
        steps_html = (
            "<ol class=\"steps\">"
            "<li>Tap <strong>Open in CARZO app</strong> below — same pattern as other apps (opens CARZO when this browser allows it).</li>"
            "<li>If nothing happens, tap <strong>Continue in Safari</strong>. From Safari, the listing opens in CARZO (Universal Link).</li>"
            "</ol>"
        )
        buttons_html = f"""
  <button type="button" class="btn" id="carzo-try-app-ios" style="margin-top:0">Open in CARZO app</button>
  <a class="btn btn-secondary" href="{esc_href}" target="_blank" rel="noopener noreferrer" id="carzo-open-safari" style="margin-top:0.75rem">Continue in Safari</a>
"""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Open in CARZO</title>
  <meta property="og:url" content="{esc_href}"/>
  <meta property="al:ios:url" content="{esc_deep}"/>
  <meta property="al:ios:app_name" content="CARZO"/>
  <meta property="al:android:url" content="{esc_deep}"/>
  <meta property="al:android:package" content="com.carzo.app"/>
  <meta property="al:android:app_name" content="CARZO"/>
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
    .btn-secondary {{
      background: transparent;
      color: #ff9a4a !important;
      border: 2px solid #e85f00;
      margin-top: 0.75rem;
    }}
    .muted {{
      max-width: 22rem;
      margin-top: 1rem;
      color: #aaa;
      font-size: 0.88rem;
      line-height: 1.5;
    }}
    .steps {{
      max-width: 22rem;
      text-align: left;
      color: #ccc;
      font-size: 0.9rem;
      line-height: 1.55;
      margin: 0 0 1.25rem;
    }}
    .steps strong {{ color: #fff; }}
  </style>
</head>
<body>
  <p class="muted" style="margin-top:0;margin-bottom:0.75rem;font-size:1rem;color:#fff;font-weight:600">
    Open this listing in CARZO
  </p>
  {steps_html}
  {buttons_html}
  <p class="muted">Instagram opens links inside its own browser first — the buttons above are how other apps hand you off to the real app or to Safari.</p>
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
            f"#Intent;scheme=carzo;package=com.carzo.app;"
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
    fps = [x.strip() for x in raw.split(",") if x.strip()]
    if not fps:
        abort(404)
    body = [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "com.carzo.app",
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


@bp.route("/listing/<listing_id>", methods=["GET"])
def listing_share_landing(listing_id: str):
    """Public listing page for shared URLs: ``https://<host>/listing/<id>`` *is* the listing."""
    from sqlalchemy.orm import joinedload, selectinload

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
    if not car:
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
    <p style="font-size:1rem;margin:0 0 0.75rem;max-width:22rem;line-height:1.5">Instagram / Snapchat cannot open CARZO from here.</p>
    <p style="font-size:0.88rem;margin:0 0 1rem;max-width:22rem;line-height:1.5;color:#bbb">Tap the <strong>compass</strong> at the bottom (Open in Safari), or <strong>⋯</strong> → Open in Safari.</p>
    <a href="{page_url_esc}" target="_blank" rel="noopener noreferrer" id="carzo-handoff-link" style="display:block;width:100%;max-width:20rem;padding:1.1rem 1.25rem;background:linear-gradient(180deg,#ff7a1a,#e85f00);color:#fff;font-weight:700;font-size:1.1rem;border-radius:14px;text-decoration:none;-webkit-appearance:none;">Open in Safari</a>
    <button type="button" id="carzo-handoff-btn" style="display:none;margin-top:0.75rem;width:100%;max-width:20rem;padding:1rem;background:#333;color:#fff;font-weight:600;font-size:1rem;border-radius:12px;border:1px solid #555">Open in app (Android)</button>
  </div>"""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>{title} · CARZO</title>
  <link rel="canonical" href="{page_url_esc}"/>
  <meta property="og:type" content="website"/>
  <meta property="og:title" content="{title} · CARZO"/>
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
    .hint {{
      font-size: 0.8rem;
      color: #666;
      line-height: 1.45;
      margin: 0 0 0.25rem;
    }}
    .foot {{
      margin-top: 1rem;
      padding-top: 1rem;
      border-top: 1px solid #eee;
      font-size: 0.8rem;
      color: #888;
    }}
    .foot a {{ color: #e85f00; font-weight: 600; }}
  </style>
</head>
<body>
{handoff_overlay}
  <div id="web-shell">
  <div class="topbar">CARZO</div>
  <div class="wrap">
    <div class="card">
      {img_block}
      <div class="inner">
        <h1>{title}</h1>
        {subline_html}
        <p class="meta">{year} · {mile_s} · {loc}</p>
        <p class="price">{currency} {price_s}</p>
        <div class="desc">{desc_html}</div>
        <a href="{esc_deep}" class="cta" id="carzo-open-btn" rel="noopener noreferrer">Open in CARZO app</a>
        <p class="hint">
          Opening CARZO… If nothing happens, tap the orange button above.
        </p>
        <p class="foot">
          Universal Links open this URL in CARZO when iOS/Android is fully configured.
          Web-only view: add <strong>?web=1</strong> to the URL to skip opening the app.
        </p>
      </div>
    </div>
  </div>
  </div>
{cta_script}
</body>
</html>"""
    return Response(html, 200, {"Content-Type": "text/html; charset=utf-8"})


@bp.route("/static/<path:filename>")
def static_files(filename: str):
    """Serve static files from kk/static, then repo root static/ as fallback.

    User-generated uploads (photos/videos) are stored under UPLOAD_FOLDER (see app_factory).
    When UPLOAD_FOLDER points to a persistent volume, serve those files here so URLs like
    /static/uploads/car_videos/... keep working after redeploys.
    """
    if filename.startswith("uploads/uploads/"):
        filename = filename[len("uploads/") :]

    # 1) Configured upload root (may be outside kk/static for persistent storage)
    upload_root = (current_app.config.get("UPLOAD_FOLDER") or "").strip()
    if upload_root and filename.startswith("uploads/"):
        rel_under_uploads = filename[len("uploads/") :]
        try:
            safe_path = safe_join(upload_root, rel_under_uploads)
            if safe_path and os.path.isfile(safe_path):
                return send_from_directory(upload_root, rel_under_uploads)
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
            return send_from_directory(static_dir, filename)
    except Exception as e:
        logger.warning("static_files kk/static failed for %s: %s", filename, e, exc_info=True)

    repo_static = os.path.abspath(os.path.join(current_app.root_path, "..", "static"))
    try:
        safe_path = safe_join(repo_static, filename)
        if safe_path and os.path.isfile(safe_path):
            return send_from_directory(repo_static, filename)
    except Exception as e:
        logger.warning("static_files repo static failed for %s: %s", filename, e, exc_info=True)

    abort(404)

