"""Regression tests for the UPLOAD_IMAGE_MAX_DIM default change (1200 -> 2048).

Benchmark rationale (see the plate-blur image-quality audit report): 2048
matches Flutter's own ``image_picker`` ``maxWidth``/``maxHeight`` cap
exactly, so most uploads need no further backend resize at all. This file
proves, against the real production entrypoints
(``kk.media_processing.process_and_store_image`` and
``kk.tasks.image_tasks._process_image_path`` -- the two intentionally
duplicated pipelines), that:

  - the new default is genuinely 2048 (not silently still 1200)
  - a 2048px input is passed through with NO unnecessary resize
  - images larger than 2048 are still capped, correctly, at 2048
  - portrait and landscape aspect ratios are preserved by the cap
  - both duplicated pipelines (media_processing.py / image_tasks.py) agree
    on the same default and produce identical output dimensions
  - blurred and non-blurred uploads still end at identical final
    dimensions once the cap actually engages (not just when it's a no-op)
  - EXIF stripping/orientation-normalization still works at the new default
  - the M-06 decompression-bomb guard is not weakened by this change
"""

from __future__ import annotations

import glob
import os
import sys
from io import BytesIO
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import PIL.Image as PILImage  # noqa: E402
from PIL import ExifTags, Image, ImageOps  # noqa: E402

from kk import media_processing  # noqa: E402
from kk.tasks import image_tasks  # noqa: E402


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


class _FakeFileStorage:
    """Minimal stand-in for werkzeug's FileStorage: .filename + .save(path)."""

    def __init__(self, data: bytes, filename: str):
        self._data = data
        self.filename = filename

    def save(self, path: str) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(self._data)


def _solid_jpeg_bytes(width: int, height: int, color=(120, 130, 140), quality=90) -> bytes:
    """A plain, valid JPEG at an arbitrary resolution -- dimension/aspect
    behavior doesn't depend on image content, so a solid color keeps these
    tests fast even at multi-megapixel sizes."""
    im = Image.new("RGB", (width, height), color=color)
    buf = BytesIO()
    im.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


@pytest.fixture
def upload_env(monkeypatch, tmp_path):
    """Route process_and_store_image()/persist_jpeg_bytes() to local disk
    only -- no ROBOFLOW_API_KEY, no R2 config, so no network access."""
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)
    monkeypatch.delenv("UPLOAD_IMAGE_MAX_DIM", raising=False)
    monkeypatch.delenv("UPLOAD_IMAGE_JPEG_QUALITY", raising=False)
    upload_folder = str(tmp_path)
    monkeypatch.setattr(
        media_processing,
        "current_app",
        MagicMock(config={"UPLOAD_FOLDER": upload_folder}),
    )
    return upload_folder


def _stored_files(upload_folder: str) -> list[str]:
    return glob.glob(os.path.join(upload_folder, "car_photos", "*"))


def _read_sole_output(upload_folder: str) -> bytes:
    matches = _stored_files(upload_folder)
    assert len(matches) == 1, f"expected exactly one stored file, found {matches}"
    with open(matches[0], "rb") as fh:
        return fh.read()


# ---------------------------------------------------------------------------
# A. The default is genuinely 2048 (env unset)
# ---------------------------------------------------------------------------


class TestDefaultIsNowTwentyFortyEight:
    def test_media_processing_default_is_2048_not_1200(self, upload_env, monkeypatch):
        """A 1600px-longest-side image must survive untouched -- it would
        have been downscaled to 1200 under the OLD default, proving the
        default really did change (not just the env-var name/docs)."""
        src = _solid_jpeg_bytes(1600, 1067)
        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert out_im.size == (1600, 1067)

    def test_image_tasks_default_is_2048_not_1200(self, upload_env, tmp_path):
        src = _solid_jpeg_bytes(1600, 1067)
        temp_abs = str(tmp_path / "incoming.jpg")
        with open(temp_abs, "wb") as fh:
            fh.write(src)

        image_tasks._process_image_path(
            temp_abs=temp_abs, original_filename="photo.jpg", inline_base64=False, skip_blur=True
        )
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert out_im.size == (1600, 1067)

    def test_explicit_env_override_still_wins(self, upload_env, monkeypatch):
        """The default changed, but an operator-set UPLOAD_IMAGE_MAX_DIM
        must still take precedence (no default is hardcoded/ignored)."""
        monkeypatch.setenv("UPLOAD_IMAGE_MAX_DIM", "800")
        src = _solid_jpeg_bytes(1600, 1067)
        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert max(out_im.size) == 800


# ---------------------------------------------------------------------------
# B. A 2048px input is not unnecessarily resized
# ---------------------------------------------------------------------------


