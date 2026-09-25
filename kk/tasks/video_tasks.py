"""Phase 1 + Phase 2 of the server-side video transcode fallback: Celery
tasks for SOURCE video staging cleanup (Phase 1) and server-side
transcoding + PROCESSED video staging + its own cleanup (Phase 2).

See ``kk/media_processing.py`` (``video_source_staging_key``,
``processed_video_staging_key``) and ``kk/routes/media.py``'s
``sign_video_source_upload`` / ``finalize_video_source_upload`` endpoints
for the rest of this feature. Actual ffmpeg/ffprobe command construction
and source/output contract validation live in ``kk/video_transcoding.py``
(kept ffmpeg/Celery-independent so it can be unit-tested without a broker);
this module only orchestrates: download -> validate -> transcode ->
validate -> upload -> cleanup.
"""

from __future__ import annotations

import logging
import os
import tempfile
from uuid import uuid4

from .celery_app import celery_app

logger = logging.getLogger(__name__)

# Phase 1: 6h matches the image-staging sweep's own convention/rationale
# (see kk.tasks.image_tasks.cleanup_stale_image_staging_objects's
# docstring): real uploads should finish in well under this, so anything
# still present after 6 hours is safely assumed abandoned, not merely slow.
#
# Phase 2 raises this to 24h. Once a finalize call can enqueue a transcode
# task that itself deletes the source object on success (see
# ``transcode_car_video_source`` below), a SHORT source-staging TTL creates
# a race: a task that sits queued for a while (broker backlog, worker
# briefly down) could have its source deleted out from under it by this
# sweep before it even starts. The task's own Celery message TTL
# (``VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS``, enforced at enqueue time in
# ``kk/routes/media.py::finalize_video_source_upload``) is kept well below
# this cleanup TTL so an abandoned/expired task's source is still reliably
# reclaimed, just not so aggressively that a merely-delayed-but-still-live
# task can lose its input out from under it.
_VIDEO_SOURCE_STAGING_STALE_AFTER_SECONDS = 24 * 3600

# Phase 2: processed (transcoded) staging needs a materially LONGER TTL
# than source staging -- a seller may finish uploading/transcoding, then
# leave the app before actually submitting the listing (Phase 3's attach
# step, not implemented yet, is what will consume this object). 48h gives
# a returning seller about two days to resume and complete the listing
# submission without having to re-upload/re-transcode from scratch.
_PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS = 48 * 3600

# Enqueue-time Celery message TTL for the transcode task itself -- see the
# race-avoidance rationale above. Deliberately well below
# ``_VIDEO_SOURCE_STAGING_STALE_AFTER_SECONDS``: a task that hasn't even
# started within 2 hours of being queued is itself considered abandoned
# (broker/worker outage), and letting the message expire instead of running
# stale is safer than transcoding a possibly-already-swept source.
VIDEO_TRANSCODE_TASK_EXPIRES_SECONDS = 2 * 3600

