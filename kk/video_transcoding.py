"""Phase 2 of the server-side video transcode fallback: ffmpeg/ffprobe
provider resolution, structured ffprobe parsing, source/output contract
validation, and ffmpeg command construction.

This module contains ONLY pure/deterministic helpers and thin subprocess
wrappers -- it has no Flask/Celery/R2 dependency of its own, so it can be
unit-tested with subprocess fully mocked. The Celery task that orchestrates
an actual end-to-end transcode job lives in ``kk/tasks/video_tasks.py``.

============================================================================
FFMPEG/FFPROBE PROVIDER
============================================================================
Resolution order (see :func:`resolve_ffmpeg_paths`):
  1. Explicit ``FFMPEG_PATH``/``FFPROBE_PATH`` env vars, if BOTH point at
     existing files -- lets an operator pin a specific system/container
     build without touching this module.
  2. The ``static-ffmpeg`` PyPI package (pinned exact version -- see
     ``kk/requirements.txt``). It ships prebuilt, GPL ffmpeg/ffprobe
     binaries for win32/darwin/darwin_arm64/linux/linux_arm64 and downloads
     them into its own package directory on first use (cached there after
     that -- NOT re-downloaded per call, per process, or per transcode
     job). Chosen over ``imageio-ffmpeg`` specifically because this worker
     design requires STRUCTURED ffprobe JSON output (imageio-ffmpeg only
     ships an ffmpeg binary, no ffprobe).

This module never assumes the resolved build has any particular optional
capability (libx264/aac/zscale/tonemap) -- see :func:`probe_ffmpeg_capabilities`,
which introspects the REAL resolved binary's `-encoders`/`-filters` output
once per worker process and caches the result, rather than assuming a given
package version implies a given feature set on every platform.

============================================================================
HDR / DOLBY VISION
============================================================================
A source whose primary video stream's ``color_transfer`` is SMPTE ST 2084
(PQ, ffprobe name ``smpte2084``) or HLG (ffprobe name ``arib-std-b67``) is
treated as HDR. HDR sources are NEVER merely relabeled as SDR (the exact
mistake this Phase 2 work exists to avoid repeating -- see the Android
``light_compressor_v2`` fork's HDR-metadata-retagging comments for the
prior, deliberately-scoped-differently workaround). Instead, a real
pixel-domain tone-map filter chain (``zscale`` -> linear-light -> ``tonemap``
-> ``zscale`` back to BT.709 SDR) is used -- see
:func:`build_video_filter_chain`. If the resolved ffmpeg build lacks either
``zscale`` or ``tonemap`` (see ``FfmpegCapabilities.supports_hdr_tonemap``),
callers MUST refuse to transcode that source at all (an explicit
``VideoValidationError``/capability failure) rather than silently producing
incorrectly-colored SDR output.
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
import threading
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Output contract constants (Phase 2 spec). These mirror -- but are
# independently defined from -- the Dart-side constants in
# lib/features/sell/sell_video_compression.dart, since that file compresses
# on-device and this module compresses on the server; keeping them as
# separate named constants (not shared code, no Dart<->Python coupling) is
# intentional, not an oversight.
# ---------------------------------------------------------------------------
MAX_LONG_EDGE = 1920
MAX_FPS = 30
MAX_SOURCE_DURATION_SECONDS = 30.0
MAX_SOURCE_BYTES = 500 * 1024 * 1024
# Mirrors the EXISTING, UNRELATED, and UNCHANGED final-listing-video cap
# (kk/routes/media.py::upload_car_videos -> validate_file_upload(max_size_mb=100)).
# This constant exists so the transcoder targets comfortably under that
# limit -- it must never be used to raise/relax what that endpoint accepts.
FINAL_MAX_BYTES = 100 * 1024 * 1024
PREFERRED_VIDEO_BITRATE_BPS = 10_000_000
AUDIO_BITRATE_BPS = 128_000

# When computing a duration-aware max video bitrate, use at most this
# fraction of the total byte budget for encoded (video+audio) payload --
# the rest is headroom for container/moov overhead and general safety
# margin so the ACTUAL encoded file (re-verified by ffprobe afterward, see
# validate_output_media()) lands comfortably under FINAL_MAX_BYTES, not
# exactly at it.
_CONTAINER_OVERHEAD_SAFETY_FACTOR = 0.90

# Never target below this even for a pathologically long duration -- an
# unwatchably low bitrate is not a useful output; compute_target_video_bitrate_bps()
# callers must treat hitting this floor as "duration is too long for this
# byte budget", which cannot happen in practice given the 30s source cap,
# but the floor exists so the function never returns something nonsensical.
_MIN_VIDEO_BITRATE_BPS = 300_000

# Overshoot handling (spec section 5): if the first encode attempt lands
# at/above FINAL_MAX_BYTES, retry EXACTLY ONCE at this fraction of the
# original bitrate, then accept whatever validate_output_media() decides --
# no unbounded retry loop. See kk/tasks/video_tasks.py's orchestration.
OVERSHOOT_RETRY_BITRATE_FACTOR = 0.6

# Operational ceiling on SOURCE resolution, checked BEFORE ffmpeg ever
# attempts to decode a frame, against the RAW ENCODED stream
# width/height (i.e. before any rotation-based display-dimension swap --
# see validate_source_media()). Sized for normal phone 4K video, NOT for
# 8K: the real measured 3840x2160/120fps/10-bit-HDR fixture already peaked
# at ~1.77 GiB ffmpeg RSS on this worker's zscale/tonemap HDR pipeline: an
# 8K-class source could exceed a 4GB worker substantially, and this
# worker's Celery reliability options deliberately do NOT include a hard
# time_limit as a resource backstop (see kk/tasks/video_tasks.py), so this
# input-side bound is the operative safety control instead.
#
# Two independent checks are applied together (both against the raw
# encoded dimensions):
#   MAX_SOURCE_LONG_EDGE: neither raw dimension may exceed this by itself
#     -- catches an oversized/pathological single edge (e.g. 7680x4320).
#   MAX_SOURCE_PIXELS: the raw width*height area may not exceed this even
#     when BOTH individual edges are each <= MAX_SOURCE_LONG_EDGE -- catches
#     a pathological high-area/square input (e.g. 4096x4096) that the
#     long-edge check alone would not reject.
# Together these accept all normal phone 4K orientations/aspect ratios
# (3840x2160, 2160x3840, 4096x2160, 2160x4096, 4096x2304, ...) while
# rejecting 8K-class and pathological square/high-area sources.
MAX_SOURCE_LONG_EDGE = 4096
MAX_SOURCE_PIXELS = 4096 * 2304

# ffprobe's color_transfer values for SMPTE ST 2084 (PQ) and HLG.
_HDR_TRANSFER_FUNCTIONS = frozenset({"smpte2084", "arib-std-b67"})


class FfmpegUnavailableError(RuntimeError):
    """Neither an explicit FFMPEG_PATH/FFPROBE_PATH override nor the
    bundled static-ffmpeg provider produced two working executables."""


class VideoValidationError(RuntimeError):
    """User-safe, durable validation failure (bad source OR bad output).

    Message text must never leak internal paths or stack traces -- it is
    safe to store verbatim as a Celery task's failure reason and eventually
    surface to a client.
    """


class TranscodeError(RuntimeError):
    """The ffmpeg subprocess itself failed (non-zero exit or timeout) --
    distinct from VideoValidationError (bad input/output CONTRACT) so
    callers can log/handle the two cases differently if useful."""


# ---------------------------------------------------------------------------
# Provider resolution (once per worker process)
# ---------------------------------------------------------------------------

_resolve_lock = threading.Lock()
_resolved_paths: tuple[str, str] | None = None


def resolve_ffmpeg_paths() -> tuple[str, str]:
    """
    Resolve absolute paths to ``(ffmpeg, ffprobe)``, once per worker
    process (cached in a module-level variable guarded by a lock -- safe
    under Celery's prefork/threaded worker pools).

    Resolution order:
      1. ``FFMPEG_PATH``/``FFPROBE_PATH`` env vars, if BOTH are set and
         point at existing files.
      2. The bundled ``static-ffmpeg`` package -- downloads its platform
         binaries on first use; that download itself is cached by the
         package on disk, and this function additionally caches the
         resolved paths for the remaining lifetime of this process, so a
         transcode task never re-triggers resolution/download work.

    Raises :class:`FfmpegUnavailableError` if neither path resolves to two
    real, existing files. This function does NOT check for any OPTIONAL
    capability (libx264/aac/zscale/tonemap) -- see
    :func:`probe_ffmpeg_capabilities` for that.
    """
    global _resolved_paths
    with _resolve_lock:
        if _resolved_paths is not None:
            return _resolved_paths

        env_ffmpeg = (os.environ.get("FFMPEG_PATH") or "").strip()
        env_ffprobe = (os.environ.get("FFPROBE_PATH") or "").strip()
        if env_ffmpeg and env_ffprobe:
            if not (os.path.isfile(env_ffmpeg) and os.path.isfile(env_ffprobe)):
                raise FfmpegUnavailableError(
                    "FFMPEG_PATH/FFPROBE_PATH are set but do not both point "
                    "at existing files."
                )
            _resolved_paths = (env_ffmpeg, env_ffprobe)
            return _resolved_paths

        try:
            from static_ffmpeg import run as _static_ffmpeg_run
        except ImportError as e:
            raise FfmpegUnavailableError(
                "Neither FFMPEG_PATH/FFPROBE_PATH nor the static-ffmpeg "
                "package are available. Install static-ffmpeg (see "
                "kk/requirements.txt) or set both env vars to an existing "
                "ffmpeg/ffprobe build."
            ) from e

        try:
            ffmpeg_path, ffprobe_path = (
                _static_ffmpeg_run.get_or_fetch_platform_executables_else_raise()
            )
        except Exception as e:
            raise FfmpegUnavailableError(
                f"static-ffmpeg could not resolve/fetch ffmpeg/ffprobe binaries: {e}"
            ) from e

        if not (os.path.isfile(ffmpeg_path) and os.path.isfile(ffprobe_path)):
            raise FfmpegUnavailableError(
                "static-ffmpeg reported ffmpeg/ffprobe paths that do not "
                "exist on disk."
            )
        _resolved_paths = (str(ffmpeg_path), str(ffprobe_path))
        return _resolved_paths


def reset_resolved_paths_for_tests() -> None:
    """Test-only: drop the cached resolved paths so resolution runs again."""
    global _resolved_paths
    with _resolve_lock:
        _resolved_paths = None


# ---------------------------------------------------------------------------
# Capability probing (once per worker process)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class FfmpegCapabilities:
    ffmpeg_path: str
    ffprobe_path: str
    ffmpeg_version: str
    ffprobe_version: str
    has_libx264: bool
    has_aac_encoder: bool
    has_zscale_filter: bool
    has_tonemap_filter: bool

    @property
    def supports_hdr_tonemap(self) -> bool:
        """Both ``zscale`` AND ``tonemap`` are required for the real
        pixel-domain HDR->SDR pipeline this module uses (see
        :func:`build_video_filter_chain`)."""
        return self.has_zscale_filter and self.has_tonemap_filter

    def as_report_dict(self) -> dict:
        return {
            "ffmpeg_version": self.ffmpeg_version,
            "ffprobe_version": self.ffprobe_version,
            "has_libx264": self.has_libx264,
            "has_aac_encoder": self.has_aac_encoder,
            "has_zscale_filter": self.has_zscale_filter,
            "has_tonemap_filter": self.has_tonemap_filter,
            "supports_hdr_tonemap": self.supports_hdr_tonemap,
        }


_capabilities_cache: FfmpegCapabilities | None = None
_capabilities_lock = threading.Lock()

_LIBX264_ENCODER_RE = re.compile(r"(?m)^\s*V[.\w]*\s+libx264\s")
_AAC_ENCODER_RE = re.compile(r"(?m)^\s*A[.\w]*\s+aac\s")
_ZSCALE_FILTER_RE = re.compile(r"(?m)^\s*\S*\s+zscale\s")
# Deliberately requires whitespace right after "tonemap" so this does not
# also match "tonemap_vaapi" (a different, VAAPI-hardware-only filter this
# module does not use).
_TONEMAP_FILTER_RE = re.compile(r"(?m)^\s*\S*\s+tonemap\s")


def _run_capture(argv: list[str], *, timeout: float = 20) -> str:
    proc = subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )
    return (proc.stdout or b"").decode("utf-8", errors="replace")


def _first_line(text: str) -> str:
    return (text.splitlines() or [""])[0].strip()


def probe_ffmpeg_capabilities(*, force_refresh: bool = False) -> FfmpegCapabilities:
    """
    Resolve + introspect the ffmpeg/ffprobe build once per worker process
    (cached; pass ``force_refresh=True`` only from tests). Each of
    ``-version``/``-encoders``/``-filters`` is one cheap subprocess call
    made at most once per process -- never repeated per transcode job.
    """
    global _capabilities_cache
    with _capabilities_lock:
        if _capabilities_cache is not None and not force_refresh:
            return _capabilities_cache

        ffmpeg_path, ffprobe_path = resolve_ffmpeg_paths()

        ffmpeg_version = _first_line(_run_capture([ffmpeg_path, "-version"]))
        ffprobe_version = _first_line(_run_capture([ffprobe_path, "-version"]))
        encoders_out = _run_capture([ffmpeg_path, "-hide_banner", "-encoders"])
        filters_out = _run_capture([ffmpeg_path, "-hide_banner", "-filters"])

        caps = FfmpegCapabilities(
            ffmpeg_path=ffmpeg_path,
            ffprobe_path=ffprobe_path,
            ffmpeg_version=ffmpeg_version,
            ffprobe_version=ffprobe_version,
            has_libx264=bool(_LIBX264_ENCODER_RE.search(encoders_out)),
            has_aac_encoder=bool(_AAC_ENCODER_RE.search(encoders_out)),
            has_zscale_filter=bool(_ZSCALE_FILTER_RE.search(filters_out)),
            has_tonemap_filter=bool(_TONEMAP_FILTER_RE.search(filters_out)),
        )
        _capabilities_cache = caps
        return caps


def reset_capabilities_for_tests() -> None:
    global _capabilities_cache
    with _capabilities_lock:
        _capabilities_cache = None


# ---------------------------------------------------------------------------
# Structured ffprobe
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ProbedStream:
    codec_type: str
    codec_name: str | None
    width: int | None
    height: int | None
    r_frame_rate: float | None
    duration_seconds: float | None
    color_transfer: str | None
    color_primaries: str | None
    color_space: str | None
    rotation_degrees: int = 0


@dataclass(frozen=True)
class ProbedMedia:
    format_name: str | None
    duration_seconds: float | None
    size_bytes: int | None
    streams: list[ProbedStream] = field(default_factory=list)

    @property
    def video_streams(self) -> list[ProbedStream]:
        return [s for s in self.streams if s.codec_type == "video"]

    @property
    def audio_streams(self) -> list[ProbedStream]:
        return [s for s in self.streams if s.codec_type == "audio"]

    @property
    def primary_video(self) -> ProbedStream | None:
        streams = self.video_streams
        return streams[0] if streams else None

    @property
    def has_audio(self) -> bool:
        return bool(self.audio_streams)


def _safe_float(v) -> float | None:
    try:
        if v is None:
            return None
        return float(v)
    except (TypeError, ValueError):
        return None


def _safe_int(v) -> int | None:
    try:
        if v is None:
            return None
        return int(float(v))
    except (TypeError, ValueError):
        return None


def _parse_frame_rate(raw) -> float | None:
    if not raw:
        return None
    raw = str(raw)
    if "/" in raw:
        num, _, den = raw.partition("/")
        n, d = _safe_float(num), _safe_float(den)
        if n is None or not d:
            return None
        return n / d
    return _safe_float(raw)


def _extract_rotation(stream: dict) -> int:
    """Rotation MAGNITUDE, in degrees (one of 0/90/180/270), needed to
    display this stream correctly.

    Checked in two places, mirroring what real MOV/MP4 files from
    different pipelines actually use: the classic ``tags.rotate`` string
    tag, and the modern ``side_data_list`` display-matrix entry (which
    ffprobe surfaces as a signed ``rotation`` key, e.g. ``-90``, once it
    has already decoded the matrix for us).

    Deliberately returns ``abs(value) % 360`` rather than trying to also
    preserve clockwise-vs-counterclockwise sign: the only thing this
    module needs the rotation for is deciding whether the DISPLAY
    width/height are swapped relative to the stored width/height (true
    for 90/270, false for 0/180) so :func:`compute_scaled_dimensions` can
    size the ``-vf scale=`` filter correctly. The actual pixel rotation
    itself is applied automatically by ffmpeg's decoder (``-autorotate``
    is on by default) before any user ``-vf`` filter runs -- this module
    never applies its own ``transpose``, which would double-rotate.
    """
    tags = stream.get("tags") or {}
    raw = tags.get("rotate")
    if raw is not None:
        v = _safe_int(raw)
        if v is not None:
            return abs(v) % 360
    for sd in stream.get("side_data_list") or []:
        if isinstance(sd, dict) and "rotation" in sd:
            v = _safe_int(sd.get("rotation"))
            if v is not None:
                return abs(v) % 360
    return 0


def _parse_probe_json(data: dict) -> ProbedMedia:
    fmt = data.get("format") or {}
    fmt_duration = _safe_float(fmt.get("duration"))
    streams: list[ProbedStream] = []
    for s in data.get("streams") or []:
        streams.append(
            ProbedStream(
                codec_type=str(s.get("codec_type") or ""),
                codec_name=s.get("codec_name"),
                width=_safe_int(s.get("width")),
                height=_safe_int(s.get("height")),
                r_frame_rate=_parse_frame_rate(s.get("r_frame_rate")),
                duration_seconds=_safe_float(s.get("duration")) or fmt_duration,
                color_transfer=s.get("color_transfer"),
                color_primaries=s.get("color_primaries"),
                color_space=s.get("color_space"),
                rotation_degrees=_extract_rotation(s),
            )
        )
    return ProbedMedia(
        format_name=fmt.get("format_name"),
        duration_seconds=fmt_duration,
        size_bytes=_safe_int(fmt.get("size")),
        streams=streams,
    )


def ffprobe_media(path: str, *, timeout: float = 30) -> ProbedMedia:
    """
    Run ``ffprobe -show_format -show_streams -of json`` and parse the
    structured JSON stdout. NEVER parses ffprobe's human-readable stderr
    text for any decision -- stderr is only ever logged (see callers), not
    inspected for content.
    """
    _ffmpeg_path, ffprobe_path = resolve_ffmpeg_paths()
    argv = [
        ffprobe_path,
        "-v",
        "error",
        "-show_format",
        "-show_streams",
        "-of",
        "json",
        path,
    ]
    try:
        proc = subprocess.run(
            argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False
        )
    except subprocess.TimeoutExpired as e:
        raise VideoValidationError("ffprobe timed out") from e

    if proc.returncode != 0:
        logger.info(
            "ffprobe exited %s for a probed file (stderr not parsed for logic, "
            "logged for diagnostics only)",
            proc.returncode,
        )
        raise VideoValidationError("File could not be probed as media (ffprobe failed)")

    try:
        data = json.loads((proc.stdout or b"").decode("utf-8", errors="replace"))
    except json.JSONDecodeError as e:
        raise VideoValidationError("ffprobe produced invalid JSON output") from e

    if not isinstance(data, dict):
        raise VideoValidationError("ffprobe produced unexpected JSON output")

    return _parse_probe_json(data)


# ---------------------------------------------------------------------------
# Source validation
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class SourceValidation:
    probe: ProbedMedia
    primary_video: ProbedStream
    is_hdr: bool
    rotation_degrees: int
    display_width: int
    display_height: int
    has_audio: bool


def validate_source_media(path: str, *, max_bytes: int = MAX_SOURCE_BYTES) -> SourceValidation:
    """
    Authoritative SOURCE validation. Must run AFTER download to local
    disk, BEFORE any ffmpeg decode/transcode attempt. Never trusts the
    file extension or the R2-declared Content-Type as proof this is
    actually a video -- that limitation was already documented in Phase 1
    (``sign_video_source_upload``/``finalize_video_source_upload``'s
    docstrings); this is the authoritative check Phase 1 deferred to here.
    """
    try:
        actual_bytes = os.path.getsize(path)
    except OSError as e:
        raise VideoValidationError("Source file is not accessible") from e
    if actual_bytes <= 0:
        raise VideoValidationError("Source file is empty")
    if actual_bytes > max_bytes:
        raise VideoValidationError(
            f"Source file exceeds the {max_bytes}-byte cap (actual={actual_bytes})"
        )

    probe = ffprobe_media(path)
    video = probe.primary_video
    if video is None:
        raise VideoValidationError("Source has no video stream")

    duration = probe.duration_seconds or video.duration_seconds
    if duration is None or duration <= 0:
        raise VideoValidationError("Source duration is missing or not positive")
    if duration > MAX_SOURCE_DURATION_SECONDS:
        raise VideoValidationError(
            f"Source duration {duration:.2f}s exceeds the "
            f"{MAX_SOURCE_DURATION_SECONDS}s cap"
        )

    # Checked against the RAW ENCODED width/height (not yet rotation-swapped
    # -- see below for the separate display-dimension computation used for
    # scaling/rendering, not for this input-side safety bound).
    width, height = video.width, video.height
    if not width or not height or width <= 0 or height <= 0:
        raise VideoValidationError("Source video dimensions are missing or not positive")
    if width > MAX_SOURCE_LONG_EDGE or height > MAX_SOURCE_LONG_EDGE:
        raise VideoValidationError(
            f"Source resolution {width}x{height} exceeds the maximum "
            f"supported edge length ({MAX_SOURCE_LONG_EDGE}px)"
        )
    if width * height > MAX_SOURCE_PIXELS:
        raise VideoValidationError(
            f"Source resolution {width}x{height} ({width * height} px) exceeds "
            f"the maximum supported pixel count ({MAX_SOURCE_PIXELS} px)"
        )

    rotation = video.rotation_degrees
    display_width, display_height = (
        (height, width) if rotation in (90, 270) else (width, height)
    )

    is_hdr = (video.color_transfer or "").strip().lower() in _HDR_TRANSFER_FUNCTIONS

    return SourceValidation(
        probe=probe,
        primary_video=video,
        is_hdr=is_hdr,
        rotation_degrees=rotation,
        display_width=display_width,
        display_height=display_height,
        has_audio=probe.has_audio,
    )


# ---------------------------------------------------------------------------
# Bitrate / dimension planning
# ---------------------------------------------------------------------------


def _evenize(v: int) -> int:
    return v - 1 if v % 2 else v


def compute_scaled_dimensions(
    width: int, height: int, *, max_long_edge: int = MAX_LONG_EDGE
) -> tuple[int, int]:
    """
    Scale ``(width, height)`` (already the DISPLAY-orientation dimensions
    -- see ``SourceValidation.display_width/height``) so the long edge is
    ``<= max_long_edge``, preserving aspect ratio, rounded to even numbers
    (H.264 requires even dimensions). Never upscales.
    """
    long_edge = max(width, height)
    scale = 1.0 if long_edge <= max_long_edge else max_long_edge / long_edge
    new_w = _evenize(max(2, round(width * scale)))
    new_h = _evenize(max(2, round(height * scale)))
    return new_w, new_h


def compute_target_video_bitrate_bps(
    duration_seconds: float,
    *,
    has_audio: bool,
    final_max_bytes: int = FINAL_MAX_BYTES,
    preferred_bps: int = PREFERRED_VIDEO_BITRATE_BPS,
) -> int:
    """
    Duration-aware max VIDEO bitrate so the final MP4 cannot reasonably
    exceed ``final_max_bytes`` -- reserves room for audio, container/moov
    overhead, and a safety margin (``_CONTAINER_OVERHEAD_SAFETY_FACTOR``),
    then also caps at ``preferred_bps`` (~10Mbps) so a very short clip
    doesn't get an absurdly high bitrate just because the byte budget
    allows it.
    """
    if duration_seconds <= 0:
        return _MIN_VIDEO_BITRATE_BPS
    audio_bps = AUDIO_BITRATE_BPS if has_audio else 0
    total_budget_bits = final_max_bytes * 8 * _CONTAINER_OVERHEAD_SAFETY_FACTOR
    video_budget_bps = (total_budget_bits / duration_seconds) - audio_bps
    video_budget_bps = max(video_budget_bps, _MIN_VIDEO_BITRATE_BPS)
    return int(min(video_budget_bps, preferred_bps))


def compute_overshoot_retry_bitrate_bps(previous_bitrate_bps: int) -> int:
    """The single, deterministic retry bitrate used after a first encode
    attempt lands at/above ``FINAL_MAX_BYTES`` -- see
    ``OVERSHOOT_RETRY_BITRATE_FACTOR``."""
    return max(
        int(previous_bitrate_bps * OVERSHOOT_RETRY_BITRATE_FACTOR),
        _MIN_VIDEO_BITRATE_BPS,
    )


# ---------------------------------------------------------------------------
# ffmpeg command construction
# ---------------------------------------------------------------------------


def build_video_filter_chain(
    *,
    target_width: int,
    target_height: int,
    is_hdr: bool,
    fps: int = MAX_FPS,
) -> str:
    """
    Build the ``-vf`` filter-chain string.

    SDR source: scale + fps cap + ``yuv420p`` only -- no unnecessary
    tone-mapping (spec section 3: "For normal SDR sources: do not
    unnecessarily tone-map").

    HDR source (PQ/HLG): a REAL pixel-domain tone-map pipeline --
    ``zscale`` to a linear-light intermediate, ``tonemap`` (Hable operator)
    to actually compress the dynamic range, then ``zscale`` back to
    BT.709/SDR/limited-range. This never merely relabels HDR metadata as
    SDR (the exact mistake this Phase 2 work exists to avoid repeating).

    OOM-fix (real 4K/120fps HDR device repro): ``scale``/``fps`` run
    FIRST here, BEFORE the zscale/tonemap chain -- NOT after, as a
    prior revision had it. The float32 linear-light intermediate this
    chain uses (``format=gbrpf32le``: 3 channels * 4 bytes, unsubsampled)
    is what actually drove this worker's OOM: at native 4K
    (3840x2160) that is ~95 MiB for a SINGLE frame, and ffmpeg's
    filter-graph threading can have several such frames in flight at
    once (measured ~1.77 GiB peak ffmpeg RSS on the real repro fixture --
    see ``kk/tasks/video_tasks.py``'s module-level comment). Running
    ``scale``/``fps`` first shrinks BOTH the per-frame size (by the same
    ratio the OUTPUT contract already downscales by -- >=4x for a 4K
    source going to the <=1920 long-edge cap) and the number of frames
    per second (120fps source -> <=30fps here, so ~4x fewer frames ever
    reach the expensive stage) that the linear-light/tonemap stage has
    to touch at all. ``zscale``/``tonemap`` are per-pixel (pointwise)
    operations -- applying them to a smaller, already-decimated frame
    does not change what the OUTPUT CONTRACT promises (still a real
    pixel-domain PQ/HLG -> BT.709 conversion, never a metadata relabel),
    only how much data that conversion has to process. Verified against
    a real ffmpeg build (manual smoke test + this module's own
    ``kk/tests/test_video_transcoding_real_ffmpeg_integration.py``) to
    still produce a valid, output-contract-passing result -- and
    measurably faster, since far fewer pixels flow through the float32
    stage.

    Callers MUST have already confirmed
    ``FfmpegCapabilities.supports_hdr_tonemap`` is ``True`` before calling
    this with ``is_hdr=True`` -- this function has no access to the
    capability probe result and does not check it itself; it only builds a
    filter string, which would simply fail at ffmpeg-run time (loudly, as a
    ``TranscodeError``) on a build missing ``zscale``/``tonemap``.
    """
    scale_filter = f"scale={target_width}:{target_height}"
    fps_filter = f"fps={fps}"
    if not is_hdr:
        return f"{scale_filter},{fps_filter},format=yuv420p"

    return (
        f"{scale_filter},{fps_filter},"
        "zscale=t=linear:npl=100,"
        "format=gbrpf32le,"
        "zscale=p=bt709,"
        "tonemap=tonemap=hable:desat=0,"
        "zscale=t=bt709:m=bt709:r=tv,"
        "format=yuv420p"
    )


# OOM-fix: conservative, explicit thread cap applied uniformly to
# decode/filter/encode (see build_transcode_argv's docstring for exactly
# WHERE each of the three placements below applies). This worker
# (carr-worker-fra) runs at 0.5 CPU on Render -- ffmpeg's own automatic
# thread-count autodetection is based on the number of CPUs the
# container's kernel reports, which is commonly the HOST's full logical
# core count (cgroup CPU-share limits like "0.5 CPU" are not the same
# thing as a reduced CPU_COUNT for this purpose), not the fractional
# entitlement actually available. Extra decoder/filter/encoder threads on
# an instance this small mean extra concurrent per-thread frame
# buffers/lookahead -- i.e. more PEAK MEMORY -- without any real
# parallelism gain (there is less than 1 physical core to share), which
# is exactly the mechanism behind this worker's measured ~1.77 GiB peak
# ffmpeg RSS OOM. Previously only the ENCODER thread count was set
# (``-threads 2`` after ``-c:v``); the decoder and the ``-vf``
# filter-graph were left on ffmpeg's own autodetection.
SERVER_TRANSCODE_THREADS = 1


def build_transcode_argv(
    *,
    ffmpeg_path: str,
    source_path: str,
    output_path: str,
    video_filter_chain: str,
    video_bitrate_bps: int,
    has_audio: bool,
    threads: int = SERVER_TRANSCODE_THREADS,
) -> list[str]:
    """
    Build the ffmpeg argv list for one transcode attempt. Always a plain
    list of arguments -- NEVER a shell string, and NEVER shell=True at the
    call site (see :func:`run_ffmpeg`). Every value here is either a fixed
    literal or a number/string this module itself computed
    (filter chain, bitrate, paths already resolved server-side) -- no
    argument is ever built from an arbitrary user-provided filter/command
    string.

    ``threads`` (default :data:`SERVER_TRANSCODE_THREADS`, 1) is applied
    at THREE separate places, each governing a DIFFERENT ffmpeg thread
    pool -- setting only one would leave the others on ffmpeg's own
    (memory-hungry, on this worker's 0.5-CPU instance) autodetection:
      - ``-filter_threads``/``-filter_complex_threads`` (GLOBAL options,
        so placed before ``-i``): bound the ``-vf`` filter-graph's own
        thread pool. This module only ever builds a SIMPLE filtergraph
        (``-vf``, never ``-filter_complex`` -- see
        :func:`build_video_filter_chain`), so ``-filter_complex_threads``
        is a documented no-op for this module's own pipeline today; it is
        set anyway (harmless -- ffmpeg ignores it when ``-filter_complex``
        is not used) so this stays correct if a future caller ever adds
        one.
      - ``-threads`` BEFORE ``-i`` (an INPUT-file option): bounds the
        SOURCE DECODER's thread count. Must be placed before ``-i`` --
        ffmpeg attaches a per-file ``-threads`` value to whichever
        file/stream context follows it, so a bare ``-threads`` placed
        after ``-i`` would not affect the decoder.
      - ``-threads`` AFTER ``-c:v libx264`` (an OUTPUT/per-stream
        option): bounds the ENCODER's (libx264's own) thread count --
        ffmpeg's libx264 wrapper maps this directly onto libx264's own
        ``threads`` parameter, so no separate ``-x264-params threads=``
        is needed to also constrain libx264 specifically. This is the
        one placement the PRIOR revision already had (with a default of
        2, now 1).
    Using both an input-side and an output-side ``-threads`` in the same
    command (two different attachment points, not a conflicting
    duplicate) is valid ffmpeg usage -- verified against a real,
    resolved ffmpeg build (manual smoke test) before this change was
    made.
    """
    argv = [
        ffmpeg_path,
        "-y",
        "-nostdin",
        "-filter_threads",
        str(threads),
        "-filter_complex_threads",
        str(threads),
        "-threads",
        str(threads),
        "-i",
        source_path,
        "-map",
        "0:v:0",
    ]
    if has_audio:
        argv += ["-map", "0:a:0?"]
    argv += [
        "-vf",
        video_filter_chain,
        "-c:v",
        "libx264",
        "-profile:v",
        "high",
        "-pix_fmt",
        "yuv420p",
        "-b:v",
        str(video_bitrate_bps),
        "-maxrate",
        str(int(video_bitrate_bps * 1.2)),
        "-bufsize",
        str(int(video_bitrate_bps * 2)),
        "-threads",
        str(threads),
        "-movflags",
        "+faststart",
    ]
    if has_audio:
        argv += ["-c:a", "aac", "-b:a", str(AUDIO_BITRATE_BPS)]
    else:
        argv += ["-an"]
    argv.append(output_path)
    return argv


def run_ffmpeg(argv: list[str], *, timeout: float = 180) -> None:
    """
    Run one ffmpeg command to completion. NEVER uses ``shell=True`` --
    ``argv`` is always a plain argument list.

    Raises :class:`TranscodeError` on a non-zero exit or timeout. ffmpeg's
    stderr is logged (truncated) for operator diagnostics only -- it is
    NEVER parsed to make any pass/fail decision; that decision is made
    exclusively from the process exit code here, and from structured
    ffprobe JSON afterward (see :func:`validate_output_media`).
    """
    try:
        proc = subprocess.run(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as e:
        raise TranscodeError(f"ffmpeg timed out after {timeout}s") from e

    if proc.returncode != 0:
        stderr_tail = (proc.stderr or b"").decode("utf-8", errors="replace")[-2000:]
        logger.warning("ffmpeg exited %s; stderr tail: %s", proc.returncode, stderr_tail)
        raise TranscodeError(f"ffmpeg exited with status {proc.returncode}")


# ---------------------------------------------------------------------------
# Output validation
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class OutputValidation:
    probe: ProbedMedia
    video: ProbedStream
    audio: ProbedStream | None
    size_bytes: int


def validate_output_media(
    path: str, *, expect_audio: bool, max_bytes: int = FINAL_MAX_BYTES
) -> OutputValidation:
    """
    Authoritative OUTPUT validation -- run AFTER encode, BEFORE ever
    uploading the result anywhere. Never trusts the encoder settings that
    were REQUESTED (``build_transcode_argv``'s arguments) as proof of what
    was actually produced; every check here is against the ACTUAL encoded
    file, re-probed from scratch.
    """
    try:
        size_bytes = os.path.getsize(path)
    except OSError as e:
        raise VideoValidationError("Encoded output is not accessible") from e
    if size_bytes <= 0:
        raise VideoValidationError("Encoded output is empty")

    probe = ffprobe_media(path)
    video = probe.primary_video
    if video is None:
        raise VideoValidationError("Encoded output has no video stream")
    if (video.codec_name or "").lower() != "h264":
        raise VideoValidationError(
            f"Encoded output codec is {video.codec_name!r}, expected h264"
        )

    width, height = video.width, video.height
    if not width or not height:
        raise VideoValidationError("Encoded output dimensions are missing")
    if max(width, height) > MAX_LONG_EDGE + 2:
        raise VideoValidationError(
            f"Encoded output long edge {max(width, height)} exceeds the "
            f"{MAX_LONG_EDGE} cap"
        )

    fps = video.r_frame_rate
    if fps is not None and fps > MAX_FPS + 0.5:
        raise VideoValidationError(
            f"Encoded output frame rate {fps} exceeds the {MAX_FPS} cap"
        )

    duration = probe.duration_seconds or video.duration_seconds
    if duration is None or duration <= 0:
        raise VideoValidationError("Encoded output duration is missing or not positive")

    audio = probe.audio_streams[0] if probe.audio_streams else None
    if expect_audio:
        if audio is None:
            raise VideoValidationError(
                "Encoded output is missing the expected audio stream"
            )
        if (audio.codec_name or "").lower() != "aac":
            raise VideoValidationError(
                f"Encoded output audio codec is {audio.codec_name!r}, expected aac"
            )
    else:
        if audio is not None:
            raise VideoValidationError(
                "Encoded output has an unexpected audio stream (source had none)"
            )

    if size_bytes >= max_bytes:
        raise VideoValidationError(
            f"Encoded output size {size_bytes} is not below the "
            f"{max_bytes}-byte final cap"
        )

    return OutputValidation(probe=probe, video=video, audio=audio, size_bytes=size_bytes)
