"""Regression tests for the plate-blur image-quality-loss audit/fix.

Root cause recap (see the audit report for full detail): ``blur_license_plates()``
(``kk/license_plate_blur.py``) used to build a *lossy JPEG/WEBP re-encode* of
the whole image purely to normalize EXIF orientation for the Roboflow
request, then decoded THAT re-encoded copy (not the original bytes) as the
source of the pixels it blurred and re-encoded again. Every blurred upload
therefore picked up two extra full-frame JPEG generations (quality 95, then
92) on top of the shared downstream downscale/re-encode step every listing
photo (blurred or not) already goes through -- visibly softening the ENTIRE
photo, not just the plate.

The fix decodes the original bytes exactly once (``_decode_full_resolution_bgr``)
and uses that buffer as the only pixel source for both the blur and the
final encode; the Roboflow-only "detection copy" (optionally downscaled via
``PLATE_DETECT_MAX_DIM``) is now clearly separated from the persisted-pixel
path, with detected boxes mapped back to full-resolution coordinates before
any drawing happens.

This file proves (item G of the audit):
  A. original dimensions are preserved by blur processing
  B. detector-downscaled coordinates map correctly to full-resolution image
  C. only the plate ROI is altered -- the rest of the frame is bit-identical
     (proven losslessly via PNG, which also proves there is no extra
     generation loss hiding in the non-ROI pixels)
  D. EXIF stripping / orientation normalization still works through the
     real blur_license_plates() path (not just the skip_blur path already
     covered by test_l03_exif_orientation.py)
  E. the "no plates found" path returns the original bytes completely
     unchanged -- no unnecessary re-encode/degrade
  F. blurred vs. non-blurred parity through the real persistence pipeline
     (process_and_store_image): identical output dimensions for the same
     source image
"""

from __future__ import annotations

import os
import sys
from io import BytesIO
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from kk import license_plate_blur  # noqa: E402
from kk.license_plate_blur import PlateBox  # noqa: E402

cv2 = pytest.importorskip("cv2")
np = pytest.importorskip("numpy")
PILImage = pytest.importorskip("PIL.Image")
from PIL import ExifTags, Image, ImageOps  # noqa: E402


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


def _noise_png_bytes(width: int, height: int, seed: int = 42) -> bytes:
    """A PNG (lossless) with real high-frequency detail everywhere, so a
    Gaussian blur visibly changes pixels wherever it's applied, and a
    lossless round trip proves untouched regions are bit-identical."""
    rng = np.random.default_rng(seed)
    arr = rng.integers(0, 256, size=(height, width, 3), dtype=np.uint8)
    im = Image.fromarray(arr, mode="RGB")
    buf = BytesIO()
    im.save(buf, format="PNG")
    return buf.getvalue(), arr


def _fake_detector(boxes=None, meta=None):
    d = MagicMock()
    d.is_configured.return_value = True
    d.detect_with_meta.return_value = (boxes or [], meta or {"detect_status": "ok"})
    return d


def _make_marker_jpeg(*, orientation: int | None, with_privacy_exif: bool) -> bytes:
    """Landscape JPEG with a red marker in the top-left corner (mirrors
    test_l03_exif_orientation.py's helper, kept local/self-contained here)."""
    width, height = 80, 40
    im = Image.new("RGB", (width, height), color=(255, 255, 255))
    marker = Image.new("RGB", (14, 14), color=(220, 20, 20))
    im.paste(marker, (0, 0))

    save_kwargs = {}
    if orientation is not None or with_privacy_exif:
        exif = Image.Exif()
        if orientation is not None:
            exif[ExifTags.Base.Orientation] = orientation
        if with_privacy_exif:
            exif[ExifTags.Base.Make] = "UnitTestCam"
            exif[ExifTags.Base.GPSInfo] = {1: "N", 2: (37.0, 46.0, 30.0), 3: "E", 4: (23.0, 43.0, 0.0)}
        save_kwargs["exif"] = exif

    buf = BytesIO()
    im.save(buf, format="JPEG", quality=95, **save_kwargs)
    return buf.getvalue()


def _corner_regions(im: Image.Image, box: int = 14) -> dict:
    w, h = im.size
    return {
        "top_left": im.crop((0, 0, min(box, w), min(box, h))),
        "top_right": im.crop((max(0, w - box), 0, w, min(box, h))),
        "bottom_left": im.crop((0, max(0, h - box), min(box, w), h)),
        "bottom_right": im.crop((max(0, w - box), max(0, h - box), w, h)),
    }