# ---------------------------------------------------------------------------
# Phase 3A durability hardening: server-side AUTHORIZATION durability for
# ``attach_transcoded_video()`` (kk/routes/media.py).
#
# That endpoint's authorization for "may this caller attach THIS processed
# video" depends on THREE separate server-side records all still being
# readable at attach time:
#   1. the enqueue-time job-ownership registration (``register_job_owner``
#      -- kk/job_ownership.py)
#   2. the enqueue-time idempotent dedupe-key -> task_id binding
#      (``register_idempotent_job_task_id`` -- same module) -- this is the
#      one that authoritatively proves task_id<->draft_media_id
#   3. the Celery RESULT backend still reporting this task_id's state as
#      SUCCESS (``AsyncResult.state``/``.result``)
#
# All three were previously written with a plain 24h TTL (job_ownership.py's
# own defaults) / Celery's own default ``result_expires`` (also 1 day) --
# SHORTER than ``_PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS`` (48h). A
# seller who finished transcoding but did not return to actually submit the
# listing until, say, hour 30 would find the PROCESSED VIDEO OBJECT still
# present (staging TTL not yet expired) but the attach endpoint unable to
# authorize attaching it (job ownership / dedupe binding / Celery result all
# already expired at ~24h) -- an avoidable dead end that would force a full
# re-upload/re-transcode for no reason other than an TTL mismatch.
#
# Chosen policy: AUTH/RESULT TTL (72h) >= PROCESSED_STAGING_TTL (48h) + a
# 24h safety margin (covers clock/scheduling skew and the up-to-1h
# staging-cleanup sweep interval, see ``celery_app.py``'s
# ``beat_schedule``). ``_PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS``
# itself is left UNCHANGED (extending durability by raising the SHORTER
# side is strictly less disruptive than shortening the processed-staging
# window a returning seller already relies on).
#
# This constant is passed EXPLICITLY as ``ttl_s=`` to
# ``register_job_owner`` / ``register_idempotent_job_task_id`` at THIS
# task's own enqueue call site only (``finalize_video_source_upload()`` in
# kk/routes/media.py) -- it deliberately does NOT change either function's
# own default ``ttl_s``, which other, unrelated callers (e.g. the async
# image-processing job registration in the same route module) still use
# unchanged. Celery's global ``result_expires`` IS changed (see
# ``celery_app.py``) to this same value, since Celery has no supported
# per-task override for that backend-wide setting -- a longer result TTL
# is a strictly safe change for every task type (more forgiving client
# polling, at the cost of a little extra Redis memory), not a
# correctness/security concern.
VIDEO_JOB_AUTH_TTL_SECONDS = 72 * 3600

# ---------------------------------------------------------------------------
# Operational hardening (real-device verification): a real 6.95s 4K/120fps
# HDR (Dolby Vision Profile 8.4) fixture measured ~108.82s of real ffmpeg
# wall-clock time on Linux (static-ffmpeg==3.0) -- roughly 15.65x realtime
# for this worker's zscale/tonemap HDR pipeline. Extrapolated to this
# module's own ``MAX_SOURCE_DURATION_SECONDS`` (30s, see
# ``kk/video_transcoding.py``) worst case, a single legitimate transcode can
# need on the order of ~470s of ffmpeg time. ``vt.run_ffmpeg()``'s own
# default timeout (180s) is too short for that worst case -- this task
# passes its own, explicit, materially larger timeout at the call site
# instead of changing that shared default (other/future callers of
# ``run_ffmpeg`` may have very different -- shorter -- legitimate runtimes,
# so the shared default is intentionally left alone).
# ---------------------------------------------------------------------------

# Passed explicitly to ``vt.run_ffmpeg(argv, timeout=...)`` at this task's
# own call site (see ``_encode`` in ``_transcode_video_source_impl``).
# Comfortably above the ~470s extrapolated worst case, while still bounding
# a genuinely stuck ffmpeg process. ``subprocess.run(..., timeout=...)``
# (which this wraps) already terminates and waits for its direct child
# cleanly on timeout, so the NORMAL "ffmpeg is just slow" path never
# orphans a subprocess. This subprocess timeout is currently the ONLY
# bounded-execution mechanism for the expensive part of this task -- see
# below for why a Celery-level hard time_limit is deliberately NOT also
# used here.
VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS = 600

# ---------------------------------------------------------------------------
# Deliberately NO Celery ``time_limit``/``soft_time_limit`` on this task.
#
# A prior revision added a hard ``time_limit`` (660s) as a "backstop above
# the subprocess timeout". That was incorrect: Celery's hard time_limit
# works by SIGKILLing the worker CHILD PROCESS running the task, not by
# cooperating with it -- if that fires while ``vt.run_ffmpeg()``'s own
# ``subprocess.run(..., timeout=...)`` has an ffmpeg grandchild running,
# the ffmpeg process can be ORPHANED (left running/writing temp output)
# rather than cleanly terminated. Combined with ``reject_on_worker_lost``
# (see below), that SIGKILL is itself indistinguishable, from the broker's
# point of view, from an external OOM/crash -- so it would also trigger a
# requeue of this same task while the previous attempt's ffmpeg could
# still be alive. That made the "a redelivered execution cannot overlap
# the prior attempt" claim unprovable, so it has been removed.
#
# A ``soft_time_limit`` is not used either (per explicit instruction):
# it relies on this task catching ``SoftTimeLimitExceeded`` and itself
# cleanly terminating the already-spawned ffmpeg child, which this module
# has no SIGCHLD/process-group plumbing to prove happens reliably -- an
# unproven "soft" cleanup would be misleading.
#
# ``VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS`` (600s, above) is therefore
# the ONLY bounded-execution mechanism for the expensive ffmpeg step:
# ``subprocess.run(timeout=...)`` terminates and waits for its own direct
# child on expiry, which does not have the orphaning risk a Celery-level
# SIGKILL does. Genuine catastrophic worker/container loss (OOM kill,
# host eviction, etc.) is still handled by ``acks_late`` +
# ``reject_on_worker_lost`` below, but whether an ffmpeg grandchild
# actually dies alongside the worker child in that case depends on the
# HOSTING ENVIRONMENT reaping the whole process group/container -- this
# module does not claim otherwise (see the task docstring's redelivery
# section). This is also why the worker needs sufficient RAM headroom
# (measured ~1.77 GiB peak ffmpeg RSS) rather than relying on a hard
# time_limit to bound resource usage.
# ---------------------------------------------------------------------------


