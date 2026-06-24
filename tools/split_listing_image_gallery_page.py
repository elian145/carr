"""Split listing_image_gallery_page.dart into focused part files."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FILE = REPO / "lib/pages/listing_image_gallery_page.dart"
OUT = REPO / "lib/pages"

lines = FILE.read_text(encoding="utf-8").splitlines()

markers = [
    ("listing_media_viewer_page.dart", "class ListingMediaViewerPage"),
    ("listing_image_gallery_grid_page.dart", "class ListingImageGalleryPage"),
    ("listing_preview_media_grid_page.dart", "class ListingPreviewMediaGridPage"),
    ("listing_preview_media_viewer_page.dart", "class ListingPreviewMediaViewerPage"),
    ("listing_gallery_widgets.dart", "class _GalleryTile"),
]

indices = []
for _, class_prefix in markers:
    idx = next(
        (i for i, line in enumerate(lines) if line.lstrip().startswith(class_prefix)),
        None,
    )
    if idx is None:
        raise ValueError(f"marker not found: {class_prefix!r}")
    indices.append(idx)
imports = "\n".join(lines[: indices[0]]).rstrip()

parts = [f"part '{name}';" for name, _ in markers]
(FILE).write_text(imports + "\n\n" + "\n".join(parts) + "\n", encoding="utf-8")

for idx, (name, _) in enumerate(markers):
    end = indices[idx + 1] if idx + 1 < len(indices) else len(lines)
    block = "\n".join(lines[indices[idx]:end]).rstrip()
    (OUT / name).write_text(f"part of 'listing_image_gallery_page.dart';\n\n{block}\n", encoding="utf-8")

print("Split listing_image_gallery_page into", len(markers), "parts")
