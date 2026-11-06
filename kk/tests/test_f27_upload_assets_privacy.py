"""F-27: committed upload images must not carry GPS / personal metadata, no new
media may be committed under the upload dirs, and ``/static/<path>`` stays hardened.

Context: ``kk/static/uploads`` and ``static/uploads`` hold 266 tracked files (137
listing photos + 1 root photo + 128 brand logos) that are served publicly by
``/static/<path>``. Four listing photos shipped full iPhone EXIF incl. GPS. They were
sanitised in place (APP1/APP13 segments removed, pixel data byte-identical).

The checks below read the *tracked* files (``git ls-files``) so runtime uploads in
the ignored upload dirs never make the test flaky.
"""

from __future__ import annotations

import io
import os
import re
import subprocess
import tempfile

import pytest
from PIL import Image

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UPLOAD_DIRS = ("kk/static/uploads", "static/uploads")
MANIFEST = os.path.join(os.path.dirname(__file__), "f27_legacy_upload_manifest.txt")

# Brand logos are the ONLY thing that may be (force-)added under the upload dirs.
LOGO_RE = re.compile(r"^kk/static/uploads/car_brand_logos/[A-Za-z0-9_. \-]+\.png$")

# Purely structural EXIF tags that identify neither a person, place, device nor time.
BENIGN_EXIF_TAGS = frozenset(
    {
        "ExifOffset",
        "ExifVersion",
        "ImageWidth",
        "ImageLength",
        "LightSource",
        "Orientation",
        "Software",
    }
)
# Tags that must never appear, whatever else is allowed (explicit for readable failures).
FORBIDDEN_EXIF_TAGS = frozenset(
    {
        "GPSInfo", "Make", "Model", "DateTime", "DateTimeOriginal", "DateTimeDigitized",
        "MakerNote", "Artist", "Copyright", "CameraOwnerName", "BodySerialNumber",
        "LensSerialNumber", "ImageUniqueID", "ImageDescription", "UserComment",
        "HostComputer", "XPAuthor", "XPComment", "LensModel", "LensMake",
    }
)
MEDIA_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic", ".heif", ".mp4", ".mov", ".webm", ".m4v", ".avi", ".mkv", ".3gp"}


def _tracked_upload_files() -> list[str]:
    try:
        out = subprocess.run(
            ["git", "ls-files", "-z", "--", *UPLOAD_DIRS],
            cwd=REPO_ROOT, capture_output=True, check=True,
        ).stdout.decode("utf-8")
    except Exception as exc:  # pragma: no cover - git missing
        pytest.skip(f"git not available: {exc}")
    return [p for p in out.split("\0") if p]


def _legacy_manifest() -> set[str]:
    with open(MANIFEST, "r", encoding="ascii") as fh:
        return {ln.strip() for ln in fh.read().splitlines() if ln.strip()}


def _jpeg_segments(data: bytes) -> list[int]:
    assert data[:2] == b"\xff\xd8"
    markers, i = [], 2
    while i + 4 <= len(data) and data[i] == 0xFF:
        m = data[i + 1]
        if m == 0xDA:
            break
        markers.append(m)
        i += 2 + int.from_bytes(data[i + 2:i + 4], "big")
    return markers


def personal_metadata_problems(data: bytes, name: str = "") -> list[str]:
    """Return human-readable reasons why ``data`` carries personal metadata ([] = clean)."""
    problems: list[str] = []
    im = Image.open(io.BytesIO(data))
    exif = im.getexif()
    names: set[str] = set()
    from PIL import ExifTags

    for k in exif.keys():
        names.add(ExifTags.TAGS.get(k, str(k)))
    for ifd_id in (0x8769, 0x8825, 0xA005):
        try:
            sub = exif.get_ifd(ifd_id)
        except Exception:
            sub = {}
        tbl = ExifTags.GPSTAGS if ifd_id == 0x8825 else ExifTags.TAGS
        for k in sub.keys():
            names.add(("GPS:" if ifd_id == 0x8825 else "") + tbl.get(k, str(k)))
    if any(n.startswith("GPS:") for n in names) or "GPSInfo" in names:
        problems.append("GPS data")
    bad = (names & FORBIDDEN_EXIF_TAGS)
    if bad:
        problems.append("forbidden EXIF tags: " + ",".join(sorted(bad)))
    extra = {n for n in names if not n.startswith("GPS:")} - BENIGN_EXIF_TAGS - FORBIDDEN_EXIF_TAGS
    if extra:
        problems.append("non-allow-listed EXIF tags: " + ",".join(sorted(extra)))
    if im.format == "JPEG":
        segs = _jpeg_segments(data)
        # APP13 = Photoshop/IPTC, APP3..APP12/APP15 = vendor metadata, COM = free text.
        odd = [m for m in segs if m in (0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEF, 0xFE)]
        if odd:
            problems.append("IPTC/vendor/comment segments: " + ",".join("%02X" % m for m in odd))
    if b"http://ns.adobe.com/xap/1.0/" in data or b"<x:xmpmeta" in data:
        problems.append("XMP packet")
    if im.format == "PNG":
        extras = [k for k in im.info if k in ("exif", "XML:com.adobe.xmp")]
        if extras:
            problems.append("PNG metadata chunks: " + ",".join(extras))
        # Free-text chunks other than the tool name could hold anything.
        for k in im.info:
            if k in ("Comment", "Author", "Description", "Copyright", "Title", "Source", "Creation Time", "Disclaimer", "Warning"):
                problems.append(f"PNG text chunk {k}")
        if "Software" in im.info and im.info["Software"] not in ("Adobe ImageReady",):
            problems.append("PNG Software chunk with unexpected value")
    return problems


