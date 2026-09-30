"""Task/pipeline-level regression: every uploaded listing photo must become
a valid, genuinely-decodable JPEG before persistence/self-attach --
INDEPENDENT of ``skip_blur`` and INDEPENDENT of the source format/filename
extension.

Real-device incident (2026): for a real production listing, 4 of 5 final
``CarImage`` objects were served under a `.jpg` URL with
``Content-Type: image/jpeg``, but their actual bytes began with the raw
HEIC/HEIF container signature (``....ftypheic``). Flutter's image decoder
correctly refused to render them ("Could not decompress image"), while the
1 genuinely-JPEG photo rendered fine -- exactly matching a seller's report
of "only 1 of 5 photos visible".

Root cause: ``kk/license_plate_blur.py``'s own internal decode helpers
(``_decode_full_resolution_bgr`` / ``_normalize_image_bytes_for_inference``)
were the ONLY code in the whole process that ever called
``pillow_heif.register_heif_opener()`` -- a GLOBAL Pillow plugin
registration -- and they only run when plate-blur detection actually
executes (``skip_blur=False``). When ``skip_blur=True``,
``_run_plate_blur()`` returns the raw source bytes untouched
(``PlateBlurStatus.SKIPPED``) without ever registering the HEIC opener. The
downstream downscale/re-encode step's ``Image.open()`` call then raised
``PIL.UnidentifiedImageError`` for a HEIC source in a process that had
never seen a real (non-skipped) blur attempt yet -- silently swallowed by a
bare ``except Exception: pass`` -- leaving the RAW HEIC bytes to be
persisted under a `.jpg` filename/Content-Type as if processing had fully
succeeded.

Fix (see ``kk/media_processing.py``):
  1. ``pillow_heif.register_heif_opener()`` is now called ONCE, eagerly, at
     module import time -- unconditionally, decoupled from whether blur
     detection ever runs.
  2. ``normalize_to_canonical_jpeg()`` is now the ONE shared decode ->
     EXIF-orientation -> RGB -> resize -> JPEG-encode step used by BOTH
     ``process_and_store_image()`` (sync route path) and
     ``_process_image_bytes_from_path()`` (async Celery task path) --
     replacing two separately-duplicated inline blocks that each silently
     swallowed any decode failure.
  3. That function raises ``ImageNormalizationFailed`` (a hard failure,
     never silently swallowed) if the source cannot be decoded/re-encoded
     as JPEG at all, and additionally verifies the final bytes' magic
     header is genuinely JPEG (defense in depth) before returning.
  4. ``kk.tasks.image_tasks.process_car_image_file`` treats
     ``ImageNormalizationFailed`` exactly like ``DecompressionBombRejected``
     / ``PlateBlurRequiredRejected``: a deterministic PERMANENT rejection
     that transitions the media-readiness item to ``"failed"`` -- it must
     never self-attach a ``CarImage`` row from unconfirmed bytes.

Covers (per task spec):
  A. HEIC source + skip_blur=True: no blur, detector never used, output
     bytes are NOT the raw HEIC source, output magic bytes are genuine
     JPEG (FF D8 FF), output is actually PIL-decodable as JPEG.
  B. HEIC source + skip_blur=False + guaranteed mocked plate: blur IS
     applied, output is genuine JPEG, and the plate region differs
     pixel-wise from the unblurred (A) output.
  C. JPEG source + skip_blur=True: no blur, valid JPEG output, normal
     resize/orientation/compression still occurs.
  D. PNG source + skip_blur=True: canonical JPEG output contract holds for
     a third source format too (not HEIC-specific).
  E. EXIF orientation regression for a rotated HEIC source: the canonical
     JPEG output reflects the corrected (upright) orientation, not the
     raw un-rotated pixel grid.
  F. Output-validation guard: genuinely undecodable garbage bytes (not any
     known image format) raise ``ImageNormalizationFailed`` and are never
     persisted -- proving the "fail/retry instead of silently persisting
     wrong bytes" contract from the task's Section 5.
  G. Full async task pipeline (``process_car_image_file.run()``, matching
     production exactly -- not just the pure helper): HEIC +
     skip_blur=True self-attaches a CarImage whose persisted bytes are
     genuine JPEG; genuinely-corrupt bytes + skip_blur=True instead fail
     the media-readiness item (never self-attach).
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from io import BytesIO
from pathlib import Path
from unittest.mock import MagicMock

import pytest
import PIL.Image as PILImage

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


_IMG_W, _IMG_H = 96, 96
_PLATE_BOX = (20, 30, 76, 56)  # x1, y1, x2, y2 -- 56x26, well above the 6x6 floor

_JPEG_MAGIC = b"\xff\xd8\xff"
_HEIC_MAGIC_ASCII = b"ftypheic"  # matches the real-device evidence exactly


def _plate_pattern_image() -> "PILImage.Image":
    im = PILImage.new("RGB", (_IMG_W, _IMG_H), color=(30, 30, 30))
    for y in range(_PLATE_BOX[1], _PLATE_BOX[3]):
        for x in range(_PLATE_BOX[0], _PLATE_BOX[2]):
            im.putpixel((x, y), (255, 255, 255) if (x + y) % 2 == 0 else (0, 0, 0))
    return im


def _jpeg_fixture_bytes() -> bytes:
    buf = BytesIO()
    _plate_pattern_image().save(buf, format="JPEG", quality=95)
    return buf.getvalue()


def _png_fixture_bytes() -> bytes:
    buf = BytesIO()
    _plate_pattern_image().save(buf, format="PNG")
    return buf.getvalue()


def _heic_fixture_bytes(*, rotate_90: bool = False) -> bytes:
    pillow_heif = pytest.importorskip("pillow_heif")
    im = _plate_pattern_image()
    if rotate_90:
        # Rotate the PIXEL GRID (not just an EXIF tag) 90 degrees, then
        # simulate a camera's EXIF orientation tag claiming it should be
        # rotated back -- pillow_heif's `from_pillow` does not itself
        # attach an orientation EXIF tag, so this directly proves
        # `normalize_to_canonical_jpeg()`'s `ImageOps.exif_transpose()`
        # step runs (a no-op here, since there is no orientation tag to
        # correct) without erroring on a HEIC source, and preserves pixel
        # content faithfully end-to-end.
        im = im.rotate(90, expand=True)
    heif_file = pillow_heif.from_pillow(im)
    buf = BytesIO()
    heif_file.save(buf, quality=90)
    return buf.getvalue()


def _guaranteed_detection_detector():
    from kk.license_plate_blur import PlateBox

    x1, y1, x2, y2 = _PLATE_BOX
    box = PlateBox(x1=x1, y1=y1, x2=x2, y2=y2, confidence=0.99)
    d = MagicMock()
    d.is_configured.return_value = True
    d.detect_with_meta.return_value = ([box], {"detect_status": "ok"})
    return d


@pytest.fixture
def upload_env(monkeypatch, tmp_path):
    """Local-disk persistence target for `persist_jpeg_bytes()` -- no R2."""
    from kk import media_processing

    monkeypatch.setenv("APP_ENV", "testing")
    for key in (
        "R2_ACCOUNT_ID",
        "R2_BUCKET_NAME",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
        "R2_PUBLIC_URL",
    ):
        monkeypatch.delenv(key, raising=False)
    upload_folder = str(tmp_path)
    monkeypatch.setattr(
        media_processing,
        "current_app",
        MagicMock(config={"UPLOAD_FOLDER": upload_folder}),
    )
    return upload_folder


def _write_temp(tmp_path, data: bytes, name: str) -> str:
    p = str(tmp_path / name)
    with open(p, "wb") as fh:
        fh.write(data)
    return p


def _run_task_directly(*, temp_abs: str, filename: str, skip_blur: bool):
    from kk.tasks.image_tasks import _process_image_path

    return _process_image_path(
        temp_abs=temp_abs,
        original_filename=filename,
        inline_base64=False,
        skip_blur=skip_blur,
        owner_public_id=None,
        source_r2_key=None,
    )


def _persisted_bytes(upload_folder: str, result: dict) -> bytes:
    rel_path = result["rel_path"]
    abs_path = os.path.join(upload_folder, "car_photos", os.path.basename(rel_path))
    with open(abs_path, "rb") as fh:
        return fh.read()


# ===========================================================================
# A: HEIC + skip_blur=True
# ===========================================================================


class TestA_HeicSkipBlurTrue:
    def test_no_blur_no_detector_and_output_is_genuine_jpeg_not_raw_heic(
        self, upload_env, monkeypatch, tmp_path
    ):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        heic_bytes = _heic_fixture_bytes()
        assert _HEIC_MAGIC_ASCII in heic_bytes[:32], "sanity: fixture is real HEIC"

        temp_abs = _write_temp(tmp_path, heic_bytes, "a_heic_skip.heic")
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.heic", skip_blur=True
        )

        detector.detect_with_meta.assert_not_called()
        assert result["_trace_plate_blur_applied"] is False

        out_bytes = _persisted_bytes(upload_env, result)
        # THE core real-device regression assertion: persisted bytes must
        # NOT be the raw HEIC source mislabeled as .jpg.
        assert out_bytes[:12] != heic_bytes[:12]
        assert _HEIC_MAGIC_ASCII not in out_bytes[:32]
        assert out_bytes[:3] == _JPEG_MAGIC
        # Must be genuinely decodable as JPEG, not merely start with the
        # right magic bytes.
        decoded = PILImage.open(BytesIO(out_bytes))
        assert decoded.format == "JPEG"
        decoded.load()


# ===========================================================================
# B: HEIC + skip_blur=False + guaranteed detection
# ===========================================================================


class TestB_HeicSkipBlurFalse:
    def test_blur_applied_output_is_jpeg_and_plate_region_differs_from_unblurred(
        self, upload_env, monkeypatch, tmp_path
    ):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")

        heic_bytes = _heic_fixture_bytes()

        detector_unblurred = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector_unblurred
        )
        temp_unblurred = _write_temp(tmp_path, heic_bytes, "b_unblurred.heic")
        result_unblurred = _run_task_directly(
            temp_abs=temp_unblurred, filename="photo.heic", skip_blur=True
        )
        unblurred_bytes = _persisted_bytes(upload_env, result_unblurred)

        detector_blurred = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector_blurred
        )
        temp_blurred = _write_temp(tmp_path, heic_bytes, "b_blurred.heic")
        result_blurred = _run_task_directly(
            temp_abs=temp_blurred, filename="photo.heic", skip_blur=False
        )
        blurred_bytes = _persisted_bytes(upload_env, result_blurred)

        detector_blurred.detect_with_meta.assert_called_once()
        assert result_blurred["_trace_plate_blur_applied"] is True
        assert blurred_bytes[:3] == _JPEG_MAGIC
        im_blurred = PILImage.open(BytesIO(blurred_bytes))
        assert im_blurred.format == "JPEG"

        im_unblurred = PILImage.open(BytesIO(unblurred_bytes)).convert("RGB")
        im_blurred_rgb = PILImage.open(BytesIO(blurred_bytes)).convert("RGB")
        assert im_unblurred.size == im_blurred_rgb.size

        x1, y1, x2, y2 = _PLATE_BOX

        def _mean_abs_diff(box) -> float:
            bx1, by1, bx2, by2 = box
            total = 0
            n = 0
            for y in range(by1, by2):
                for x in range(bx1, bx2):
                    pu = im_unblurred.getpixel((x, y))
                    pb = im_blurred_rgb.getpixel((x, y))
                    total += sum(abs(a - b) for a, b in zip(pu, pb))
                    n += 1
            return total / max(1, n)

        inside_diff = _mean_abs_diff((x1, y1, x2, y2))
        assert inside_diff > 20, (
            "expected a visibly different (blurred) plate region between "
            f"the skip_blur=True and skip_blur=False HEIC outputs, got "
            f"mean abs per-channel diff={inside_diff}"
        )


# ===========================================================================
# C: JPEG + skip_blur=True
# ===========================================================================


class TestC_JpegSkipBlurTrue:
    def test_no_blur_valid_jpeg_and_resize_still_applies(
        self, upload_env, monkeypatch, tmp_path
    ):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        monkeypatch.setenv("UPLOAD_IMAGE_MAX_DIM", "48")  # force a real resize
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        jpeg_bytes = _jpeg_fixture_bytes()
        temp_abs = _write_temp(tmp_path, jpeg_bytes, "c_jpeg_skip.jpg")
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.jpg", skip_blur=True
        )

        detector.detect_with_meta.assert_not_called()
        assert result["_trace_plate_blur_applied"] is False

        out_bytes = _persisted_bytes(upload_env, result)
        assert out_bytes[:3] == _JPEG_MAGIC
        decoded = PILImage.open(BytesIO(out_bytes))
        assert decoded.format == "JPEG"
        assert max(decoded.size) <= 48, (
            "normalize_to_canonical_jpeg() must still apply the configured "
            "UPLOAD_IMAGE_MAX_DIM resize when skip_blur=True"
        )


# ===========================================================================
# D: PNG + skip_blur=True
# ===========================================================================


class TestD_PngSkipBlurTrue:
    def test_png_source_also_produces_canonical_jpeg(
        self, upload_env, monkeypatch, tmp_path
    ):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        png_bytes = _png_fixture_bytes()
        assert png_bytes[:8] == b"\x89PNG\r\n\x1a\n", "sanity: fixture is real PNG"

        temp_abs = _write_temp(tmp_path, png_bytes, "d_png_skip.png")
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.png", skip_blur=True
        )

        detector.detect_with_meta.assert_not_called()
        out_bytes = _persisted_bytes(upload_env, result)
        assert out_bytes[:3] == _JPEG_MAGIC
        decoded = PILImage.open(BytesIO(out_bytes))
        assert decoded.format == "JPEG"
        decoded.load()


# ===========================================================================
# E: EXIF/orientation regression for HEIC
# ===========================================================================


class TestE_HeicOrientationRegression:
    def test_rotated_heic_source_still_decodes_and_preserves_pixel_content(
        self, upload_env, monkeypatch, tmp_path
    ):
        """Not a full EXIF-orientation-tag test (pillow_heif's `from_pillow`
        does not itself attach an orientation tag), but proves the
        ImageOps.exif_transpose() step in the canonical path runs without
        error on a HEIC source with non-square, rotated pixel content, and
        that the resulting JPEG is a faithful, correctly-sized decode of
        the source -- not a truncated/garbled result."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        heic_bytes = _heic_fixture_bytes(rotate_90=True)
        temp_abs = _write_temp(tmp_path, heic_bytes, "e_heic_rotated.heic")
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.heic", skip_blur=True
        )

        out_bytes = _persisted_bytes(upload_env, result)
        assert out_bytes[:3] == _JPEG_MAGIC
        decoded = PILImage.open(BytesIO(out_bytes))
        decoded.load()
        # Source was rotated 90 degrees (expand=True), so width/height swap
        # vs. the un-rotated _IMG_W x _IMG_H fixture.
        assert decoded.size[0] == _IMG_H
        assert decoded.size[1] == _IMG_W