def _is_red(region: Image.Image) -> bool:
    from PIL import ImageStat

    r, g, b = ImageStat.Stat(region.convert("RGB")).mean
    return r > 150 and g < 150 and b < 150


def _red_corner(im: Image.Image) -> str:
    from PIL import ImageStat  # noqa: F401

    reds = [name for name, region in _corner_regions(im).items() if _is_red(region)]
    assert len(reds) == 1, f"expected exactly one red corner, found {reds}"
    return reds[0]


# ---------------------------------------------------------------------------
# A + C: dimensions preserved, only the plate ROI is altered
# ---------------------------------------------------------------------------


class TestDimensionsPreservedAndOnlyRoiAltered:
    def test_full_resolution_preserved_and_non_roi_pixels_bit_identical(self):
        """The central regression test: run a real (non-mocked cv2) blur
        through a lossless PNG so we can assert, pixel-for-pixel, that (1)
        output dimensions exactly match input dimensions and (2) every
        pixel OUTSIDE the detected box is bit-identical to the source --
        proving there is no hidden extra encode/decode/resize generation
        touching the rest of the photo."""
        width, height = 400, 300
        src_bytes, src_arr = _noise_png_bytes(width, height)

        box = PlateBox(x1=50, y1=60, x2=150, y2=140, confidence=0.95)
        detector = _fake_detector(boxes=[box])

        out_bytes, meta = license_plate_blur.blur_license_plates(
            image_bytes=src_bytes,
            output_ext=".png",
            detector=detector,
            expand_ratio=0.0,
        )
        assert meta.get("status") == "blurred"
        assert meta.get("applied") == 1

        out_im = Image.open(BytesIO(out_bytes))
        assert out_im.size == (width, height), "blur must not change image dimensions"
        out_arr = np.array(out_im.convert("RGB"))

        # Build a mask for everything OUTSIDE the (unexpanded) detected box.
        mask = np.ones((height, width), dtype=bool)
        mask[box.y1 : box.y2, box.x1 : box.x2] = False

        assert np.array_equal(out_arr[mask], src_arr[mask]), (
            "pixels outside the plate ROI must be bit-identical to the "
            "source image -- the blur pipeline must not soften/resample/"
            "re-encode the rest of the photo"
        )

        # Sanity: the ROI itself really was changed (blur actually applied).
        assert not np.array_equal(
            out_arr[box.y1 : box.y2, box.x1 : box.x2],
            src_arr[box.y1 : box.y2, box.x1 : box.x2],
        ), "the detected ROI must actually be blurred"

    def test_large_image_dimensions_preserved_through_blur(self):
        """A stand-in for the reported real-world case (e.g. a 4032x3024
        phone photo): blur_license_plates() itself must never downsize the
        image it returns."""
        width, height = 2016, 1512  # kept modest for test speed; same ratio
        src_bytes, _ = _noise_png_bytes(width, height)
        box = PlateBox(x1=800, y1=700, x2=1000, y2=780, confidence=0.9)
        detector = _fake_detector(boxes=[box])

        out_bytes, meta = license_plate_blur.blur_license_plates(
            image_bytes=src_bytes,
            output_ext=".jpg",
            detector=detector,
        )
        assert meta.get("status") == "blurred"
        out_im = Image.open(BytesIO(out_bytes))
        assert out_im.size == (width, height)


# ---------------------------------------------------------------------------
# B: detector-downscaled coordinates map correctly to full-resolution image
# ---------------------------------------------------------------------------


