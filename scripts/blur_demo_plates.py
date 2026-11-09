#!/usr/bin/env python
"""Obscure licence plates in the committed demo photos / replace a personal photo.

Why: ``kk/static/uploads`` and ``static/uploads`` hold demo listing photos that are
served publicly at ``/static/uploads/...`` (see docs/PRIVACY_DRAFT_ACCOUNT_DELETION.md,
F-27). Some show legible licence plates (the owner's own car, and dealer-showroom cars).
The URLs/paths must keep working (a production row may reference them), so files are
modified IN PLACE (same path, same dimensions for blurred files, valid JPEG, no EXIF/GPS).

What it does (deterministic; needs only Pillow, already a backend dependency):

* ``PLATE_RULES``: rules keyed by the sha256 of the ORIGINAL file bytes (the bytes as
  they were at ``--source-rev``). For every tracked file under the upload dirs whose
  original bytes match, the listed pixel rectangles (determined by looking at the images)
  are replaced by a mosaic + Gaussian blur. Because the key is the content hash, all
  byte-identical duplicate files (the showroom photos exist as 13-24 copies each) get
  the same result. JPEG quantisation tables / subsampling are kept ("keep") so the rest
  of the picture is not recompressed at a different quality, the ICC profile is kept,
  and NO EXIF/IPTC/XMP is written.
* ``PLACEHOLDER_RULES``: rules keyed by path. The file is replaced by a small neutral
  generated placeholder JPEG (grey, "CarNet" text) at the same path.
* Files whose original sha256 is in no rule are never touched.

Usage (from the repo root)::

    python scripts/blur_demo_plates.py --dry-run     # list what would change
    python scripts/blur_demo_plates.py --apply       # rewrite files in the work tree
    python scripts/blur_demo_plates.py --check       # exit 1 unless work tree == output

``--source-rev`` (default ``1aab2ef``, the last commit before the cleanup) is where the
original bytes are read from with ``git show <rev>:<path>``, so the script is re-runnable
and idempotent. Git history is not modified by this script.

Rectangles are ``(x0, y0, x1, y1, block)`` in pixels of the original image (x1/y1
exclusive); ``block`` is the mosaic cell size in pixels.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
UPLOAD_DIRS = ("kk/static/uploads", "static/uploads")
DEFAULT_SOURCE_REV = "1aab2ef"

_P = "kk/static/uploads/car_photos/"

# sha256(original bytes) -> list of (x0, y0, x1, y1, block). All coordinates were read off
# the images with a pixel grid overlay; see the comment above each entry.
PLATE_RULES: dict[str, list[tuple[int, int, int, int, int]]] = {
    # --- owner's Prado, "image_picker_*" photos (1920x3413) -------------------------------
    # ...10C63405...: rear plate + a legible plate on a black SUV in the background.
    "1b1f1e9c8bc311e4deb55648ea08fc9a113b859380f9d5a30aaec379b4f87a93": [
        (486, 2292, 704, 2464, 36),
        (1584, 1982, 1648, 2024, 8),
    ],
    # ...24FDFB53...: only a sliver of the plate is visible at the right image edge.
    "f7eb7866622a70a7deda5fb76361acef6c7dd611209e4b9740e264b88747ff61": [
        (1856, 2338, 1920, 2522, 24),
    ],
    # ...55F56E0C...: rear plate of the parked car.
    "c6f118a87711c98be378fcf3a72ba6284006e4fa7f42f538d690b536e3819400": [
        (118, 2214, 426, 2616, 60),
    ],
    # ...E5673601...: front plate.
    "9e6f55028efcad942582791a41c43d88adf12b506b5959085a71da9ab2b1ff97": [
        (812, 2592, 1166, 2822, 56),
    ],
    # --- dealer-showroom Prado photos (250x333 / 250x243; 68 byte-identical copies) -------
    # 20250820_170800_scaled_87.jpg group: front plate
    "070f09a2090b9d9faeeb7c03d74ddfe424fac88ce8f49ee8abd941db05eeb149": [
        (84, 206, 174, 233, 7),
    ],
    # ..._scaled_90.jpg group: slanted front plate
    "ffbb730749641e2239ba2df330ba198334a1421779dd08e6ffb8af37e8ec0acd": [
        (193, 218, 240, 252, 8),
    ],
    # ..._scaled_93.jpg group: slanted front plate at the left edge
    "ba30498e2b434fa858f0c4e345f1c31984209b184db537df966183e81affee9a": [
        (3, 138, 42, 178, 8),
    ],
    # ..._scaled_94.jpg group: rear plate
    "1ea4aa050bb27ac91c7a5c94ae80d7e5167043d899090b787e2d329a8e15e792": [
        (83, 241, 168, 264, 6),
    ],
}

# path -> (width, height, label). Replaces the whole picture (same path/URL).
PLACEHOLDER_RULES: dict[str, tuple[int, int, str]] = {
    # personal street photo of a car with a legible plate; not referenced anywhere in the repo.
    "static/uploads/car_photos/20250820_015056_scaled_IMG_3018.jpg": (270, 480, "CarNet\nphoto placeholder"),
}
# sha256 of the original, so the placeholder rule only fires on the original bytes.
PLACEHOLDER_ORIGINAL_SHA = {
    "static/uploads/car_photos/20250820_015056_scaled_IMG_3018.jpg":
        "a859449d8af7e9082b102b206818a8173a40186153e414a773f804e324892787",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tracked_upload_files() -> list[str]:
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", *UPLOAD_DIRS], cwd=REPO_ROOT, capture_output=True, check=True
    ).stdout.decode("utf-8")
    return [p for p in out.split("\0") if p]


def read_original(rel: str, rev: str) -> bytes:
    return subprocess.run(
        ["git", "show", f"{rev}:{rel}"], cwd=REPO_ROOT, capture_output=True, check=True
    ).stdout


def obscure(im: Image.Image, rect: tuple[int, int, int, int, int]) -> None:
    """Mosaic + Gaussian blur of ``rect`` in place (image size unchanged)."""
    x0, y0, x1, y1, block = rect
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(im.width, x1), min(im.height, y1)
    assert x1 > x0 and y1 > y0, rect
    region = im.crop((x0, y0, x1, y1))
    w, h = region.size
    small = region.resize((max(1, w // block), max(1, h // block)), Image.BOX)
    mosaic = small.resize((w, h), Image.NEAREST)
    mosaic = mosaic.filter(ImageFilter.GaussianBlur(radius=max(2.0, block * 0.6)))
    im.paste(mosaic, (x0, y0))


def blur_jpeg(original: bytes, rects: list[tuple[int, int, int, int, int]]) -> bytes:
    src = Image.open(io.BytesIO(original))
    assert src.format == "JPEG"
    icc = src.info.get("icc_profile")
    im = src.convert("RGB") if src.mode != "RGB" else src.copy()
    for r in rects:
        obscure(im, r)
    # ``quality="keep"`` / ``subsampling="keep"`` read these attributes of a JPEG-source image;
    # ``Image.copy()`` drops them, so re-attach the source's quantisation tables and sampling.
    im.format = "JPEG"
    im.quantization = src.quantization
    im.layer = src.layer
    im.layers = src.layers
    save_kw = {"format": "JPEG", "quality": "keep", "subsampling": "keep"}
    if icc:
        save_kw["icc_profile"] = icc
    out = io.BytesIO()
    im.save(out, **save_kw)  # no exif=/xmp= passed: nothing but JFIF (+ICC) is written
    return out.getvalue()


def make_placeholder(width: int, height: int, label: str) -> bytes:
    im = Image.new("RGB", (width, height), (206, 210, 216))
    d = ImageDraw.Draw(im)
    d.rectangle([(0, height // 2 - 1), (width, height // 2 + 1)], fill=(190, 194, 200))
    try:
        font = ImageFont.load_default(size=max(14, width // 10))
    except TypeError:  # very old Pillow: fixed-size bitmap font
        font = ImageFont.load_default()
    d.multiline_text((width // 2, height // 2), label, fill=(120, 126, 136), font=font, anchor="mm", align="center")
    out = io.BytesIO()
    im.save(out, format="JPEG", quality=80, optimize=False)  # no EXIF/ICC/XMP written
    return out.getvalue()


def plan(rev: str) -> list[tuple[str, bytes, bytes, str]]:
    """Return ``[(rel, original, new_bytes, kind)]`` for every file a rule applies to."""
    items = []
    for rel in tracked_upload_files():
        orig = read_original(rel, rev)
        h = sha256(orig)
        if h in PLATE_RULES:
            items.append((rel, orig, blur_jpeg(orig, PLATE_RULES[h]), "blur"))
        elif rel in PLACEHOLDER_RULES and PLACEHOLDER_ORIGINAL_SHA.get(rel) == h:
            items.append((rel, orig, make_placeholder(*PLACEHOLDER_RULES[rel]), "placeholder"))
    return items


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true", help="list planned changes only")
    mode.add_argument("--apply", action="store_true", help="write the results into the work tree")
    mode.add_argument("--check", action="store_true", help="exit 1 unless the work tree equals the output")
    ap.add_argument("--source-rev", default=DEFAULT_SOURCE_REV, help="git revision holding the original bytes")
    args = ap.parse_args(argv)

    items = plan(args.source_rev)
    unique_new = {sha256(n) for _, _, n, _ in items}
    bad = 0
    for rel, orig, new, kind in items:
        path = os.path.join(REPO_ROOT, rel)
        cur = open(path, "rb").read() if os.path.exists(path) else b""
        print(f"{kind:11s} {rel}\n    before={sha256(orig)}\n    after ={sha256(new)}  ({len(orig)} -> {len(new)} bytes)")
        if args.apply:
            with open(path, "wb") as fh:
                fh.write(new)
        elif args.check and cur != new:
            bad += 1
            print("    MISMATCH: work tree differs from regenerated output")
    print(f"{len(items)} file(s) affected, {len(unique_new)} distinct output blob(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
