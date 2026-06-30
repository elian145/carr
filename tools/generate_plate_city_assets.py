"""Generate plate-city filter images from the unified Iraqi/KR private-plate template.

Deprecated: use the official reference sheet instead.
  1. Place it at assets/plate_cities/reference_sheet.png
  2. Run: python tools/extract_plate_city_reference.py

That extracts code_11.png … code_29.png with no pixel edits.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PLATE_CITY_CODES: dict[str, str] = {
    "Baghdad": "11",
    "Basra": "14",
    "Erbil": "22",
    "Najaf": "28",
    "Karbala": "19",
    "Kirkuk": "25",
    "Mosul": "12",
    "Sulaymaniyah": "21",
    "Dohuk": "24",
    "Anbar": "15",
    "Halabja": "23",
    "Diyala": "20",
    "Diyarbakir": "21",
    "Maysan": "13",
    "Muthanna": "17",
    "Dhi Qar": "27",
    "Salaheldeen": "26",
}

KR_CITY_CODES = {"21", "22", "23", "24"}
TEMPLATE_CODE = "22"

OUTPUT_SCALE = 3
TILE_CROP = (0, 0, 148, 52)
TILE_OUTPUT_SIZE = (444, 156)

REPO = Path(__file__).resolve().parents[1]
TEMPLATE_PATH = REPO / "assets" / "plate_types" / "private.png"
OUT_DIR = REPO / "assets" / "plate_cities"

# Governorate code slot on private.png (replaces template "22").
CODE_ERASE = (50, 8, 68, 44)
KR_ERASE = (4, 35, 23, 50)

# Glyphs measured from private.png (260×52).
DIGIT_BOXES: dict[str, tuple[int, int, int, int]] = {
    "2": (53, 10, 67, 42),
    "3": (113, 10, 125, 42),
    "4": (135, 10, 146, 42),
    "5": (148, 10, 159, 42),
    "6": (161, 10, 173, 42),
    "7": (174, 10, 186, 42),
}


def _load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (
        REPO / "assets" / "fonts" / "FE-Mittelschrift.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/ARIALNBI.TTF",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf",
    ):
        p = Path(path)
        if p.is_file():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def _trim(img: Image.Image) -> Image.Image:
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def _extract_glyph(template: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    return _trim(template.crop(box))


def _fit_font_glyph(ch: str, ref: Image.Image) -> Image.Image:
    target_h = ref.height
    best: Image.Image | None = None
    best_delta = 999
    for size in range(14, 42):
        font = _load_font(size)
        canvas = Image.new("RGBA", (ref.width * 4, target_h + 8), (0, 0, 0, 0))
        draw = ImageDraw.Draw(canvas)
        bbox = draw.textbbox((0, 0), ch, font=font)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        x = (canvas.width - tw) // 2 - bbox[0]
        y = (canvas.height - th) // 2 - bbox[1]
        draw.text((x, y), ch, fill=(0, 0, 0, 255), font=font)
        glyph = _trim(canvas)
        delta = abs(glyph.height - target_h)
        if delta < best_delta:
            best_delta = delta
            best = glyph
    return best or ref


def _match_glyph_height(glyph: Image.Image, ref: Image.Image) -> Image.Image:
    if glyph.height == ref.height:
        return glyph
    ratio = ref.height / glyph.height
    return glyph.resize(
        (max(1, int(glyph.width * ratio)), ref.height),
        Image.Resampling.LANCZOS,
    )


def _build_digit_atlas(template: Image.Image) -> dict[str, Image.Image]:
    atlas = {name: _extract_glyph(template, box) for name, box in DIGIT_BOXES.items()}
    ref = atlas["3"]
    atlas["1"] = _match_glyph_height(_fit_font_glyph("1", ref), ref)
    atlas["9"] = _match_glyph_height(atlas["6"].rotate(180, expand=True), ref)
    atlas["0"] = _match_glyph_height(_fit_font_glyph("0", ref), ref)
    atlas["8"] = _match_glyph_height(_fit_font_glyph("8", ref), ref)
    return atlas


def _erase_rect(img: Image.Image, box: tuple[int, int, int, int]) -> None:
    x1, y1, x2, y2 = box
    patch = Image.new("RGBA", (x2 - x1, y2 - y1), (255, 255, 255, 255))
    img.paste(patch, (x1, y1))


def _compose_code_strip(code: str, atlas: dict[str, Image.Image]) -> Image.Image:
    glyphs = [atlas[ch] for ch in code]
    max_h = max(g.height for g in glyphs)
    total_w = sum(g.width for g in glyphs)
    strip = Image.new("RGBA", (total_w, max_h), (0, 0, 0, 0))
    x = 0
    for g in glyphs:
        y = (max_h - g.height) // 2
        strip.paste(g, (x, y), g)
        x += g.width
    return strip


def _paste_city_code(img: Image.Image, code: str, atlas: dict[str, Image.Image]) -> None:
    _erase_rect(img, CODE_ERASE)
    strip = _compose_code_strip(code, atlas)
    x1, y1, x2, y2 = CODE_ERASE
    box_w, box_h = x2 - x1, y2 - y1

    if strip.width > box_w:
        ratio = box_w / strip.width
        strip = strip.resize(
            (box_w, max(1, int(strip.height * ratio))),
            Image.Resampling.LANCZOS,
        )
    if strip.height > box_h:
        ratio = box_h / strip.height
        strip = strip.resize(
            (max(1, int(strip.width * ratio)), box_h),
            Image.Resampling.LANCZOS,
        )

    paste_x = x1 + (box_w - strip.width) // 2
    paste_y = y1 + (box_h - strip.height) // 2
    img.paste(strip, (paste_x, paste_y), strip)


def _draw_plate(code: str, template: Image.Image, atlas: dict[str, Image.Image]) -> Image.Image:
    img = template.copy()
    if code not in KR_CITY_CODES:
        _erase_rect(img, KR_ERASE)
    if code != TEMPLATE_CODE:
        _paste_city_code(img, code, atlas)
    cropped = img.crop(TILE_CROP)
    if OUTPUT_SCALE != 1:
        cropped = cropped.resize(TILE_OUTPUT_SIZE, Image.Resampling.NEAREST)
    return cropped


def _slug(city: str) -> str:
    return city.lower().replace(" ", "_")


def main() -> None:
    if not TEMPLATE_PATH.is_file():
        raise SystemExit(f"Missing template: {TEMPLATE_PATH}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    template = Image.open(TEMPLATE_PATH).convert("RGBA")
    atlas = _build_digit_atlas(template)

    for city, code in PLATE_CITY_CODES.items():
        img = _draw_plate(code, template, atlas)
        out_path = OUT_DIR / f"{_slug(city)}.png"
        img.save(out_path, optimize=True, compress_level=6)
        print(f"Wrote {out_path.name} ({code})")
    print(f"Done — {len(PLATE_CITY_CODES)} images in {OUT_DIR}")


if __name__ == "__main__":
    main()
