"""M-08 regression tests.

PRODUCTION_AUDIT.md M-08 (MEDIUM): "Plate blur fails open -- uploads succeed
with unblurred plates if Roboflow errors or ROBOFLOW_API_KEY is unset"
(``kk/media_processing.py``).

Investigation (see the M-08 investigation report) confirmed this **VALID**:
``blur_image_bytes()`` (``kk/media_processing.py``) wrapped the entire blur
attempt in a bare ``except Exception: out_bytes = raw_bytes`` and, separately,
skipped the attempt entirely (also returning the original bytes) whenever
``RoboflowPlateDetector.is_configured()`` was False (e.g. ``ROBOFLOW_API_KEY``
unset) -- in both cases the caller received the ORIGINAL, unblurred bytes
with no error, no rejection, and no way to distinguish this from a genuine
"no plates detected" result.

This file tests the implemented fix: a new, explicit, opt-in
``PLATE_BLUR_REQUIRE_SUCCESS`` flag (default off -- preserves the exact
pre-M-08 fail-open behavior byte-for-byte) that, when enabled, makes the
blur pipeline return a definitive ``PlateBlurStatus`` for every attempt and
raise ``PlateBlurRequiredRejected`` (rather than silently returning the
original bytes) for every status except ``BLURRED_SUCCESS`` and
``NO_PLATES``:

    BLURRED_SUCCESS    -- plate(s) detected and blurred            -> persist blurred bytes
    NO_PLATES          -- detection ran; genuinely no plates found -> persist ORIGINAL bytes (this is success, not failure)
    SKIPPED            -- skip_blur honored (fail-open mode only)  -> persist ORIGINAL bytes
    NOT_CONFIGURED     -- PLATE_BLUR_ENABLED=0 / no ROBOFLOW_API_KEY -> REJECT (fail-closed mode only)
    DETECTION_FAILED   -- Roboflow network/API/timeout/bad response -> REJECT (fail-closed mode only)
    PROCESSING_FAILED  -- decode failure, or detected boxes unusable -> REJECT (fail-closed mode only)
    ENCODING_FAILED     -- re-encoding the blurred image failed      -> REJECT (fail-closed mode only)
    OTHER_FAILURE       -- any unexpected/ambiguous outcome          -> REJECT (fail-closed mode only)

Also covered:
  - M-08's explicit security requirement that an ordinary client-controlled
    ``skip_blur=1`` request parameter must NOT be able to bypass
    ``PLATE_BLUR_REQUIRE_SUCCESS=1`` (it still bypasses the attempt
    entirely in the default fail-open mode, unchanged).
  - The async Celery path (``kk/tasks/image_tasks.py::_process_image_path()``)
    obeys the identical policy, since both call the same
    ``blur_image_bytes()`` choke point and read the same plain environment
    variable.
  - M-06 (decompression-bomb) protection composes correctly with the new
    M-08 gate: it is untouched, still fires, and is never suppressed or
    bypassed by the new logic in either direction.
"""

from __future__ import annotations

import glob
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

from kk import media_processing  # noqa: E402
from kk.media_processing import PlateBlurStatus, PlateBlurRequiredRejected  # noqa: E402


def _tiny_jpeg_bytes(color=(200, 40, 40), size=(20, 20)) -> bytes:
    im = PILImage.new("RGB", size, color=color)
    buf = BytesIO()
    im.save(buf, format="JPEG", quality=80)
    return buf.getvalue()


class _FakeFileStorage:
    """Minimal stand-in for werkzeug's FileStorage: .filename + .save(path)."""

    def __init__(self, data: bytes, filename: str):
        self._data = data
        self.filename = filename

    def save(self, path: str) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as fh:
            fh.write(self._data)


def _fake_detector(*, configured: bool = True, boxes=None, meta=None):
    """A MagicMock standing in for RoboflowPlateDetector."""
    d = MagicMock()
    d.is_configured.return_value = configured
    d.detect_with_meta.return_value = (boxes or [], meta or {"detect_status": "ok"})
    return d


