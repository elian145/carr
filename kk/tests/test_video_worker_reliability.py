"""Operational hardening: server-video Celery runtime reliability.

Focused tests for the remaining reliability fixes on top of Phase 2
(``kk/tests/test_video_transcode_phase2.py`` covers the transcode
pipeline's own contract; this file covers ONLY the Celery-level task
options, the ffmpeg-timeout call-site override, the worker prefetch
setting, and idempotency-under-redelivery):

  1. ``transcode_car_video_source`` uses ``acks_late=True``,
     ``reject_on_worker_lost=True``, ``track_started=True``, and
     DELIBERATELY has NO Celery ``time_limit``/``soft_time_limit`` (a
     prior revision added a hard ``time_limit`` as a "backstop" but that
     was removed -- a Celery hard time_limit SIGKILLs the worker child
     process, which can orphan an already-running ffmpeg grandchild and
     makes "a redelivered execution cannot overlap the prior attempt"
     unprovable; see ``kk/tasks/video_tasks.py``'s module-level comment).
  2. The task's own ffmpeg invocation passes an explicit
     ``timeout=VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS`` (600), not
     ``kk.video_transcoding.run_ffmpeg``'s shared 180s default -- this
     subprocess timeout (which ``subprocess.run(timeout=...)`` enforces by
     cleanly terminating and waiting on its OWN direct child) is now the
     ONLY bounded-execution mechanism for the expensive ffmpeg step.
  3. ``celery_app.conf.worker_prefetch_multiplier == 1``.
  4. ``VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS`` (the enqueue-time message
     TTL) remains safely above the real measured worst-case execution
     window (itself bounded by ``VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS``).
  5. The task is idempotent AT THE OBJECT-KEY LEVEL under a simulated
     duplicate/redelivered execution (same task args run twice against
     fakes standing in for R2 -- no real R2 credentials/network needed,
     same pattern as ``test_video_transcode_phase2.py``). This file does
     NOT claim a redelivered execution can never overlap an ffmpeg
     process left behind by a prior, externally-killed attempt -- that
     depends on the hosting environment reaping child processes on
     worker/container loss, which is outside what this application code
     can prove or test.

Every ffmpeg subprocess call and every R2 call is mocked -- no real
ffmpeg/ffprobe binary and no real R2 credentials are required to run this
file. Deliberately does NOT touch/re-assert
``kk/tests/test_be13_worker_concurrency_config.py`` (the stale
--concurrency=2 expectation there is a separate, already-reported fix).
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
from kk.tasks import video_tasks  # noqa: E402
from kk.tasks.celery_app import celery_app  # noqa: E402

# Reuse the exact same pure (non-fixture) fake-data builders Phase 2's own
# test file already defines, rather than duplicating them -- these are
# plain functions, not pytest fixtures, so a direct import is safe/stable.
from kk.tests.test_video_transcode_phase2 import (  # noqa: E402
    _full_caps,
    _passing_output_validation,
    _sdr_source_validation,
)

_R2_KEYS = (
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
)


# ---------------------------------------------------------------------------
# 1) Celery task options on transcode_car_video_source itself
# ---------------------------------------------------------------------------


class TestVideoTaskCeleryOptions:
    def test_uses_late_acknowledgement(self):
        assert video_tasks.transcode_car_video_source.acks_late is True

    def test_rejects_and_requeues_on_worker_loss(self):
        assert video_tasks.transcode_car_video_source.reject_on_worker_lost is True

    def test_tracks_started_state(self):
        assert video_tasks.transcode_car_video_source.track_started is True

    def test_has_no_hard_time_limit(self):
        """A Celery hard time_limit was deliberately REMOVED: it SIGKILLs
        the worker child process, which can orphan an already-running
        ffmpeg grandchild rather than terminate it cleanly -- combined
        with reject_on_worker_lost, that made "a redelivered execution
        cannot overlap the prior attempt's ffmpeg process" unprovable. The
        plain subprocess timeout (VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS)
        is now the only bounded-execution mechanism for the expensive
        step -- see kk/tasks/video_tasks.py's module-level comment."""
        assert video_tasks.transcode_car_video_source.time_limit is None
        assert not hasattr(video_tasks, "VIDEO_TRANSCODE_TASK_TIME_LIMIT_SECONDS")

    def test_does_not_use_a_soft_time_limit(self):
        """Deliberate: a soft_time_limit this module cannot prove cleanly
        terminates an already-spawned ffmpeg child is worse than no soft
        limit at all -- see the module-level comment in
        kk/tasks/video_tasks.py next to VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS."""
        assert video_tasks.transcode_car_video_source.soft_time_limit is None

    def test_acks_late_is_not_a_global_default(self):
        """acks_late/reject_on_worker_lost must be opt-in on THIS task
        only, not silently applied to every Celery task in the app (other
        tasks -- e.g. image processing -- were not audited for the same
        redelivery-idempotency guarantees)."""
        assert celery_app.conf.task_acks_late is not True
        assert celery_app.conf.task_reject_on_worker_lost is not True

    def test_other_video_tasks_are_unaffected(self):
        """Only the transcode task itself gets the new reliability
        options -- the two cleanup sweep tasks are short/idempotent Beat
        jobs and were not asked to change."""
        assert video_tasks.cleanup_stale_video_staging_objects.acks_late is not True
        assert video_tasks.cleanup_stale_processed_video_staging_objects.acks_late is not True