class VideoTranscodeTaskError(RuntimeError):
    """User-safe, durable Celery task failure for
    ``transcode_car_video_source`` -- covers both input-validation
    rejections and environment/capability failures. Message text must
    never leak internal paths/stack traces (mirrors
    ``kk.video_transcoding.VideoValidationError``'s same contract)."""


def celery_state_to_video_job_state(celery_state: str | None) -> str:
    """
    Map a raw Celery ``AsyncResult.state`` string onto the small,
    product-facing job-state vocabulary this feature promises (spec
    section 8): ``staged`` (source verified, not yet queued -- this
    mapping is never asked to produce that value itself; callers use it
    literally before a task_id exists), ``queued``, ``processing``,
    ``succeeded``, ``failed``. Never leaks a raw/unexpected Celery state
    string to a client -- any unrecognized value maps to ``"queued"``, the
    safest default (a client should keep polling either way).
    """
    state = (celery_state or "").strip().upper()
    if state in ("SUCCESS",):
        return "succeeded"
    if state in ("FAILURE", "REVOKED"):
        return "failed"
    if state in ("STARTED", "RETRY"):
        return "processing"
    # PENDING and any other/unknown state.
    return "queued"


def video_job_dedupe_key(owner_public_id: str, draft_media_id: str) -> str:
    """
    The idempotency key ``finalize_video_source_upload()`` uses (via
    ``kk/job_ownership.py``'s ``get_idempotent_job_task_id`` /
    ``register_idempotent_job_task_id``) to guarantee repeated finalize
    calls for the same (owner, draft_media_id) enqueue at most one
    transcode task. Deliberately a plain, non-secret string -- unlike R2
    object keys, this is a server-internal Redis key never exposed to any
    client, so it does not need HMAC owner-tag obfuscation the way
    ``video_source_staging_key()``/``processed_video_staging_key()`` do.
    """
    return f"video_source_job:{owner_public_id}:{draft_media_id}"


@celery_app.task(name="kk.cleanup_stale_video_staging_objects")
def cleanup_stale_video_staging_objects():
    """Backstop sweep for abandoned R2 SOURCE-video-staging objects.

    Registered under the exact SHORT name Celery Beat schedules it by (see
    ``kk/tasks/celery_app.py``'s ``beat_schedule``) -- the Beat task-name
    mismatch that broke the sibling image-staging sweep
    (registered name did not match the string Beat sent) was fixed
    independently just before this task was added; this task's name and
    its Beat schedule entry are deliberately written identically from the
    start to avoid repeating that bug.

    Only ever targets ``VIDEO_SOURCE_STAGING_KEY_PREFIX``
    (``car_videos/_staging/``) -- never the permanent ``car_videos/``
    namespace, and never ``PROCESSED_VIDEO_STAGING_KEY_PREFIX`` (see
    :func:`cleanup_stale_processed_video_staging_objects` for that one).
    """
    from flask import current_app

    from ..media_processing import VIDEO_SOURCE_STAGING_KEY_PREFIX, _r2_configured

    if not _r2_configured():
        return {"ok": True, "deleted": 0, "skipped": "r2_not_configured"}

    from ..r2_ops import r2_cleanup_stale_staging

    deleted = r2_cleanup_stale_staging(
        prefix=VIDEO_SOURCE_STAGING_KEY_PREFIX,
        older_than_seconds=_VIDEO_SOURCE_STAGING_STALE_AFTER_SECONDS,
    )
    if deleted:
        current_app.logger.info(
            "cleanup_stale_video_staging_objects: deleted %d stale staging object(s)",
            deleted,
        )
    return {"ok": True, "deleted": deleted}


