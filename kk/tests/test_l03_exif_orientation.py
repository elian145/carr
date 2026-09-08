"""L-03: EXIF must be stripped from stored car-listing photos, and any EXIF
Orientation tag must be normalized into the pixels *before* it is discarded
(otherwise sideways/upside-down phone photos would be stored without any way
to correct their orientation).

These tests exercise the real `process_and_store_image()` / `_process_image_path()`
pipelines (the "downscale/compress" step) against local disk, with R2 and the
Roboflow plate-blur network dependency both disabled -- no network access is
required or performed.
"""

from __future__ import annotations

import base64
import glob
import os
from io import BytesIO
from unittest.mock import MagicMock

import pytest
from PIL import ExifTags, Image, ImageOps, ImageStat

from kk import media_processing
from kk.tasks import image_tasks

# A 14x14 pure-red marker painted into one corner of an otherwise white image.
# Which corner it ends up in after processing tells us whether/how the image
# was rotated, without hard-coding Pillow's own orientation->transpose mapping.
_MARKER_BOX = 14


def _make_marker_jpeg(*, orientation: int | None, with_privacy_exif: bool) -> bytes:
    """Landscape JPEG with a red marker in the top-left corner.

    ``orientation`` (if not None) is written as the EXIF Orientation tag.
    ``with_privacy_exif`` additionally embeds GPS/camera/timestamp EXIF, the
    kind of metadata this fix must guarantee never survives into storage.
    """
    width, height = 60, 30
    im = Image.new("RGB", (width, height), color=(255, 255, 255))
    marker = Image.new("RGB", (_MARKER_BOX, _MARKER_BOX), color=(220, 20, 20))
    im.paste(marker, (0, 0))

    save_kwargs = {}
    if orientation is not None or with_privacy_exif:
        exif = Image.Exif()
        if orientation is not None:
            exif[ExifTags.Base.Orientation] = orientation
        if with_privacy_exif:
            exif[ExifTags.Base.Make] = "UnitTestCam"
            exif[ExifTags.Base.Model] = "UnitTestModel"
            exif[ExifTags.Base.DateTimeOriginal] = "2024:01:01 12:00:00"
            exif[ExifTags.Base.GPSInfo] = {
                1: "N",
                2: (37.0, 46.0, 30.0),
                3: "E",
                4: (23.0, 43.0, 0.0),
            }
        save_kwargs["exif"] = exif

    buf = BytesIO()
    im.save(buf, format="JPEG", quality=95, **save_kwargs)
    return buf.getvalue()


def _corner_regions(im: Image.Image, box: int = _MARKER_BOX) -> dict:
    w, h = im.size
    return {
        "top_left": im.crop((0, 0, min(box, w), min(box, h))),
        "top_right": im.crop((max(0, w - box), 0, w, min(box, h))),
        "bottom_left": im.crop((0, max(0, h - box), min(box, w), h)),
        "bottom_right": im.crop((max(0, w - box), max(0, h - box), w, h)),
    }


def _is_red(region: Image.Image) -> bool:
    r, g, b = ImageStat.Stat(region.convert("RGB")).mean
    return r > 150 and g < 150 and b < 150


def _red_corner(im: Image.Image) -> str:
    reds = [name for name, region in _corner_regions(im).items() if _is_red(region)]
    assert len(reds) == 1, f"expected exactly one red corner, found {reds}"
    return reds[0]


def _assert_no_exif(im: Image.Image) -> None:
    assert not im.getexif(), "output image must carry no EXIF tags"
    assert not im.info.get("exif"), "output image must carry no raw EXIF bytes"


class _FakeFileStorage:
    """Minimal stand-in for werkzeug's FileStorage: .filename + .save(path)."""

    def __init__(self, data: bytes, filename: str):
        self._data = data
        self.filename = filename

    def save(self, path: str) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(self._data)


@pytest.fixture
def upload_env(monkeypatch, tmp_path):
    """Route process_and_store_image()/persist_jpeg_bytes() to local disk only.

    R2_* config keys are intentionally absent, so `_r2_configured()` is False
    and no network call is attempted. ROBOFLOW_API_KEY is unset so the
    plate-blur detector reports `is_configured() == False` and also performs
    no network call.
    """
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)
    upload_folder = str(tmp_path)
    monkeypatch.setattr(
        media_processing,
        "current_app",
        MagicMock(config={"UPLOAD_FOLDER": upload_folder}),
    )
    return upload_folder


def _read_sole_output(upload_folder: str) -> bytes:
    matches = glob.glob(os.path.join(upload_folder, "car_photos", "*"))
    assert len(matches) == 1, f"expected exactly one stored file, found {matches}"
    with open(matches[0], "rb") as fh:
        return fh.read()


# ---------------------------------------------------------------------------
# A. EXIF stripping
# ---------------------------------------------------------------------------


def test_process_and_store_image_strips_exif_when_blur_skipped(upload_env):
    src = _make_marker_jpeg(orientation=None, with_privacy_exif=True)
    fs = _FakeFileStorage(src, "photo.jpg")

    media_processing.process_and_store_image(fs, False, skip_blur=True)

    out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
    _assert_no_exif(out_im)


