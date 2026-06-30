"""Extract governorate plate rows from the official reference sheet (no edits)."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[1]
SOURCE = REPO / "assets" / "plate_types" / "plate_city_reference_sheet.png"
OUT_DIR = REPO / "assets" / "plate_types"
FIRST_CODE = 11
LAST_CODE = 29
NORMALIZED_OUTPUT_SIZE = (378, 74)

BORDER_ROW_MIN_DARK = 200
FULL_BORDER_MIN_INK = 300
GAP_INK_THRESHOLD = 200
BORDER_INK_THRESHOLD = 250
TRIM_PADDING = 4


def _rgb_array(img: Image.Image) -> np.ndarray:
    return np.array(img.convert("RGB"))


def _row_dark(arr: np.ndarray) -> np.ndarray:
    return (arr.min(axis=2) < 100).sum(axis=1)


def _row_ink(arr: np.ndarray, *, threshold: int = BORDER_INK_THRESHOLD) -> np.ndarray:
    return (arr.min(axis=2) < threshold).sum(axis=1)


def _gap_runs(row_ink: np.ndarray) -> list[tuple[int, int]]:
    gaps: list[int] = [y for y in range(len(row_ink)) if row_ink[y] < 20]
    if not gaps:
        return []

    runs: list[tuple[int, int]] = []
    start = gaps[0]
    prev = gaps[0]
    for y in gaps[1:]:
        if y == prev + 1:
            prev = y
            continue
        if prev - start >= 3:
            runs.append((start, prev))
        start = y
        prev = y
    if prev - start >= 3:
        runs.append((start, prev))
    return runs


def _dark_border_runs(dark: np.ndarray, y1: int, y2: int) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    y = y1
    while y <= y2:
        if dark[y] >= BORDER_ROW_MIN_DARK:
            start = y
            while y <= y2 and dark[y] >= BORDER_ROW_MIN_DARK:
                y += 1
            runs.append((start, y - 1))
        else:
            y += 1
    return runs


def _refine_plate_top(arr: np.ndarray, y1: int, y2: int) -> int:
    """Drop the prior plate's bottom line when it appears at the crop top."""
    dark = _row_dark(arr)
    runs = _dark_border_runs(dark, y1, y2)
    if not runs:
        return y1

    top_run = runs[0]
    if len(runs) >= 2:
        first_end = runs[0][1]
        second_start = runs[1][0]
        if second_start - first_end <= 6:
            gap = dark[first_end + 1 : second_start]
            if len(gap) == 0 or int(gap.max()) < BORDER_ROW_MIN_DARK:
                top_run = runs[1]
    return top_run[0]


def _border_groups(row_ink: np.ndarray) -> list[tuple[int, int]]:
    groups: list[tuple[int, int]] = []
    in_group = False
    start = 0
    for y, ink in enumerate(row_ink):
        is_border = ink >= FULL_BORDER_MIN_INK
        if is_border and not in_group:
            start = y
            in_group = True
        elif not is_border and in_group:
            groups.append((start, y - 1))
            in_group = False
    if in_group:
        groups.append((start, len(row_ink) - 1))
    return groups


def _drop_leading_orphan_border(
    groups: list[tuple[int, int]], row_ink: np.ndarray
) -> list[tuple[int, int]]:
    """Remove the prior plate's bottom border when it was included at the crop top."""
    if len(groups) < 2:
        return groups

    first_start, first_end = groups[0]
    if first_end - first_start + 1 < 5:
        return groups

    second_start, _ = groups[1]
    if second_start - first_end > 6:
        return groups

    gap = row_ink[first_end + 1 : second_start]
    if len(gap) == 0 or int(gap.max()) >= FULL_BORDER_MIN_INK:
        return groups

    return groups[1:]


