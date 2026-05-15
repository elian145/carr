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


# User-agents for social / messenger in-app browsers. A 302 to ``carzo://`` here often
# leaves the WebView stuck on "Loading..." (Snapchat, Instagram, etc.).
_IN_APP_BROWSER_MARKERS = (
    "snapchat",
    "instagram",
    "whatsapp",
    "fbav",
    "fban",
    "facebook",
    "twitter",
    "tiktok",
    "musical_ly",
    "line/",
    "linkedinapp",
    "pinterest",
    "gsa/",
)


def _is_in_app_browser(user_agent: str) -> bool:
    ua = (user_agent or "").lower()
    return any(m in ua for m in _IN_APP_BROWSER_MARKERS)


def _listing_canonical_https_url(listing_id: str) -> str:
    qid = quote(listing_id, safe="")
    return request.url_root.rstrip("/") + f"/listing/{qid}"


def _listing_in_app_bridge_html(listing_id: str) -> Response:
    """Minimal page when Snapchat / Instagram open the link in an in-app WebView.

    iOS blocks ``carzo://``. Use the same HTTPS Universal Link (real ``<a>``) so a tap can
    hand off to Safari and open CARZO — same pattern as WhatsApp-style app links.
    """
    ua = (request.headers.get("User-Agent") or "").lower()
    is_android = "android" in ua
    qid = quote(listing_id, safe="")
    canonical = _listing_canonical_https_url(listing_id)
    esc_href = escape(canonical, quote=True)
    id_js = json.dumps(listing_id)
    web_fallback = quote(f"{canonical}?web=1", safe="")

    # iOS in-app WebViews: open HTTPS in a new context so Universal Links can run in Safari.
    link_target = "_blank" if not is_android else "_top"
    open_script = f"""
    var listingId = {id_js};
    var webFallback = {json.dumps(web_fallback)};
    var a = document.getElementById("carzo-open");
    if (!a) return;
    a.addEventListener("click", function (e) {{
      if ({json.dumps(is_android)}) {{
        e.preventDefault();
        window.location.href =
          "intent://listing?id=" + encodeURIComponent(listingId) +
          "#Intent;scheme=carzo;package=com.carzo.app;S.browser_fallback_url=" + webFallback + ";end";
      }}
    }});
"""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Open in CARZO</title>
  <meta property="og:url" content="{esc_href}"/>
  <meta property="al:ios:url" content="{esc_href}"/>
  <meta property="al:ios:app_name" content="CARZO"/>
  <meta property="al:android:url" content="{escape(f"carzo://listing?id={qid}", quote=True)}"/>
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
    }}
    .muted {{
      max-width: 22rem;
      margin-top: 1rem;
      color: #888;
      font-size: 0.82rem;
      line-height: 1.45;
    }}
  </style>
</head>
<body>
  <a class="btn" id="carzo-open" href="{esc_href}" target="{link_target}" rel="noopener noreferrer">Open in CARZO</a>
  <p class="muted">Opens this listing in the CARZO app.</p>
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

    if _is_in_app_browser(ua):
        return None

    # iOS Safari / Chrome: Universal Links on tap — no server redirect.
    return None


def _apple_app_site_association_payload() -> dict:
    team = (os.environ.get("APPLE_TEAM_ID") or "").strip()
    if not team:
        raise ValueError("APPLE_TEAM_ID not set")
    app_id = f"{team}.com.carzo.app"
    path_patterns = _listing_share_path_globs()
    components: list[dict] = [
        {
            "/": "/listing/*",
            "?": {"web": "1"},
            "exclude": True,
            "comment": "Web-only preview; do not open app",
        },
    ]
    for pattern in path_patterns:
        components.append({"/": pattern, "comment": "CARZO listing share"})
    paths = list(path_patterns) + ["NOT /listing/*?web=1", "NOT /listing/*?web=1&*"]
    return {
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appIDs": [app_id],
                    "paths": paths,
                    "components": components,
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
        if _is_in_app_browser(ua):
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

    canonical_js = json.dumps(canonical)
    fallback_js = json.dumps(f"{canonical}?web=1")
    id_js = json.dumps(raw)

    cta_script = f"""  <script>
(function () {{
  var universal = {canonical_js};
  var fallback = {fallback_js};
  var id = {id_js};
  function openCarzoFromShare(ev) {{
    var ua = navigator.userAgent || "";
    if (/Android/i.test(ua)) {{
      if (ev) ev.preventDefault();
      var q = encodeURIComponent(id);
      var fb = encodeURIComponent(fallback);
      var intent =
        "intent://listing?id=" + q +
        "#Intent;scheme=carzo;package=com.carzo.app;S.browser_fallback_url=" + fb + ";end";
      try {{
        window.top.location.href = intent;
      }} catch (e1) {{
        try {{ window.location.href = intent; }} catch (e2) {{}}
      }}
      return;
    }}
    /* iOS: same HTTPS URL as share link — Universal Links open CARZO (not carzo://). */
    if (ev) ev.preventDefault();
    var inApp = /Snapchat|Instagram|FBAN|FBAV|WhatsApp|TikTok|Twitter/i.test(ua);
    try {{
      if (inApp) window.open(universal, "_blank");
      else window.top.location.href = universal;
    }} catch (e3) {{
      try {{ window.location.href = universal; }} catch (e4) {{}}
    }}
  }}
  function bindCta() {{
    var b = document.getElementById("carzo-open-btn");
    if (!b) return;
    b.addEventListener("click", openCarzoFromShare);
  }}
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", bindCta);
  else
    bindCta();
}})();
</script>
"""

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
        <a href="{page_url_esc}" class="cta" id="carzo-open-btn" rel="noopener noreferrer">Open in CARZO app</a>
        <p class="hint">
          Tap the button to open this listing in CARZO. In Snapchat or Instagram, it may open Safari first, then the app.
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

