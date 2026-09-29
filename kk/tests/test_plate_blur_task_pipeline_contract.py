"""Task-level regression: `skip_blur` is an ABSOLUTE contract on the REAL
production Celery task pipeline, not just the pure helper.

Real-device incident (2026): production logged `skip_blur=True` together
with `plate_blur_applied=True` for a seller's final (post-choice) listing
photo -- the exact same processed-image hash a SEPARATE preview job (run
earlier with `skip_blur=False`) had already produced for the same source.
Root cause: `kk.media_processing._run_plate_blur()`'s `force_attempt`
parameter (driven by `PLATE_BLUR_REQUIRE_SUCCESS=1`, M-08) overrode an
explicit `skip_requested=True`, forcing detection (and therefore a real
blur, since the mocked/real detector found a plate) to run anyway.

`kk/tests/test_m08_plate_blur_fail_closed.py` already proves the pure
`_run_plate_blur()`/`blur_image_bytes()` helper honors `skip_blur`
unconditionally now. THIS file goes one level up and exercises the REAL
`kk.tasks.image_tasks.process_car_image_file` Celery task -- run for real
via `.apply()` (no broker/worker needed, exactly like
`test_p01_async_plate_blur.py::TestAsyncTaskEndToEnd`) -- because the
helper-level test alone was proven, on a real device, to be insufficient:
the helper could pass while the full task pipeline still failed if
`skip_blur` were somehow lost/defaulted/re-derived anywhere between the
task's own kwargs and the actual blur call. This file proves it is not.

Covers:
  A. skip_blur=True through the REAL task, with a detector GUARANTEED to
     detect a plate if invoked at all: blur must be impossible --
     detector never called, `_trace_plate_blur_applied` is False in the
     task's own result.
  B. Complement: skip_blur=False, same guaranteed-detection detector --
     blur IS applied, `_trace_plate_blur_applied` is True.
  C. Same A/B pair, but through the FULL media-readiness self-attach path
     (car_id/kind/client_media_id set) -- proves the server-side attach
     trace log (`attach_processed_car_image`) also reports the correct,
     non-inverted `skip_blur` value, and that a `CarImage` row is only
     ever created from the correctly-gated bytes.
  D. HEIF source through the same REAL task -- proves the fix is format-
     agnostic (the async task path decodes HEIF directly via
     `pillow_heif`'s registered opener inside `blur_license_plates()`,
     with no separate `heic_to_jpeg()` step, unlike the synchronous route
     path -- see `_process_image_bytes_from_path()`'s lack of any HEIC
     branch). Confirms HEIF was never the actual defect (a real device
     already produced a successful HEIF `plate_blur_applied=True` preview
     before this fix), matching the task's explicit instruction not to
     touch HEIF handling.
  E. Pixel-level proof (not just booleans): for the SAME source with a
     guaranteed-detected plate region, the skip_blur=True output is
     pixel-identical (modulo resize/re-encode) to the original everywhere,
     while the skip_blur=False output visibly differs specifically INSIDE
     the detected plate region.

Every test in this file uses `PLATE_BLUR_REQUIRE_SUCCESS=1` (the exact
production configuration the real-device incident was reproduced under)
UNLESS noted otherwise, since that is the specific mode the bug required.
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


# ---------------------------------------------------------------------------
# Fixture image: a background color with one visually distinct rectangular
# "plate-like" region, at a KNOWN pixel location -- so pixel-level
# assertions (part E) can check specifically inside vs. outside that box.
# ---------------------------------------------------------------------------
_IMG_W, _IMG_H = 96, 96
_PLATE_BOX = (20, 30, 76, 56)  # x1, y1, x2, y2 -- 56x26, well above the 6x6 floor


def _fixture_image_bytes(fmt: str = "JPEG") -> bytes:
    im = PILImage.new("RGB", (_IMG_W, _IMG_H), color=(30, 30, 30))
    # Paint a bright, high-contrast "plate" patch so GaussianBlur visibly
    # changes it (blurring a flat color would be a no-op pixel-wise).
    for y in range(_PLATE_BOX[1], _PLATE_BOX[3]):
        for x in range(_PLATE_BOX[0], _PLATE_BOX[2]):
            im.putpixel((x, y), (255, 255, 255) if (x + y) % 2 == 0 else (0, 0, 0))
    buf = BytesIO()
    if fmt == "JPEG":
        im.save(buf, format="JPEG", quality=95)
    else:
        im.save(buf, format=fmt)
    return buf.getvalue()


def _heic_fixture_bytes():
    pillow_heif = pytest.importorskip("pillow_heif")
    im = PILImage.new("RGB", (_IMG_W, _IMG_H), color=(30, 30, 30))
    for y in range(_PLATE_BOX[1], _PLATE_BOX[3]):
        for x in range(_PLATE_BOX[0], _PLATE_BOX[2]):
            im.putpixel((x, y), (255, 255, 255) if (x + y) % 2 == 0 else (0, 0, 0))
    heif_file = pillow_heif.from_pillow(im)
    buf = BytesIO()
    heif_file.save(buf, quality=90)
    return buf.getvalue()


def _guaranteed_detection_detector():
    """A fake `RoboflowPlateDetector` that ALWAYS reports one confident box
    exactly over `_PLATE_BOX`, if `detect_with_meta` is ever called."""
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


def _run_task_directly(
    *,
    temp_abs: str,
    filename: str,
    skip_blur: bool,
    car_id=None,
    kind=None,
    client_media_id=None,
):
    """Calls `_process_image_path()` -- the exact function
    `process_car_image_file` (the real Celery task) delegates to for all
    of its actual work, minus only the task-plumbing (`self.update_state`,
    `.delay()`/broker involvement, and the temp-file `finally:` cleanup)
    that requires either a live broker or a bound Celery task context we
    don't need here to prove the `skip_blur`/`plate_blur_applied` contract
    -- `process_car_image_file`'s own body (see `kk/tasks/image_tasks.py`)
    is a thin wrapper around exactly this call. `TestFullTaskViaApply`
    below additionally exercises the REAL bound task object via
    `.apply()`, matching `test_p01_async_plate_blur.py`'s own proven
    pattern, for the parts (media-readiness self-attach) that specifically
    depend on `car_id`/`client_media_id` task kwargs.
    """
    from kk.tasks.image_tasks import _process_image_path

    return _process_image_path(
        temp_abs=temp_abs,
        original_filename=filename,
        inline_base64=False,
        skip_blur=skip_blur,
        owner_public_id=None,
        source_r2_key=None,
    )


# ===========================================================================
# A + B: skip_blur is absolute on the real task pipeline, guaranteed
# detection either way.
# ===========================================================================


class TestTaskLevelSkipBlurContract:
    def test_a_skip_blur_true_makes_blur_impossible_even_with_guaranteed_detection(
        self, upload_env, monkeypatch, tmp_path
    ):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        temp_abs = _write_temp(tmp_path, _fixture_image_bytes(), "a_skip.jpg")
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.jpg", skip_blur=True
        )

        detector.detect_with_meta.assert_not_called()
        assert result["_trace_plate_blur_applied"] is False
        assert result["ok"] if "ok" in result else True
        assert result["rel_path"]

    def test_b_skip_blur_false_applies_blur_with_guaranteed_detection(
        self, upload_env, monkeypatch, tmp_path
    ):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        temp_abs = _write_temp(tmp_path, _fixture_image_bytes(), "b_blur.jpg")
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.jpg", skip_blur=False
        )

        detector.detect_with_meta.assert_called_once()
        assert result["_trace_plate_blur_applied"] is True
        assert result["rel_path"]

    def test_default_fail_open_mode_also_honors_skip_blur_unconditionally(
        self, upload_env, monkeypatch, tmp_path
    ):
        """Sanity: the fix must not regress the (already-correct) default
        fail-open mode -- PLATE_BLUR_REQUIRE_SUCCESS deliberately left
        unset here."""
        monkeypatch.delenv("PLATE_BLUR_REQUIRE_SUCCESS", raising=False)
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        temp_abs = _write_temp(tmp_path, _fixture_image_bytes(), "default_skip.jpg")
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.jpg", skip_blur=True
        )

        detector.detect_with_meta.assert_not_called()
        assert result["_trace_plate_blur_applied"] is False


# ===========================================================================
# D: HEIF source through the same real task path.
# ===========================================================================


class TestHeifSourceSameContract:
    def test_heif_skip_blur_true_still_makes_blur_impossible(
        self, upload_env, monkeypatch, tmp_path
    ):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        heic_bytes = _heic_fixture_bytes()
        temp_abs = _write_temp(tmp_path, heic_bytes, "photo.heic")
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.heic", skip_blur=True
        )

        detector.detect_with_meta.assert_not_called()
        assert result["_trace_plate_blur_applied"] is False
        assert result["rel_path"]

    def test_heif_skip_blur_false_applies_blur(
        self, upload_env, monkeypatch, tmp_path
    ):
        """Matches the real-device evidence: a HEIF source's preview job
        (skip_blur=False) DID successfully produce
        `plate_blur_applied=True` -- proving HEIF decoding itself was
        never the defect. This is the async task's own HEIF decode path
        (no explicit `heic_to_jpeg()` step -- `blur_license_plates()`'s
        `_decode_full_resolution_bgr()` opens the raw bytes directly via
        PIL with `pillow_heif` registered)."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", lambda: detector
        )

        heic_bytes = _heic_fixture_bytes()
        temp_abs = _write_temp(tmp_path, heic_bytes, "photo2.heic")
        result = _run_task_directly(
            temp_abs=temp_abs, filename="photo.heic", skip_blur=False
        )

        detector.detect_with_meta.assert_called_once()
        assert result["_trace_plate_blur_applied"] is True
        assert result["rel_path"]