# --------------------------------------------------------------------------------------
# Tracked-files checks
# --------------------------------------------------------------------------------------

def test_tracked_upload_images_carry_no_gps_or_personal_metadata():
    files = _tracked_upload_files()
    assert files, "expected tracked upload assets"
    failures = {}
    for rel in files:
        with open(os.path.join(REPO_ROOT, rel), "rb") as fh:
            data = fh.read()
        probs = personal_metadata_problems(data, rel)
        if probs:
            failures[rel] = probs
    assert not failures, "tracked upload files carry personal metadata: %r" % failures


def test_no_new_media_committed_under_upload_dirs_outside_allow_list():
    legacy = _legacy_manifest()
    offenders = []
    for rel in _tracked_upload_files():
        if LOGO_RE.match(rel) or rel in legacy:
            continue
        offenders.append(rel)
    assert not offenders, (
        "new files under the upload dirs are not allowed (runtime uploads are served publicly "
        "and carry EXIF/GPS). Only brand logos (car_brand_logos/*.png) and the frozen legacy "
        f"manifest are allow-listed: {offenders}"
    )


def test_legacy_manifest_only_lists_images_in_the_upload_dirs():
    for rel in _legacy_manifest():
        assert rel.startswith(UPLOAD_DIRS) and os.path.splitext(rel)[1] in (".jpg", ".jpeg")


def test_no_video_files_tracked_under_upload_dirs():
    vids = [r for r in _tracked_upload_files() if os.path.splitext(r)[1].lower() in MEDIA_EXTS - {".jpg", ".jpeg", ".png"}]
    assert vids == []


@pytest.mark.parametrize(
    "path",
    [
        "kk/static/uploads/car_photos/new_user_photo.jpg",
        "kk/static/uploads/car_videos/clip.mp4",
        "kk/static/uploads/profile_pictures/me.jpg",
        "kk/static/uploads/dealer_covers/cover.jpg",
        "static/uploads/car_photos/x.jpg",
        "static/uploads/anything/else.png",
    ],
)
def test_gitignore_blocks_new_runtime_uploads(path):
    r = subprocess.run(["git", "check-ignore", "-q", "--no-index", path], cwd=REPO_ROOT)
    assert r.returncode == 0, f"{path} is not git-ignored"


# --------------------------------------------------------------------------------------
# Detector negative controls (prove the checks above can actually fail)
# --------------------------------------------------------------------------------------

def _jpeg_with_exif(*, gps: bool = False, make: bool = False) -> bytes:
    im = Image.new("RGB", (16, 16), (120, 40, 40))
    ex = Image.Exif()
    ex[0x0112] = 1
    if make:
        ex[0x010F] = "ACME"
        ex[0x0110] = "Phone 1"
    if gps:
        ex[0x8825] = {1: "N", 2: (36.0, 19.0, 0.0), 3: "E", 4: (44.0, 0.0, 0.0)}
    buf = io.BytesIO()
    im.save(buf, "JPEG", exif=ex)
    return buf.getvalue()


def test_detector_flags_gps_exif():
    assert "GPS data" in personal_metadata_problems(_jpeg_with_exif(gps=True))


def test_detector_flags_device_make_model():
    probs = personal_metadata_problems(_jpeg_with_exif(make=True))
    assert any("forbidden EXIF tags" in p for p in probs)