class TestDetectionDownscaleCoordinateMapping:
    def test_scale_box_to_full_res_unit(self):
        b = PlateBox(x1=25, y1=20, x2=75, y2=50, confidence=0.8)
        scaled = license_plate_blur._scale_box_to_full_res(b, 0.5)
        assert (scaled.x1, scaled.y1, scaled.x2, scaled.y2) == (50, 40, 150, 100)
        assert scaled.confidence == 0.8

    def test_scale_box_to_full_res_noop_when_scale_is_one(self):
        b = PlateBox(x1=25, y1=20, x2=75, y2=50, confidence=0.8)
        assert license_plate_blur._scale_box_to_full_res(b, 1.0) == b

    def test_end_to_end_downscaled_detection_maps_back_to_full_res(self, monkeypatch):
        """Full pipeline: force PLATE_DETECT_MAX_DIM so the copy sent to the
        (mocked) detector is genuinely downscaled, have the mock return a
        box in THAT downscaled coordinate space (as the real Roboflow API
        would), and assert the blur lands at the correctly upscaled
        location on the full-resolution output -- never on the wrong
        region, and never persisting the downscaled copy itself."""
        width, height = 800, 600
        max_dim = 400  # -> detection copy is 400x300, scale = 0.5
        monkeypatch.setenv("PLATE_DETECT_MAX_DIM", str(max_dim))

        src_bytes, src_arr = _noise_png_bytes(width, height)

        seen_detect_sizes = []

        def _detect_with_meta(image_bytes):
            im = Image.open(BytesIO(image_bytes))
            seen_detect_sizes.append(im.size)
            # A box in the (downscaled) detection image's coordinate space.
            box = PlateBox(x1=50, y1=40, x2=150, y2=100, confidence=0.9)
            return [box], {"detect_status": "ok"}

        detector = MagicMock()
        detector.is_configured.return_value = True
        detector.detect_with_meta.side_effect = _detect_with_meta

        out_bytes, meta = license_plate_blur.blur_license_plates(
            image_bytes=src_bytes,
            output_ext=".png",
            detector=detector,
        )

        assert meta.get("status") == "blurred"
        # Proves the detector really did receive a downscaled copy (never
        # the full-resolution image) -- requirement A ("smaller working
        # copy for performance").
        assert seen_detect_sizes == [(400, 300)]
        assert meta.get("detect_scale") == pytest.approx(0.5)

        out_im = Image.open(BytesIO(out_bytes))
        assert out_im.size == (width, height), (
            "the downscaled detection copy must never be saved/returned"
        )
        out_arr = np.array(out_im.convert("RGB"))

        # Expected full-res box: detection box * (1/scale) = *2.
        full_box = (100, 80, 300, 200)
        mask = np.ones((height, width), dtype=bool)
        mask[full_box[1] : full_box[3], full_box[0] : full_box[2]] = False

        assert np.array_equal(out_arr[mask], src_arr[mask]), (
            "everything outside the correctly-upscaled box must be untouched"
        )
        assert not np.array_equal(
            out_arr[full_box[1] : full_box[3], full_box[0] : full_box[2]],
            src_arr[full_box[1] : full_box[3], full_box[0] : full_box[2]],
        ), "the upscaled box region must actually be blurred"

        # And a region that would have been "inside the box" if the code
        # had wrongly used the *unscaled* detection coordinates directly
        # (50,40)-(150,100) but is outside the correctly-scaled box must be
        # unaffected -- catches the specific bug of forgetting to map back.
        assert np.array_equal(
            out_arr[40:80, 50:100], src_arr[40:80, 50:100]
        ), "must not blur using raw (un-scaled) detection-space coordinates"


# ---------------------------------------------------------------------------
# D: EXIF stripping / orientation normalization through the real blur path
# ---------------------------------------------------------------------------


class TestExifAndOrientationThroughRealBlur:
    def test_orientation_and_exif_stripped_when_a_plate_is_blurred(self):
        """Same guarantee as test_l03_exif_orientation.py, but exercised
        through the actual detect-and-blur code path (a real box is
        supplied and really blurred), not just the skip_blur/no-key
        fallback path."""
        src = _make_marker_jpeg(orientation=6, with_privacy_exif=True)

        expected = ImageOps.exif_transpose(Image.open(BytesIO(src)))
        expected_size = expected.size
        expected_corner = _red_corner(expected)

        # A box far from the marker corner, in POST-rotation (expected)
        # pixel coordinates -- detection always runs against the
        # orientation-normalized copy.
        ew, eh = expected_size
        box = PlateBox(
            x1=max(0, ew - 20), y1=max(0, eh - 15), x2=ew, y2=eh, confidence=0.9
        )
        detector = _fake_detector(boxes=[box])

        out_bytes, meta = license_plate_blur.blur_license_plates(
            image_bytes=src, output_ext=".jpg", detector=detector
        )
        assert meta.get("status") == "blurred"

        out_im = Image.open(BytesIO(out_bytes))
        assert out_im.size == expected_size
        assert _red_corner(out_im) == expected_corner

        # No EXIF (GPS/camera/orientation tag) survives.
        assert not out_im.getexif(), "output must carry no EXIF tags"
        assert not out_im.info.get("exif"), "output must carry no raw EXIF bytes"