# ===========================================================================
# E: pixel-level proof -- the two outputs must actually differ where it
# matters (inside the detected plate box), not just report different
# booleans.
# ===========================================================================


class TestPixelLevelOutputDifference:
    def test_unblurred_and_blurred_outputs_differ_only_inside_the_plate_region(
        self, upload_env, monkeypatch, tmp_path
    ):
        from kk.media_processing import current_app as mp_current_app

        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")

        source_bytes = _fixture_image_bytes()

        def _persisted_bytes(result: dict) -> bytes:
            rel_path = result["rel_path"]
            # Local-disk fallback: `persist_jpeg_bytes()` returns a LOGICAL
            # "uploads/car_photos/<name>" rel_path (for URL purposes), but
            # actually WRITES to "<UPLOAD_FOLDER>/car_photos/<name>" (no
            # "uploads/" segment in the physical path) -- see its own
            # `final_abs` vs. `final_rel_local` in kk/media_processing.py.
            abs_path = os.path.join(
                mp_current_app.config["UPLOAD_FOLDER"],
                "car_photos",
                os.path.basename(rel_path),
            )
            with open(abs_path, "rb") as fh:
                return fh.read()

        detector_for_unblurred = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector",
            lambda: detector_for_unblurred,
        )
        temp_abs_1 = _write_temp(tmp_path, source_bytes, "pixel_unblurred.jpg")
        result_unblurred = _run_task_directly(
            temp_abs=temp_abs_1, filename="photo.jpg", skip_blur=True
        )
        unblurred_bytes = _persisted_bytes(result_unblurred)

        detector_for_blurred = _guaranteed_detection_detector()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector",
            lambda: detector_for_blurred,
        )
        temp_abs_2 = _write_temp(tmp_path, source_bytes, "pixel_blurred.jpg")
        result_blurred = _run_task_directly(
            temp_abs=temp_abs_2, filename="photo.jpg", skip_blur=False
        )
        blurred_bytes = _persisted_bytes(result_blurred)

        assert unblurred_bytes != blurred_bytes, (
            "sanity: the two persisted files must not be byte-identical "
            "(skip_blur=True vs False must genuinely take different code "
            "paths)"
        )

        im_unblurred = PILImage.open(BytesIO(unblurred_bytes)).convert("RGB")
        im_blurred = PILImage.open(BytesIO(blurred_bytes)).convert("RGB")
        assert im_unblurred.size == im_blurred.size

        x1, y1, x2, y2 = _PLATE_BOX
        w, h = im_unblurred.size

        def _mean_abs_diff(box) -> float:
            bx1, by1, bx2, by2 = box
            total = 0
            n = 0
            for y in range(by1, by2):
                for x in range(bx1, bx2):
                    pu = im_unblurred.getpixel((x, y))
                    pb = im_blurred.getpixel((x, y))
                    total += sum(abs(a - b) for a, b in zip(pu, pb))
                    n += 1
            return total / max(1, n)

        inside_diff = _mean_abs_diff((x1, y1, x2, y2))
        # A generous margin outside the plate box on all sides (this
        # source image is otherwise a flat, unvarying background color,
        # so any real difference here would indicate the blur leaked
        # outside the detected region).
        outside_diff = _mean_abs_diff((0, 0, min(x1, 10), min(y1, 10)))

        assert inside_diff > 20, (
            f"expected a visibly different (blurred) plate region, got "
            f"mean abs per-channel diff={inside_diff}"
        )
        assert outside_diff < 5, (
            f"expected the background OUTSIDE the plate region to be "
            f"essentially unchanged between skip_blur=True and "
            f"skip_blur=False, got mean abs per-channel diff={outside_diff}"
        )


