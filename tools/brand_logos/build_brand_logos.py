#!/usr/bin/env python3
"""Rebuild the CarNet brand logos that used to render badly in circles.

Round 1: BAW, Forthing, Hyptec, Ineos, JAECOO, Jonway, Karry, Kawasaki, POER,
Polaris, Vanderhall.
Round 2 (physical-phone review): Huanghai, KAWEI, Polarsun, XEV, Zimmer.

Inputs are the ORIGINAL supplied artwork kept (unmodified) in ``source/``
(copied from ``D:\\car logos scraper\\logos``). Nothing is redrawn: every
output is the supplied artwork, cropped / matted / re-canvased only.

Per-brand treatment (see ``RECIPES``):
  * ``crop``       emblem-only crop of the supplied official lock-up
                   (Forthing, Hyptec, POER, Vanderhall).
  * ``matte``      remove an unwanted rectangular white background while
                   keeping the real logo colours and inner white details.
  * ``kind``       force emblem margins for badge-shaped logos that are wide
                   (Karry's oval). No colours are ever altered.
  * tight crop to the visible artwork, then a small per-kind transparent
    margin so the artwork sits comfortably inside a circle.

Output: transparent RGBA PNG, longest side 256 px, aspect ratio preserved,
written to BOTH ``kk/static/images/brands/<slug>.png`` (backend CDN) and
``assets/brand_logos/<slug>.png`` (bundled in the app).

Usage (from the repo root)::

    python tools/brand_logos/build_brand_logos.py            # write files
    python tools/brand_logos/build_brand_logos.py --check    # exit 1 if stale

SVG sources (BAW, JAECOO, Kawasaki) are rasterised with headless Edge/Chromium
through Playwright.
"""
from __future__ import annotations

import argparse
import io
import re
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent / "source"
OUT_DIRS = [REPO / "kk/static/images/brands", REPO / "assets/brand_logos"]

LONG_SIDE = 256
# Transparent margin added around the tight artwork bbox, as a fraction of the
# longest side. Emblems are inset so that, in the 36 dp box of a 52 dp circle,
# they land at ~91% fill (about the same visual size as Toyota / Mercedes).
EMBLEM_MARGIN = 0.045
WORDMARK_MARGIN = 0.015
# Artwork wider than this (w / h) is treated as a wordmark.
WORDMARK_ASPECT = 1.6
# Alpha below this is ignored when finding the artwork bounds (resampling noise).
ALPHA_FLOOR = 10

RECIPES: dict[str, dict] = {
    "baw": {"src": "baw.svg"},
    "forthing": {"src": "forthing.png", "crop": (0, 0, 40, 51)},
    "hyptec": {
        "src": "hyptec.png",
        "crop": (0, 0, 76, 88),
        "matte": "black_on_white",
    },
    "ineos": {"src": "ineos.png"},
    "jaecoo": {"src": "jaecoo.svg"},
    "jonway": {"src": "jonway.gif", "matte": "flood_white"},
    # Official Chery Commercial Vehicle Karry badge (see PROVENANCE.md). The oval
    # is a badge, not a wordmark, so it gets emblem margins like Jonway/Toyota.
    "karry": {"src": "karry.png", "kind": "emblem"},
    "kawasaki": {"src": "kawasaki.svg"},
    "poer": {"src": "poer.png", "crop": (0, 0, 84, 141)},
    "polaris": {"src": "polaris.png"},
    # The supplied Vanderhall lock-up has a WHITE wordmark (made for dark
    # backgrounds) that vanishes on the white tile. The shield emblem from the
    # same official file is dark/grey and legible on both themes.
    "vanderhall": {"src": "vanderhall.webp", "crop": (0, 0, 142, 162)},
    # --- second round (found on the physical phone, Search Cars picker) ------
    # Huanghai had NO file at all (generic orange car icon). This is the
    # brand's own chrome oval emblem, already transparent (see PROVENANCE.md);
    # the scraper's earlier huanghai.png was the SG Automotive PARENT mark and
    # is deliberately not used.
    "huanghai": {"src": "huanghai.png", "kind": "emblem"},
    # JPEG / GIF originals on an opaque white rectangle: remove only the outer
    # white (flood fill from the border), keep inner whites and colours.
    "kawei": {"src": "kawei.jpg", "matte": "flood_white"},
    "polarsun": {"src": "polarsun.gif", "matte": "flood_white"},
    "zimmer": {"src": "zimmer.jpg", "matte": "flood_white"},
    # XEV's official light-background lock-up (blue X + grey EV), published by
    # XEV itself at https://www.xevcars.it/images/logos/logo-xev.svg. The
    # scraper's earlier file was the dark-background variant (white "EV"),
    # which is invisible on the always-white coin, so the full official
    # lock-up replaces the X-only crop used before.
    "xev": {"src": "xev.svg"},
}