# ---------------------------------------------------------------------------
# 2) worker_prefetch_multiplier
# ---------------------------------------------------------------------------


class TestWorkerPrefetchMultiplier:
    def test_prefetch_multiplier_is_one(self):
        assert celery_app.conf.worker_prefetch_multiplier == 1


# ---------------------------------------------------------------------------
# 2b) Broker-level redelivery for a WHOLE-CONTAINER loss (not just a
#     worker-child crash the surviving parent process can detect and
#     reject/requeue itself). acks_late/reject_on_worker_lost do nothing
#     if the entire process tree -- parent included -- is killed (exactly
#     what Render's "Ran out of memory... Instance failed" event means);
#     redelivery in that case depends entirely on the Redis broker's own
#     "visibility_timeout". See kk/tasks/celery_app.py's module-level
#     comment for the full mechanism.
# ---------------------------------------------------------------------------


class TestBrokerVisibilityTimeout:
    def test_visibility_timeout_is_configured(self):
        opts = celery_app.conf.broker_transport_options
        assert isinstance(opts, dict)
        assert "visibility_timeout" in opts

    def test_visibility_timeout_is_far_below_the_redis_transport_default(self):
        """kombu's Redis transport default (verified directly against the
        installed version) is 3600s (1 hour) -- exactly what produced the
        "task never reaches SUCCESS/FAILURE, client polls forever"
        production symptom for a whole-container-killed worker. This must
        be materially lower."""
        import kombu.transport.redis as redis_transport

        kombu_default = redis_transport.Channel.visibility_timeout
        assert kombu_default == 3600  # documents the exact default being improved on
        configured = celery_app.conf.broker_transport_options["visibility_timeout"]
        assert configured < kombu_default

    def test_visibility_timeout_exceeds_the_absolute_worst_case_single_attempt_wall_time(self):
        """Must never be so low that a still-legitimately-running attempt
        (not actually lost) gets redelivered while it is still working --
        that would risk two overlapping executions. Sum every internal
        step timeout this task could hit back-to-back (the true upper
        bound before the task's OWN code would already have raised/
        returned): r2_get_file (120s) + source ffprobe (30s) + the ffmpeg
        subprocess itself (600s) + output ffprobe (30s) + r2_put_file
        (120s) + the best-effort source r2_delete_object (30s) = 930s."""
        configured = celery_app.conf.broker_transport_options["visibility_timeout"]
        worst_case_internal_timeouts_seconds = 120 + 30 + 600 + 30 + 120 + 30
        assert worst_case_internal_timeouts_seconds == 930
        assert configured > worst_case_internal_timeouts_seconds
        assert configured > video_tasks.VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS

    def test_visibility_timeout_applies_broker_wide_not_just_to_the_video_task(self):
        """Documents that this is a broker-connection-wide Celery setting
        (no supported per-task override exists) -- harmless for every
        OTHER task registered here, since none of them use acks_late and
        so are acked immediately on delivery, long before
        visibility_timeout could ever matter for them."""
        assert celery_app.conf.task_acks_late is not True
        opts = celery_app.conf.broker_transport_options
        assert "visibility_timeout" in opts


# ---------------------------------------------------------------------------
# 3) Task message expiry stays safely above the real worst-case execution
#    window. With the Celery hard time_limit removed, the operative bound
#    on the expensive step is VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS (the
#    plain subprocess timeout) itself.
# ---------------------------------------------------------------------------


class TestExpiryVsExecutionWindow:
    def test_message_expiry_exceeds_ffmpeg_timeout(self):
        assert (
            video_tasks.VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS
            > video_tasks.VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS
        )

    def test_ffmpeg_timeout_exceeds_real_measured_worst_case_with_margin(self):
        # Real measurement (Linux/WSL, static-ffmpeg==3.0): 108.82s for a
        # 6.9517s 4K/120fps HDR fixture => ~15.65x realtime. Extrapolated
        # to the module's own 30s source cap:
        real_seconds = 108.82
        real_fixture_duration = 6.9517
        max_source_duration = vt.MAX_SOURCE_DURATION_SECONDS
        worst_case_seconds = real_seconds / real_fixture_duration * max_source_duration
        assert worst_case_seconds < video_tasks.VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS
        assert (
            video_tasks.VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS
            < video_tasks.VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS
        )