class TestExactlyAtCapIsNotResized:
    @pytest.mark.parametrize(
        "dims",
        [(2048, 1536), (2048, 2048), (1536, 2048)],
    )
    def test_media_processing_leaves_2048_untouched(self, upload_env, dims):
        src = _solid_jpeg_bytes(*dims)
        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert out_im.size == dims, "a 2048-longest-side image must not be resized at all"

    def test_image_tasks_leaves_2048_untouched(self, upload_env, tmp_path):
        src = _solid_jpeg_bytes(2048, 1536)
        temp_abs = str(tmp_path / "incoming.jpg")
        with open(temp_abs, "wb") as fh:
            fh.write(src)
        image_tasks._process_image_path(
            temp_abs=temp_abs, original_filename="photo.jpg", inline_base64=False, skip_blur=True
        )
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert out_im.size == (2048, 1536)

    def test_just_under_cap_is_not_resized(self, upload_env):
        src = _solid_jpeg_bytes(2047, 1536)
        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert out_im.size == (2047, 1536)


# ---------------------------------------------------------------------------
# C. Images larger than 2048 are capped correctly, aspect ratio preserved
# ---------------------------------------------------------------------------


class TestOverCapIsCorrectlyCappedWithAspectPreserved:
    def test_landscape_over_cap_scales_long_edge_to_2048(self, upload_env):
        # 4032x3024 (the reported real-world phone-photo resolution).
        src = _solid_jpeg_bytes(4032, 3024)
        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert max(out_im.size) == 2048
        w, h = out_im.size
        assert w == 2048
        # Aspect ratio preserved within Pillow's integer-rounding tolerance.
        expected_h = round(3024 * (2048 / 4032))
        assert abs(h - expected_h) <= 1

    def test_portrait_over_cap_scales_long_edge_to_2048(self, upload_env):
        # Portrait phone photo, e.g. 3024x4032.
        src = _solid_jpeg_bytes(3024, 4032)
        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert max(out_im.size) == 2048
        w, h = out_im.size
        assert h == 2048
        expected_w = round(3024 * (2048 / 4032))
        assert abs(w - expected_w) <= 1

    def test_square_over_cap_stays_square(self, upload_env):
        src = _solid_jpeg_bytes(3000, 3000)
        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert out_im.size == (2048, 2048)

    def test_image_tasks_over_cap_matches_media_processing_exactly(self, upload_env, tmp_path):
        """The two duplicated pipelines (media_processing.py and
        image_tasks.py) must agree on the exact same capped dimensions for
        the same oversized source -- proving item 6 (same defaults, same
        behavior), not just the same env var name."""
        src = _solid_jpeg_bytes(4032, 3024)

        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        via_media_processing = Image.open(BytesIO(_read_sole_output(upload_env))).size

        for f in glob.glob(os.path.join(upload_env, "car_photos", "*")):
            os.remove(f)

        temp_abs = str(tmp_path / "incoming.jpg")
        with open(temp_abs, "wb") as fh:
            fh.write(src)
        image_tasks._process_image_path(
            temp_abs=temp_abs, original_filename="photo.jpg", inline_base64=False, skip_blur=True
        )
        via_image_tasks = Image.open(BytesIO(_read_sole_output(upload_env))).size

        assert via_media_processing == via_image_tasks == (2048, 1536)


# ---------------------------------------------------------------------------
# D. Blurred and non-blurred paths end at identical dimensions, including
#    when the NEW (2048) cap actually engages.
# ---------------------------------------------------------------------------


class TestBlurredAndNonBlurredIdenticalDimensionsAtNewCap:
    def _fake_detector(self, boxes=None):
        d = MagicMock()
        d.is_configured.return_value = True
        d.detect_with_meta.return_value = (boxes or [], {"detect_status": "ok"})
        return d

    def test_identical_dimensions_when_a_plate_is_blurred_and_cap_engages(
        self, upload_env, monkeypatch
    ):
        from kk.license_plate_blur import PlateBox

        # 4032x3024 source -- well over the new 2048 cap, so the shared
        # downstream resize genuinely engages for both runs.
        src = _solid_jpeg_bytes(4032, 3024)

        box = PlateBox(x1=1600, y1=1200, x2=1900, y2=1350, confidence=0.9)
        detector = self._fake_detector(boxes=[box])
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        fs_blurred = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs_blurred, False, skip_blur=False)
        blurred_dims = Image.open(BytesIO(_read_sole_output(upload_env))).size

        for f in glob.glob(os.path.join(upload_env, "car_photos", "*")):
            os.remove(f)

        fs_plain = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs_plain, False, skip_blur=True)
        plain_dims = Image.open(BytesIO(_read_sole_output(upload_env))).size

        assert blurred_dims == plain_dims == (2048, 1536)

    def test_identical_dimensions_when_no_plate_found_and_cap_engages(
        self, upload_env, monkeypatch
    ):
        src = _solid_jpeg_bytes(3024, 4032)
        detector = self._fake_detector(boxes=[])
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        fs_a = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs_a, False, skip_blur=False)
        a_dims = Image.open(BytesIO(_read_sole_output(upload_env))).size

        for f in glob.glob(os.path.join(upload_env, "car_photos", "*")):
            os.remove(f)

        fs_b = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs_b, False, skip_blur=True)
        b_dims = Image.open(BytesIO(_read_sole_output(upload_env))).size

        assert a_dims == b_dims == (1536, 2048)