# ---------------------------------------------------------------------------
# E: "no plates found" must not unnecessarily degrade/re-encode
# ---------------------------------------------------------------------------


class TestNoPlatesFoundNoUnnecessaryReencode:
    def test_no_plates_returns_byte_identical_original(self):
        src_bytes, _ = _noise_png_bytes(120, 90)
        detector = _fake_detector(boxes=[])

        out_bytes, meta = license_plate_blur.blur_license_plates(
            image_bytes=src_bytes, output_ext=".png", detector=detector
        )
        assert meta.get("status") == "no_plates"
        assert out_bytes == src_bytes, (
            "when no plate is detected, the original bytes must be returned "
            "completely unchanged -- no re-encode, no resize, no quality loss"
        )

    def test_detect_failed_also_returns_byte_identical_original(self):
        src_bytes, _ = _noise_png_bytes(120, 90)
        detector = _fake_detector(boxes=[], meta={"detect_status": "detect_failed"})

        out_bytes, meta = license_plate_blur.blur_license_plates(
            image_bytes=src_bytes, output_ext=".png", detector=detector
        )
        assert meta.get("status") == "detect_failed"
        assert out_bytes == src_bytes


# ---------------------------------------------------------------------------
# F: blurred vs. non-blurred parity through the real persistence pipeline
# ---------------------------------------------------------------------------


class TestBlurredVsNonBlurredParityThroughPersistence:
    """Exercises kk.media_processing.process_and_store_image() -- the real
    entrypoint used by POST /api/cars/<id>/images -- with a mocked detector,
    comparing a plate-blurred upload against an identical skip_blur=True
    upload of the exact same source image."""

    @pytest.fixture
    def upload_env(self, monkeypatch, tmp_path):
        monkeypatch.setenv("APP_ENV", "testing")
        monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)
        upload_folder = str(tmp_path)
        from kk import media_processing

        monkeypatch.setattr(
            media_processing,
            "current_app",
            MagicMock(config={"UPLOAD_FOLDER": upload_folder}),
        )
        return upload_folder

    class _FakeFileStorage:
        def __init__(self, data: bytes, filename: str):
            self._data = data
            self.filename = filename

        def save(self, path: str) -> None:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as fh:
                fh.write(self._data)

    @staticmethod
    def _read(upload_folder: str) -> bytes:
        import glob

        matches = glob.glob(os.path.join(upload_folder, "car_photos", "*"))
        assert len(matches) == 1
        with open(matches[0], "rb") as fh:
            return fh.read()

    def test_blurred_and_nonblurred_uploads_have_identical_final_dimensions(
        self, upload_env, monkeypatch
    ):
        from kk import media_processing

        # Source is well under UPLOAD_IMAGE_MAX_DIM (2048 by default) so the
        # shared downstream downscale step is a no-op for both runs --
        # isolating whether the BLUR step itself introduces any size
        # difference.
        width, height = 640, 480
        rng = np.random.default_rng(7)
        arr = rng.integers(0, 256, size=(height, width, 3), dtype=np.uint8)
        im = Image.fromarray(arr, mode="RGB")
        buf = BytesIO()
        im.save(buf, format="JPEG", quality=95)
        src_bytes = buf.getvalue()

        # Run 1: a plate IS detected and blurred.
        box = PlateBox(x1=200, y1=200, x2=320, y2=260, confidence=0.9)
        detector = _fake_detector(boxes=[box])
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")

        fs1 = self._FakeFileStorage(src_bytes, "photo.jpg")
        media_processing.process_and_store_image(fs1, False, skip_blur=False)
        blurred_out = Image.open(BytesIO(self._read(upload_env)))

        # Clean the folder before run 2.
        import glob

        for f in glob.glob(os.path.join(upload_env, "car_photos", "*")):
            os.remove(f)

        # Run 2: identical source, blur skipped entirely.
        fs2 = self._FakeFileStorage(src_bytes, "photo.jpg")
        media_processing.process_and_store_image(fs2, False, skip_blur=True)
        plain_out = Image.open(BytesIO(self._read(upload_env)))

        assert blurred_out.size == (width, height)
        assert plain_out.size == (width, height)
        assert blurred_out.size == plain_out.size, (
            "a plate-blurred upload and a non-blurred upload of the same "
            "source image must end up with identical stored dimensions"
        )
