"""Phase 2 of the server-side video transcode fallback:
``kk/video_transcoding.py`` -- ffmpeg/ffprobe provider resolution,
structured ffprobe parsing, source/output contract validation, and command
construction.

Every test here mocks ``subprocess.run`` (and, where relevant,
``resolve_ffmpeg_paths``) -- no real ffmpeg/ffprobe binary and no real R2
credentials are required to run this file. A SEPARATE, optional local
integration test (using a real, resolved ffmpeg/ffprobe build) lives in
``test_video_transcoding_real_ffmpeg_integration.py``.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import kk.video_transcoding as vt  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_module_caches():
    vt.reset_resolved_paths_for_tests()
    vt.reset_capabilities_for_tests()
    yield
    vt.reset_resolved_paths_for_tests()
    vt.reset_capabilities_for_tests()


def _fake_completed_process(*, returncode=0, stdout=b"", stderr=b""):
    proc = MagicMock()
    proc.returncode = returncode
    proc.stdout = stdout
    proc.stderr = stderr
    return proc


def _probe_json_bytes(streams, *, format_extra=None):
    fmt = {"duration": "5.0", "size": "1000"}
    if format_extra:
        fmt.update(format_extra)
    return json.dumps({"format": fmt, "streams": streams}).encode("utf-8")


def _video_stream(
    *,
    width=1080,
    height=1920,
    codec_name="h264",
    r_frame_rate="30/1",
    duration="5.0",
    color_transfer=None,
    color_primaries=None,
    rotate_tag=None,
    side_data_rotation=None,
):
    stream = {
        "codec_type": "video",
        "codec_name": codec_name,
        "width": width,
        "height": height,
        "r_frame_rate": r_frame_rate,
        "duration": duration,
        "color_transfer": color_transfer,
        "color_primaries": color_primaries,
        "color_space": color_primaries,
    }
    if rotate_tag is not None:
        stream["tags"] = {"rotate": str(rotate_tag)}
    if side_data_rotation is not None:
        stream["side_data_list"] = [{"rotation": side_data_rotation}]
    return stream


def _audio_stream(*, codec_name="aac", duration="5.0"):
    return {"codec_type": "audio", "codec_name": codec_name, "duration": duration}


# ---------------------------------------------------------------------------
# resolve_ffmpeg_paths
# ---------------------------------------------------------------------------


class TestResolveFfmpegPaths:
    def test_uses_explicit_env_vars_when_both_exist(self, monkeypatch, tmp_path):
        fake_ffmpeg = tmp_path / "ffmpeg.exe"
        fake_ffprobe = tmp_path / "ffprobe.exe"
        fake_ffmpeg.write_bytes(b"x")
        fake_ffprobe.write_bytes(b"x")
        monkeypatch.setenv("FFMPEG_PATH", str(fake_ffmpeg))
        monkeypatch.setenv("FFPROBE_PATH", str(fake_ffprobe))

        ffmpeg_path, ffprobe_path = vt.resolve_ffmpeg_paths()
        assert ffmpeg_path == str(fake_ffmpeg)
        assert ffprobe_path == str(fake_ffprobe)

    def test_env_vars_must_both_point_at_real_files(self, monkeypatch, tmp_path):
        monkeypatch.setenv("FFMPEG_PATH", str(tmp_path / "missing_ffmpeg"))
        monkeypatch.setenv("FFPROBE_PATH", str(tmp_path / "missing_ffprobe"))
        with pytest.raises(vt.FfmpegUnavailableError):
            vt.resolve_ffmpeg_paths()

    def test_raises_when_static_ffmpeg_unavailable_and_no_env_vars(self, monkeypatch):
        monkeypatch.delenv("FFMPEG_PATH", raising=False)
        monkeypatch.delenv("FFPROBE_PATH", raising=False)
        import builtins

        real_import = builtins.__import__

        def fake_import(name, *args, **kwargs):
            if name == "static_ffmpeg":
                raise ImportError("not installed")
            return real_import(name, *args, **kwargs)

        monkeypatch.setattr(builtins, "__import__", fake_import)
        with pytest.raises(vt.FfmpegUnavailableError):
            vt.resolve_ffmpeg_paths()

    def test_caches_resolved_paths_across_calls(self, monkeypatch, tmp_path):
        fake_ffmpeg = tmp_path / "ffmpeg.exe"
        fake_ffprobe = tmp_path / "ffprobe.exe"
        fake_ffmpeg.write_bytes(b"x")
        fake_ffprobe.write_bytes(b"x")
        monkeypatch.setenv("FFMPEG_PATH", str(fake_ffmpeg))
        monkeypatch.setenv("FFPROBE_PATH", str(fake_ffprobe))

        first = vt.resolve_ffmpeg_paths()
        # Removing env vars after the first resolution must not matter --
        # the result is cached for the rest of the process.
        monkeypatch.delenv("FFMPEG_PATH", raising=False)
        monkeypatch.delenv("FFPROBE_PATH", raising=False)
        second = vt.resolve_ffmpeg_paths()
        assert first == second


# ---------------------------------------------------------------------------
# probe_ffmpeg_capabilities
# ---------------------------------------------------------------------------


class TestProbeFfmpegCapabilities:
    def _patch_resolve(self, monkeypatch, ffmpeg="ffmpeg", ffprobe="ffprobe"):
        monkeypatch.setattr(vt, "resolve_ffmpeg_paths", lambda: (ffmpeg, ffprobe))

    def test_detects_all_capabilities_present(self, monkeypatch):
        self._patch_resolve(monkeypatch)

        def fake_run_capture(argv, *, timeout=20):
            if "-version" in argv:
                return "ffmpeg version 8.0.1 Copyright ...\nbuilt with gcc"
            if "-encoders" in argv:
                return (
                    " V....D libx264              libx264 H.264\n"
                    " A....D aac                  AAC (Advanced Audio Coding)\n"
                )
            if "-filters" in argv:
                return (
                    " .S tonemap           V->V       desc\n"
                    " .. tonemap_vaapi     V->V       desc\n"
                    " .S zscale            V->V       desc\n"
                )
            return ""

        monkeypatch.setattr(vt, "_run_capture", fake_run_capture)
        caps = vt.probe_ffmpeg_capabilities()
        assert caps.has_libx264 is True
        assert caps.has_aac_encoder is True
        assert caps.has_zscale_filter is True
        assert caps.has_tonemap_filter is True
        assert caps.supports_hdr_tonemap is True

    def test_tonemap_vaapi_alone_does_not_count_as_tonemap(self, monkeypatch):
        self._patch_resolve(monkeypatch)

        def fake_run_capture(argv, *, timeout=20):
            if "-version" in argv:
                return "ffmpeg version 8.0.1"
            if "-encoders" in argv:
                return " V....D libx264              libx264\n A....D aac  AAC\n"
            if "-filters" in argv:
                return " .. tonemap_vaapi     V->V       desc\n .S zscale  V->V desc\n"
            return ""

        monkeypatch.setattr(vt, "_run_capture", fake_run_capture)
        caps = vt.probe_ffmpeg_capabilities()
        assert caps.has_tonemap_filter is False
        assert caps.supports_hdr_tonemap is False

    def test_missing_capabilities_detected(self, monkeypatch):
        self._patch_resolve(monkeypatch)
        monkeypatch.setattr(vt, "_run_capture", lambda argv, timeout=20: "nothing useful here")
        caps = vt.probe_ffmpeg_capabilities()
        assert caps.has_libx264 is False
        assert caps.has_aac_encoder is False
        assert caps.has_zscale_filter is False
        assert caps.has_tonemap_filter is False
        assert caps.supports_hdr_tonemap is False

    def test_result_cached_across_calls(self, monkeypatch):
        self._patch_resolve(monkeypatch)
        calls = {"n": 0}

        def fake_run_capture(argv, *, timeout=20):
            calls["n"] += 1
            return "ffmpeg version 8.0.1"

        monkeypatch.setattr(vt, "_run_capture", fake_run_capture)
        vt.probe_ffmpeg_capabilities()
        n_after_first = calls["n"]
        vt.probe_ffmpeg_capabilities()
        assert calls["n"] == n_after_first  # no new subprocess calls made

    def test_as_report_dict_shape(self, monkeypatch):
        self._patch_resolve(monkeypatch)
        monkeypatch.setattr(vt, "_run_capture", lambda argv, timeout=20: "ffmpeg version 8.0.1")
        caps = vt.probe_ffmpeg_capabilities()
        report = caps.as_report_dict()
        for key in (
            "ffmpeg_version",
            "ffprobe_version",
            "has_libx264",
            "has_aac_encoder",
            "has_zscale_filter",
            "has_tonemap_filter",
            "supports_hdr_tonemap",
        ):
            assert key in report


# ---------------------------------------------------------------------------
# ffprobe_media (structured JSON parsing)
# ---------------------------------------------------------------------------


class TestFfprobeMedia:
    def _patch(self, monkeypatch, *, returncode=0, stdout=b"{}"):
        monkeypatch.setattr(vt, "resolve_ffmpeg_paths", lambda: ("ffmpeg", "ffprobe"))
        monkeypatch.setattr(
            subprocess,
            "run",
            lambda *a, **k: _fake_completed_process(returncode=returncode, stdout=stdout),
        )

    def test_parses_valid_probe_json(self, monkeypatch):
        stdout = _probe_json_bytes([_video_stream(), _audio_stream()])
        self._patch(monkeypatch, stdout=stdout)
        media = vt.ffprobe_media("/fake/path.mp4")
        assert media.primary_video is not None
        assert media.primary_video.width == 1080
        assert media.primary_video.height == 1920
        assert media.has_audio is True
        assert media.duration_seconds == 5.0

    def test_raises_on_nonzero_exit(self, monkeypatch):
        self._patch(monkeypatch, returncode=1, stdout=b"")
        with pytest.raises(vt.VideoValidationError):
            vt.ffprobe_media("/fake/path.mp4")

    def test_raises_on_invalid_json(self, monkeypatch):
        self._patch(monkeypatch, returncode=0, stdout=b"not json{{{")
        with pytest.raises(vt.VideoValidationError):
            vt.ffprobe_media("/fake/path.mp4")

    def test_frame_rate_parsed_from_fraction(self, monkeypatch):
        stdout = _probe_json_bytes([_video_stream(r_frame_rate="30000/1001")])
        self._patch(monkeypatch, stdout=stdout)
        media = vt.ffprobe_media("/fake/path.mp4")
        assert media.primary_video.r_frame_rate == pytest.approx(29.97, abs=0.01)

    def test_rotation_tag_parsed(self, monkeypatch):
        stdout = _probe_json_bytes([_video_stream(rotate_tag=90)])
        self._patch(monkeypatch, stdout=stdout)
        media = vt.ffprobe_media("/fake/path.mp4")
        assert media.primary_video.rotation_degrees == 90

    def test_rotation_side_data_parsed_as_magnitude(self, monkeypatch):
        stdout = _probe_json_bytes([_video_stream(side_data_rotation=-90)])
        self._patch(monkeypatch, stdout=stdout)
        media = vt.ffprobe_media("/fake/path.mp4")
        assert media.primary_video.rotation_degrees == 90


# ---------------------------------------------------------------------------
# validate_source_media
# ---------------------------------------------------------------------------


class TestValidateSourceMedia:
    def _write_tmp(self, tmp_path, *, size_bytes=1024):
        p = tmp_path / "source.mov"
        p.write_bytes(b"\x00" * size_bytes)
        return str(p)

    def _patch_ffprobe(self, monkeypatch, media):
        monkeypatch.setattr(vt, "ffprobe_media", lambda path, timeout=30: media)

    def test_rejects_empty_file(self, tmp_path):
        p = tmp_path / "empty.mov"
        p.write_bytes(b"")
        with pytest.raises(vt.VideoValidationError):
            vt.validate_source_media(str(p))

    def test_rejects_file_over_max_bytes(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path, size_bytes=100)
        with pytest.raises(vt.VideoValidationError):
            vt.validate_source_media(path, max_bytes=50)

    def test_rejects_no_video_stream(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        media = vt._parse_probe_json(json.loads(_probe_json_bytes([_audio_stream()])))
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="no video stream"):
            vt.validate_source_media(path)

    def test_rejects_missing_duration(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(duration=None)], format_extra={"duration": None}))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="duration"):
            vt.validate_source_media(path)

    def test_rejects_duration_over_30_seconds(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(
            _probe_json_bytes([_video_stream(duration="45.0")], format_extra={"duration": "45.0"})
        )
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="30"):
            vt.validate_source_media(path)

    def test_accepts_duration_at_exactly_30_seconds(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(
            _probe_json_bytes([_video_stream(duration="30.0")], format_extra={"duration": "30.0"})
        )
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_source_media(path)
        assert result is not None

    def test_rejects_zero_dimensions(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(width=0, height=0)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="dimensions"):
            vt.validate_source_media(path)

    def test_rejects_excessive_resolution(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(width=20000, height=20000)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="maximum"):
            vt.validate_source_media(path)

    # -----------------------------------------------------------------
    # Explicit 4K-class source resolution/pixel-count bounds
    # (MAX_SOURCE_LONG_EDGE=4096, MAX_SOURCE_PIXELS=4096*2304). Checked
    # against the RAW ENCODED width/height, i.e. before any rotation-based
    # display-dimension swap.
    # -----------------------------------------------------------------

    @pytest.mark.parametrize(
        "width,height",
        [
            (3840, 2160),  # common landscape 4K
            (2160, 3840),  # common portrait 4K (phone)
            (4096, 2160),  # DCI 4K landscape
            (2160, 4096),  # DCI 4K portrait
            (4096, 2304),  # exactly at MAX_SOURCE_PIXELS (boundary, accepted)
        ],
    )
    def test_accepts_normal_4k_class_resolutions(self, tmp_path, monkeypatch, width, height):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(width=width, height=height)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_source_media(path)
        assert (result.primary_video.width, result.primary_video.height) == (width, height)

    def test_rejects_4096x4096_due_to_pixel_count_even_though_each_edge_is_at_the_limit(
        self, tmp_path, monkeypatch
    ):
        # Each individual edge (4096) is NOT above MAX_SOURCE_LONG_EDGE, but
        # the area (4096*4096 = 16,777,216) exceeds MAX_SOURCE_PIXELS
        # (4096*2304 = 9,437,184) -- must be rejected on pixel count, not
        # edge length.
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(width=4096, height=4096)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="pixel count"):
            vt.validate_source_media(path)

    def test_rejects_8k_class_long_edge(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(width=7680, height=4320)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError):
            vt.validate_source_media(path)

    def test_rejects_8192x8192(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(width=8192, height=8192)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError):
            vt.validate_source_media(path)

    def test_rejects_pixel_count_exceeded_even_when_both_edges_under_long_edge_limit(
        self, tmp_path, monkeypatch
    ):
        # A pathological case where BOTH edges are individually under
        # MAX_SOURCE_LONG_EDGE (4096) but the area is still too large --
        # confirms the pixel-count check is not merely redundant with the
        # long-edge check.
        width, height = 4090, 4090
        assert width < vt.MAX_SOURCE_LONG_EDGE and height < vt.MAX_SOURCE_LONG_EDGE
        assert width * height > vt.MAX_SOURCE_PIXELS
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(width=width, height=height)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="pixel count"):
            vt.validate_source_media(path)

    def test_accepts_valid_sdr_source(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(), _audio_stream()]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_source_media(path)
        assert result.is_hdr is False
        assert result.has_audio is True

    def test_no_audio_source_has_audio_false(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream()]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_source_media(path)
        assert result.has_audio is False

    @pytest.mark.parametrize("transfer", ["smpte2084", "arib-std-b67"])
    def test_detects_hdr_transfer_functions(self, tmp_path, monkeypatch, transfer):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(color_transfer=transfer)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_source_media(path)
        assert result.is_hdr is True

    def test_sdr_transfer_function_not_flagged_hdr(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(color_transfer="bt709")]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_source_media(path)
        assert result.is_hdr is False

    def test_display_dimensions_swapped_for_90_degree_rotation(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(width=1920, height=1080, rotate_tag=90)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_source_media(path)
        assert (result.display_width, result.display_height) == (1080, 1920)

    def test_display_dimensions_not_swapped_for_0_degree_rotation(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        raw = json.loads(_probe_json_bytes([_video_stream(width=1920, height=1080)]))
        media = vt._parse_probe_json(raw)
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_source_media(path)
        assert (result.display_width, result.display_height) == (1920, 1080)


# ---------------------------------------------------------------------------
# validate_output_media
# ---------------------------------------------------------------------------


class TestValidateOutputMedia:
    def _write_tmp(self, tmp_path, *, size_bytes=1024, name="out.mp4"):
        p = tmp_path / name
        p.write_bytes(b"\x00" * size_bytes)
        return str(p)

    def _patch_ffprobe(self, monkeypatch, media):
        monkeypatch.setattr(vt, "ffprobe_media", lambda path, timeout=30: media)

    def test_rejects_empty_output(self, tmp_path):
        p = tmp_path / "empty.mp4"
        p.write_bytes(b"")
        with pytest.raises(vt.VideoValidationError):
            vt.validate_output_media(str(p), expect_audio=False)

    def test_rejects_non_h264_codec(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        media = vt._parse_probe_json(json.loads(_probe_json_bytes([_video_stream(codec_name="hevc")])))
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="h264"):
            vt.validate_output_media(path, expect_audio=False)

    def test_rejects_over_max_long_edge(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        media = vt._parse_probe_json(
            json.loads(_probe_json_bytes([_video_stream(width=3840, height=2160)]))
        )
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="long edge"):
            vt.validate_output_media(path, expect_audio=False)

    def test_rejects_over_max_fps(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        media = vt._parse_probe_json(
            json.loads(_probe_json_bytes([_video_stream(r_frame_rate="60/1")]))
        )
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="frame rate"):
            vt.validate_output_media(path, expect_audio=False)

    def test_rejects_oversized_result(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path, size_bytes=1024)
        media = vt._parse_probe_json(json.loads(_probe_json_bytes([_video_stream()])))
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="cap"):
            vt.validate_output_media(path, expect_audio=False, max_bytes=100)

    def test_rejects_missing_audio_when_expected(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        media = vt._parse_probe_json(json.loads(_probe_json_bytes([_video_stream()])))
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="audio"):
            vt.validate_output_media(path, expect_audio=True)

    def test_rejects_unexpected_audio_when_none_expected(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        media = vt._parse_probe_json(
            json.loads(_probe_json_bytes([_video_stream(), _audio_stream()]))
        )
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="unexpected audio"):
            vt.validate_output_media(path, expect_audio=False)

    def test_rejects_non_aac_audio_codec(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        media = vt._parse_probe_json(
            json.loads(_probe_json_bytes([_video_stream(), _audio_stream(codec_name="mp3")]))
        )
        self._patch_ffprobe(monkeypatch, media)
        with pytest.raises(vt.VideoValidationError, match="aac"):
            vt.validate_output_media(path, expect_audio=True)

    def test_accepts_valid_output_with_audio(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        media = vt._parse_probe_json(
            json.loads(_probe_json_bytes([_video_stream(), _audio_stream()]))
        )
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_output_media(path, expect_audio=True)
        assert result.video.codec_name == "h264"
        assert result.audio.codec_name == "aac"

    def test_accepts_valid_output_without_audio(self, tmp_path, monkeypatch):
        path = self._write_tmp(tmp_path)
        media = vt._parse_probe_json(json.loads(_probe_json_bytes([_video_stream()])))
        self._patch_ffprobe(monkeypatch, media)
        result = vt.validate_output_media(path, expect_audio=False)
        assert result.audio is None


# ---------------------------------------------------------------------------
# Dimension / bitrate planning
# ---------------------------------------------------------------------------


class TestDimensionAndBitratePlanning:
    def test_downscales_preserving_aspect_ratio(self):
        w, h = vt.compute_scaled_dimensions(3840, 2160)
        assert max(w, h) <= vt.MAX_LONG_EDGE
        assert abs((w / h) - (3840 / 2160)) < 0.01

    def test_never_upscales(self):
        w, h = vt.compute_scaled_dimensions(640, 360)
        assert (w, h) == (640, 360)

    def test_dimensions_always_even(self):
        w, h = vt.compute_scaled_dimensions(3839, 2161)
        assert w % 2 == 0
        assert h % 2 == 0

    def test_bitrate_lower_for_longer_duration(self):
        short = vt.compute_target_video_bitrate_bps(2.0, has_audio=False)
        long = vt.compute_target_video_bitrate_bps(30.0, has_audio=False)
        assert long <= short

    def test_bitrate_reserves_room_for_audio(self):
        # Use a duration long enough that the byte-budget-derived bitrate is
        # actually the binding constraint (not PREFERRED_VIDEO_BITRATE_BPS),
        # so the audio reservation is visible in the result.
        with_audio = vt.compute_target_video_bitrate_bps(100.0, has_audio=True)
        without_audio = vt.compute_target_video_bitrate_bps(100.0, has_audio=False)
        assert with_audio < without_audio

    def test_bitrate_capped_at_preferred_for_short_clips(self):
        bps = vt.compute_target_video_bitrate_bps(0.5, has_audio=False)
        assert bps <= vt.PREFERRED_VIDEO_BITRATE_BPS

    def test_overshoot_retry_bitrate_is_lower(self):
        retry = vt.compute_overshoot_retry_bitrate_bps(5_000_000)
        assert retry < 5_000_000
        assert retry >= vt._MIN_VIDEO_BITRATE_BPS


# ---------------------------------------------------------------------------
# Command construction
# ---------------------------------------------------------------------------


class TestCommandConstruction:
    def test_sdr_filter_chain_has_no_tonemap(self):
        chain = vt.build_video_filter_chain(target_width=640, target_height=360, is_hdr=False)
        assert "tonemap" not in chain
        assert "zscale" not in chain
        assert "scale=640:360" in chain

    def test_hdr_filter_chain_includes_real_tonemap_pipeline(self):
        chain = vt.build_video_filter_chain(target_width=640, target_height=360, is_hdr=True)
        assert "zscale" in chain
        assert "tonemap=" in chain
        assert "scale=640:360" in chain

    def test_transcode_argv_is_plain_list_not_shell_string(self):
        argv = vt.build_transcode_argv(
            ffmpeg_path="/bin/ffmpeg",
            source_path="/tmp/src.mov",
            output_path="/tmp/out.mp4",
            video_filter_chain="scale=640:360,format=yuv420p",
            video_bitrate_bps=1_000_000,
            has_audio=True,
        )
        assert isinstance(argv, list)
        assert all(isinstance(a, str) for a in argv)
        assert argv[0] == "/bin/ffmpeg"

    def test_transcode_argv_with_audio_maps_and_encodes_aac(self):
        argv = vt.build_transcode_argv(
            ffmpeg_path="ffmpeg",
            source_path="src",
            output_path="out.mp4",
            video_filter_chain="scale=1:1",
            video_bitrate_bps=1_000_000,
            has_audio=True,
        )
        assert "-c:a" in argv and "aac" in argv
        assert "-an" not in argv

    def test_transcode_argv_without_audio_uses_an_flag(self):
        argv = vt.build_transcode_argv(
            ffmpeg_path="ffmpeg",
            source_path="src",
            output_path="out.mp4",
            video_filter_chain="scale=1:1",
            video_bitrate_bps=1_000_000,
            has_audio=False,
        )
        assert "-an" in argv
        assert "-c:a" not in argv

    def test_transcode_argv_always_uses_libx264_yuv420p_faststart(self):
        argv = vt.build_transcode_argv(
            ffmpeg_path="ffmpeg",
            source_path="src",
            output_path="out.mp4",
            video_filter_chain="scale=1:1",
            video_bitrate_bps=1_000_000,
            has_audio=False,
        )
        assert "libx264" in argv
        assert "yuv420p" in argv
        assert "+faststart" in argv


class TestRunFfmpeg:
    def test_raises_transcode_error_on_nonzero_exit(self, monkeypatch):
        monkeypatch.setattr(
            subprocess,
            "run",
            lambda *a, **k: _fake_completed_process(returncode=1, stderr=b"boom"),
        )
        with pytest.raises(vt.TranscodeError):
            vt.run_ffmpeg(["ffmpeg", "-version"])

    def test_raises_transcode_error_on_timeout(self, monkeypatch):
        def fake_run(*a, **k):
            raise subprocess.TimeoutExpired(cmd="ffmpeg", timeout=1)

        monkeypatch.setattr(subprocess, "run", fake_run)
        with pytest.raises(vt.TranscodeError, match="timed out"):
            vt.run_ffmpeg(["ffmpeg", "-version"], timeout=1)

    def test_no_exception_on_success(self, monkeypatch):
        monkeypatch.setattr(subprocess, "run", lambda *a, **k: _fake_completed_process(returncode=0))
        vt.run_ffmpeg(["ffmpeg", "-version"])  # must not raise