@celery_app.task(name="kk.cleanup_stale_processed_video_staging_objects")
def cleanup_stale_processed_video_staging_objects():
    """Backstop sweep for abandoned R2 PROCESSED-video-staging objects.

    Only ever targets ``PROCESSED_VIDEO_STAGING_KEY_PREFIX``
    (``car_videos/_processed_staging/``) -- never the permanent
    ``car_videos/`` namespace, and never
    ``VIDEO_SOURCE_STAGING_KEY_PREFIX``. A successful Phase 3 attach (not
    implemented yet) will delete its own processed-staging object once
    promoted to permanent storage, exactly mirroring how
    ``transcode_car_video_source`` deletes its own source object on
    success -- this sweep is strictly the same kind of abandoned-job
    backstop as its Phase 1 sibling above, just with a much longer TTL (see
    ``_PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS``'s docstring).
    """
    from flask import current_app

    from ..media_processing import PROCESSED_VIDEO_STAGING_KEY_PREFIX, _r2_configured

    if not _r2_configured():
        return {"ok": True, "deleted": 0, "skipped": "r2_not_configured"}

    from ..r2_ops import r2_cleanup_stale_staging

    deleted = r2_cleanup_stale_staging(
        prefix=PROCESSED_VIDEO_STAGING_KEY_PREFIX,
        older_than_seconds=_PROCESSED_VIDEO_STAGING_STALE_AFTER_SECONDS,
    )
    if deleted:
        current_app.logger.info(
            "cleanup_stale_processed_video_staging_objects: deleted %d stale staging object(s)",
            deleted,
        )
    return {"ok": True, "deleted": deleted}