# ===========================================================================
# PART 1: `plate_blur_require_success_enabled()` -- the config flag itself
# ===========================================================================


class TestConfigFlag:
    def test_default_unset_is_fail_open(self, monkeypatch):
        monkeypatch.delenv("PLATE_BLUR_REQUIRE_SUCCESS", raising=False)
        assert media_processing.plate_blur_require_success_enabled() is False

    def test_explicit_zero_is_fail_open(self, monkeypatch):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "0")
        assert media_processing.plate_blur_require_success_enabled() is False

    @pytest.mark.parametrize("val", ["1", "true", "TRUE", "yes", "on"])
    def test_truthy_values_enable_fail_closed(self, monkeypatch, val):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", val)
        assert media_processing.plate_blur_require_success_enabled() is True

    def test_not_gated_by_app_env(self, monkeypatch):
        """M-08: unlike M-01's dev_debug_response_fields_enabled(), this flag
        is a plain env var, deliberately not tied to APP_ENV -- it must work
        the same in "production" as in "development"/"testing"."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        for env in ("production", "development", "testing", ""):
            monkeypatch.setenv("APP_ENV", env)
            assert media_processing.plate_blur_require_success_enabled() is True


# ===========================================================================
# PART 2: `_map_blur_meta_status()` -- state-machine mapping (exhaustive)
# ===========================================================================


class TestStatusMapping:
    @pytest.mark.parametrize(
        "raw_status,expected",
        [
            ("blurred", PlateBlurStatus.BLURRED_SUCCESS),
            ("no_plates", PlateBlurStatus.NO_PLATES),
            ("not_configured", PlateBlurStatus.NOT_CONFIGURED),
            ("detect_failed", PlateBlurStatus.DETECTION_FAILED),
            ("bad_response", PlateBlurStatus.DETECTION_FAILED),
            ("decode_failed", PlateBlurStatus.PROCESSING_FAILED),
            ("no_valid_rois", PlateBlurStatus.PROCESSING_FAILED),
            ("opencv_missing", PlateBlurStatus.OTHER_FAILURE),
            ("encode_failed", PlateBlurStatus.ENCODING_FAILED),
            ("error", PlateBlurStatus.OTHER_FAILURE),
        ],
    )
    def test_known_statuses(self, raw_status, expected):
        assert media_processing._map_blur_meta_status(raw_status) == expected

    @pytest.mark.parametrize("raw_status", [None, "", "totally_unknown_future_status", 42])
    def test_unknown_or_missing_status_fails_closed(self, raw_status):
        """M-08 item 6: any status this process doesn't explicitly recognize
        as confirmed-safe must map to OTHER_FAILURE, never to a success-like
        bucket -- 'fail closed on ambiguity', not 'fail open by default'."""
        assert media_processing._map_blur_meta_status(raw_status) == PlateBlurStatus.OTHER_FAILURE


# ===========================================================================
# PART 3: `_run_plate_blur()` -- unit-level, mocked detector/blur_license_plates
# ===========================================================================


class TestRunPlateBlurUnit:
    def test_skip_requested_without_force_attempt_is_skipped_no_detector_call(self, monkeypatch):
        """Default fail-open semantics: skip_blur=True must not even invoke
        the detector -- exact pre-M-08 behavior."""
        fake_get_detector = MagicMock()
        monkeypatch.setattr(
            "kk.license_plate_blur.get_plate_detector", fake_get_detector
        )
        raw = b"RAWBYTES"
        outcome = media_processing._run_plate_blur(
            raw, ".jpg", skip_requested=True, force_attempt=False
        )
        assert outcome.status == PlateBlurStatus.SKIPPED
        assert outcome.out_bytes == raw
        fake_get_detector.assert_not_called()

    def test_skip_requested_with_force_attempt_still_runs_detection(self, monkeypatch):
        """M-08 security requirement: when fail-closed mode is enforcing,
        skip_blur=True must NOT bypass detection -- the detector is still
        invoked."""
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, meta={"detect_status": "ok"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        outcome = media_processing._run_plate_blur(
            raw, ".jpg", skip_requested=True, force_attempt=True
        )
        detector.detect_with_meta.assert_called_once()
        assert outcome.status == PlateBlurStatus.NO_PLATES

    def test_plate_blur_disabled_globally_is_not_configured(self, monkeypatch):
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "0")
        outcome = media_processing._run_plate_blur(
            b"raw", ".jpg", skip_requested=False, force_attempt=True
        )
        assert outcome.status == PlateBlurStatus.NOT_CONFIGURED
        assert outcome.out_bytes == b"raw"

    def test_missing_api_key_detector_not_configured(self, monkeypatch):
        """A: missing ROBOFLOW_API_KEY -> detector.is_configured() False."""
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=False)
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = b"raw-bytes"
        outcome = media_processing._run_plate_blur(
            raw, ".jpg", skip_requested=False, force_attempt=True
        )
        assert outcome.status == PlateBlurStatus.NOT_CONFIGURED
        assert outcome.out_bytes == raw
        detector.detect_with_meta.assert_not_called()

    def test_roboflow_network_failure_maps_to_detection_failed(self, monkeypatch):
        """B: a genuine network/timeout failure inside detect_with_meta()
        already reports {"status": "detect_failed"} via blur_license_plates
        -- confirm it maps to DETECTION_FAILED and original bytes flow
        through unblurred."""
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(
            configured=True, meta={"detect_status": "detect_failed", "detect_error": "REDACTED"}
        )
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        outcome = media_processing._run_plate_blur(
            raw, ".jpg", skip_requested=False, force_attempt=True
        )
        assert outcome.status == PlateBlurStatus.DETECTION_FAILED
        assert outcome.out_bytes == raw

    def test_roboflow_bad_response_maps_to_detection_failed(self, monkeypatch):
        """C: a malformed/unexpected Roboflow API response."""
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(
            configured=True, meta={"detect_status": "bad_response", "detect_keys": []}
        )
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        outcome = media_processing._run_plate_blur(
            raw, ".jpg", skip_requested=False, force_attempt=True
        )
        assert outcome.status == PlateBlurStatus.DETECTION_FAILED
        assert outcome.out_bytes == raw

    def test_successful_detection_and_blur_is_blurred_success(self, monkeypatch):
        """D: real cv2 blur path with a mocked detector returning one box."""
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(
            configured=True,
            boxes=[
                __import__("kk.license_plate_blur", fromlist=["PlateBox"]).PlateBox(
                    x1=2, y1=2, x2=15, y2=10, confidence=0.9
                )
            ],
            meta={"detect_status": "ok"},
        )
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        outcome = media_processing._run_plate_blur(
            raw, ".jpg", skip_requested=False, force_attempt=True
        )
        assert outcome.status == PlateBlurStatus.BLURRED_SUCCESS
        assert isinstance(outcome.out_bytes, bytes)
        assert outcome.out_bytes != raw, "a real blur should change the encoded bytes"

    def test_no_plates_detected_is_a_confirmed_success_not_a_failure(self, monkeypatch):
        """E: detection ran cleanly and found zero plates -- NO_PLATES, and
        the original bytes are returned unchanged (nothing to blur)."""
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, boxes=[], meta={"detect_status": "ok"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        outcome = media_processing._run_plate_blur(
            raw, ".jpg", skip_requested=False, force_attempt=True
        )
        assert outcome.status == PlateBlurStatus.NO_PLATES
        assert outcome.out_bytes == raw

    def test_no_valid_rois_is_processing_failed_not_no_plates(self, monkeypatch):
        """A box WAS detected but every ROI was too small to blur -- this
        must NOT be conflated with the genuine 'no plates' case."""
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        tiny_box = __import__(
            "kk.license_plate_blur", fromlist=["PlateBox"]
        ).PlateBox(x1=0, y1=0, x2=1, y2=1, confidence=0.5)
        detector = _fake_detector(configured=True, boxes=[tiny_box], meta={"detect_status": "ok"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        outcome = media_processing._run_plate_blur(
            raw, ".jpg", skip_requested=False, force_attempt=True
        )
        assert outcome.status == PlateBlurStatus.PROCESSING_FAILED

    def test_unexpected_exception_is_other_failure(self, monkeypatch):
        """Item 6: anything unexpected must fail closed (OTHER_FAILURE), not
        be silently treated as safe."""
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")

        def _boom():
            raise RuntimeError("simulated unexpected failure")

        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", _boom)

        raw = b"raw"
        outcome = media_processing._run_plate_blur(
            raw, ".jpg", skip_requested=False, force_attempt=True
        )
        assert outcome.status == PlateBlurStatus.OTHER_FAILURE
        assert outcome.out_bytes == raw


# ===========================================================================
# PART 4: `blur_image_bytes()` -- the public choke point (gating on/off)
# ===========================================================================


class TestBlurImageBytesGating:
    def test_fail_open_default_never_raises_on_not_configured(self, monkeypatch):
        """Negative-control: with PLATE_BLUR_REQUIRE_SUCCESS unset (default),
        an unconfigured detector must behave EXACTLY like the pre-M-08 code
        -- return original bytes, never raise."""
        monkeypatch.delenv("PLATE_BLUR_REQUIRE_SUCCESS", raising=False)
        monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")

        raw = _tiny_jpeg_bytes()
        out = media_processing.blur_image_bytes(raw, ".jpg", skip_blur=False)
        assert out == raw

    def test_fail_open_explicit_zero_never_raises_on_detection_failure(self, monkeypatch):
        """F: fail-open compatibility mode, explicitly configured (not just
        left at the default) -- a forced Roboflow failure must still return
        the original bytes with no exception."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "0")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, meta={"detect_status": "detect_failed"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        out = media_processing.blur_image_bytes(raw, ".jpg", skip_blur=False)
        assert out == raw

    def test_fail_closed_missing_api_key_raises(self, monkeypatch):
        """A: fail-closed + missing ROBOFLOW_API_KEY -> rejected."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=False)
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        with pytest.raises(PlateBlurRequiredRejected) as exc_info:
            media_processing.blur_image_bytes(_tiny_jpeg_bytes(), ".jpg", skip_blur=False)
        assert exc_info.value.status == PlateBlurStatus.NOT_CONFIGURED

    def test_fail_closed_network_failure_raises(self, monkeypatch):
        """B: fail-closed + simulated Roboflow network failure -> rejected."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, meta={"detect_status": "detect_failed"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        with pytest.raises(PlateBlurRequiredRejected) as exc_info:
            media_processing.blur_image_bytes(_tiny_jpeg_bytes(), ".jpg", skip_blur=False)
        assert exc_info.value.status == PlateBlurStatus.DETECTION_FAILED

    def test_fail_closed_api_bad_response_raises(self, monkeypatch):
        """C: fail-closed + malformed Roboflow API response -> rejected."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, meta={"detect_status": "bad_response"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        with pytest.raises(PlateBlurRequiredRejected) as exc_info:
            media_processing.blur_image_bytes(_tiny_jpeg_bytes(), ".jpg", skip_blur=False)
        assert exc_info.value.status == PlateBlurStatus.DETECTION_FAILED

    def test_fail_closed_successful_blur_returns_blurred_bytes(self, monkeypatch):
        """D: fail-closed + successful detection/blur -> blurred bytes
        returned normally, no exception."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        PlateBox = __import__("kk.license_plate_blur", fromlist=["PlateBox"]).PlateBox
        detector = _fake_detector(
            configured=True,
            boxes=[PlateBox(x1=2, y1=2, x2=15, y2=10, confidence=0.9)],
            meta={"detect_status": "ok"},
        )
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        out = media_processing.blur_image_bytes(raw, ".jpg", skip_blur=False)
        assert out != raw

    def test_fail_closed_no_plates_returns_original_bytes_unchanged(self, monkeypatch):
        """E: fail-closed + valid image with no plates -> accepted, bytes
        unchanged, no exception."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, boxes=[], meta={"detect_status": "ok"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        out = media_processing.blur_image_bytes(raw, ".jpg", skip_blur=False)
        assert out == raw


# ===========================================================================
# PART 5: skip_blur security semantics (item J)
# ===========================================================================


class TestSkipBlurSemantics:
    def test_fail_open_mode_skip_blur_bypasses_entirely_unchanged(self, monkeypatch):
        """Pre-M-08 product behavior preserved exactly: in the default
        fail-open mode, skip_blur=True still means 'don't even attempt
        detection'."""
        monkeypatch.delenv("PLATE_BLUR_REQUIRE_SUCCESS", raising=False)
        fake_get_detector = MagicMock()
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", fake_get_detector)

        raw = _tiny_jpeg_bytes()
        out = media_processing.blur_image_bytes(raw, ".jpg", skip_blur=True)
        assert out == raw
        fake_get_detector.assert_not_called()

    def test_fail_closed_mode_skip_blur_does_not_bypass_requirement(self, monkeypatch):
        """M-08 security requirement: once PLATE_BLUR_REQUIRE_SUCCESS=1 is
        set, an ordinary client-controlled skip_blur=1 must NOT be able to
        make an unconfirmed image pass through -- detection is still forced
        to run, and failure still rejects the upload."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=False)
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        with pytest.raises(PlateBlurRequiredRejected):
            media_processing.blur_image_bytes(_tiny_jpeg_bytes(), ".jpg", skip_blur=True)

    def test_fail_closed_mode_skip_blur_still_persists_on_confirmed_success(self, monkeypatch):
        """Complement of the above: if fail-closed mode forces a detection
        attempt despite skip_blur=1, and that attempt genuinely finds no
        plates, the image is still accepted (this is not a punitive mode --
        it only rejects unconfirmed outcomes)."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, boxes=[], meta={"detect_status": "ok"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        raw = _tiny_jpeg_bytes()
        out = media_processing.blur_image_bytes(raw, ".jpg", skip_blur=True)
        assert out == raw
        detector.detect_with_meta.assert_called_once()