def test_detector_accepts_clean_jpeg():
    buf = io.BytesIO()
    Image.new("RGB", (16, 16), (1, 2, 3)).save(buf, "JPEG")
    assert personal_metadata_problems(buf.getvalue()) == []


def test_detector_flags_iptc_segment():
    base = _jpeg_with_exif()
    # inject an APP13 segment right after SOI
    seg = b"\xff\xed\x00\x10Photoshop 3.0\x00"
    assert any("IPTC" in p for p in personal_metadata_problems(b"\xff\xd8" + seg + base[2:]))


def test_detector_flags_png_text_comment():
    from PIL.PngImagePlugin import PngInfo

    info = PngInfo()
    info.add_text("Comment", "owner: someone")
    buf = io.BytesIO()
    Image.new("RGB", (4, 4)).save(buf, "PNG", pnginfo=info)
    assert personal_metadata_problems(buf.getvalue())


# --------------------------------------------------------------------------------------
# /static/<path> hardening
# --------------------------------------------------------------------------------------

@pytest.fixture(scope="module")
def static_client():
    """Minimal Flask app exposing only ``misc.static_files`` (the real handler).

    Avoids ``create_app()`` (runs the whole alembic chain on SQLite, minutes); the real-app
    wiring of this route is already pinned by ``test_a03_route_collisions``.
    """
    from flask import Flask

    from kk.routes.misc import bp

    d = tempfile.TemporaryDirectory(prefix="carlist_f27_", ignore_cleanup_errors=True)
    upload_root = os.path.join(d.name, "persistent-uploads")
    photos = os.path.join(upload_root, "car_photos")
    os.makedirs(photos)
    app = Flask("kk", static_folder=None)  # root_path = the kk package dir, like production
    app.config["UPLOAD_FOLDER"] = upload_root
    app.register_blueprint(bp)
    with open(os.path.join(photos, "ok.jpg"), "wb") as fh:
        fh.write(b"jpegbytes")
    for n in ("evil.html", "evil.svg", "evil.js", "evil.xml", "EVIL.HTM"):
        with open(os.path.join(photos, n), "wb") as fh:
            fh.write(b"<script>alert(1)</script>")
    with open(os.path.join(photos, ".hidden"), "wb") as fh:
        fh.write(b"secret")
    # a file outside the allowed roots that traversal would reach
    with open(os.path.join(d.name, "outside.txt"), "wb") as fh:
        fh.write(b"outside-secret")
    yield app.test_client()
    d.cleanup()


def test_static_serves_normal_upload_with_nosniff_and_csp(static_client):
    r = static_client.get("/static/uploads/car_photos/ok.jpg")
    assert r.status_code == 200 and r.data == b"jpegbytes"
    assert r.headers.get("X-Content-Type-Options") == "nosniff"
    assert "sandbox" in r.headers.get("Content-Security-Policy", "")


@pytest.mark.parametrize("name", ["evil.html", "evil.svg", "evil.js", "evil.xml", "EVIL.HTM"])
def test_static_refuses_active_content_under_uploads(static_client, name):
    assert static_client.get(f"/static/uploads/car_photos/{name}").status_code == 404


def test_static_refuses_dotfiles(static_client):
    assert static_client.get("/static/uploads/car_photos/.hidden").status_code == 404
    assert static_client.get("/static/.env").status_code == 404
    assert static_client.get("/static/.git/config").status_code == 404


@pytest.mark.parametrize(
    "url",
    [
        "/static/../outside.txt",
        "/static/uploads/../../outside.txt",
        "/static/uploads/car_photos/../../../outside.txt",
        "/static/uploads/car_photos/%2e%2e/%2e%2e/outside.txt",
        "/static/..%2foutside.txt",
        "/static/uploads/car_photos/..%5c..%5coutside.txt",
        "/static/%2e%2e/%2e%2e/%2e%2e/etc/passwd",
        "/static/uploads/car_photos/ok.jpg%00.html",
    ],
)
def test_static_path_traversal_is_rejected(static_client, url):
    r = static_client.get(url)
    assert r.status_code in (301, 308, 400, 404)
    assert b"outside-secret" not in r.data and b"root:" not in r.data


def test_static_has_no_directory_listing(static_client):
    for url in ("/static/", "/static/uploads/", "/static/uploads/car_photos/", "/static/uploads/car_photos"):
        assert static_client.get(url).status_code == 404


def test_static_still_serves_packaged_assets(static_client):
    # kk/static/images/body_types/*.svg is a legitimate packaged asset (outside uploads/).
    r = static_client.get("/static/images/body_types/coupe.svg")
    assert r.status_code == 200