# ---------------------------------------------------------------------------
# 4) ffmpeg invocation from the video task uses the explicit 600s timeout
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_vidreliability_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "vidreliability.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    for key in _R2_KEYS + ("R2_PUBLIC_URL",):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def r2_configured(app_ctx, monkeypatch):
    for key in _R2_KEYS:
        monkeypatch.setitem(app_ctx.config, key, f"test-{key.lower()}")
    return app_ctx


def _patch_r2_and_ffmpeg(monkeypatch, *, source_bytes=b"\x00" * 2048, output_bytes_size=1024):
    """Minimal local variant of test_video_transcode_phase2.py's
    _patch_common, plus capturing the exact kwargs run_ffmpeg was called
    with (needed for the timeout=600 assertion, which _patch_common's own
    fake does not expose to callers)."""

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

    monkeypatch.setattr(vt, "validate_source_media", lambda path: _sdr_source_validation(has_audio=False))
    monkeypatch.setattr(vt, "probe_ffmpeg_capabilities", lambda: _full_caps())

    run_ffmpeg_calls: list[dict] = []

    def fake_run_ffmpeg(argv, timeout=180):
        run_ffmpeg_calls.append({"argv": argv, "timeout": timeout})
        out_path = argv[-1]
        with open(out_path, "wb") as fh:
            fh.write(b"\x00" * output_bytes_size)

    monkeypatch.setattr(vt, "run_ffmpeg", fake_run_ffmpeg)
    monkeypatch.setattr(
        vt,
        "validate_output_media",
        lambda path, **kw: _passing_output_validation(has_audio=False, size_bytes=output_bytes_size),
    )

    return {"put_calls": put_calls, "delete_calls": delete_calls, "run_ffmpeg_calls": run_ffmpeg_calls}


class TestFfmpegTimeoutAtCallSite:
    def test_run_ffmpeg_called_with_timeout_600(self, app_ctx, r2_configured, monkeypatch):
        from kk.media_processing import video_source_staging_key
        from kk.tasks.video_tasks import _transcode_video_source_impl

        calls = _patch_r2_and_ffmpeg(monkeypatch)

        with app_ctx.app_context():
            key = video_source_staging_key("pub-owner-timeout", "draft-timeout")
            result = _transcode_video_source_impl(
                source_staging_key=key,
                owner_public_id="pub-owner-timeout",
                draft_media_id="draft-timeout",
            )

        assert result["status"] == "succeeded"
        assert len(calls["run_ffmpeg_calls"]) == 1
        assert calls["run_ffmpeg_calls"][0]["timeout"] == 600
        assert calls["run_ffmpeg_calls"][0]["timeout"] == video_tasks.VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS
        # Explicitly NOT the shared kk.video_transcoding.run_ffmpeg default.
        assert calls["run_ffmpeg_calls"][0]["timeout"] != 180


# ---------------------------------------------------------------------------
# 5) Idempotency under a simulated duplicate/redelivered execution
#
# Scope note (corrected): these tests prove idempotency at the R2
# OBJECT-KEY level (deterministic keys + overwrite-safe PUT + two-branch
# source-retention policy). They deliberately do NOT claim -- and must
# not be read as claiming -- that a redelivered execution can never
# overlap an ffmpeg process left running by a prior, externally-killed
# attempt. That would depend on the hosting environment reaping child
# processes on worker/container loss, which this application code cannot
# prove and does not test.
# ---------------------------------------------------------------------------


