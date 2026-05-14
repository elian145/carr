from __future__ import annotations

import logging
import os
import re
import json

from flask import Blueprint, Response, abort, current_app, jsonify, request, send_from_directory
from urllib.parse import quote
from html import escape
from werkzeug.utils import safe_join

bp = Blueprint("misc", __name__)
logger = logging.getLogger(__name__)

# Public listing share URLs from the mobile app resolve here (same host as API_BASE).
_LISTING_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{1,128}$")


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


@bp.route("/.well-known/apple-app-site-association", methods=["GET"])
def apple_app_site_association():
    """iOS Universal Links — set ``APPLE_TEAM_ID`` (10-char) on the server."""
    team = (os.environ.get("APPLE_TEAM_ID") or "").strip()
    if not team:
        abort(404)
    data = {
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appID": f"{team}.com.carzo.app",
                    "paths": _listing_share_path_globs(),
                }
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
    """Fallback HTML when a shared ``https://…/listing/<id>`` URL opens in a browser.

    With **Universal Links** (iOS) / **App Links** (Android) configured on the server,
    the app opens the listing directly and this page is not used. Otherwise the user
    taps **Open listing** (``carzo://`` on iOS, ``intent:`` on Android).
    """
    raw = (listing_id or "").strip()
    if not raw or not _LISTING_ID_RE.match(raw):
        abort(404)
    qid = quote(raw, safe="")
    deep = f"carzo://listing?id={qid}"
    esc_deep = escape(deep, quote=True)
    deep_js = json.dumps(deep)

    ua = (request.headers.get("User-Agent") or "").lower()
    is_ios = "iphone" in ua or "ipad" in ua or "ipod" in ua
    is_android = "android" in ua

    intent_href = f"intent://listing?id={qid}#Intent;scheme=carzo;package=com.carzo.app;end"
    esc_intent = escape(intent_href, quote=True)

    if is_android:
        cta_html = f'<a class="btn" href="{esc_intent}">Open listing</a>'
        body_msg = (
            "Tap the button below. If CARZO is installed, the listing will open in the app."
        )
        hint = "If nothing happens, install CARZO from the Play Store, then try again."
    elif is_ios:
        body_msg = (
            "Tap Open listing to open CARZO. "
            "If Universal Links are set up on the server, this page is skipped."
        )
        hint = (
            "If the button does nothing, you are probably inside CARZO's in-app browser "
            "(you see CARZO at the top-left). Tap Share, choose Open in Safari, then tap "
            "Open listing again. Or tap Copy app link, paste into Notes, and tap the link there. "
            "If CARZO is not installed, get it from the App Store first."
        )
        cta_html = f"""
    <button type="button" class="btn" id="open-listing-btn">Open listing</button>
    <button type="button" class="btn btn-secondary" id="copy-listing-deep">Copy app link</button>
    <p class="hint" id="copy-done" style="display:none;font-weight:600;">Copied — open Notes, paste, then tap the link.</p>
    <p class="sub"><a class="link-plain" href="{esc_deep}">Open as link</a></p>
    <script>(function(){{
      var u = {deep_js};
      var b = document.getElementById("open-listing-btn");
      if (b) {{
        b.addEventListener("click", function () {{
          try {{ window.top.location.href = u; }} catch (e) {{ window.location.href = u; }}
        }});
      }}
      var c = document.getElementById("copy-listing-deep");
      var m = document.getElementById("copy-done");
      if (c && navigator.clipboard && navigator.clipboard.writeText) {{
        c.addEventListener("click", function () {{
          navigator.clipboard.writeText(u).then(function () {{
            if (m) m.style.display = "block";
          }}).catch(function () {{}});
        }});
      }}
    }})();</script>"""
    else:
        body_msg = "Tap Open listing to open this listing in the CARZO app."
        hint = ""
        cta_html = f"""
    <button type="button" class="btn" id="open-listing-btn">Open listing</button>
    <p class="sub"><a class="link-plain" href="{esc_deep}">Open as link</a></p>
    <script>(function(){{
      var u = {deep_js};
      var b = document.getElementById("open-listing-btn");
      if (b) {{
        b.addEventListener("click", function () {{
          try {{ window.top.location.href = u; }} catch (e) {{ window.location.href = u; }}
        }});
      }}
    }})();</script>"""

    hint_html = f'<p class="hint">{escape(hint)}</p>' if hint else ""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>CARZO — open listing</title>
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
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f2f2f7;
      color: #111;
    }}
    .card {{
      max-width: 22rem;
      width: 100%;
      background: #fff;
      border-radius: 16px;
      padding: 1.75rem 1.35rem;
      box-shadow: 0 4px 24px rgba(0, 0, 0, 0.08);
      text-align: center;
    }}
    h1 {{
      font-size: 1.2rem;
      font-weight: 700;
      margin: 0 0 0.75rem;
    }}
    .body {{
      margin: 0 0 1.25rem;
      color: #444;
      line-height: 1.5;
      font-size: 0.95rem;
    }}
    .btn {{
      display: block;
      width: 100%;
      padding: 1rem 1.25rem;
      margin: 0 0 0.6rem;
      background: #ff6b00;
      color: #fff !important;
      text-decoration: none;
      font-weight: 700;
      font-size: 1.05rem;
      border-radius: 12px;
      text-align: center;
      border: none;
      cursor: pointer;
      font-family: inherit;
    }}
    a.btn {{ color: #fff !important; }}
    .btn-secondary {{
      background: #555;
      color: #fff !important;
    }}
    .hint {{
      margin: 1rem 0 0;
      font-size: 0.8rem;
      color: #666;
      line-height: 1.4;
    }}
    .sub {{ margin: 0.75rem 0 0; font-size: 0.85rem; }}
    .link-plain {{ color: #ff6b00; font-weight: 600; }}
  </style>
</head>
<body>
  <div class="card">
    <h1>Open in CARZO</h1>
    <p class="body">{escape(body_msg)}</p>
    {cta_html}
    {hint_html}
  </div>
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

