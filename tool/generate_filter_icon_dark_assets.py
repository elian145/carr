#!/usr/bin/env python3
"""Generate *_dark.png variants: same icon pixels, transparent background."""

from __future__ import annotations

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BORDER_WHITE_THRESH = 240
INTERIOR_WHITE_THRESH = 230


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


def main() -> None:
    vehicle_folders = [
        ROOT / 'assets' / 'body_types_png',
        ROOT / 'assets' / 'drive_types',
        ROOT / 'assets' / 'transmission_types',
    ]
    plate_folder = ROOT / 'assets' / 'plate_types'

    for folder in vehicle_folders:
        for src in sorted(folder.glob('*.png')):
            if src.name.endswith('_dark.png'):
                continue
            dest = src.with_name(f'{src.stem}_dark.png')
            make_transparent_background_variant(
                src,
                dest,
                remove_interior_white=True,
            )
            print(f'wrote {dest.relative_to(ROOT)}')

    for src in sorted(plate_folder.glob('*.png')):
        if src.name.endswith('_dark.png') or 'reference_sheet' in src.name:
            continue
        if src.stem.endswith('_mult'):
            continue
        dest = src.with_name(f'{src.stem}_dark.png')
        make_transparent_background_variant(
            src,
            dest,
            remove_interior_white=False,
        )
        print(f'wrote {dest.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