def _trim_outer_whitespace(img: Image.Image, padding: int = TRIM_PADDING) -> Image.Image:
    arr = _rgb_array(img)
    row_ink = _row_ink(arr)
    mask = arr.min(axis=2) < BORDER_INK_THRESHOLD
    ys, xs = np.where(mask)
    if len(xs) == 0 or len(ys) == 0:
        return img

    groups = _drop_leading_orphan_border(_border_groups(row_ink), row_ink)
    y1 = groups[0][0] if groups else int(ys.min())
    y2 = int(ys.max())

    x1, x2 = int(xs.min()), int(xs.max())
    plate = img.crop((x1, y1, x2 + 1, y2 + 1))
    padded = Image.new(
        plate.mode,
        (plate.width + padding * 2, plate.height + padding * 2),
        (255, 255, 255),
    )
    padded.paste(plate, (padding, padding))
    return padded


def _plate_bands(img: Image.Image) -> list[tuple[int, int]]:
    arr = _rgb_array(img)
    gap_row_ink = _row_ink(arr, threshold=GAP_INK_THRESHOLD)
    h = len(gap_row_ink)

    starts: list[int] = []
    for _, gap_end in _gap_runs(gap_row_ink):
        y = gap_end + 1
        if y < h and max(gap_row_ink[y : min(y + 8, h)]) > 250:
            starts.append(y)

    plate_count = LAST_CODE - FIRST_CODE + 1
    return [
        (
            _refine_plate_top(arr, start, (starts[i + 1] - 1) if i + 1 < len(starts) else h - 1),
            (starts[i + 1] - 1) if i + 1 < len(starts) else h - 1,
        )
        for i, start in enumerate(starts[:plate_count])
    ]


def _normalize_plate_size(img: Image.Image) -> Image.Image:
    if img.size == NORMALIZED_OUTPUT_SIZE:
        return img
    return img.resize(NORMALIZED_OUTPUT_SIZE, Image.Resampling.LANCZOS)


def _ensure_visible_bottom_border(img: Image.Image) -> Image.Image:
    arr = _rgb_array(img)
    row_ink = (arr.min(axis=2) < BORDER_INK_THRESHOLD).sum(axis=1)

    top_border_y = next(
        (y for y in range(min(16, img.height)) if row_ink[y] > img.width * 0.75),
        None,
    )
    if top_border_y is None:
        return img

    top_row_mask = arr[top_border_y].min(axis=1) < BORDER_INK_THRESHOLD
    xs = np.where(top_row_mask)[0]
    if len(xs) == 0:
        return img

    bottom_candidates = [
        y
        for y in range(img.height - 1, max(-1, img.height - 20), -1)
        if row_ink[y] > 20
    ]
    if not bottom_candidates:
        return img

    bottom_y = bottom_candidates[0]
    x1, x2 = int(xs.min()), int(xs.max())
    # The official source's bottom edge is very faint; thicken it so it remains
    # visible after the asset is scaled down inside the filter tile.
    arr[max(0, bottom_y - 2) : bottom_y + 1, x1 : x2 + 1] = (0, 0, 0)
    return Image.fromarray(arr)


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Missing reference sheet: {SOURCE}")

    img = Image.open(SOURCE)
    bands = _plate_bands(img)
    expected = LAST_CODE - FIRST_CODE + 1
    if len(bands) != expected:
        raise SystemExit(f"Expected {expected} plates, found {len(bands)}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for code, (y1, y2) in zip(range(FIRST_CODE, LAST_CODE + 1), bands, strict=True):
        crop = _ensure_visible_bottom_border(
            _normalize_plate_size(
                _trim_outer_whitespace(img.crop((0, y1, img.width, y2 + 1)))
            )
        )
        out_path = OUT_DIR / f"code_{code}.png"
        crop.save(out_path, optimize=True)
        print(f"Wrote {out_path.name} ({crop.size[0]}x{crop.size[1]})")

    print(f"Done — {expected} plates in {OUT_DIR}")


if __name__ == "__main__":
    main()