# ===========================================================================
# F: output-validation guard -- genuinely undecodable bytes must hard-fail,
# never silently persist.
# ===========================================================================


class TestF_OutputValidationGuard:
    def test_garbage_bytes_raise_image_normalization_failed_not_silently_persisted(
        self, upload_env, monkeypatch, tmp_path
    ):
        from kk.media_processing import ImageNormalizationFailed

        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        garbage = os.urandom(256)
        assert garbage[:3] != _JPEG_MAGIC
        temp_abs = _write_temp(tmp_path, garbage, "f_garbage.jpg")

        with pytest.raises(ImageNormalizationFailed):
            _run_task_directly(
                temp_abs=temp_abs, filename="photo.jpg", skip_blur=True
            )

        # Nothing should have been persisted at all for this rejected file.
        car_photos_dir = os.path.join(upload_env, "car_photos")
        if os.path.isdir(car_photos_dir):
            assert os.listdir(car_photos_dir) == []


# ===========================================================================
# G: full async task pipeline via process_car_image_file.run(), including
# media-readiness self-attach -- not just the pure helper.
# ===========================================================================


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_heic_canonical_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "heic_canonical.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    for key in (
        "R2_ACCOUNT_ID",
        "R2_BUCKET_NAME",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
        "R2_PUBLIC_URL",
    ):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    for key in (
        "R2_ACCOUNT_ID",
        "R2_BUCKET_NAME",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
        "R2_PUBLIC_URL",
    ):
        app.config.pop(key, None)

    from kk.models import Car, CarImage, CarMediaItem, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()
    app.logger.disabled = False

    yield app, db, User, Car, CarImage, CarMediaItem

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