# ---------------------------------------------------------------------------
# E. EXIF stripping / orientation normalization still works at the new default
# ---------------------------------------------------------------------------


class TestExifStillHandledAtNewDefault:
    @staticmethod
    def _marker_jpeg(orientation: int, w=2400, h=1800) -> bytes:
        """A landscape JPEG larger than the new 2048 cap, with a red marker
        in the top-left corner and an EXIF Orientation tag -- exercises
        both the resize path AND orientation normalization together."""
        im = Image.new("RGB", (w, h), color=(255, 255, 255))
        marker = Image.new("RGB", (60, 60), color=(220, 20, 20))
        im.paste(marker, (0, 0))
        exif = Image.Exif()
        exif[ExifTags.Base.Orientation] = orientation
        exif[ExifTags.Base.Make] = "UnitTestCam"
        exif[ExifTags.Base.GPSInfo] = {1: "N", 2: (1.0, 0.0, 0.0), 3: "E", 4: (2.0, 0.0, 0.0)}
        buf = BytesIO()
        im.save(buf, format="JPEG", quality=90, exif=exif)
        return buf.getvalue()

    def test_orientation_and_exif_stripped_with_resize_over_new_cap(self, upload_env):
        src = self._marker_jpeg(orientation=6, w=2400, h=1800)
        expected = ImageOps.exif_transpose(Image.open(BytesIO(src)))

        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))

        # Orientation 6 swaps width/height; output must also be capped at
        # 2048 on the new long edge.
        assert max(out_im.size) == 2048
        exp_w, exp_h = expected.size
        long_is_width = exp_w >= exp_h
        if long_is_width:
            assert out_im.size[0] == 2048
        else:
            assert out_im.size[1] == 2048

        assert not out_im.getexif(), "output must carry no EXIF tags"
        assert not out_im.info.get("exif"), "output must carry no raw EXIF bytes"

    def test_orientation_1_unchanged_with_resize_over_new_cap(self, upload_env):
        src = self._marker_jpeg(orientation=1, w=2400, h=1800)
        fs = _FakeFileStorage(src, "photo.jpg")
        media_processing.process_and_store_image(fs, False, skip_blur=True)
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert out_im.size[0] == 2048  # landscape long edge is width
        assert not out_im.getexif()


# ---------------------------------------------------------------------------
# F. The M-06 decompression-bomb guard is not weakened by this change
# ---------------------------------------------------------------------------


class TestDecompressionBombGuardUnweakened:
    def test_process_and_store_image_still_rejects_bomb_at_new_default(
        self, upload_env, monkeypatch
    ):
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        src = _solid_jpeg_bytes(20, 20)
        fs = _FakeFileStorage(src, "photo.jpg")
        with pytest.raises(media_processing.DecompressionBombRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=True)
        assert _stored_files(upload_env) == []

    def test_image_tasks_still_rejects_bomb_at_new_default(
        self, upload_env, monkeypatch, tmp_path
    ):
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)
        src = _solid_jpeg_bytes(20, 20)
        temp_abs = str(tmp_path / "incoming.jpg")
        with open(temp_abs, "wb") as fh:
            fh.write(src)

        with pytest.raises(media_processing.DecompressionBombRejected):
            image_tasks._process_image_path(
                temp_abs=temp_abs,
                original_filename="photo.jpg",
                inline_base64=False,
                skip_blur=True,
            )
        assert _stored_files(upload_env) == []

    def test_normal_image_at_new_cap_still_succeeds_with_real_pillow_default(
        self, upload_env
    ):
        """Sanity regression: the real (non-monkeypatched) Pillow
        MAX_IMAGE_PIXELS default must keep processing an ordinary
        multi-megapixel photo (well under Pillow's own bomb threshold)
        exactly as before, now landing at the new 2048 cap."""
        src = _solid_jpeg_bytes(4032, 3024)
        fs = _FakeFileStorage(src, "photo.jpg")
        rel_path, _b64 = media_processing.process_and_store_image(fs, False, skip_blur=True)
        assert rel_path
        out_im = Image.open(BytesIO(_read_sole_output(upload_env)))
        assert max(out_im.size) == 2048