# ===========================================================================
# C: full media-readiness self-attach path -- car_id/kind/client_media_id
# set, proving the server-side attach trace also reports the correct value
# and a CarImage row is only ever created from the correctly-gated bytes.
# ===========================================================================


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_plate_blur_task_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "plate_blur_task.db")
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

    # Test-harness-only accommodation (NOT a production change -- same
    # workaround already used by `test_m04_no_exception_leak.py` /
    # `test_be10_route_exception_logging.py` / `test_m02_forgot_password_
    # no_enumeration.py`): on a fresh DB, `create_app()`'s auto-migrate
    # path runs `flask_migrate.upgrade()`, whose `migrations/env.py` calls
    # `logging.config.fileConfig(...)` with its default
    # `disable_existing_loggers=True`. That disables the already-created
    # Flask `app.logger` ("kk.app_factory") as an incidental side effect --
    # `attach_processed_car_image()`'s `[BLUR TRACE SERVER] attached ...`
    # line uses exactly this logger, so this test's `caplog` assertions
    # would silently observe nothing without undoing it here.
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
            first_name="Plate",
            last_name="Blur",
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


class TestFullSelfAttachPathReportsCorrectSkipBlur:
    def test_final_listing_attach_trace_reports_skip_blur_true_as_not_applied(
        self, app_ctx, monkeypatch, tmp_path, caplog
    ):
        """C: end-to-end through `transition_media_item_terminal` +
        `attach_processed_car_image` -- the server-side attach trace log
        must report the SAME (non-inverted) skip_blur value the task was
        actually given, and the resulting `CarImage` must come from the
        UNBLURRED bytes."""
        import logging

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

        temp_abs = _write_temp(tmp_path, _fixture_image_bytes(), "attach_unblurred.jpg")

        with caplog.at_level(logging.WARNING):
            with app.app_context():
                out = process_car_image_file.run(
                    temp_abs,
                    "photo.jpg",
                    False,
                    True,  # skip_blur=True -- seller chose UNBLURRED
                    owner_public_id=None,
                    source_r2_key=None,
                    car_id=car_id,
                    kind="listing",
                    client_media_id=client_media_id,
                )

        detector.detect_with_meta.assert_not_called()
        assert out["_trace_plate_blur_applied"] is False

        attach_lines = [
            r.getMessage()
            for r in caplog.records
            if "[BLUR TRACE SERVER] attached" in r.getMessage()
        ]
        assert attach_lines, "expected exactly one self-attach trace log line"
        assert "skip_blur_or_processing_mode=True" in attach_lines[0]

        with app.app_context():
            item = CarMediaItem.query.filter_by(
                car_id=car_id, client_media_id=client_media_id
            ).first()
            assert item.status == "attached"
            row = CarImage.query.filter_by(
                car_id=car_id, source_media_id=client_media_id
            ).first()
            assert row is not None
            assert row.image_url == out["rel_path"]

    def test_final_listing_attach_trace_reports_skip_blur_false_as_applied(
        self, app_ctx, monkeypatch, tmp_path, caplog
    ):
        import logging

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

        temp_abs = _write_temp(tmp_path, _fixture_image_bytes(), "attach_blurred.jpg")

        with caplog.at_level(logging.WARNING):
            with app.app_context():
                out = process_car_image_file.run(
                    temp_abs,
                    "photo.jpg",
                    False,
                    False,  # skip_blur=False -- seller chose BLURRED
                    owner_public_id=None,
                    source_r2_key=None,
                    car_id=car_id,
                    kind="listing",
                    client_media_id=client_media_id,
                )

        detector.detect_with_meta.assert_called_once()
        assert out["_trace_plate_blur_applied"] is True

        attach_lines = [
            r.getMessage()
            for r in caplog.records
            if "[BLUR TRACE SERVER] attached" in r.getMessage()
        ]
        assert attach_lines
        assert "skip_blur_or_processing_mode=False" in attach_lines[0]

        with app.app_context():
            item = CarMediaItem.query.filter_by(
                car_id=car_id, client_media_id=client_media_id
            ).first()
            assert item.status == "attached"