def test_process_and_store_image_strips_exif_when_blur_attempted(upload_env):
    """Same as above but with skip_blur=False: PLATE_BLUR_ENABLED path runs,
    but with no ROBOFLOW_API_KEY configured, get_plate_detector().is_configured()
    is False, so blur_license_plates() is never called (no network) and the
    bytes fall through to the same downscale/compress step under test.
    """
    src = _make_marker_jpeg(orientation=None, with_privacy_exif=True)
    fs = _FakeFileStorage(src, "photo.jpg")

    media_processing.process_and_store_image(fs, False, skip_blur=False)

    out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
    _assert_no_exif(out_im)


def test_heic_to_jpeg_strips_camera_and_gps_exif():
    pillow_heif = pytest.importorskip("pillow_heif")

    im = Image.new("RGB", (32, 16), color=(0, 200, 0))
    exif = Image.Exif()
    exif[ExifTags.Base.Make] = "UnitTestCam"
    exif[ExifTags.Base.GPSInfo] = {1: "N", 2: (1.0, 0.0, 0.0), 3: "E", 4: (2.0, 0.0, 0.0)}

    heif_file = pillow_heif.from_pillow(im)
    heif_file.info["exif"] = exif.tobytes()
    buf = BytesIO()
    heif_file.save(buf, quality=90)

    out_bytes, converted = media_processing.heic_to_jpeg(buf.getvalue())

    assert converted is True
    out_im = Image.open(BytesIO(out_bytes))
    assert out_im.format == "JPEG"
    _assert_no_exif(out_im)


# ---------------------------------------------------------------------------
# B. Orientation is applied to pixels before it is discarded
# ---------------------------------------------------------------------------


def test_process_and_store_image_normalizes_orientation_6(upload_env):
    src = _make_marker_jpeg(orientation=6, with_privacy_exif=True)

    # Reference transform computed directly with Pillow -- this is exactly
    # what the fix is supposed to apply, so we don't hard-code the specific
    # rotation direction Pillow's orientation table uses for tag 6.
    expected = ImageOps.exif_transpose(Image.open(BytesIO(src)))
    expected_size = expected.size
    expected_corner = _red_corner(expected)

    fs = _FakeFileStorage(src, "photo.jpg")
    media_processing.process_and_store_image(fs, False, skip_blur=True)

    out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
    assert out_im.size == expected_size
    assert _red_corner(out_im) == expected_corner
    _assert_no_exif(out_im)


def test_process_image_path_normalizes_orientation_6(upload_env, tmp_path):
    """Same guarantee for the Celery task's duplicate pipeline."""
    src = _make_marker_jpeg(orientation=6, with_privacy_exif=True)
    expected = ImageOps.exif_transpose(Image.open(BytesIO(src)))
    expected_size = expected.size
    expected_corner = _red_corner(expected)

    temp_abs = str(tmp_path / "incoming.jpg")
    with open(temp_abs, "wb") as fh:
        fh.write(src)

    result = image_tasks._process_image_path(
        temp_abs=temp_abs,
        original_filename="incoming.jpg",
        inline_base64=True,
        skip_blur=True,
    )

    out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
    assert out_im.size == expected_size
    assert _red_corner(out_im) == expected_corner
    _assert_no_exif(out_im)

    # The inline base64 preview must also be EXIF-free.
    assert result["base64"]
    _, encoded = result["base64"].split(",", 1)
    preview_im = Image.open(BytesIO(base64.b64decode(encoded)))
    _assert_no_exif(preview_im)


# ---------------------------------------------------------------------------
# C. Orientation=1 regression: already-correct images must not be re-rotated
# ---------------------------------------------------------------------------


def test_process_and_store_image_orientation_1_is_unchanged(upload_env):
    src = _make_marker_jpeg(orientation=1, with_privacy_exif=True)
    src_im = Image.open(BytesIO(src))
    original_size = src_im.size
    original_corner = _red_corner(src_im)

    fs = _FakeFileStorage(src, "photo.jpg")
    media_processing.process_and_store_image(fs, False, skip_blur=True)

    out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
    assert out_im.size == original_size
    assert _red_corner(out_im) == original_corner
    _assert_no_exif(out_im)


def test_process_and_store_image_no_orientation_tag_is_unchanged(upload_env):
    """No Orientation tag at all (common case: most non-EXIF/edited images)
    must be treated the same as Orientation=1 -- no rotation, no crash."""
    src = _make_marker_jpeg(orientation=None, with_privacy_exif=False)
    src_im = Image.open(BytesIO(src))
    original_size = src_im.size
    original_corner = _red_corner(src_im)

    fs = _FakeFileStorage(src, "photo.jpg")
    media_processing.process_and_store_image(fs, False, skip_blur=True)

    out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
    assert out_im.size == original_size
    assert _red_corner(out_im) == original_corner
    _assert_no_exif(out_im)