class TestIdempotentUnderRedelivery:
    def test_two_executions_of_the_same_task_args_are_safe(self, app_ctx, r2_configured, monkeypatch):
        """Simulates Celery redelivering the SAME task (same
        source_staging_key/owner/draft) a second time after the first
        attempt's worker was lost mid-run -- e.g. via
        reject_on_worker_lost -- by simply invoking the plain-function
        core twice in a row with identical arguments. Both runs must
        derive the exact same keys and both must succeed without needing
        any different/duplicate state; the second run's PUT to the
        processed key is a plain overwrite, never a second/different key."""
        from kk.media_processing import (
            processed_video_staging_key,
            video_source_staging_key,
        )
        from kk.tasks.video_tasks import _transcode_video_source_impl

        owner = "pub-owner-redelivery"
        draft = "draft-redelivery"

        with app_ctx.app_context():
            source_key = video_source_staging_key(owner, draft)
            expected_processed_key = processed_video_staging_key(owner, draft)

        # --- "first attempt" (e.g. the one whose worker got OOM-killed
        # mid-encode, before the exception-handling/delete-on-success
        # branches ever ran) ---
        calls_1 = _patch_r2_and_ffmpeg(monkeypatch)
        with app_ctx.app_context():
            result_1 = _transcode_video_source_impl(
                source_staging_key=source_key, owner_public_id=owner, draft_media_id=draft
            )
        assert result_1["status"] == "succeeded"
        assert result_1["processed_staging_key"] == expected_processed_key
        assert calls_1["put_calls"][0]["key"] == expected_processed_key
        assert calls_1["delete_calls"] == [source_key]

        # --- "redelivered attempt" -- same task args, run again from
        # scratch (a fresh set of R2/ffmpeg fakes, since the real R2
        # object the first attempt uploaded/deleted is not shared state
        # across these two monkeypatched fake layers -- but the KEYS
        # computed by the task itself must be identical both times, which
        # is the actual property under test). ---
        calls_2 = _patch_r2_and_ffmpeg(monkeypatch)
        with app_ctx.app_context():
            result_2 = _transcode_video_source_impl(
                source_staging_key=source_key, owner_public_id=owner, draft_media_id=draft
            )
        assert result_2["status"] == "succeeded"
        assert result_2["processed_staging_key"] == expected_processed_key
        # Same processed key both times -- a redelivered run overwrites,
        # it never creates a second/different permanent-staging object.
        assert result_1["processed_staging_key"] == result_2["processed_staging_key"]
        assert calls_2["put_calls"][0]["key"] == expected_processed_key
        assert calls_2["delete_calls"] == [source_key]

    def test_redelivery_after_worker_loss_finds_source_still_present(
        self, app_ctx, r2_configured, monkeypatch
    ):
        """Specifically models the acks_late/reject_on_worker_lost failure
        mode: the worker is lost WHILE run_ffmpeg() is still running (i.e.
        before either the permanent-invalid-source delete branch or the
        post-success delete branch could possibly have run). The source
        object must still be there for the redelivered attempt -- modeled
        here by a run_ffmpeg fake that raises (simulating the process
        never returning from that call), confirming the source is NOT
        deleted in that case, so a real redelivery would still find it."""
        from kk.media_processing import video_source_staging_key
        from kk.tasks.video_tasks import _transcode_video_source_impl

        owner = "pub-owner-lost-midrun"
        draft = "draft-lost-midrun"

        calls = _patch_r2_and_ffmpeg(monkeypatch)

        def never_returns(argv, timeout=180):
            # Stands in for "the worker process was killed while this
            # call was in flight" -- from the source-retention policy's
            # point of view, what matters is that neither the
            # permanent-invalid nor the post-success delete branch runs.
            # A real ffmpeg-subprocess-level failure (TranscodeError) is
            # NOT wrapped into VideoTranscodeTaskError by this code path --
            # it propagates as-is, which is fine: the property under test
            # is source retention, not the exact exception type.
            raise vt.TranscodeError("simulated worker loss mid-ffmpeg")

        monkeypatch.setattr(vt, "run_ffmpeg", never_returns)

        with app_ctx.app_context():
            key = video_source_staging_key(owner, draft)
            with pytest.raises(vt.TranscodeError):
                _transcode_video_source_impl(
                    source_staging_key=key, owner_public_id=owner, draft_media_id=draft
                )

        # Source must NOT have been deleted -- a redelivered attempt can
        # still download and process it.
        assert calls["delete_calls"] == []
        assert calls["put_calls"] == []


# ---------------------------------------------------------------------------
# 6) Normal (non-worker-loss) failures must not become infinite requeue
#    loops -- no autoretry/max_retries is configured on this task, so a
#    plain raised exception is a single ordinary FAILURE, not a retry.
# ---------------------------------------------------------------------------


class TestNormalFailuresDoNotAutoRetry:
    def test_task_has_no_autoretry_configured(self):
        task = video_tasks.transcode_car_video_source
        assert getattr(task, "autoretry_for", None) in (None, ())
        # Celery's own default max_retries (3) is irrelevant when nothing
        # ever calls self.retry()/raises Retry -- confirm this task's
        # implementation never does so for a normal validation failure by
        # checking the source module for the one call that matters.
        import inspect

        src = inspect.getsource(video_tasks)
        assert ".retry(" not in src, (
            "transcode_car_video_source must not call self.retry() for a normal "
            "handled failure -- that would risk an unbounded requeue loop "
            "independent of reject_on_worker_lost"
        )
