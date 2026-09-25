"""Phase 2 of the server-side video transcode fallback: ONE optional, local
integration test that exercises ``kk/video_transcoding.py`` against a REAL
ffmpeg/ffprobe build (resolved via ``static-ffmpeg``, same as production).

Every other test file in this suite (``test_video_transcoding_module.py``,
``test_video_transcode_phase2.py``) mocks subprocess/R2 entirely and never
needs a real binary. This file is the deliberate exception -- it actually
invokes ffmpeg to transcode two small SYNTHETIC clips (SDR + HDR/PQ) it
generates itself with ffmpeg, and asserts the real, re-probed output
contract.

NOTE ON THE REAL DEVICE REPRO FILE: the spec for this phase asked to run
the exact 112,329,351-byte Samsung(-labeled)/iPhone Dolby Vision MOV
(from an earlier diagnostic session) through this pipeline if still
available. It was NOT available in that earlier session -- no cached
local copy remained. It HAS since been recovered (byte size and SHA-256
both verified to match exactly) and was manually run through this real
production pipeline end-to-end, on both Windows and a Linux (WSL Ubuntu
24.04, static-ffmpeg==3.0) environment, with successful output-contract
validation and visual/audio acceptance. See ``TestRealDolbyReproFixture``
below for the corresponding *optional*, env-gated regression test that
exercises this exact fixture. The 112MB file itself is never committed to
git (see ``.gitignore``) and is not bundled with this repo -- the test
skips whenever the env var pointing at it is unset or the file is
missing, so it never runs in CI or on a fresh checkout.

Deliberately skipped (not failed) when no ffmpeg/ffprobe build can be
resolved at all, so this file never breaks a CI/dev environment that has
neither ``static-ffmpeg`` installed nor ``FFMPEG_PATH``/``FFPROBE_PATH``
set.
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import kk.video_transcoding as vt  # noqa: E402


def _ffmpeg_available() -> tuple[str, str] | None:
    try:
        return vt.resolve_ffmpeg_paths()
    except vt.FfmpegUnavailableError:
        return None


_RESOLVED = _ffmpeg_available()

pytestmark = pytest.mark.skipif(
    _RESOLVED is None,
    reason="No ffmpeg/ffprobe build available (install static-ffmpeg, or "
    "set FFMPEG_PATH/FFPROBE_PATH) -- this integration test is optional.",
)


@pytest.fixture(scope="module")
def tmp_dir():
    with tempfile.TemporaryDirectory(prefix="vt_real_ffmpeg_") as d:
        yield d


def _make_sdr_source(ffmpeg_path: str, out_path: str) -> None:
    argv = [
        ffmpeg_path,
        "-y",
        "-f",
        "lavfi",
        "-i",
        "testsrc2=size=640x360:rate=30:duration=2",
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=440:duration=2",
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        out_path,
    ]
    subprocess.run(argv, check=True, capture_output=True, timeout=30)


def _make_hdr_source(ffmpeg_path: str, out_path: str) -> bool:
    """Returns False (and does not create the file) if this ffmpeg build
    cannot encode HEVC Main10 -- some minimal builds may lack libx265."""
    argv = [
        ffmpeg_path,
        "-y",
        "-f",
        "lavfi",
        "-i",
        "gradients=size=640x360:rate=30:duration=2:c0=black:c1=white",
        "-vf",
        "format=yuv420p10le",
        "-c:v",
        "libx265",
        "-pix_fmt",
        "yuv420p10le",
        "-color_primaries",
        "bt2020",
        "-color_trc",
        "smpte2084",
        "-colorspace",
        "bt2020nc",
        # The plain -color_primaries/-color_trc/-colorspace options above
        # are not always sufficient by themselves to make libx265 actually
        # write PQ/BT.2020 VUI metadata into the encoded stream (observed
        # empirically -- some resolutions/builds silently drop them);
        # -x265-params reliably forces it, which is what this test needs
        # ffprobe to read back.
        "-x265-params",
        "hdr10=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc",
        out_path,
    ]
    proc = subprocess.run(argv, capture_output=True, timeout=30)
    return proc.returncode == 0 and os.path.isfile(out_path)


class TestRealFfmpegSdrPipeline:
    def test_sdr_source_transcodes_to_contract(self, tmp_dir):
        ffmpeg_path, _ffprobe_path = _RESOLVED
        source_path = os.path.join(tmp_dir, "sdr_source.mp4")
        _make_sdr_source(ffmpeg_path, source_path)

        caps = vt.probe_ffmpeg_capabilities()
        assert caps.has_libx264, "static-ffmpeg build must have libx264"
        assert caps.has_aac_encoder, "static-ffmpeg build must have an AAC encoder"

        sv = vt.validate_source_media(source_path)
        assert sv.is_hdr is False
        assert sv.has_audio is True

        target_w, target_h = vt.compute_scaled_dimensions(sv.display_width, sv.display_height)
        duration = sv.probe.duration_seconds or sv.primary_video.duration_seconds or 0.0
        vf = vt.build_video_filter_chain(
            target_width=target_w, target_height=target_h, is_hdr=False
        )
        bitrate = vt.compute_target_video_bitrate_bps(duration, has_audio=True)

        out_path = os.path.join(tmp_dir, "sdr_out.mp4")
        argv = vt.build_transcode_argv(
            ffmpeg_path=caps.ffmpeg_path,
            source_path=source_path,
            output_path=out_path,
            video_filter_chain=vf,
            video_bitrate_bps=bitrate,
            has_audio=True,
        )
        vt.run_ffmpeg(argv, timeout=60)

        ov = vt.validate_output_media(out_path, expect_audio=True)
        assert ov.video.codec_name == "h264"
        assert ov.audio.codec_name == "aac"
        assert max(ov.video.width, ov.video.height) <= vt.MAX_LONG_EDGE
        assert ov.size_bytes < vt.FINAL_MAX_BYTES


class TestRealFfmpegHdrPipeline:
    def test_hdr_pq_source_is_detected_and_real_tonemap_applied(self, tmp_dir):
        ffmpeg_path, _ffprobe_path = _RESOLVED
        source_path = os.path.join(tmp_dir, "hdr_source.mp4")
        if not _make_hdr_source(ffmpeg_path, source_path):
            pytest.skip("This ffmpeg build cannot encode HEVC Main10 (libx265)")

        caps = vt.probe_ffmpeg_capabilities()
        sv = vt.validate_source_media(source_path)
        assert sv.is_hdr is True, "PQ-tagged source must be detected as HDR"

        if not caps.supports_hdr_tonemap:
            pytest.skip("This ffmpeg build lacks zscale/tonemap -- cannot verify real tone-mapping")

        target_w, target_h = vt.compute_scaled_dimensions(sv.display_width, sv.display_height)
        duration = sv.probe.duration_seconds or sv.primary_video.duration_seconds or 0.0
        vf = vt.build_video_filter_chain(target_width=target_w, target_height=target_h, is_hdr=True)
        assert "tonemap" in vf and "zscale" in vf
        bitrate = vt.compute_target_video_bitrate_bps(duration, has_audio=False)

        out_path = os.path.join(tmp_dir, "hdr_out.mp4")
        argv = vt.build_transcode_argv(
            ffmpeg_path=caps.ffmpeg_path,
            source_path=source_path,
            output_path=out_path,
            video_filter_chain=vf,
            video_bitrate_bps=bitrate,
            has_audio=False,
        )
        vt.run_ffmpeg(argv, timeout=60)

        ov = vt.validate_output_media(out_path, expect_audio=False)
        assert ov.video.codec_name == "h264"
        assert ov.size_bytes < vt.FINAL_MAX_BYTES
        # The output is SDR (no HDR color tags carried forward) -- ffprobe
        # on a plain yuv420p H.264 stream reports no HDR transfer function.
        assert (ov.video.color_transfer or "").lower() not in ("smpte2084", "arib-std-b67")


# ---------------------------------------------------------------------------
# Optional real-device regression test (Section 8 of the real-fixture
# verification pass). Runs ONLY when CARNET_REAL_DOLBY_REPRO_PATH is set to
# an existing file; skipped otherwise. The 112MB fixture itself is NEVER
# committed to this repo -- see .gitignore's /repro_samsung_dolby.mov entry.
# ---------------------------------------------------------------------------

_REAL_REPRO_ENV_VAR = "CARNET_REAL_DOLBY_REPRO_PATH"
_REAL_REPRO_EXPECTED_SIZE = 112329351
_REAL_REPRO_EXPECTED_SHA256 = (
    "c2509e89e4e7190044466b6703222daff547f9d0b436c342d639c2d4f4f6cafc"
)

_REAL_REPRO_PATH = os.environ.get(_REAL_REPRO_ENV_VAR, "").strip()
_REAL_REPRO_AVAILABLE = bool(_REAL_REPRO_PATH) and os.path.isfile(_REAL_REPRO_PATH)


def _sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


@pytest.mark.skipif(
    _RESOLVED is None,
    reason="No ffmpeg/ffprobe build available (install static-ffmpeg, or "
    "set FFMPEG_PATH/FFPROBE_PATH) -- this integration test is optional.",
)
@pytest.mark.skipif(
    not _REAL_REPRO_AVAILABLE,
    reason=(
        f"Set {_REAL_REPRO_ENV_VAR} to the absolute path of the real "
        "Dolby Vision repro .mov to run this optional regression test. "
        "Skipped by default (the 112MB fixture is never committed to git)."
    ),
)
class TestRealDolbyReproFixture:
    """Exercises the exact real-device Dolby Vision Profile 8.4 (HLG,
    HEVC Main10, 3840x2160, ~120fps, portrait) repro file end-to-end
    through the real production pipeline. Only runs locally/manually with
    CARNET_REAL_DOLBY_REPRO_PATH set; never part of the default/CI suite.
    """

    def test_real_repro_fixture_transcodes_to_contract(self, tmp_dir):
        source_path = _REAL_REPRO_PATH

        # 1. Verify fixture identity before doing anything else -- if this
        # ever points at the wrong file, fail loudly rather than silently
        # validating a different (possibly non-representative) video.
        actual_size = os.path.getsize(source_path)
        assert actual_size == _REAL_REPRO_EXPECTED_SIZE, (
            f"{_REAL_REPRO_ENV_VAR} points at a file of size {actual_size}, "
            f"expected exactly {_REAL_REPRO_EXPECTED_SIZE}"
        )
        actual_sha256 = _sha256_of(source_path)
        assert actual_sha256 == _REAL_REPRO_EXPECTED_SHA256, (
            f"{_REAL_REPRO_ENV_VAR} points at a file with SHA-256 "
            f"{actual_sha256}, expected {_REAL_REPRO_EXPECTED_SHA256}"
        )

        ffmpeg_path, _ffprobe_path = _RESOLVED
        caps = vt.probe_ffmpeg_capabilities()
        assert caps.has_libx264 and caps.has_aac_encoder

        # 2. Real source validation -- this file is real HDR (DV
        # Profile 8.4 / HLG), so HDR detection must fire.
        sv = vt.validate_source_media(source_path)
        assert sv.is_hdr is True
        assert sv.has_audio is True

        target_w, target_h = vt.compute_scaled_dimensions(sv.display_width, sv.display_height)
        duration = sv.probe.duration_seconds or sv.primary_video.duration_seconds or 0.0
        vf = vt.build_video_filter_chain(target_width=target_w, target_height=target_h, is_hdr=True)
        bitrate = vt.compute_target_video_bitrate_bps(duration, has_audio=True)

        out_path = os.path.join(tmp_dir, "real_repro_out.mp4")
        argv = vt.build_transcode_argv(
            ffmpeg_path=caps.ffmpeg_path,
            source_path=source_path,
            output_path=out_path,
            video_filter_chain=vf,
            video_bitrate_bps=bitrate,
            has_audio=True,
        )

        # 3. Real transcode -- a 4K/~120fps HDR tonemap pass is slow, so
        # this needs a generous timeout (observed ~100-110s locally).
        start = time.time()
        vt.run_ffmpeg(argv, timeout=240)
        elapsed = time.time() - start

        # 4. Output contract re-validation (production validator) plus
        # this test's own explicit assertions on the contract from the
        # spec: H.264, long edge <=1920, fps<=30, <100MiB.
        ov = vt.validate_output_media(out_path, expect_audio=True)
        assert ov.video.codec_name == "h264"
        assert max(ov.video.width, ov.video.height) <= vt.MAX_LONG_EDGE
        assert ov.video.r_frame_rate is not None and ov.video.r_frame_rate <= 30.5
        assert ov.audio is not None and ov.audio.codec_name == "aac"
        assert ov.size_bytes < vt.FINAL_MAX_BYTES
        assert elapsed < 240