@celery_app.task(
    bind=True,
    name="kk.transcode_car_video_source",
    # Operational hardening -- these three are set on THIS task only, not
    # globally (see kk/tasks/celery_app.py; other tasks are not audited for
    # the same idempotency guarantees this one has, see docstring below):
    #   acks_late=True + reject_on_worker_lost=True: if the prefork worker
    #     child running this task is abruptly lost (OOM-killed, crashed,
    #     host/container terminated), the message is requeued instead of
    #     silently dropped. acks_late ALONE does not guarantee this for an
    #     abruptly-killed child -- Celery still acks early in that case
    #     unless reject_on_worker_lost is also set; both are required
    #     together for this specific failure mode.
    #   track_started=True: makes this task's own STARTED-state reporting
    #     explicit/robust at the task level (already implied by the global
    #     task_track_started=True in celery_app.py, but set here too so
    #     this task's contract does not silently depend on that global
    #     never changing).
    # Deliberately NO time_limit/soft_time_limit here -- see the
    # module-level comment above VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS for
    # why a Celery hard time_limit was removed (SIGKILL-orphan risk that
    # made "no overlapping redelivery" unprovable).
    acks_late=True,
    reject_on_worker_lost=True,
    track_started=True,
)
def transcode_car_video_source(
    self, source_staging_key: str, owner_public_id: str, draft_media_id: str
):
    """
    Phase 2: download a Phase-1-staged SOURCE video, validate it, transcode
    it to the normalized output contract (MP4/H.264/<=1920 long edge/
    <=30fps/yuv420p/AAC-if-audio/<100MiB), validate the RESULT, and upload
    it to owner-scoped PROCESSED staging
    (``kk.media_processing.processed_video_staging_key``).

    Inputs are minimal and server-controlled -- ``source_staging_key`` is
    NEVER trusted as-is; it must exactly equal the key this process itself
    reconstructs from ``owner_public_id`` + ``draft_media_id`` (mirroring
    ``finalize_video_source_upload()``'s exact same "reconstruct, don't
    trust" pattern), which is what stops this task from ever being made to
    download/process a foreign/arbitrary R2 key.

    Source-retention policy on failure (documented + tested -- see
    ``kk/tests/test_video_transcode_phase2.py``):
      - Source validation rejects the file (bad duration/dimensions/no
        video stream/oversized download) => the input is PERMANENTLY
        invalid; retrying against the same object can never succeed, so
        the source staging object IS deleted.
      - Any other failure (ffmpeg subprocess crash/timeout, R2 download/
        upload error, missing HDR tone-map capability on this worker
        build, output-contract validation failure after the one allowed
        overshoot retry) is treated as TRANSIENT/environmental -- the
        source object is RETAINED so a future retry (manual re-enqueue, or
        a fixed/redeployed worker) can still succeed from the same
        already-uploaded source, without asking the seller to re-upload.

    Local temp files (downloaded source + encoded output) are always
    removed in a ``finally`` block, success or failure. No partial
    PROCESSED object is ever uploaded -- the upload only happens after the
    encoded output has already passed full contract re-validation.

    Idempotent under redelivery (required by ``acks_late``/
    ``reject_on_worker_lost`` above -- a worker-lost event requeues this
    EXACT same task_id/args to run again from scratch):
      - ``source_staging_key``/``processed_key`` are BOTH deterministically
        re-derived from ``(owner_public_id, draft_media_id)`` on every
        invocation (see ``video_source_staging_key``/
        ``processed_video_staging_key``) -- a redelivered run reconstructs
        the exact same keys, not new ones.
      - The source object is only ever deleted in two places: (a) a
        PERMANENT validation failure, before any encoding starts, or (b)
        after a fully successful upload. If the worker is lost mid-encode
        (the long/expensive part), by construction neither branch has run
        yet, so the source object is still present in R2 for the
        redelivered attempt to download and process again.
      - Re-uploading to the same ``processed_key`` (``r2_put_file``) is a
        plain overwrite (S3/R2 PUT semantics), not a create-only/append
        operation -- a redelivered run's upload safely replaces any
        partial/previous attempt's object at that same key, and Phase 3
        (not implemented yet) will only ever read the final object at that
        key, so no duplicate permanent media can result.
      - The enqueue-time HTTP-layer dedupe (``video_job_dedupe_key`` /
        ``get_idempotent_job_task_id`` in ``kk/job_ownership.py``) prevents
        ``finalize_video_source_upload`` from ever creating a SECOND
        task_id for the same (owner, draft) -- there is only ever one
        logical task_id per draft to begin with.
      - Celery's own broker-level redelivery (triggered by
        ``reject_on_worker_lost`` on an abrupt worker-child loss) re-runs
        that SAME already-enqueued task_id from scratch. Because the
        object keys above are deterministic, that re-run is safe AT THE
        OBJECT-KEY level regardless of how many times it happens.
      - The NORMAL bounded-execution mechanism for the expensive ffmpeg
        step is the plain subprocess timeout
        (``VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS``, 600s) -- ffmpeg is
        terminated and waited on by ``subprocess.run(timeout=...)`` itself
        before this task ever reaches a FAILURE/redelivery decision, so
        the common "ffmpeg is just slow/stuck" case never overlaps with a
        redelivery at all.
      - What this task does NOT prove: that an ffmpeg subprocess is always
        gone before a redelivered attempt starts in the CATASTROPHIC
        worker/container-loss case (OOM kill, host eviction, etc.) that
        ``reject_on_worker_lost`` exists for. Whether the ffmpeg
        grandchild is also reaped in that case is a property of the
        HOSTING ENVIRONMENT (process-group/container teardown killing all
        descendants), not of this application code -- this module makes
        no stronger process-lifetime guarantee than that. This is also
        why the deployed worker needs sufficient RAM headroom above the
        measured ~1.77 GiB peak ffmpeg RSS: a hard Celery time_limit is
        deliberately not used as a substitute resource bound (see above).
      - Given this worker's ``--concurrency=1``, at least no TWO
        redelivered attempts of this task can run inside THIS worker
        process concurrently -- but that says nothing about an ffmpeg
        grandchild left behind by a previous, externally-killed attempt.
      - Normal (non-worker-loss) failures -- e.g. a permanently invalid
        source, or a transient output-validation failure -- are handled by
        Celery as an ordinary single FAILURE state once this function
        raises; ``reject_on_worker_lost`` only affects the abrupt
        process-loss case above, and no automatic retry/``autoretry_for``
        is configured on this task, so a normal handled failure is acked
        exactly once and does NOT loop.
    """
    owner = (owner_public_id or "").strip()
    draft = (draft_media_id or "").strip()
    if owner:
        try:
            self.update_state(
                state="STARTED", meta={"owner_public_id": owner, "draft_media_id": draft}
            )
        except Exception:
            pass

    return _transcode_video_source_impl(
        source_staging_key=source_staging_key,
        owner_public_id=owner_public_id,
        draft_media_id=draft_media_id,
    )


