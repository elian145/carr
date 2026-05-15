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


def _listing_in_app_bridge_html(listing_id: str) -> Response:
    """Guide page for Snapchat / Instagram / etc. — their WebView blocks ``carzo://`` taps."""
    ua = (request.headers.get("User-Agent") or "").lower()
    is_android = "android" in ua
    qid = quote(listing_id, safe="")
    deep = f"carzo://listing?id={qid}"
    https_url = request.url_root.rstrip("/") + f"/listing/{qid}"
    web_fallback = quote(f"{https_url}?web=1", safe="")
    https_js = json.dumps(https_url)
    deep_js = json.dumps(deep)
    id_js = json.dumps(listing_id)

    android_extra = ""
    if is_android:
        android_extra = """
    <button type="button" class="btn" id="carzo-open">Try open in CARZO app</button>
    <p class="muted">If nothing happens, use Copy link and open it in Chrome.</p>"""

    ios_steps = """
    <ol class="steps">
      <li>Tap the <strong>compass</strong> icon at the bottom of this screen</li>
      <li>Choose <strong>Open in Safari</strong></li>
      <li>CARZO will open on this listing automatically</li>
    </ol>
    <p class="muted">Snapchat and similar apps block the &ldquo;open app&rdquo; button here — Safari is required once.</p>"""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Open in CARZO</title>
  <style>
    body {{
      margin: 0;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 1.5rem 1.25rem 2rem;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      background: #111;
      color: #fff;
      text-align: center;
    }}
    h1 {{ font-size: 1.2rem; margin: 0 0 1rem; max-width: 22rem; }}
    .steps {{
      text-align: left;
      max-width: 22rem;
      margin: 0 0 1rem;
      padding-left: 1.2rem;
      color: #ddd;
      font-size: 0.95rem;
      line-height: 1.55;
    }}
    .steps li {{ margin-bottom: 0.5rem; }}
    .muted {{ color: #999; font-size: 0.85rem; line-height: 1.45; max-width: 22rem; margin: 0.5rem 0; }}
    .btn {{
      display: block;
      width: 100%;
      max-width: 20rem;
      margin: 0.75rem 0 0;
      padding: 1rem;
      background: #ff6b00;
      color: #fff !important;
      font-weight: 700;
      font-size: 1.05rem;
      border-radius: 12px;
      text-decoration: none;
      border: none;
      cursor: pointer;
      font-family: inherit;
    }}
    .btn-secondary {{
      background: #333;
      color: #fff !important;
      font-weight: 600;
      font-size: 0.95rem;
    }}
    .link-box {{
      margin-top: 0.75rem;
      padding: 0.65rem 0.75rem;
      background: #222;
      border-radius: 8px;
      font-size: 0.72rem;
      color: #aaa;
      word-break: break-all;
      max-width: 20rem;
    }}
    #copied {{ color: #6fcf97; font-size: 0.85rem; min-height: 1.2rem; margin-top: 0.35rem; }}
  </style>
</head>
<body>
  <h1>Open this listing in CARZO</h1>
  {"" if is_android else ios_steps}
  <button type="button" class="btn btn-secondary" id="copy-link">Copy link</button>
  <p id="copied"></p>
  <div class="link-box">{escape(https_url)}</div>
  {android_extra}
  <script>
  (function () {{
    var httpsUrl = {https_js};
    var deep = {deep_js};
    var copyBtn = document.getElementById("copy-link");
    var copied = document.getElementById("copied");
    function showCopied() {{
      if (copied) copied.textContent = "Copied — paste in Safari address bar, or use the compass icon.";
    }}
    if (copyBtn) {{
      copyBtn.addEventListener("click", function () {{
        if (navigator.clipboard && navigator.clipboard.writeText) {{
          navigator.clipboard.writeText(httpsUrl).then(showCopied).catch(function () {{
            try {{
              var ta = document.createElement("textarea");
              ta.value = httpsUrl;
              document.body.appendChild(ta);
              ta.select();
              document.execCommand("copy");
              document.body.removeChild(ta);
              showCopied();
            }} catch (e) {{}}
          }});
        }}
      }});
    }}
    var openBtn = document.getElementById("carzo-open");
    if (openBtn) {{
      openBtn.addEventListener("click", function () {{
        var intent =
          "intent://listing?id=" + encodeURIComponent({id_js}) +
          "#Intent;scheme=carzo;package=com.carzo.app;S.browser_fallback_url={web_fallback};end";
        window.location.href = intent;
      }});
    }}
  }})();
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


def _listing_mobile_app_redirect(listing_id: str):
    """302 to native app for mobile Safari/Chrome only (not in-app WebViews).

    In-app browsers must not get a ``carzo://`` redirect — they hang on Loading.
    Desktop and ``?web=1`` skip this and get the full HTML preview instead.
    """
    ua = (request.headers.get("User-Agent") or "").lower()
    if _is_in_app_browser(ua):
        return None

    qid = quote(listing_id, safe="")
    deep = f"carzo://listing?id={qid}"
    canonical = request.url_root.rstrip("/") + f"/listing/{qid}"
    web_fallback = quote(f"{canonical}?web=1", safe="")

    if "android" in ua:
        intent = (
            f"intent://listing?id={qid}"
            f"#Intent;scheme=carzo;package=com.carzo.app;"
            f"S.browser_fallback_url={web_fallback};end"
        )
        return redirect(intent, code=302)

    if any(x in ua for x in ("iphone", "ipad", "ipod")):
        return redirect(deep, code=302)

    return None


@bp.route("/.well-known/apple-app-site-association", methods=["GET"])
def apple_app_site_association():
    """iOS Universal Links — set ``APPLE_TEAM_ID`` (10-char) on the server."""
    team = (os.environ.get("APPLE_TEAM_ID") or "").strip()
    if not team:
        abort(404)
    app_id = f"{team}.com.carzo.app"
    paths = _listing_share_path_globs()
    data = {
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appIDs": [app_id],
                    "components": [{"/": p} for p in paths],
                },
                {
                    "appID": app_id,
                    "paths": paths,
                },
            ],
        }
    }
    return Response(
        json.dumps(data),
        200,
        mimetype="application/json",
        headers={"Cache-Control": "public, max-age=300"},
    )


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
    if request.args.get("web") != "1" and _is_in_app_browser(ua):
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

    if request.args.get("web") != "1":
        app_redirect = _listing_mobile_app_redirect(raw)
        if app_redirect is not None:
            return app_redirect

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

    deep_js = json.dumps(deep)
    fallback_js = json.dumps(f"{canonical}?web=1")
    id_js = json.dumps(raw)

    cta_script = f"""  <script>
(function () {{
  var deep = {deep_js};
  var fallback = {fallback_js};
  var id = {id_js};
  function openCarzoFromShare() {{
    var ua = navigator.userAgent || "";
    if (/Android/i.test(ua)) {{
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
    try {{
      window.top.location.href = deep;
    }} catch (e3) {{
      try {{ window.location.href = deep; }} catch (e4) {{}}
    }}
  }}
  function bindCta() {{
    var b = document.getElementById("carzo-open-btn");
    if (!b) return;
    b.addEventListener("click", function (ev) {{
      ev.preventDefault();
      openCarzoFromShare();
    }});
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
        <button type="button" class="cta" id="carzo-open-btn">Open in CARZO app</button>
        <p class="hint">
          If the button does nothing, you may be inside an in-app browser — use
          <strong>Share → Open in Safari</strong> (iOS) or <strong>Open in Chrome</strong>, then tap the button again.
          You can also copy <a href="{esc_deep}" target="_top" rel="noopener noreferrer">this link</a> and paste it into the address bar.
        </p>
        <p class="hint">
          This page tries to open CARZO automatically when the app is installed.
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

