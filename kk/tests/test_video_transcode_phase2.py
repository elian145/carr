"""Phase 2 of the server-side video transcode fallback: SERVER-SIDE VIDEO
TRANSCODING + PROCESSED-VIDEO STAGING.

Covers:
  - ``kk/tasks/video_tasks.py``'s ``_transcode_video_source_impl`` (the
    plain-function core of the ``kk.transcode_car_video_source`` Celery
    task -- mirrors ``kk/tasks/image_tasks.py``'s
    ``_process_image_path``/``process_car_image_file`` split so it can be
    unit-tested without Celery's bound-task request/backend machinery).
  - ``kk/media_processing.py::processed_video_staging_key`` (owner
    isolation / idempotency).
  - ``finalize_video_source_upload()``'s Phase 2 enqueue-on-finalize
    idempotency, job ownership registration, and job-state reporting.
  - The new PROCESSED-video-staging Beat cleanup sweep, and that neither
    cleanup sweep can ever target the permanent ``car_videos/`` namespace.

Every ffmpeg subprocess call and every R2 call is mocked -- no real
ffmpeg/ffprobe binary and no real R2 credentials are required to run this
file.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import kk.r2_ops as r2_ops_module  # noqa: E402
import kk.video_transcoding as vt  # noqa: E402

_PASSWORD = "Aa123456!"
_R2_KEYS = (
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
)
_FINALIZE_URL = "/api/media/r2/finalize-video-source-upload"


# ---------------------------------------------------------------------------
# Fixtures (mirrors test_video_source_staging_phase1.py's conventions)
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_vidtranscode_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "vidtranscode.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    for key in _R2_KEYS + ("R2_PUBLIC_URL",):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[2]


@pytest.fixture
def r2_configured(app_ctx, monkeypatch):
    app = app_ctx[0]
    for key in _R2_KEYS:
        monkeypatch.setitem(app.config, key, f"test-{key.lower()}")
    return app


@pytest.fixture(autouse=True)
def _enable_video_source_staging(monkeypatch):
    monkeypatch.setenv("VIDEO_SOURCE_STAGING_ENABLED", "1")


@pytest.fixture(autouse=True)
def _clear_job_registries():
    from kk.job_ownership import clear_idempotent_jobs_for_tests, clear_job_owners_for_tests

    clear_job_owners_for_tests()
    clear_idempotent_jobs_for_tests()
    yield
    clear_job_owners_for_tests()
    clear_idempotent_jobs_for_tests()


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str, phone: str) -> str:
    app, _socketio, _client, db, User = app_ctx
    with app.app_context():
        existing = User.query.filter_by(username=username).first()
        if existing:
            return existing.public_id
        user = User(
            username=username,
            phone_number=phone,
            first_name=username.title(),
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.public_id


def _login(client, username: str) -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def seller_ctx(app_ctx):
    username = f"vidtc_seller_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


@pytest.fixture(scope="module")
def other_seller_ctx(app_ctx):
    username = f"vidtc_other_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


def _mock_head_object(monkeypatch, *, exists, size=0, content_type="video/mp4"):
    def _fake_head_object(*, key, timeout=30):
        if not exists:
            return {"exists": False, "size": None, "content_type": None}
        return {"exists": True, "size": size, "content_type": content_type}

    monkeypatch.setattr(r2_ops_module, "r2_head_object", _fake_head_object)


# ---------------------------------------------------------------------------
# processed_video_staging_key() -- owner isolation / idempotency
# ---------------------------------------------------------------------------


class TestProcessedVideoStagingKeyUnit:
    def test_deterministic_for_same_inputs(self, app_ctx):
        from kk.media_processing import processed_video_staging_key

        with app_ctx[0].app_context():
            k1 = processed_video_staging_key("pub-owner-1", "draft-1")
            k2 = processed_video_staging_key("pub-owner-1", "draft-1")
        assert k1 == k2 and k1 is not None

    def test_differs_by_owner(self, app_ctx):
        from kk.media_processing import processed_video_staging_key

        with app_ctx[0].app_context():
            k1 = processed_video_staging_key("pub-owner-1", "draft-1")
            k2 = processed_video_staging_key("pub-owner-2", "draft-1")
        assert k1 != k2

    def test_differs_by_draft_media_id(self, app_ctx):
        from kk.media_processing import processed_video_staging_key

        with app_ctx[0].app_context():
            k1 = processed_video_staging_key("pub-owner-1", "draft-1")
            k2 = processed_video_staging_key("pub-owner-1", "draft-2")
        assert k1 != k2

    def test_returns_none_for_invalid_draft_media_id(self, app_ctx):
        from kk.media_processing import processed_video_staging_key

        with app_ctx[0].app_context():
            assert processed_video_staging_key("pub-owner-1", "../x") is None

    def test_key_shape_and_extension(self, app_ctx):
        from kk.media_processing import (
            PROCESSED_VIDEO_STAGING_KEY_PREFIX,
            processed_video_staging_key,
        )

        with app_ctx[0].app_context():
            key = processed_video_staging_key("pub-owner-1", "safe-id_123")
        assert key.startswith(PROCESSED_VIDEO_STAGING_KEY_PREFIX)
        assert key.endswith(".mp4")

    def test_never_collides_with_source_staging_prefix(self, app_ctx):
        from kk.media_processing import (
            PROCESSED_VIDEO_STAGING_KEY_PREFIX,
            VIDEO_SOURCE_STAGING_KEY_PREFIX,
        )

        assert PROCESSED_VIDEO_STAGING_KEY_PREFIX != VIDEO_SOURCE_STAGING_KEY_PREFIX
        assert not PROCESSED_VIDEO_STAGING_KEY_PREFIX.startswith(
            VIDEO_SOURCE_STAGING_KEY_PREFIX
        )
        assert not VIDEO_SOURCE_STAGING_KEY_PREFIX.startswith(
            PROCESSED_VIDEO_STAGING_KEY_PREFIX
        )


# ---------------------------------------------------------------------------
# _transcode_video_source_impl() -- the Celery task's core pipeline
# ---------------------------------------------------------------------------


def _patch_common(
    monkeypatch,
    *,
    source_bytes=b"\x00" * 2048,
    source_validation=None,
    caps=None,
    output_validation=None,
    output_bytes_size=1024,
):
    """Patch every external dependency of ``_transcode_video_source_impl``
    (R2 + ffmpeg) so it runs entirely against fakes."""
    from kk.tasks import video_tasks

    def fake_get_file(*, key, dest_path, timeout=120):
        with open(dest_path, "wb") as fh:
            fh.write(source_bytes)

    put_calls: list[dict] = []

    def fake_put_file(*, key, file_path, content_type, timeout=120):
        with open(file_path, "rb") as fh:
            body = fh.read()
        put_calls.append({"key": key, "content_type": content_type, "size": len(body)})

    delete_calls: list[str] = []

    def fake_delete_object(*, key, timeout=30):
        delete_calls.append(key)

    monkeypatch.setattr(r2_ops_module, "r2_get_file", fake_get_file)
    monkeypatch.setattr(r2_ops_module, "r2_put_file", fake_put_file)
    monkeypatch.setattr(r2_ops_module, "r2_delete_object", fake_delete_object)

    if source_validation is not None:
        monkeypatch.setattr(vt, "validate_source_media", lambda path: source_validation)
    if caps is not None:
        monkeypatch.setattr(vt, "probe_ffmpeg_capabilities", lambda: caps)

    def fake_run_ffmpeg(argv, timeout=180):
        out_path = argv[-1]
        with open(out_path, "wb") as fh:
            fh.write(b"\x00" * output_bytes_size)

    monkeypatch.setattr(vt, "run_ffmpeg", fake_run_ffmpeg)

    if output_validation is not None:
        monkeypatch.setattr(vt, "validate_output_media", lambda path, **kw: output_validation)

    return {"put_calls": put_calls, "delete_calls": delete_calls}


def _full_caps(*, hdr_ok=True):
    return vt.FfmpegCapabilities(
        ffmpeg_path="ffmpeg",
        ffprobe_path="ffprobe",
        ffmpeg_version="ffmpeg version 8.0.1",
        ffprobe_version="ffprobe version 8.0.1",
        has_libx264=True,
        has_aac_encoder=True,
        has_zscale_filter=hdr_ok,
        has_tonemap_filter=hdr_ok,
    )


def _sdr_source_validation(*, has_audio=True):
    video = vt.ProbedStream(
        codec_type="video",
        codec_name="h264",
        width=1080,
        height=1920,
        r_frame_rate=30.0,
        duration_seconds=5.0,
        color_transfer="bt709",
        color_primaries="bt709",
        color_space="bt709",
    )
    streams = [video]
    if has_audio:
        streams.append(
            vt.ProbedStream(
                codec_type="audio",
                codec_name="aac",
                width=None,
                height=None,
                r_frame_rate=None,
                duration_seconds=5.0,
                color_transfer=None,
                color_primaries=None,
                color_space=None,
            )
        )
    probe = vt.ProbedMedia(format_name="mov,mp4", duration_seconds=5.0, size_bytes=2048, streams=streams)
    return vt.SourceValidation(
        probe=probe,
        primary_video=video,
        is_hdr=False,
        rotation_degrees=0,
        display_width=1080,
        display_height=1920,
        has_audio=has_audio,
    )


def _hdr_source_validation():
    sdr = _sdr_source_validation(has_audio=False)
    video = vt.ProbedStream(
        codec_type="video",
        codec_name="hevc",
        width=1080,
        height=1920,
        r_frame_rate=30.0,
        duration_seconds=5.0,
        color_transfer="smpte2084",
        color_primaries="bt2020",
        color_space="bt2020nc",
    )
    probe = vt.ProbedMedia(
        format_name="mov,mp4", duration_seconds=5.0, size_bytes=2048, streams=[video]
    )
    return vt.SourceValidation(
        probe=probe,
        primary_video=video,
        is_hdr=True,
        rotation_degrees=0,
        display_width=1080,
        display_height=1920,
        has_audio=False,
    )


def _passing_output_validation(*, has_audio=True, size_bytes=1024):
    video = vt.ProbedStream(
        codec_type="video",
        codec_name="h264",
        width=1080,
        height=1920,
        r_frame_rate=30.0,
        duration_seconds=5.0,
        color_transfer="bt709",
        color_primaries="bt709",
        color_space="bt709",
    )
    audio = None
    if has_audio:
        audio = vt.ProbedStream(
            codec_type="audio",
            codec_name="aac",
            width=None,
            height=None,
            r_frame_rate=None,
            duration_seconds=5.0,
            color_transfer=None,
            color_primaries=None,
            color_space=None,
        )
    probe = vt.ProbedMedia(format_name="mp4", duration_seconds=5.0, size_bytes=size_bytes, streams=[])
    return vt.OutputValidation(probe=probe, video=video, audio=audio, size_bytes=size_bytes)


class TestTranscodeVideoSourceImpl:
    def _run(self, *, app, owner, draft, source_key=None, **patch_kwargs):
        from kk.tasks.video_tasks import _transcode_video_source_impl
        from kk.media_processing import video_source_staging_key

        with app.app_context():
            key = source_key or video_source_staging_key(owner, draft)
            return _transcode_video_source_impl(
                source_staging_key=key, owner_public_id=owner, draft_media_id=draft
            )

    def test_rejects_foreign_source_key(self, app_ctx, r2_configured, monkeypatch):
        from kk.tasks.video_tasks import (
            VideoTranscodeTaskError,
            _transcode_video_source_impl,
        )

        _patch_common(monkeypatch)
        with app_ctx[0].app_context():
            with pytest.raises(VideoTranscodeTaskError, match="does not match"):
                _transcode_video_source_impl(
                    source_staging_key="car_videos/_staging/someone-elses-tag/x.src",
                    owner_public_id="pub-owner-1",
                    draft_media_id="draft-1",
                )

    def test_rejects_invalid_draft_media_id(self, app_ctx, r2_configured, monkeypatch):
        from kk.tasks.video_tasks import (
            VideoTranscodeTaskError,
            _transcode_video_source_impl,
        )

        _patch_common(monkeypatch)
        with app_ctx[0].app_context():
            with pytest.raises(VideoTranscodeTaskError):
                _transcode_video_source_impl(
                    source_staging_key="whatever",
                    owner_public_id="pub-owner-1",
                    draft_media_id="../etc",
                )

    def test_successful_sdr_transcode_uploads_and_deletes_source(
        self, app_ctx, r2_configured, monkeypatch
    ):
        calls = _patch_common(
            monkeypatch,
            source_validation=_sdr_source_validation(has_audio=True),
            caps=_full_caps(),
            output_validation=_passing_output_validation(has_audio=True),
        )
        result = self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-sdr")
        assert result["status"] == "succeeded"
        assert result["video_codec"] == "h264"
        assert result["audio_codec"] == "aac"
        assert len(calls["put_calls"]) == 1
        assert calls["put_calls"][0]["key"] == result["processed_staging_key"]
        assert len(calls["delete_calls"]) == 1  # source deleted after success

    def test_successful_transcode_with_no_audio_source(self, app_ctx, r2_configured, monkeypatch):
        calls = _patch_common(
            monkeypatch,
            source_validation=_sdr_source_validation(has_audio=False),
            caps=_full_caps(),
            output_validation=_passing_output_validation(has_audio=False),
        )
        result = self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-noaudio")
        assert result["status"] == "succeeded"
        assert result["audio_codec"] is None

    def test_hdr_source_uses_tonemap_capable_worker(self, app_ctx, r2_configured, monkeypatch):
        calls = _patch_common(
            monkeypatch,
            source_validation=_hdr_source_validation(),
            caps=_full_caps(hdr_ok=True),
            output_validation=_passing_output_validation(has_audio=False),
        )
        result = self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-hdr")
        assert result["status"] == "succeeded"

    def test_hdr_source_refuses_when_worker_lacks_tonemap_capability(
        self, app_ctx, r2_configured, monkeypatch
    ):
        from kk.tasks.video_tasks import VideoTranscodeTaskError

        calls = _patch_common(
            monkeypatch,
            source_validation=_hdr_source_validation(),
            caps=_full_caps(hdr_ok=False),
        )
        with pytest.raises(VideoTranscodeTaskError, match="HDR"):
            self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-hdr-nocaps")
        # Capability failure is NOT the source's fault -- must be retained.
        assert calls["delete_calls"] == []

    def test_permanently_invalid_source_is_deleted(self, app_ctx, r2_configured, monkeypatch):
        from kk.tasks.video_tasks import VideoTranscodeTaskError

        def raise_validation_error(path):
            raise vt.VideoValidationError("Source duration 45.00s exceeds the 30.0s cap")

        calls = _patch_common(monkeypatch)
        monkeypatch.setattr(vt, "validate_source_media", raise_validation_error)
        with pytest.raises(VideoTranscodeTaskError):
            self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-toolong")
        from kk.media_processing import video_source_staging_key

        with app_ctx[0].app_context():
            expected_key = video_source_staging_key("pub-owner-1", "draft-toolong")
        assert calls["delete_calls"] == [expected_key]

    def test_transient_output_failure_retains_source_and_uploads_nothing(
        self, app_ctx, r2_configured, monkeypatch
    ):
        from kk.tasks.video_tasks import VideoTranscodeTaskError

        def raise_output_error(path, **kw):
            raise vt.VideoValidationError("Encoded output codec is 'vp9', expected h264")

        calls = _patch_common(
            monkeypatch,
            source_validation=_sdr_source_validation(has_audio=False),
            caps=_full_caps(),
        )
        monkeypatch.setattr(vt, "validate_output_media", raise_output_error)
        with pytest.raises(VideoTranscodeTaskError):
            self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-badoutput")
        # Source content itself was valid -- must NOT be deleted.
        assert calls["delete_calls"] == []
        # No partial processed object uploaded.
        assert calls["put_calls"] == []

    def test_overshoot_triggers_exactly_one_retry_at_lower_bitrate(
        self, app_ctx, r2_configured, monkeypatch
    ):
        from kk.tasks import video_tasks

        encode_calls: list[int] = []

        def fake_get_file(*, key, dest_path, timeout=120):
            with open(dest_path, "wb") as fh:
                fh.write(b"\x00" * 2048)

        monkeypatch.setattr(r2_ops_module, "r2_get_file", fake_get_file)
        monkeypatch.setattr(r2_ops_module, "r2_put_file", lambda **kw: None)
        monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **kw: None)
        monkeypatch.setattr(
            vt, "validate_source_media", lambda path: _sdr_source_validation(has_audio=False)
        )
        monkeypatch.setattr(vt, "probe_ffmpeg_capabilities", lambda: _full_caps())

        # First encode "overshoots" (writes a file >= FINAL_MAX_BYTES is
        # unrealistic in a test -- instead we simulate the overshoot check
        # directly by writing a large-enough marker file size via a small
        # FINAL_MAX_BYTES monkeypatch on the module constant read inside
        # the impl through vt.FINAL_MAX_BYTES).
        monkeypatch.setattr(vt, "FINAL_MAX_BYTES", 100)

        def fake_run_ffmpeg(argv, timeout=180):
            out_path = argv[-1]
            # Bitrate is the value right after "-b:v" in the built argv.
            bps = int(argv[argv.index("-b:v") + 1])
            encode_calls.append(bps)
            size = 200 if len(encode_calls) == 1 else 50
            with open(out_path, "wb") as fh:
                fh.write(b"\x00" * size)

        monkeypatch.setattr(vt, "run_ffmpeg", fake_run_ffmpeg)
        monkeypatch.setattr(
            vt,
            "validate_output_media",
            lambda path, **kw: _passing_output_validation(has_audio=False, size_bytes=50),
        )

        result = self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-overshoot")
        assert result["status"] == "succeeded"
        assert len(encode_calls) == 2  # exactly one retry
        assert encode_calls[1] < encode_calls[0]  # retry bitrate is lower

    def test_missing_encoder_capability_is_transient_not_permanent(
        self, app_ctx, r2_configured, monkeypatch
    ):
        from kk.tasks.video_tasks import VideoTranscodeTaskError

        caps = vt.FfmpegCapabilities(
            ffmpeg_path="ffmpeg",
            ffprobe_path="ffprobe",
            ffmpeg_version="v",
            ffprobe_version="v",
            has_libx264=False,
            has_aac_encoder=True,
            has_zscale_filter=True,
            has_tonemap_filter=True,
        )
        calls = _patch_common(
            monkeypatch, source_validation=_sdr_source_validation(has_audio=False), caps=caps
        )
        with pytest.raises(VideoTranscodeTaskError, match="libx264"):
            self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-nolibx264")
        assert calls["delete_calls"] == []

    def test_no_partial_processed_object_on_r2_upload_failure(
        self, app_ctx, r2_configured, monkeypatch
    ):
        calls = _patch_common(
            monkeypatch,
            source_validation=_sdr_source_validation(has_audio=False),
            caps=_full_caps(),
            output_validation=_passing_output_validation(has_audio=False),
        )

        def failing_put_file(**kw):
            raise RuntimeError("network blip")

        monkeypatch.setattr(r2_ops_module, "r2_put_file", failing_put_file)
        with pytest.raises(RuntimeError):
            self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-uploadfail")
        # Source must be retained (upload failure is transient), and no
        # delete of source happened either since we never reached success.
        assert calls["delete_calls"] == []

    def test_local_temp_files_cleaned_up_on_success(self, app_ctx, r2_configured, monkeypatch):
        from kk.tasks import video_tasks

        captured_paths: dict = {}

        def fake_get_file(*, key, dest_path, timeout=120):
            captured_paths["source"] = dest_path
            with open(dest_path, "wb") as fh:
                fh.write(b"\x00" * 2048)

        def fake_run_ffmpeg(argv, timeout=180):
            out_path = argv[-1]
            captured_paths["output"] = out_path
            with open(out_path, "wb") as fh:
                fh.write(b"\x00" * 512)

        monkeypatch.setattr(r2_ops_module, "r2_get_file", fake_get_file)
        monkeypatch.setattr(r2_ops_module, "r2_put_file", lambda **kw: None)
        monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **kw: None)
        monkeypatch.setattr(
            vt, "validate_source_media", lambda path: _sdr_source_validation(has_audio=False)
        )
        monkeypatch.setattr(vt, "probe_ffmpeg_capabilities", lambda: _full_caps())
        monkeypatch.setattr(vt, "run_ffmpeg", fake_run_ffmpeg)
        monkeypatch.setattr(
            vt,
            "validate_output_media",
            lambda path, **kw: _passing_output_validation(has_audio=False, size_bytes=512),
        )

        self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-cleanup")
        assert not os.path.isfile(captured_paths["source"])
        assert not os.path.isfile(captured_paths["output"])

    def test_local_temp_files_cleaned_up_on_failure(self, app_ctx, r2_configured, monkeypatch):
        from kk.tasks.video_tasks import VideoTranscodeTaskError

        captured_paths: dict = {}

        def fake_get_file(*, key, dest_path, timeout=120):
            captured_paths["source"] = dest_path
            with open(dest_path, "wb") as fh:
                fh.write(b"\x00" * 2048)

        monkeypatch.setattr(r2_ops_module, "r2_get_file", fake_get_file)
        monkeypatch.setattr(r2_ops_module, "r2_delete_object", lambda **kw: None)

        def raise_validation_error(path):
            captured_paths["source_at_validation"] = path
            raise vt.VideoValidationError("no video stream")

        monkeypatch.setattr(vt, "validate_source_media", raise_validation_error)

        with pytest.raises(VideoTranscodeTaskError):
            self._run(app=app_ctx[0], owner="pub-owner-1", draft="draft-cleanup-fail")
        assert not os.path.isfile(captured_paths["source"])


# ---------------------------------------------------------------------------
# Finalize endpoint: enqueue-on-finalize idempotency
# ---------------------------------------------------------------------------


class TestFinalizeEnqueuesTranscode:
    def test_finalize_enqueues_transcode_task_once(
        self, client, r2_configured, seller_ctx, monkeypatch
    ):
        _mock_head_object(monkeypatch, exists=True, size=2048)
        from kk.tasks import video_tasks

        enqueue_calls: list[dict] = []
        real_apply_async = video_tasks.transcode_car_video_source.apply_async

        class _FakeAsyncResult:
            id = "fake-task-id-0000000000000001"

            def __init__(self):
                self.state = "PENDING"

        def fake_apply_async(*, kwargs, expires):
            enqueue_calls.append({"kwargs": kwargs, "expires": expires})
            return _FakeAsyncResult()

        monkeypatch.setattr(video_tasks.transcode_car_video_source, "apply_async", fake_apply_async)
        monkeypatch.setattr(
            video_tasks.transcode_car_video_source,
            "AsyncResult",
            lambda tid: _FakeAsyncResult(),
        )

        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL, headers=_auth(token), json={"draft_media_id": "enqueue-once"}
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert body["task_id"] == "fake-task-id-0000000000000001"
        assert body["job_state"] == "queued"
        assert len(enqueue_calls) == 1
        assert enqueue_calls[0]["kwargs"]["draft_media_id"] == "enqueue-once"
        assert enqueue_calls[0]["expires"] == video_tasks.VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS

    def test_repeated_finalize_does_not_enqueue_twice(
        self, client, r2_configured, seller_ctx, monkeypatch
    ):
        _mock_head_object(monkeypatch, exists=True, size=2048)
        from kk.tasks import video_tasks

        enqueue_calls: list[dict] = []

        class _FakeAsyncResult:
            def __init__(self, tid):
                self.id = tid
                self.state = "STARTED"

        def fake_apply_async(*, kwargs, expires):
            enqueue_calls.append(kwargs)
            return _FakeAsyncResult("fake-task-id-0000000000000002")

        monkeypatch.setattr(video_tasks.transcode_car_video_source, "apply_async", fake_apply_async)
        monkeypatch.setattr(
            video_tasks.transcode_car_video_source,
            "AsyncResult",
            lambda tid: _FakeAsyncResult(tid),
        )

        token = _login(client, seller_ctx[0])
        r1 = client.post(
            _FINALIZE_URL, headers=_auth(token), json={"draft_media_id": "enqueue-idempotent"}
        )
        r2 = client.post(
            _FINALIZE_URL, headers=_auth(token), json={"draft_media_id": "enqueue-idempotent"}
        )
        assert r1.status_code == 200 and r2.status_code == 200
        assert len(enqueue_calls) == 1  # only enqueued once
        assert r1.get_json()["task_id"] == r2.get_json()["task_id"]
        # Second call reports the SAME task's current state, not "staged".
        assert r2.get_json()["job_state"] == "processing"

    def test_finalize_registers_job_ownership(
        self, client, r2_configured, seller_ctx, monkeypatch
    ):
        from kk.job_ownership import get_registered_job_owner
        from kk.tasks import video_tasks

        _mock_head_object(monkeypatch, exists=True, size=2048)

        class _FakeAsyncResult:
            id = "fake-task-id-0000000000000003"
            state = "PENDING"

        monkeypatch.setattr(
            video_tasks.transcode_car_video_source,
            "apply_async",
            lambda *, kwargs, expires: _FakeAsyncResult(),
        )
        monkeypatch.setattr(
            video_tasks.transcode_car_video_source,
            "AsyncResult",
            lambda tid: _FakeAsyncResult(),
        )

        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL, headers=_auth(token), json={"draft_media_id": "ownership-check"}
        )
        assert resp.status_code == 200
        task_id = resp.get_json()["task_id"]
        owner = get_registered_job_owner(task_id)
        assert owner == seller_ctx[1]

    def test_finalize_registers_job_ownership_and_dedupe_with_video_auth_ttl(
        self, client, r2_configured, seller_ctx, monkeypatch
    ):
        """Phase 3A durability hardening: ``finalize_video_source_upload()``
        must register BOTH the job-ownership AND the idempotent-dedupe
        binding with the explicit, longer-than-default
        ``VIDEO_JOB_AUTH_TTL_SECONDS`` -- NOT either helper's own (shorter)
        default ``ttl_s`` -- so ``attach_transcoded_video()`` can still
        authorize an attach for as long as the processed-staging object it
        depends on is guaranteed to still exist. See
        ``kk/tasks/video_tasks.py::VIDEO_JOB_AUTH_TTL_SECONDS``'s docstring
        for the full TTL-alignment rationale."""
        from kk import job_ownership as job_ownership_module
        from kk.tasks import video_tasks
        from kk.tasks.video_tasks import VIDEO_JOB_AUTH_TTL_SECONDS

        _mock_head_object(monkeypatch, exists=True, size=2048)

        class _FakeAsyncResult:
            id = "fake-task-id-0000000000000099"
            state = "PENDING"

        monkeypatch.setattr(
            video_tasks.transcode_car_video_source,
            "apply_async",
            lambda *, kwargs, expires: _FakeAsyncResult(),
        )
        monkeypatch.setattr(
            video_tasks.transcode_car_video_source,
            "AsyncResult",
            lambda tid: _FakeAsyncResult(),
        )

        owner_calls: list[dict] = []
        idempotent_calls: list[dict] = []
        real_register_job_owner = job_ownership_module.register_job_owner
        real_register_idempotent_job_task_id = (
            job_ownership_module.register_idempotent_job_task_id
        )

        def spy_register_job_owner(task_id, owner_public_id, **kwargs):
            owner_calls.append(kwargs)
            return real_register_job_owner(task_id, owner_public_id, **kwargs)

        def spy_register_idempotent_job_task_id(dedupe_key, task_id, **kwargs):
            idempotent_calls.append(kwargs)
            return real_register_idempotent_job_task_id(dedupe_key, task_id, **kwargs)

        # media.py imports these two names directly, so patch them there.
        from kk.routes import media as media_routes

        monkeypatch.setattr(media_routes, "register_job_owner", spy_register_job_owner)
        monkeypatch.setattr(
            media_routes,
            "register_idempotent_job_task_id",
            spy_register_idempotent_job_task_id,
        )

        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL, headers=_auth(token), json={"draft_media_id": "ttl-check"}
        )
        assert resp.status_code == 200, resp.data

        assert len(owner_calls) == 1
        assert owner_calls[0].get("ttl_s") == VIDEO_JOB_AUTH_TTL_SECONDS
        assert len(idempotent_calls) == 1
        assert idempotent_calls[0].get("ttl_s") == VIDEO_JOB_AUTH_TTL_SECONDS

    def test_job_state_mapping_covers_all_celery_states(self):
        from kk.tasks.video_tasks import celery_state_to_video_job_state

        assert celery_state_to_video_job_state("PENDING") == "queued"
        assert celery_state_to_video_job_state("STARTED") == "processing"
        assert celery_state_to_video_job_state("RETRY") == "processing"
        assert celery_state_to_video_job_state("SUCCESS") == "succeeded"
        assert celery_state_to_video_job_state("FAILURE") == "failed"
        assert celery_state_to_video_job_state("REVOKED") == "failed"
        assert celery_state_to_video_job_state("SOME_UNKNOWN_STATE") == "queued"
        assert celery_state_to_video_job_state(None) == "queued"

    def test_dedupe_key_differs_by_owner_and_draft(self):
        from kk.tasks.video_tasks import video_job_dedupe_key

        a = video_job_dedupe_key("owner-1", "draft-1")
        b = video_job_dedupe_key("owner-2", "draft-1")
        c = video_job_dedupe_key("owner-1", "draft-2")
        assert a != b
        assert a != c


# ---------------------------------------------------------------------------
# Processed-video-staging Beat cleanup
# ---------------------------------------------------------------------------


class TestCleanupStaleProcessedVideoStagingObjects:
    def test_noop_when_r2_not_configured(self, app_ctx, monkeypatch):
        from kk.tasks import video_tasks

        app = app_ctx[0]
        monkeypatch.setattr(
            r2_ops_module,
            "r2_cleanup_stale_staging",
            lambda **_kw: pytest.fail("must not call R2 when it is not configured"),
        )
        with app.app_context():
            out = video_tasks.cleanup_stale_processed_video_staging_objects.run()
        assert out["ok"] is True
        assert out["deleted"] == 0

    def test_delegates_with_correct_prefix_and_48h_age(self, app_ctx, r2_configured, monkeypatch):
        from kk.tasks import video_tasks

        app = app_ctx[0]
        captured: dict = {}

        def fake_cleanup(*, prefix, older_than_seconds, timeout=60):
            captured["prefix"] = prefix
            captured["older_than_seconds"] = older_than_seconds
            return 2

        monkeypatch.setattr(r2_ops_module, "r2_cleanup_stale_staging", fake_cleanup)
        with app.app_context():
            out = video_tasks.cleanup_stale_processed_video_staging_objects.run()

        assert out == {"ok": True, "deleted": 2}
        assert captured["prefix"] == "car_videos/_processed_staging/"
        assert captured["older_than_seconds"] == 48 * 3600

    def test_beat_schedule_entry_matches_registered_task_name(self):
        from kk.tasks import video_tasks
        from kk.tasks.celery_app import celery_app

        entry = celery_app.conf.beat_schedule["cleanup-stale-processed-video-staging-objects"]
        assert entry["task"] == video_tasks.cleanup_stale_processed_video_staging_objects.name
        assert entry["task"] in celery_app.tasks

    def test_processed_staging_prefix_never_overlaps_source_or_permanent_namespace(self):
        """Safety check: none of the three car-video namespaces (permanent,
        source-staging, processed-staging) may ever be a prefix of another
        -- or a cleanup sweep targeting one could delete objects belonging
        to a different one, including permanent listing videos."""
        from kk.media_processing import (
            PROCESSED_VIDEO_STAGING_KEY_PREFIX,
            VIDEO_SOURCE_STAGING_KEY_PREFIX,
        )

        permanent_prefix = "car_videos/"
        namespaces = [
            permanent_prefix,
            VIDEO_SOURCE_STAGING_KEY_PREFIX,
            PROCESSED_VIDEO_STAGING_KEY_PREFIX,
        ]
        # The permanent prefix IS a string-prefix of the other two (both
        # live under car_videos/) -- that part is expected/by design (they
        # are namespaced *under* car_videos/). What must NEVER be true is
        # that a real permanent video's key (which never contains "_staging"
        # or "_processed_staging" as its first path segment after
        # "car_videos/") could be matched by either staging sweep's
        # prefix, and that the two staging prefixes never overlap each
        # other.
        assert not PROCESSED_VIDEO_STAGING_KEY_PREFIX.startswith(VIDEO_SOURCE_STAGING_KEY_PREFIX)
        assert not VIDEO_SOURCE_STAGING_KEY_PREFIX.startswith(PROCESSED_VIDEO_STAGING_KEY_PREFIX)
        # A real permanent listing-video key must not start with either
        # staging prefix.
        example_permanent_key = "car_videos/u1234567890abcdef/some-video.mp4"
        assert not example_permanent_key.startswith(VIDEO_SOURCE_STAGING_KEY_PREFIX)
        assert not example_permanent_key.startswith(PROCESSED_VIDEO_STAGING_KEY_PREFIX)

    def test_source_cleanup_ttl_raised_to_24h(self):
        from kk.tasks.video_tasks import _VIDEO_SOURCE_STAGING_STALE_AFTER_SECONDS

        assert _VIDEO_SOURCE_STAGING_STALE_AFTER_SECONDS == 24 * 3600

    def test_task_expiry_well_below_source_cleanup_ttl(self):
        """Avoids the race documented in
        kk/tasks/video_tasks.py::VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS's
        docstring: a queued (not yet started) task must expire well before
        its source object could be swept."""
        from kk.tasks.video_tasks import (
            VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS,
            _VIDEO_SOURCE_STAGING_STALE_AFTER_SECONDS,
        )

        assert VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS < _VIDEO_SOURCE_STAGING_STALE_AFTER_SECONDS