# --------------------------------------------------------------------------- IO
def rasterise_svg(path: Path, target_long_side: int = 2048) -> Image.Image:
    from playwright.sync_api import sync_playwright

    svg = path.read_text(encoding="utf-8")
    m = re.search(r'viewBox="([\d\.\s-]+)"', svg)
    if not m:
        raise SystemExit(f"{path.name}: no viewBox")
    _, _, w, h = [float(v) for v in m.group(1).split()]
    scale = target_long_side / max(w, h)
    W, H = int(round(w * scale)), int(round(h * scale))
    with sync_playwright() as p:
        try:
            browser = p.chromium.launch(channel="msedge")
        except Exception:
            browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": W, "height": H})
        page.goto(path.resolve().as_uri())
        page.evaluate(
            "([w,h])=>{const s=document.documentElement;"
            "s.setAttribute('width',w);s.setAttribute('height',h);}",
            [W, H],
        )
        png = page.screenshot(omit_background=True)
        browser.close()
    return Image.open(io.BytesIO(png)).convert("RGBA")


def load_source(recipe: dict) -> Image.Image:
    path = SOURCE / recipe["src"]
    if path.suffix == ".svg":
        return rasterise_svg(path)
    return Image.open(path).convert("RGBA")


# ------------------------------------------------------------------- operations
def matte_black_on_white(im: Image.Image) -> Image.Image:
    """Mono black artwork on an opaque white tile -> black with real alpha."""
    a = np.array(im.convert("RGB")).astype(np.float32)
    if (a.max(axis=2) - a.min(axis=2)).max() > 6:
        raise SystemExit("black_on_white matte needs monochrome artwork")
    alpha = 255.0 - a.min(axis=2)
    out = np.zeros((*alpha.shape, 4), np.uint8)
    out[..., 3] = np.clip(alpha, 0, 255).astype(np.uint8)
    return Image.fromarray(out)


def matte_flood_white(im: Image.Image) -> Image.Image:
    """Remove the outer white background only (flood fill from the border).

    White INSIDE the artwork (e.g. the lettering inside Jonway's red oval) is
    not connected to the border and is kept. Edge pixels that are a blend of
    the artwork colour and white are converted to partial alpha.
    """
    rgb = np.array(im.convert("RGB")).astype(np.int32)
    h, w, _ = rgb.shape
    near_white = rgb.min(axis=2) >= 222
    outside = np.zeros((h, w), bool)
    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        for y in (0, h - 1):
            if near_white[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if near_white[y, x] and not outside[y, x]:
                outside[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and near_white[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True
                q.append((ny, nx))

    alpha = np.where(outside, 0, 255).astype(np.float32)
    out_rgb = rgb.astype(np.float32).copy()

    # Un-matte the anti-aliased rim: pixels touching the removed background are
    # blends of the logo edge colour and white.
    dil = outside.copy()
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        dil |= np.roll(np.roll(outside, dy, 0), dx, 1)
    rim = dil & ~outside
    fg = np.array([rgb[..., c][~outside & ~near_white].mean() for c in range(3)])
    for y, x in zip(*np.nonzero(rim)):
        px = rgb[y, x].astype(np.float32)
        # fraction of foreground = how far the pixel is from white towards fg
        t = ((255.0 - px) / np.maximum(255.0 - fg, 1.0)).mean()
        t = float(np.clip(t, 0.0, 1.0))
        alpha[y, x] = round(255.0 * t)
        out_rgb[y, x] = fg
    out = np.dstack([np.clip(out_rgb, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(out)


def tight_crop(im: Image.Image) -> Image.Image:
    alpha = np.array(im.getchannel("A"))
    ys, xs = np.nonzero(alpha > ALPHA_FLOOR)
    if len(xs) == 0:
        raise SystemExit("empty artwork")
    return im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def finish(im: Image.Image, kind: str | None = None) -> Image.Image:
    """Tight crop -> margin -> resize so the longest side is LONG_SIDE."""
    im = tight_crop(im)
    w, h = im.size
    wordmark = (w / h) >= WORDMARK_ASPECT or (h / w) >= WORDMARK_ASPECT
    if kind == "emblem":
        wordmark = False
    margin = WORDMARK_MARGIN if wordmark else EMBLEM_MARGIN
    # Margin is a fraction of the final canvas, so solve for the artwork size.
    pad = round(LONG_SIDE * margin)
    scale = (LONG_SIDE - 2 * pad) / max(w, h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    art = im.resize((nw, nh), Image.LANCZOS)
    cw, ch = nw + 2 * pad, nh + 2 * pad
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    canvas.alpha_composite(art, (pad, pad))
    return canvas


def build(slug: str) -> Image.Image:
    r = RECIPES[slug]
    im = load_source(r)
    if "crop" in r:
        im = im.crop(r["crop"])
    matte = r.get("matte")
    if matte == "black_on_white":
        im = matte_black_on_white(im)
    elif matte == "flood_white":
        im = matte_flood_white(im)
    return finish(im, r.get("kind"))


def encode(im: Image.Image) -> bytes:
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="fail if outputs differ")
    args = ap.parse_args()
    stale = []
    for slug in RECIPES:
        data = encode(build(slug))
        for d in OUT_DIRS:
            target = d / f"{slug}.png"
            if args.check:
                if not target.exists() or target.read_bytes() != data:
                    stale.append(str(target))
            else:
                target.write_bytes(data)
        print(f"{slug:11s} {len(data):6d} bytes")
    if stale:
        print("STALE:", *stale, sep="\n  ")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