# ===========================================================================
# PART 6: `process_and_store_image()` integration (persistence layer)
# ===========================================================================


@pytest.fixture
def upload_env(monkeypatch, tmp_path):
    monkeypatch.setenv("APP_ENV", "testing")
    monkeypatch.delenv("ROBOFLOW_API_KEY", raising=False)
    upload_folder = str(tmp_path)
    monkeypatch.setattr(
        media_processing,
        "current_app",
        MagicMock(config={"UPLOAD_FOLDER": upload_folder}),
    )
    return upload_folder


def _stored_files(upload_folder: str) -> list[str]:
    return glob.glob(os.path.join(upload_folder, "car_photos", "*"))


class TestProcessAndStoreImageFailClosed:
    def test_fail_closed_rejection_persists_nothing(self, upload_env, monkeypatch):
        """A/B/C via the real persistence entrypoint: a rejected blur must
        never reach persist_jpeg_bytes()."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=False)
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        fs = _FakeFileStorage(_tiny_jpeg_bytes(), "photo.jpg")
        with pytest.raises(media_processing.PlateBlurRequiredRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=False)

        assert _stored_files(upload_env) == []

    def test_fail_closed_success_is_persisted(self, upload_env, monkeypatch):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, boxes=[], meta={"detect_status": "ok"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        fs = _FakeFileStorage(_tiny_jpeg_bytes(), "photo.jpg")
        rel_path, _b64 = media_processing.process_and_store_image(fs, False, skip_blur=False)
        assert rel_path
        assert len(_stored_files(upload_env)) == 1

    def test_fail_closed_temp_file_cleaned_up_on_rejection(self, upload_env, monkeypatch):
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=False)
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        fs = _FakeFileStorage(_tiny_jpeg_bytes(), "photo.jpg")
        with pytest.raises(media_processing.PlateBlurRequiredRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=False)

        temp_matches = glob.glob(os.path.join(upload_env, "temp", "*"))
        assert temp_matches == [], "temp file must be removed even when the image is rejected"


# ===========================================================================
# PART 7: M-06 decompression-bomb interaction (item H)
# ===========================================================================


class TestM06Interaction:
    def test_m08_rejection_happens_before_m06_downscale_bomb_check(self, upload_env, monkeypatch):
        """When M-08 rejects at the blur stage (e.g. NOT_CONFIGURED), the
        M-06 downscale/bomb-check block downstream must never even run --
        proving there is no interference/ordering hazard between the two
        independent protections."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)  # would trip M-06 if reached
        detector = _fake_detector(configured=False)
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        fs = _FakeFileStorage(_tiny_jpeg_bytes(), "photo.jpg")
        with pytest.raises(media_processing.PlateBlurRequiredRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=False)
        assert _stored_files(upload_env) == []

    def test_m06_bomb_check_still_fires_after_m08_confirms_no_plates(self, upload_env, monkeypatch):
        """When M-08 allows the file through (NO_PLATES, a confirmed-safe
        outcome), the pre-existing M-06 decompression-bomb guard downstream
        (process_and_store_image()'s own final downscale/re-encode step,
        unrelated to license_plate_blur.py's internal inference call) must
        still fire exactly as before -- M-08 must not accidentally suppress
        it. `blur_license_plates()` itself is mocked directly here (not
        just the detector) so this isolates the *downstream* M-06 check
        from license_plate_blur.py's own internal, separately-tested bomb
        handling during inference (see TestM06Interaction's other two
        tests, and kk/tests/test_m06_image_cap_and_pixel_bomb.py, for that
        internal behavior)."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True)
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)
        raw = _tiny_jpeg_bytes()
        monkeypatch.setattr(
            "kk.license_plate_blur.blur_license_plates",
            lambda **kwargs: (raw, {"status": "no_plates", "plates": 0}),
        )
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)

        fs = _FakeFileStorage(raw, "photo.jpg")
        with pytest.raises(media_processing.DecompressionBombRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=False)
        assert _stored_files(upload_env) == []

    def test_m08_other_failure_from_bomb_during_inference_still_rejects_and_persists_nothing(
        self, upload_env, monkeypatch
    ):
        """Composition edge case discovered while testing the above: if the
        decompression bomb is instead encountered *inside*
        license_plate_blur.py's own inference-normalization step (rather
        than downstream), blur_license_plates()'s pre-existing (M-06)
        catch-all swallows it into a generic {"status": "error"} result
        with the original bomb bytes -- by design, relying on
        process_and_store_image()'s own downstream check as the real last
        line of defense (see kk/license_plate_blur.py's
        `_normalize_image_bytes_for_inference()` docstring). Under M-08
        fail-closed mode, that "error" status maps to OTHER_FAILURE and is
        rejected immediately via PlateBlurRequiredRejected -- BEFORE ever
        reaching the downstream M-06 check. This is still safe (the bomb
        bytes are never persisted either way), just via a different
        exception type than the downstream-only case above; both must
        result in zero files persisted."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, boxes=[], meta={"detect_status": "ok"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)

        fs = _FakeFileStorage(_tiny_jpeg_bytes(), "photo.jpg")
        with pytest.raises(media_processing.PlateBlurRequiredRejected) as exc_info:
            media_processing.process_and_store_image(fs, False, skip_blur=False)
        assert exc_info.value.status == PlateBlurStatus.OTHER_FAILURE
        assert _stored_files(upload_env) == [], (
            "bomb-flagged bytes must never be persisted, regardless of which "
            "layer (M-08's gate or M-06's downstream check) catches it first"
        )

    def test_m06_bomb_handling_unaffected_when_m08_disabled(self, upload_env, monkeypatch):
        """Sanity regression: with PLATE_BLUR_REQUIRE_SUCCESS unset (the
        default), M-06 behavior is completely unchanged from before M-08."""
        monkeypatch.delenv("PLATE_BLUR_REQUIRE_SUCCESS", raising=False)
        monkeypatch.setattr(PILImage, "MAX_IMAGE_PIXELS", 100)

        fs = _FakeFileStorage(_tiny_jpeg_bytes(), "photo.jpg")
        with pytest.raises(media_processing.DecompressionBombRejected):
            media_processing.process_and_store_image(fs, False, skip_blur=True)
        assert _stored_files(upload_env) == []


