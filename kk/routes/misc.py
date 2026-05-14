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
    """Public listing page for shared URLs: ``https://<host>/listing/<id>`` *is* the listing."""
    from sqlalchemy.orm import joinedload, selectinload

    from ..models import Car
    from ..routes.cars import _with_media_compat

    raw = (listing_id or "").strip()
    if not raw or not _LISTING_ID_RE.match(raw):
        abort(404)

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
    title = escape((d.get("title") or "Listing").strip() or "Listing")
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
        img_block = f'<p class="hero"><img src="{esc_img}" alt="" loading="lazy"/></p>'

    deep = f"carzo://listing?id={quote(raw, safe='')}"
    esc_deep = escape(deep, quote=True)

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>{title} · CARZO</title>
  <style>
    body {{ margin: 0; font-family: system-ui, -apple-system, sans-serif; background: #f4f4f7; color: #111; }}
    .wrap {{ max-width: 40rem; margin: 0 auto; padding: 1rem 1rem 2rem; }}
    .hero img {{ width: 100%; border-radius: 12px; display: block; background: #ddd; }}
    h1 {{ font-size: 1.35rem; margin: 0.75rem 0 0.25rem; }}
    .meta {{ color: #555; font-size: 0.95rem; margin-bottom: 0.75rem; }}
    .price {{ font-size: 1.35rem; font-weight: 700; color: #ff6b00; margin: 0.25rem 0 1rem; }}
    .desc {{ line-height: 1.5; font-size: 0.95rem; color: #333; }}
    .foot {{ margin-top: 1.5rem; padding-top: 1rem; border-top: 1px solid #ddd; font-size: 0.85rem; color: #666; }}
    .foot a {{ color: #ff6b00; font-weight: 600; }}
  </style>
</head>
<body>
  <div class="wrap">
    {img_block}
    <h1>{title}</h1>
    <p class="meta">{year} · {mile_s} · {loc}</p>
    <p class="price">{currency} {price_s}</p>
    <div class="desc">{desc_html}</div>
    <p class="foot">Prefer the app? <a href="{esc_deep}">Open in CARZO</a></p>
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

