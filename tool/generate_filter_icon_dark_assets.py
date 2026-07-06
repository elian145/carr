#!/usr/bin/env python3
"""Generate *_dark.png variants for filter icons."""

from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BORDER_WHITE_THRESH = 240
INTERIOR_WHITE_THRESH = 230
DARK_TILE_BG = np.array([28, 31, 40, 255], dtype=np.uint8)


def _is_near_white(rgb: np.ndarray, threshold: int) -> bool:
    return (
        int(rgb[0]) >= threshold
        and int(rgb[1]) >= threshold
        and int(rgb[2]) >= threshold
    )


def _flood_border_background(
    arr: np.ndarray,
    threshold: int,
) -> np.ndarray:
    height, width, _ = arr.shape
    visited = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    def try_seed(y: int, x: int) -> None:
        if visited[y, x]:
            return
        if not _is_near_white(arr[y, x, :3], threshold):
            return
        visited[y, x] = True
        queue.append((y, x))

    for x in range(width):
        try_seed(0, x)
        try_seed(height - 1, x)
    for y in range(height):
        try_seed(y, 0)
        try_seed(y, width - 1)

    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width:
                try_seed(ny, nx)

    return visited


def _flood_edge_background_excluding_center(
    arr: np.ndarray,
    threshold: int,
) -> np.ndarray:
    """Flood light background from edge bands while skipping central top/bottom."""
    height, width, _ = arr.shape
    visited = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    def try_seed(y: int, x: int) -> None:
        if visited[y, x]:
            return
        if not _is_near_white(arr[y, x, :3], threshold):
            return
        visited[y, x] = True
        queue.append((y, x))

    edge_band = max(16, width // 6)
    for x in range(width):
        if x < edge_band or x >= width - edge_band:
            try_seed(height - 1, x)
    for y in range(height):
        try_seed(y, 0)
        try_seed(y, width - 1)

    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width:
                try_seed(ny, nx)

    return visited


def _body_type_white_regions(arr: np.ndarray) -> np.ndarray:
    """Select only white background, windows, and under-car floor."""
    pure_white = (
        (arr[:, :, 0] == 255)
        & (arr[:, :, 1] == 255)
        & (arr[:, :, 2] == 255)
    )
    height, width = pure_white.shape
    visited = np.zeros((height, width), dtype=bool)
    picked = np.zeros((height, width), dtype=bool)

    for y in range(height):
        for x in range(width):
            if not pure_white[y, x] or visited[y, x]:
                continue

            queue: deque[tuple[int, int]] = deque([(y, x)])
            visited[y, x] = True
            component: list[tuple[int, int]] = []
            ymin = ymax = y
            xmin = xmax = x
            touches_border = False

            while queue:
                cy, cx = queue.popleft()
                component.append((cy, cx))
                ymin = min(ymin, cy)
                ymax = max(ymax, cy)
                xmin = min(xmin, cx)
                xmax = max(xmax, cx)
                if cy in (0, height - 1) or cx in (0, width - 1):
                    touches_border = True
                for ny, nx in ((cy - 1, cx), (cy + 1, cx), (cy, cx - 1), (cy, cx + 1)):
                    if 0 <= ny < height and 0 <= nx < width:
                        if pure_white[ny, nx] and not visited[ny, nx]:
                            visited[ny, nx] = True
                            queue.append((ny, nx))

            if touches_border:
                for py, px in component:
                    picked[py, px] = True
                continue

            box_width = xmax - xmin + 1
            box_height = ymax - ymin + 1
            is_window = ymax < int(height * 0.58)
            is_floor = (
                ymin > int(height * 0.60)
                and box_width > int(width * 0.28)
                and box_height < int(height * 0.10)
            )

            if is_window or is_floor:
                for py, px in component:
                    picked[py, px] = True

    return picked


def _connected_light_edge_regions(arr: np.ndarray) -> np.ndarray:
    """Select near-white / light-neutral regions connected to the outer border."""
    height, width, _ = arr.shape
    visited = np.zeros((height, width), dtype=bool)
    picked = np.zeros((height, width), dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    def is_edge_bg(y: int, x: int) -> bool:
        rgb = arr[y, x, :3]
        if _is_near_white(rgb, BORDER_WHITE_THRESH):
            return True
        channel_range = int(np.max(rgb)) - int(np.min(rgb))
        return (
            int(rgb[0]) >= 205
            and int(rgb[1]) >= 205
            and int(rgb[2]) >= 205
            and channel_range < 26
        )

    def try_seed(y: int, x: int) -> None:
        if visited[y, x] or not is_edge_bg(y, x):
            return
        visited[y, x] = True
        picked[y, x] = True
        queue.append((y, x))

    for x in range(width):
        try_seed(0, x)
        try_seed(height - 1, x)
    for y in range(height):
        try_seed(y, 0)
        try_seed(y, width - 1)

    while queue:
        y, x = queue.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < height and 0 <= nx < width:
                try_seed(ny, nx)

    return picked


def make_transparent_background_variant(
    src: Path,
    dest: Path,
    *,
    remove_interior_white: bool,
) -> None:
    image = Image.open(src).convert('RGBA')
    arr = np.array(image)
    transparent = _flood_border_background(arr, BORDER_WHITE_THRESH)

    if remove_interior_white:
        interior_white = (
            (arr[:, :, 0] >= INTERIOR_WHITE_THRESH)
            & (arr[:, :, 1] >= INTERIOR_WHITE_THRESH)
            & (arr[:, :, 2] >= INTERIOR_WHITE_THRESH)
        )
        channel_range = (
            np.max(arr[:, :, :3], axis=2) - np.min(arr[:, :, :3], axis=2)
        )
        neutral_light = (
            (arr[:, :, 0] >= 200)
            & (arr[:, :, 1] >= 200)
            & (arr[:, :, 2] >= 200)
            & (channel_range < 28)
        )
        transparent |= interior_white | neutral_light

    arr[transparent, 3] = 0
    Image.fromarray(arr, mode='RGBA').save(dest)


def make_body_type_dark_variant(src: Path, dest: Path) -> None:
    image = Image.open(src).convert('RGBA')
    arr = np.array(image)
    replace_mask = _body_type_white_regions(arr)
    arr[replace_mask] = DARK_TILE_BG
    Image.fromarray(arr, mode='RGBA').save(dest)


def make_dark_tile_background_variant(src: Path, dest: Path) -> None:
    image = Image.open(src).convert('RGBA')
    arr = np.array(image)
    replace_mask = _connected_light_edge_regions(arr)
    arr[replace_mask] = DARK_TILE_BG
    Image.fromarray(arr, mode='RGBA').save(dest)


def make_transmission_dark_variant(src: Path, dest: Path) -> None:
    image = Image.open(src).convert('RGBA')
    arr = np.array(image)
    replace_mask = _flood_edge_background_excluding_center(arr, BORDER_WHITE_THRESH)
    arr[replace_mask] = DARK_TILE_BG
    if src.stem == 'manual':
        height, width = arr.shape[:2]
        yy, xx = np.ogrid[:height, :width]
        top_cap_mask = (
            ((xx - (width * 0.50)) / (width * 0.20)) ** 2
            + ((yy - (height * 0.18)) / (height * 0.125)) ** 2
            <= 1.0
        )
        original = np.array(image)
        arr[top_cap_mask] = original[top_cap_mask]
    Image.fromarray(arr, mode='RGBA').save(dest)


def main() -> None:
    vehicle_folders = [
        ROOT / 'assets' / 'body_types_png',
        ROOT / 'assets' / 'drive_types',
        ROOT / 'assets' / 'transmission_types',
    ]
    plate_folder = ROOT / 'assets' / 'plate_types'

    body_type_folder = ROOT / 'assets' / 'body_types_png'
    for src in sorted(body_type_folder.glob('*.png')):
        if src.name.endswith('_dark.png'):
            continue
        dest = src.with_name(f'{src.stem}_dark.png')
        make_body_type_dark_variant(src, dest)
        print(f'wrote {dest.relative_to(ROOT)}')

    for folder in vehicle_folders:
        if folder == body_type_folder:
            continue
        if folder.name == 'transmission_types':
            for src in sorted(folder.glob('*.png')):
                if src.name.endswith('_dark.png'):
                    continue
                dest = src.with_name(f'{src.stem}_dark.png')
                make_transmission_dark_variant(src, dest)
                print(f'wrote {dest.relative_to(ROOT)}')
            continue
        for src in sorted(folder.glob('*.png')):
            if src.name.endswith('_dark.png'):
                continue
            dest = src.with_name(f'{src.stem}_dark.png')
            make_dark_tile_background_variant(src, dest)
            print(f'wrote {dest.relative_to(ROOT)}')

    for src in sorted(plate_folder.glob('*.png')):
        if src.name.endswith('_dark.png') or 'reference_sheet' in src.name:
            continue
        if src.stem.endswith('_mult'):
            continue
        dest = src.with_name(f'{src.stem}_dark.png')
        make_dark_tile_background_variant(src, dest)
        print(f'wrote {dest.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