def _transcode_video_source_impl(
    *, source_staging_key: str, owner_public_id: str, draft_media_id: str
) -> dict:
    """The actual download/validate/transcode/validate/upload/cleanup
    pipeline, factored out of ``transcode_car_video_source`` so it can be
    unit-tested directly (mirrors
    ``kk/tasks/image_tasks.py``'s ``_process_image_path`` /
    ``process_car_image_file`` split) without needing Celery's bound-task
    request/backend machinery. See ``transcode_car_video_source``'s
    docstring for the full behavior contract this implements."""
    from .. import video_transcoding as vt
    from ..media_processing import (
        _r2_configured,
        is_valid_draft_media_id,
        processed_video_staging_key,
        video_source_staging_key,
    )

    owner = (owner_public_id or "").strip()
    draft = (draft_media_id or "").strip()

    if not owner or not is_valid_draft_media_id(draft):
        raise VideoTranscodeTaskError("Invalid owner_public_id/draft_media_id")

    expected_source_key = video_source_staging_key(owner, draft)
    if not expected_source_key or expected_source_key != (source_staging_key or "").strip():
        # Never process a key this process did not itself derive -- see
        # docstring. Deliberately the same "reconstruct, compare, reject on
        # mismatch" shape as finalize_video_source_upload()'s 403 branch.
        raise VideoTranscodeTaskError(
            "source_staging_key does not match owner_public_id/draft_media_id"
        )

    if not _r2_configured():
        raise VideoTranscodeTaskError("R2 storage is not configured")

    processed_key = processed_video_staging_key(owner, draft)
    if not processed_key:
        raise VideoTranscodeTaskError("Unable to derive processed staging key")

    tmp_dir = tempfile.mkdtemp(prefix="video_transcode_")
    source_path = os.path.join(tmp_dir, f"source_{uuid4().hex}.bin")
    output_path = os.path.join(tmp_dir, f"output_{uuid4().hex}.mp4")

    source_downloaded = False
    delete_source_on_exit = False
    try:
        from ..r2_ops import r2_get_file

        r2_get_file(key=expected_source_key, dest_path=source_path)
        source_downloaded = True

        actual_size = os.path.getsize(source_path)
        if actual_size > vt.MAX_SOURCE_BYTES:
            delete_source_on_exit = True
            raise VideoTranscodeTaskError(
                f"Downloaded source ({actual_size} bytes) exceeds the "
                f"{vt.MAX_SOURCE_BYTES}-byte cap"
            )

        try:
            source_validation = vt.validate_source_media(source_path)
        except vt.VideoValidationError as e:
            # Structural problem with the source content itself -- see
            # docstring's retention policy. Permanent.
            delete_source_on_exit = True
            raise VideoTranscodeTaskError(str(e)) from e

        caps = vt.probe_ffmpeg_capabilities()
        if not caps.has_libx264 or not caps.has_aac_encoder:
            # Environment/capability failure -- NOT the source's fault.
            raise VideoTranscodeTaskError(
                "Server ffmpeg build is missing a required encoder "
                "(libx264/aac)"
            )
        if source_validation.is_hdr and not caps.supports_hdr_tonemap:
            # Explicit, per spec section 3: never silently relabel HDR as
            # SDR -- refuse instead. Environment/capability failure, not a
            # permanently-invalid source (a capable worker build could
            # still process this exact object later), so the source is
            # retained.
            raise VideoTranscodeTaskError(
                "Server ffmpeg build lacks HDR tone-mapping support "
                "(zscale/tonemap); refusing to transcode an HDR source "
                "rather than produce incorrectly-colored SDR output"
            )

        target_w, target_h = vt.compute_scaled_dimensions(
            source_validation.display_width, source_validation.display_height
        )
        has_audio = source_validation.has_audio
        duration = (
            source_validation.probe.duration_seconds
            or source_validation.primary_video.duration_seconds
            or 0.0
        )
        video_filter = vt.build_video_filter_chain(
            target_width=target_w,
            target_height=target_h,
            is_hdr=source_validation.is_hdr,
        )
        bitrate_bps = vt.compute_target_video_bitrate_bps(duration, has_audio=has_audio)

        def _encode(bps: int) -> None:
            argv = vt.build_transcode_argv(
                ffmpeg_path=caps.ffmpeg_path,
                source_path=source_path,
                output_path=output_path,
                video_filter_chain=video_filter,
                video_bitrate_bps=bps,
                has_audio=has_audio,
            )
            # Explicit, task-local override of vt.run_ffmpeg()'s 180s
            # default -- see VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS's
            # module-level comment for why 180s is too short for this
            # task's real worst-case (~470s) source duration.
            vt.run_ffmpeg(argv, timeout=VIDEO_TRANSCODE_FFMPEG_TIMEOUT_SECONDS)

        _encode(bitrate_bps)

        # Overshoot handling (spec section 5): retry EXACTLY ONCE at a
        # lower bitrate if the raw output size already looks oversized,
        # before ever running the full contract re-validation.
        if os.path.exists(output_path) and os.path.getsize(output_path) >= vt.FINAL_MAX_BYTES:
            retry_bps = vt.compute_overshoot_retry_bitrate_bps(bitrate_bps)
            try:
                os.remove(output_path)
            except OSError:
                pass
            _encode(retry_bps)

        try:
            output_validation = vt.validate_output_media(output_path, expect_audio=has_audio)
        except vt.VideoValidationError as e:
            # Output-contract failure (including still-oversized after the
            # one allowed retry) -- treated as transient/environmental per
            # the docstring's retention policy: the SOURCE passed its own
            # validation, so it is retained rather than deleted.
            raise VideoTranscodeTaskError(str(e)) from e

        from ..r2_ops import r2_put_file

        r2_put_file(key=processed_key, file_path=output_path, content_type="video/mp4")

        # Definitive success -- delete the source staging object now (item
        # 10 of the task's contract). Best-effort: a failure here must not
        # fail the whole task (the seller's processed video already
        # uploaded successfully); the Phase 1 backstop sweep will
        # eventually reclaim an orphaned source object either way.
        try:
            from ..r2_ops import r2_delete_object

            r2_delete_object(key=expected_source_key)
        except Exception:
            logger.warning(
                "transcode_car_video_source: failed to delete source staging "
                "object after a successful transcode (owner=%s); the Phase 1 "
                "backstop sweep will eventually reclaim it",
                owner,
            )

        return {
            "status": "succeeded",
            "processed_staging_key": processed_key,
            "size": output_validation.size_bytes,
            "duration": output_validation.probe.duration_seconds,
            "width": output_validation.video.width,
            "height": output_validation.video.height,
            "fps": output_validation.video.r_frame_rate,
            "video_codec": output_validation.video.codec_name,
            "audio_codec": (
                output_validation.audio.codec_name if output_validation.audio else None
            ),
            "owner_public_id": owner,
            "draft_media_id": draft,
        }
    except Exception:
        if delete_source_on_exit and source_downloaded:
            try:
                from ..r2_ops import r2_delete_object

                r2_delete_object(key=expected_source_key)
            except Exception:
                logger.warning(
                    "transcode_car_video_source: failed to delete a "
                    "permanently-invalid source staging object (owner=%s)",
                    owner,
                )
        raise
    finally:
        # No partial PROCESSED object is ever left behind by THIS
        # process's own local state -- the upload above only ever runs
        # after full output-contract validation already passed. Local
        # temp files (source + output) are always removed here, success or
        # failure.
        for p in (source_path, output_path):
            try:
                if os.path.isfile(p):
                    os.remove(p)
            except OSError:
                pass
        try:
            os.rmdir(tmp_dir)
        except OSError:
            pass