# ===========================================================================
# PART 8: async Celery image-processing path (item G)
# ===========================================================================


class TestAsyncImageTaskFailClosed:
    def test_process_image_path_rejects_under_fail_closed_and_never_persists(
        self, upload_env, monkeypatch, tmp_path
    ):
        """G: `_process_image_path()` (kk/tasks/image_tasks.py) -- the
        Celery-worker duplicate of process_and_store_image()'s pipeline --
        must obey the identical PLATE_BLUR_REQUIRE_SUCCESS policy, since it
        calls the same blur_image_bytes() choke point and reads the same
        plain environment variable from its own process."""
        from kk.tasks import image_tasks

        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=False)
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        temp_abs = str(tmp_path / "incoming.jpg")
        with open(temp_abs, "wb") as fh:
            fh.write(_tiny_jpeg_bytes())

        mock_persist = MagicMock()
        monkeypatch.setattr(media_processing, "persist_jpeg_bytes", mock_persist)

        with pytest.raises(media_processing.PlateBlurRequiredRejected):
            image_tasks._process_image_path(
                temp_abs=temp_abs,
                original_filename="photo.jpg",
                inline_base64=False,
                skip_blur=False,
            )

        mock_persist.assert_not_called()
        assert _stored_files(upload_env) == []

    def test_process_image_path_skip_blur_does_not_bypass_fail_closed(
        self, upload_env, monkeypatch, tmp_path
    ):
        """Same skip_blur security requirement (item J), exercised through
        the async task's own entrypoint."""
        from kk.tasks import image_tasks

        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=False)
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        temp_abs = str(tmp_path / "incoming2.jpg")
        with open(temp_abs, "wb") as fh:
            fh.write(_tiny_jpeg_bytes())

        mock_persist = MagicMock()
        monkeypatch.setattr(media_processing, "persist_jpeg_bytes", mock_persist)

        with pytest.raises(media_processing.PlateBlurRequiredRejected):
            image_tasks._process_image_path(
                temp_abs=temp_abs,
                original_filename="photo.jpg",
                inline_base64=False,
                skip_blur=True,  # client asked to skip -- must NOT succeed
            )
        mock_persist.assert_not_called()

    def test_process_image_path_succeeds_under_fail_closed_when_confirmed_safe(
        self, upload_env, monkeypatch, tmp_path
    ):
        from kk.tasks import image_tasks

        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        monkeypatch.setenv("PLATE_BLUR_ENABLED", "1")
        detector = _fake_detector(configured=True, boxes=[], meta={"detect_status": "ok"})
        monkeypatch.setattr("kk.license_plate_blur.get_plate_detector", lambda: detector)

        temp_abs = str(tmp_path / "incoming3.jpg")
        with open(temp_abs, "wb") as fh:
            fh.write(_tiny_jpeg_bytes())

        result = image_tasks._process_image_path(
            temp_abs=temp_abs,
            original_filename="photo.jpg",
            inline_base64=False,
            skip_blur=False,
        )
        assert result["rel_path"]
        assert len(_stored_files(upload_env)) == 1