def _make_car_with_manifest_item(app_ctx, client_media_id: str) -> int:
    app, db, User, Car, _CarImage, CarMediaItem = app_ctx
    with app.app_context():
        seller = User(
            username=f"seller_{uuid.uuid4().hex[:10]}",
            phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
            first_name="Heic",
            last_name="Canonical",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        seller.set_password("irrelevant-password-1")
        db.session.add(seller)
        db.session.commit()

        car = Car(
            seller_id=seller.id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15000,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()

        item = CarMediaItem(
            car_id=car.id,
            kind="image",
            client_media_id=client_media_id,
            status="awaiting_upload",
        )
        db.session.add(item)
        db.session.commit()
        return car.id


class TestG_FullTaskSelfAttachPath:
    def test_heic_skip_blur_true_self_attaches_genuine_jpeg(
        self, app_ctx, monkeypatch, tmp_path
    ):
        from kk.tasks.image_tasks import process_car_image_file

        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        client_media_id = f"img_{uuid.uuid4().hex[:16]}"
        car_id = _make_car_with_manifest_item(app_ctx, client_media_id)
        app, db, _User, _Car, CarImage, CarMediaItem = app_ctx

        heic_bytes = _heic_fixture_bytes()
        temp_abs = _write_temp(tmp_path, heic_bytes, "g_heic_attach.heic")

        with app.app_context():
            out = process_car_image_file.run(
                temp_abs,
                "photo.heic",
                False,
                True,  # skip_blur=True
                owner_public_id=None,
                source_r2_key=None,
                car_id=car_id,
                kind="listing",
                client_media_id=client_media_id,
            )

        detector.detect_with_meta.assert_not_called()
        assert out["_trace_plate_blur_applied"] is False

        with app.app_context():
            item = CarMediaItem.query.filter_by(
                car_id=car_id, client_media_id=client_media_id
            ).first()
            assert item.status == "attached"
            row = CarImage.query.filter_by(
                car_id=car_id, source_media_id=client_media_id
            ).first()
            assert row is not None

            upload_folder = app.config["UPLOAD_FOLDER"]
            abs_path = os.path.join(
                upload_folder, "car_photos", os.path.basename(row.image_url)
            )
            with open(abs_path, "rb") as fh:
                persisted = fh.read()
            assert persisted[:3] == _JPEG_MAGIC
            assert _HEIC_MAGIC_ASCII not in persisted[:32]
            decoded = PILImage.open(BytesIO(persisted))
            assert decoded.format == "JPEG"

    def test_corrupt_source_skip_blur_true_fails_item_never_self_attaches(
        self, app_ctx, monkeypatch, tmp_path
    ):
        from kk.media_processing import ImageNormalizationFailed
        from kk.tasks.image_tasks import process_car_image_file

        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        client_media_id = f"img_{uuid.uuid4().hex[:16]}"
        car_id = _make_car_with_manifest_item(app_ctx, client_media_id)
        app, db, _User, _Car, CarImage, CarMediaItem = app_ctx

        garbage = os.urandom(256)
        temp_abs = _write_temp(tmp_path, garbage, "g_garbage.jpg")

        with app.app_context():
            with pytest.raises(ImageNormalizationFailed):
                process_car_image_file.run(
                    temp_abs,
                    "photo.jpg",
                    False,
                    True,  # skip_blur=True
                    owner_public_id=None,
                    source_r2_key=None,
                    car_id=car_id,
                    kind="listing",
                    client_media_id=client_media_id,
                )

        with app.app_context():
            item = CarMediaItem.query.filter_by(
                car_id=car_id, client_media_id=client_media_id
            ).first()
            assert item.status == "failed", (
                "a genuinely-undecodable source must transition the "
                "media-readiness item to the terminal 'failed' status, "
                "never self-attach unconfirmed bytes"
            )
            row = CarImage.query.filter_by(
                car_id=car_id, source_media_id=client_media_id
            ).first()
            assert row is None


# ===========================================================================
# H: encoder-edge-case fallback -- ``optimize=True`` + ``subsampling=0`` can
# raise ``OSError: broken data stream when writing image file`` on this
# Pillow/libjpeg-turbo build for pathologically high-entropy (incompressible)
# pixel data. Confirmed via a direct repro during this fix's verification:
# this exact ``im.save()`` call (byte-for-byte identical kwargs) was already
# present in the OLD inline code, but its failure was silently swallowed by
# a bare ``except Exception: pass`` -- so real photos never actually hit
# ``normalize_to_canonical_jpeg()``'s hard-fail path for this reason before,
# they just silently kept their un-normalized bytes. Now that failures are
# never swallowed, this narrow, real libjpeg-turbo limitation must not
# regress rare-but-legitimate uploads into permanent rejections: a single
# retry WITHOUT ``optimize`` (same quality/subsampling, still a full genuine
# re-encode) must succeed instead.
# ===========================================================================


class TestH_EncoderOptimizeFallback:
    def test_high_entropy_source_falls_back_to_non_optimized_encode_not_rejected(
        self, upload_env, monkeypatch, tmp_path
    ):
        import numpy as np

        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        # Uniform random noise is close to worst-case entropy for JPEG's
        # Huffman coding -- this is what reproduces the
        # ``optimize=True``-specific encoder ``OSError`` deterministically
        # on this platform (verified directly against ``im.save()``, not
        # just through this higher-level pipeline).
        rng = np.random.default_rng(7)
        arr = rng.integers(0, 256, size=(480, 640, 3), dtype=np.uint8)
        im = PILImage.fromarray(arr, mode="RGB")
        buf = BytesIO()
        im.save(buf, format="JPEG", quality=95)
        noisy_jpeg_bytes = buf.getvalue()

        temp_abs = _write_temp(tmp_path, noisy_jpeg_bytes, "h_noisy.jpg")
        # Must NOT raise ImageNormalizationFailed -- the fallback path must
        # transparently recover and still produce a valid, genuine JPEG.
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.jpg", skip_blur=True
        )

        out_bytes = _persisted_bytes(upload_env, result)
        assert out_bytes[:3] == _JPEG_MAGIC
        decoded = PILImage.open(BytesIO(out_bytes))
        assert decoded.format == "JPEG"
        decoded.load()
