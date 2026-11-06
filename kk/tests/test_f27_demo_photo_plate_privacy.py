"""F-27 follow-up: demo photos must not show legible licence plates and the personal
street photo must stay replaced by a neutral placeholder.

Background: ``scripts/blur_demo_plates.py`` rewrote 73 tracked files IN PLACE (same
paths/URLs, same pixel dimensions, valid JPEGs, no EXIF/GPS):

* 4 ``image_picker_*`` photos (owner's car, formerly GPS-bearing): plates blurred
* 68 byte-identical dealer-showroom copies (4 distinct pictures): plates blurred
* root ``static/uploads/car_photos/..._IMG_3018.jpg``: neutral placeholder

The tests pin the sha256 of the new blobs, assert the originals' bytes are gone, and check
that the blurred rectangles carry (almost) no edge detail. They only read tracked files, no
git history needed, no network, no DB.
"""

from __future__ import annotations

import hashlib
import importlib.util
import io
import os
import subprocess

import pytest
from PIL import Image, ImageChops, ImageStat

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UPLOAD_DIRS = ("kk/static/uploads", "static/uploads")

# sha256 of the ORIGINAL bytes (at base 1aab2ef) of every file that was changed.
ORIGINAL_SHA256 = {
    "1b1f1e9c8bc311e4deb55648ea08fc9a113b859380f9d5a30aaec379b4f87a93",  # image_picker_10C63405
    "f7eb7866622a70a7deda5fb76361acef6c7dd611209e4b9740e264b88747ff61",  # image_picker_24FDFB53
    "c6f118a87711c98be378fcf3a72ba6284006e4fa7f42f538d690b536e3819400",  # image_picker_55F56E0C
    "9e6f55028efcad942582791a41c43d88adf12b506b5959085a71da9ab2b1ff97",  # image_picker_E5673601
    "070f09a2090b9d9faeeb7c03d74ddfe424fac88ce8f49ee8abd941db05eeb149",  # showroom 87 group
    "ffbb730749641e2239ba2df330ba198334a1421779dd08e6ffb8af37e8ec0acd",  # showroom 90 group
    "ba30498e2b434fa858f0c4e345f1c31984209b184db537df966183e81affee9a",  # showroom 93 group
    "1ea4aa050bb27ac91c7a5c94ae80d7e5167043d899090b787e2d329a8e15e792",  # showroom 94 group
    "a859449d8af7e9082b102b206818a8173a40186153e414a773f804e324892787",  # root IMG_3018
}

# sha256 of the new bytes -> (expected number of tracked copies, (width, height))
AFTER_SHA256 = {
    "83f6c2ce077f578041fe2269c17a8cc7ae173a979c5ba942ed7cdee6ca64d1be": (1, (1920, 3413)),
    "58280ec2700098fb149d5a0d24052800a01c107b43f5e6619bf9a195e5833378": (1, (1920, 3413)),
    "a41474e670bcd970ef94ae711c2b91933200b118de656c587abbe9ea70805e5f": (1, (1920, 3413)),
    "67e60a206ee93596de517f90f581dcd68154b39200fbe336f9cf2751ec92d12e": (1, (1920, 3413)),
    "21710d147998fdfdbd860a922afcaf76fd4b38413ef0857a051db3a6e6d3c476": (16, (250, 333)),
    "b7930f9ae0782ffaa17be08691c67e939d09f0d9ad8b32ce73040ec85fa82bae": (24, (250, 333)),
    "957d3b6468e6b7bb86446dedd9d6c8e10b2cf3ed013ca68b6f5c5c5a790c14ab": (13, (250, 243)),
    "51e0fed531328ba46ff71779c4bc13aefe9191d701e45ff5430390af9ea35442": (15, (250, 333)),
    "75b0b2a3b3a53ee0cdbcf78d0923f7474ac628f8f890171bdd71926af26bf233": (1, (270, 480)),
}
PLACEHOLDER_PATH = "static/uploads/car_photos/20250820_015056_scaled_IMG_3018.jpg"
PLACEHOLDER_SHA256 = "75b0b2a3b3a53ee0cdbcf78d0923f7474ac628f8f890171bdd71926af26bf233"

# Blurred rectangle: mean |neighbour-pixel difference| (dx + dy, grey) must stay below this.
# Unblurred plates measured 21-70 (one dark low-contrast one 5); blurred ones measured < 9.
MAX_DETAIL = 12.0