# ===========================================================================
# PART 9: no client-facing leak of internal status/detail
# ===========================================================================


class TestNoInternalDetailLeak:
    def test_rejection_exception_message_has_no_secrets(self):
        err = PlateBlurRequiredRejected(PlateBlurStatus.DETECTION_FAILED, "detect_failed")
        text = str(err)
        assert "ROBOFLOW_API_KEY" not in text
        assert "api_key" not in text.lower()

    def test_rejection_carries_status_for_server_side_logging_only(self):
        err = PlateBlurRequiredRejected(PlateBlurStatus.NOT_CONFIGURED, "no key")
        assert err.status == PlateBlurStatus.NOT_CONFIGURED
        assert err.detail == "no key"


# ===========================================================================
# PART 10: HTTP-level end-to-end (real Flask app + SQLite)
# ===========================================================================

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_m08_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "m08.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ.pop("ROBOFLOW_API_KEY", None)
    os.environ.pop("PLATE_BLUR_REQUIRE_SUCCESS", None)
    os.environ["R2_PUBLIC_URL"] = "https://cdn.example.com"
    for key in ("R2_ACCOUNT_ID", "R2_BUCKET_NAME", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    app.config["R2_PUBLIC_URL"] = "https://cdn.example.com"
    for key in ("R2_ACCOUNT_ID", "R2_BUCKET_NAME", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        app.config.pop(key, None)
    from kk.models import Car, CarImage, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db, User, Car, CarImage

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()
    os.environ.pop("PLATE_BLUR_REQUIRE_SUCCESS", None)


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx) -> tuple[str, int, str]:
    app, _client, db, User, *_ = app_ctx
    username = f"m08_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_unique_phone(),
            first_name="M08",
            last_name="Test",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.public_id, user.id, username


def _login(client, username: str) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _make_car(app_ctx, seller_id: int) -> tuple[int, str]:
    app, _client, db, _User, Car, _CarImage = app_ctx
    with app.app_context():
        car = Car(
            seller_id=seller_id,
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
        return car.id, car.public_id


def _image_count(app_ctx, car_id: int) -> int:
    app, _client, db, _User, _Car, CarImage = app_ctx
    with app.app_context():
        return CarImage.query.filter_by(car_id=car_id).count()


def _setup_seller(app_ctx, client):
    public_id, seller_id, username = _make_user(app_ctx)
    token = _login(client, username)
    car_id, car_public_id = _make_car(app_ctx, seller_id)
    return {
        "public_id": public_id,
        "seller_id": seller_id,
        "token": token,
        "car_id": car_id,
        "car_public_id": car_public_id,
    }


class TestHttpFailClosedUploadRoute:
    def test_upload_rejected_when_fail_closed_and_no_api_key(self, app_ctx, client, monkeypatch):
        """End-to-end: PLATE_BLUR_REQUIRE_SUCCESS=1, ROBOFLOW_API_KEY unset
        -> POST /api/cars/<id>/images must reject the file (no listing
        photo persisted), instead of the pre-M-08 behavior of silently
        storing it unblurred."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        ctx = _setup_seller(app_ctx, client)

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data={"files": [(BytesIO(_tiny_jpeg_bytes()), "photo.jpg")]},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        body_text = resp.get_data(as_text=True).lower()
        assert "roboflow" not in body_text
        assert "api_key" not in body_text
        assert _image_count(app_ctx, ctx["car_id"]) == 0

    def test_upload_rejected_even_with_client_skip_blur_when_fail_closed(
        self, app_ctx, client, monkeypatch
    ):
        """J (route-level): the ordinary client-controlled ?skip_blur=1
        parameter must not bypass PLATE_BLUR_REQUIRE_SUCCESS=1."""
        monkeypatch.setenv("PLATE_BLUR_REQUIRE_SUCCESS", "1")
        ctx = _setup_seller(app_ctx, client)

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images?skip_blur=1",
            data={"files": [(BytesIO(_tiny_jpeg_bytes()), "photo.jpg")]},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 0

    def test_upload_succeeds_when_fail_open_default(self, app_ctx, client, monkeypatch):
        """Regression: default (no PLATE_BLUR_REQUIRE_SUCCESS set) must
        keep uploads working exactly as before M-08, even with no Roboflow
        key configured."""
        monkeypatch.delenv("PLATE_BLUR_REQUIRE_SUCCESS", raising=False)
        ctx = _setup_seller(app_ctx, client)

        resp = client.post(
            f"/api/cars/{ctx['car_public_id']}/images",
            data={"files": [(BytesIO(_tiny_jpeg_bytes()), "photo.jpg")]},
            headers=_auth(ctx["token"]),
            content_type="multipart/form-data",
        )
        assert resp.status_code == 201, resp.get_json()
        assert _image_count(app_ctx, ctx["car_id"]) == 1