def _load_script():
    spec = importlib.util.spec_from_file_location(
        "blur_demo_plates", os.path.join(REPO_ROOT, "scripts", "blur_demo_plates.py")
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _tracked() -> list[str]:
    try:
        out = subprocess.run(
            ["git", "ls-files", "-z", "--", *UPLOAD_DIRS], cwd=REPO_ROOT, capture_output=True, check=True
        ).stdout.decode("utf-8")
    except Exception as exc:  # pragma: no cover
        pytest.skip(f"git not available: {exc}")
    return [p for p in out.split("\0") if p]


@pytest.fixture(scope="module")
def blobs() -> dict[str, tuple[str, bytes]]:
    """path -> (sha256, bytes) of tracked upload JPEGs (PNG logos are irrelevant here)."""
    res = {}
    for rel in _tracked():
        if not rel.lower().endswith((".jpg", ".jpeg")):
            continue
        with open(os.path.join(REPO_ROOT, rel), "rb") as fh:
            data = fh.read()
        res[rel] = (hashlib.sha256(data).hexdigest(), data)
    assert res
    return res


def region_detail(im: Image.Image, rect) -> float:
    """Mean absolute neighbour difference (horizontal + vertical) of a rectangle, in grey levels."""
    x0, y0, x1, y1 = rect[:4]
    g = im.convert("L").crop((x0, y0, x1, y1))
    w, h = g.size
    dx = ImageStat.Stat(ImageChops.difference(g.crop((0, 0, w - 1, h)), g.crop((1, 0, w, h)))).mean[0]
    dy = ImageStat.Stat(ImageChops.difference(g.crop((0, 0, w, h - 1)), g.crop((0, 1, w, h)))).mean[0]
    return dx + dy


# ------------------------------------------------------------------------------------------
# The changes are in place and pinned
# ------------------------------------------------------------------------------------------

def test_original_unblurred_bytes_are_no_longer_in_the_work_tree(blobs):
    still = sorted(p for p, (h, _) in blobs.items() if h in ORIGINAL_SHA256)
    assert not still, f"original (legible-plate / GPS-era) bytes are back: {still}"


def test_changed_files_match_pinned_hashes_and_counts(blobs):
    counts: dict[str, int] = {}
    for _, (h, _data) in blobs.items():
        if h in AFTER_SHA256:
            counts[h] = counts.get(h, 0) + 1
    assert counts == {h: n for h, (n, _) in AFTER_SHA256.items()}


def test_changed_files_are_valid_jpegs_same_dimensions_without_exif_or_gps(blobs):
    checked = 0
    for rel, (h, data) in blobs.items():
        if h not in AFTER_SHA256:
            continue
        checked += 1
        im = Image.open(io.BytesIO(data))
        im.verify()
        im = Image.open(io.BytesIO(data))
        assert im.format == "JPEG" and im.mode == "RGB", rel
        assert im.size == AFTER_SHA256[h][1], rel
        assert len(im.getexif()) == 0 and "exif" not in im.info, rel
        for marker in (b"Exif\x00\x00", b"GPSLatitude", b"Photoshop 3.0", b"http://ns.adobe.com/xap/1.0/", b"<x:xmpmeta"):
            assert marker not in data, (rel, marker)
        # no APP1 (EXIF/XMP) or APP13 (IPTC) segment at all
        i = 2
        while i + 4 <= len(data) and data[i] == 0xFF and data[i + 1] != 0xDA:
            assert data[i + 1] not in (0xE1, 0xED), (rel, hex(data[i + 1]))
            i += 2 + int.from_bytes(data[i + 2:i + 4], "big")
    assert checked == sum(n for n, _ in AFTER_SHA256.values()) == 73


def test_no_changed_file_was_renamed_or_removed(blobs):
    """Paths stay: every file the script touched is still tracked under its original path."""
    assert PLACEHOLDER_PATH in blobs
    assert sum(1 for p in blobs if "image_picker" in p) == 4


# ------------------------------------------------------------------------------------------
# Plates are really obscured
# ------------------------------------------------------------------------------------------

def test_script_rules_cover_exactly_the_pinned_originals():
    s = _load_script()
    assert set(s.PLATE_RULES) | {s.PLACEHOLDER_ORIGINAL_SHA[PLACEHOLDER_PATH]} == ORIGINAL_SHA256
    assert s.PLACEHOLDER_ORIGINAL_SHA[PLACEHOLDER_PATH] in ORIGINAL_SHA256


def test_blurred_plate_rectangles_have_no_readable_detail(blobs):
    s = _load_script()
    # map rule key (original sha) -> after sha, via the order of the pinned tables
    after_for = {
        "1b1f1e9c8bc311e4deb55648ea08fc9a113b859380f9d5a30aaec379b4f87a93": "83f6c2ce077f578041fe2269c17a8cc7ae173a979c5ba942ed7cdee6ca64d1be",
        "f7eb7866622a70a7deda5fb76361acef6c7dd611209e4b9740e264b88747ff61": "58280ec2700098fb149d5a0d24052800a01c107b43f5e6619bf9a195e5833378",
        "c6f118a87711c98be378fcf3a72ba6284006e4fa7f42f538d690b536e3819400": "a41474e670bcd970ef94ae711c2b91933200b118de656c587abbe9ea70805e5f",
        "9e6f55028efcad942582791a41c43d88adf12b506b5959085a71da9ab2b1ff97": "67e60a206ee93596de517f90f581dcd68154b39200fbe336f9cf2751ec92d12e",
        "070f09a2090b9d9faeeb7c03d74ddfe424fac88ce8f49ee8abd941db05eeb149": "21710d147998fdfdbd860a922afcaf76fd4b38413ef0857a051db3a6e6d3c476",
        "ffbb730749641e2239ba2df330ba198334a1421779dd08e6ffb8af37e8ec0acd": "b7930f9ae0782ffaa17be08691c67e939d09f0d9ad8b32ce73040ec85fa82bae",
        "ba30498e2b434fa858f0c4e345f1c31984209b184db537df966183e81affee9a": "957d3b6468e6b7bb86446dedd9d6c8e10b2cf3ed013ca68b6f5c5c5a790c14ab",
        "1ea4aa050bb27ac91c7a5c94ae80d7e5167043d899090b787e2d329a8e15e792": "51e0fed531328ba46ff71779c4bc13aefe9191d701e45ff5430390af9ea35442",
    }
    by_hash = {h: d for (h, d) in blobs.values()}
    rects = 0
    for orig, rs in s.PLATE_RULES.items():
        im = Image.open(io.BytesIO(by_hash[after_for[orig]]))
        for r in rs:
            rects += 1
            assert 0 <= r[0] < r[2] <= im.width and 0 <= r[1] < r[3] <= im.height, r
            d = region_detail(im, r)
            assert d < MAX_DETAIL, f"plate rectangle {r} still has detail {d:.1f} (>= {MAX_DETAIL})"
    assert rects == 9  # 4 owner photos (5 plates incl. one background SUV) + 4 showroom pictures


def test_detail_metric_flags_a_sharp_plate_like_region_and_passes_a_blur():
    """Negative control for the metric itself."""
    from PIL import ImageDraw, ImageFilter

    sharp = Image.new("L", (120, 40), 230)
    d = ImageDraw.Draw(sharp)
    for x in range(8, 112, 12):
        d.rectangle([x, 8, x + 5, 32], fill=20)  # "characters"
    assert region_detail(sharp, (0, 0, 120, 40)) > MAX_DETAIL
    blurred = sharp.filter(ImageFilter.GaussianBlur(14))
    assert region_detail(blurred, (0, 0, 120, 40)) < MAX_DETAIL


# ------------------------------------------------------------------------------------------
# Placeholder for the personal street photo
# ------------------------------------------------------------------------------------------

def test_personal_street_photo_is_a_small_neutral_placeholder(blobs):
    h, data = blobs[PLACEHOLDER_PATH]
    assert h == PLACEHOLDER_SHA256
    assert len(data) < 20_000
    im = Image.open(io.BytesIO(data))
    assert im.format == "JPEG" and im.size == (270, 480)
    # nearly flat picture: no scene content left (a street photo has std-dev >> 30)
    assert max(ImageStat.Stat(im.convert("L")).stddev) < 25


def test_unrelated_photos_are_untouched_unique_pictures_still_present(blobs):
    """The 5 plate-free showroom pictures (86/89/91/92/96 groups) keep their original bytes."""
    unchanged = {h for (h, _d) in blobs.values()} - ORIGINAL_SHA256 - set(AFTER_SHA256)
    # 5 plate-free showroom pictures = 5 distinct unchanged JPEG blobs
    assert len(unchanged) == 5
