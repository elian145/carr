"""OOM-fix follow-up: ``tools/r2_s3_op.py``'s ``put_object`` op used to do

    with open(body_path, "rb") as fp:
        body = fp.read()
    client.put_object(Bucket=bucket, Key=key, Body=body, ContentType=content_type)

-- i.e. even though callers (``kk.r2_ops.r2_put_file()`` / ``r2_put_bytes()``)
already had the payload staged on disk, this subprocess read the *entire*
file into one in-memory ``bytes`` object before uploading it. Since this
subprocess runs on the same Render container as the ``carr`` web process,
that full-file buffer counted toward the container's total memory
footprint for every path-based R2 upload -- large video uploads
(``kk.routes.media._upload_video_file_to_r2`` -> ``r2_put_file()``) and the
async-image-staging upload (``kk.media_processing.stage_upload_for_async_job``
-> ``r2_put_file()``) alike.

Fix: the ``put_object`` op now uploads via boto3's managed file transfer
(``client.upload_file(body_path, bucket, key, ExtraArgs=..., Config=...)``),
which streams the body straight from disk (chunked/multipart under the
hood) and never holds the full file as one ``bytes`` object in this
subprocess, regardless of file size. ``r2_put_bytes()`` is unchanged at the
Python level (it still stages its bytes to a temp file first) but now also
benefits, since it funnels through this same shared op.

Follow-up memory-safety bound: an explicit ``boto3.s3.transfer.TransferConfig``
caps concurrent multipart part-upload threads at ``max_concurrency=2`` (boto3's
default of 10 would allow up to ~80 MiB of concurrently in-flight chunk
buffers at the default 8 MiB chunk size) while keeping ``multipart_chunksize``
at ~8 MiB and multipart uploads enabled (default threshold, unchanged).

These tests cover (in-process, against the real ``tools/r2_s3_op.py``
module with a fake boto3 client -- ``put_object`` genuinely needs network
access to a real bucket, which is not available in CI):

  A. The op never opens/reads the uploaded file itself (proving no
     read-all/full-file buffering) and calls the streaming
     ``upload_file`` API, never ``put_object`` with a ``Body=`` bytes arg.
  B. Content-Type is preserved via ``ExtraArgs``.
  C. Zero-byte and small-file uploads still succeed with the correct
     reported byte count.
  D. Upload failures are propagated as a JSON ``{"error": ...}`` response
     (matching the existing subprocess protocol), which
     ``kk.r2_ops._run_r2_op`` turns into a ``RuntimeError`` for callers.
  E. Both ``kk.r2_ops.r2_put_file()`` (large video / staging uploads) and
     ``r2_put_bytes()`` still hand a ``body_path`` (never a raw ``body``)
     to the subprocess -- i.e. the fix is reachable through both public
     helpers, for both caller categories named in the fix request.
  F. A ``TransferConfig`` is passed to ``upload_file()`` with
     ``max_concurrency=2`` and an ~8 MiB ``multipart_chunksize``, multipart
     uploads left enabled -- bounding concurrent in-flight chunk memory
     without reverting to a full-file read.
"""

from __future__ import annotations

import io
import json
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import tools.r2_s3_op as r2_s3_op_module  # noqa: E402

import kk.r2_ops as r2_ops_module  # noqa: E402

_DUMMY_CREDS = {
    "account_id": "dummy-account",
    "bucket": "dummy-bucket",
    "access_key": "AKIADUMMYDUMMYDUMMY",
    "secret_key": "dummysecretdummysecretdummysecretdummy1",
    "region": "auto",
}


class _FakeS3Client:
    """Records calls instead of touching the network -- lets these tests
    assert exactly which boto3 API the op used, without real R2/AWS
    credentials or network access."""

    def __init__(self, *, upload_file_error: Exception | None = None):
        self.upload_file_calls: list[dict] = []
        self.put_object_calls: list[dict] = []
        self._upload_file_error = upload_file_error

    def upload_file(self, Filename, Bucket, Key, ExtraArgs=None, Config=None):  # noqa: N803
        self.upload_file_calls.append(
            {
                "Filename": Filename,
                "Bucket": Bucket,
                "Key": Key,
                "ExtraArgs": ExtraArgs,
                "Config": Config,
            }
        )
        if self._upload_file_error is not None:
            raise self._upload_file_error

    def put_object(self, **kwargs):
        # Should never be called by the fixed `put_object` op -- recorded
        # so tests can assert on that directly.
        self.put_object_calls.append(kwargs)


def _run_put_object_op(
    monkeypatch,
    *,
    body_path: str,
    content_type: str = "application/octet-stream",
    fake_client: _FakeS3Client | None = None,
    key: str = "car_photos/_staging/deadbeef.jpg",
) -> tuple[dict, _FakeS3Client]:
    """Invoke the REAL `tools/r2_s3_op.py::main()` in-process (not via a
    subprocess -- `put_object` needs network access to a real bucket,
    which this test suite must not depend on), with `boto3.client()`
    patched to return a fake, network-free client.
    """
    client = fake_client if fake_client is not None else _FakeS3Client()

    import boto3

    monkeypatch.setattr(boto3, "client", lambda *a, **kw: client)

    payload = {
        **_DUMMY_CREDS,
        "op": "put_object",
        "key": key,
        "content_type": content_type,
        "body_path": body_path,
    }
    fake_stdin = io.StringIO(json.dumps(payload))
    fake_stdout = io.StringIO()
    monkeypatch.setattr(sys, "stdin", fake_stdin)
    monkeypatch.setattr(sys, "stdout", fake_stdout)

    try:
        r2_s3_op_module.main()
    except SystemExit:
        pass

    fake_stdout.seek(0)
    out = fake_stdout.read().strip()
    assert out, "put_object op produced no stdout output"
    return json.loads(out), client


# ---------------------------------------------------------------------------
# A. No full-file read/buffer; uses the streaming upload_file API
# ---------------------------------------------------------------------------


class TestPutObjectStreamsFromDisk:
    def test_upload_file_is_used_not_put_object_with_body_bytes(
        self, monkeypatch, tmp_path
    ):
        body_path = tmp_path / "source.jpg"
        body_path.write_bytes(b"\xff\xd8\xff\xe0" + (b"A" * 4096))

        result, client = _run_put_object_op(
            monkeypatch, body_path=str(body_path), content_type="image/jpeg"
        )

        assert result.get("ok") is True, result
        assert client.put_object_calls == [], (
            "put_object() with an in-memory Body= must never be called by "
            "the fixed op -- this is exactly the full-buffer path being "
            "removed"
        )
        assert len(client.upload_file_calls) == 1
        call = client.upload_file_calls[0]
        assert call["Filename"] == str(body_path)
        assert call["Bucket"] == _DUMMY_CREDS["bucket"]
        assert call["Key"] == "car_photos/_staging/deadbeef.jpg"

    def test_op_never_opens_or_reads_the_source_file_itself(
        self, monkeypatch, tmp_path
    ):
        """The op's OWN code must never call `open()`/`.read()` on
        `body_path` -- that responsibility is fully delegated to boto3's
        (faked-out, network-free) transfer manager. This is the direct
        proof that no read-all/full-file buffering happens in this
        subprocess."""
        body_path = tmp_path / "source_large.bin"
        # Large enough that an accidental full read would be easy to
        # notice if this test regresses (e.g. via a memory profiler run
        # manually) -- the assertion itself is behavioral, not
        # size-based.
        body_path.write_bytes(b"\x00" * (2 * 1024 * 1024))

        real_open = open
        opened_paths: list[str] = []

        def tracking_open(file, *args, **kwargs):
            try:
                opened_paths.append(os.fspath(file))
            except TypeError:
                pass
            return real_open(file, *args, **kwargs)

        monkeypatch.setattr("builtins.open", tracking_open)

        result, client = _run_put_object_op(monkeypatch, body_path=str(body_path))

        assert result.get("ok") is True, result
        assert str(body_path) not in opened_paths, (
            "the put_object op must never open() the uploaded file itself -- "
            "streaming to R2 is entirely boto3's/upload_file()'s "
            "responsibility"
        )
        assert len(client.upload_file_calls) == 1


# ---------------------------------------------------------------------------
# A2. TransferConfig bounds concurrency without reverting to a full read
# ---------------------------------------------------------------------------


class TestPutObjectTransferConfigConcurrencyBound:
    def test_transfer_config_is_passed_to_upload_file(self, monkeypatch, tmp_path):
        from boto3.s3.transfer import TransferConfig

        body_path = tmp_path / "source.jpg"
        body_path.write_bytes(b"\xff\xd8\xff\xe0" + (b"A" * 4096))

        _result, client = _run_put_object_op(monkeypatch, body_path=str(body_path))

        call = client.upload_file_calls[0]
        assert isinstance(call["Config"], TransferConfig), (
            "upload_file() must receive an explicit TransferConfig, not "
            "boto3's unbounded default"
        )

    def test_max_concurrency_is_bounded_to_two(self, monkeypatch, tmp_path):
        body_path = tmp_path / "source.jpg"
        body_path.write_bytes(b"A" * 4096)

        _result, client = _run_put_object_op(monkeypatch, body_path=str(body_path))

        config = client.upload_file_calls[0]["Config"]
        assert config.max_concurrency == 2, (
            "max_concurrency must be bounded to 2 -- boto3's default (10) "
            "allows far more concurrently in-flight chunk buffers per upload"
        )

    def test_multipart_chunksize_is_around_8_mib(self, monkeypatch, tmp_path):
        body_path = tmp_path / "source.jpg"
        body_path.write_bytes(b"A" * 4096)

        _result, client = _run_put_object_op(monkeypatch, body_path=str(body_path))

        config = client.upload_file_calls[0]["Config"]
        assert config.multipart_chunksize == 8 * 1024 * 1024

    def test_multipart_uploads_remain_enabled(self, monkeypatch, tmp_path):
        """Multipart must stay enabled (a real, positive threshold) -- this
        bound is about concurrency/chunk size, not about forcing every
        upload into one giant single-part PUT."""
        body_path = tmp_path / "source.jpg"
        body_path.write_bytes(b"A" * 4096)

        _result, client = _run_put_object_op(monkeypatch, body_path=str(body_path))

        config = client.upload_file_calls[0]["Config"]
        assert config.multipart_threshold > 0

    def test_still_uses_upload_file_not_a_full_read(self, monkeypatch, tmp_path):
        """Guard against a regression that adds TransferConfig but
        reverts to reading the whole file (e.g. by switching back to
        `put_object(Body=...)`)."""
        body_path = tmp_path / "source.jpg"
        body_path.write_bytes(b"A" * (1024 * 1024))

        real_open = open
        opened_paths: list[str] = []

        def tracking_open(file, *args, **kwargs):
            try:
                opened_paths.append(os.fspath(file))
            except TypeError:
                pass
            return real_open(file, *args, **kwargs)

        monkeypatch.setattr("builtins.open", tracking_open)

        result, client = _run_put_object_op(monkeypatch, body_path=str(body_path))

        assert result.get("ok") is True, result
        assert client.put_object_calls == []
        assert len(client.upload_file_calls) == 1
        assert str(body_path) not in opened_paths

    def test_content_type_still_preserved_alongside_transfer_config(
        self, monkeypatch, tmp_path
    ):
        body_path = tmp_path / "source.jpg"
        body_path.write_bytes(b"A" * 4096)

        _result, client = _run_put_object_op(
            monkeypatch, body_path=str(body_path), content_type="image/jpeg"
        )

        call = client.upload_file_calls[0]
        assert call["ExtraArgs"] == {"ContentType": "image/jpeg"}
        assert call["Config"] is not None


# ---------------------------------------------------------------------------
# B. Content-Type is preserved
# ---------------------------------------------------------------------------


class TestPutObjectPreservesContentType:
    @pytest.mark.parametrize(
        "content_type", ["image/jpeg", "video/mp4", "application/octet-stream"]
    )
    def test_content_type_passed_through_extra_args(
        self, monkeypatch, tmp_path, content_type
    ):
        body_path = tmp_path / "f.bin"
        body_path.write_bytes(b"hello world")

        _result, client = _run_put_object_op(
            monkeypatch, body_path=str(body_path), content_type=content_type
        )

        assert client.upload_file_calls[0]["ExtraArgs"] == {
            "ContentType": content_type
        }


# ---------------------------------------------------------------------------
# C. Zero-byte / small-file behavior
# ---------------------------------------------------------------------------


class TestPutObjectSizeEdgeCases:
    def test_small_nonempty_file_reports_correct_byte_count(
        self, monkeypatch, tmp_path
    ):
        body_path = tmp_path / "tiny.txt"
        body_path.write_bytes(b"hi")

        result, client = _run_put_object_op(monkeypatch, body_path=str(body_path))

        assert result == {
            "ok": True,
            "key": "car_photos/_staging/deadbeef.jpg",
            "bytes": 2,
        }
        assert len(client.upload_file_calls) == 1

    def test_zero_byte_file_still_uploads_successfully(self, monkeypatch, tmp_path):
        """The higher-level Python helpers (`r2_put_file`/`r2_put_bytes`)
        already reject empty bodies before ever reaching the subprocess
        (see TestR2OpsHelpersRemainPathBased below) -- this proves the op
        itself is still robust at the boundary and does not crash/behave
        incorrectly if ever invoked with a genuinely empty file."""
        body_path = tmp_path / "empty.bin"
        body_path.write_bytes(b"")

        result, client = _run_put_object_op(monkeypatch, body_path=str(body_path))

        assert result.get("ok") is True, result
        assert result.get("bytes") == 0
        assert len(client.upload_file_calls) == 1


# ---------------------------------------------------------------------------
# D. Upload failures are propagated
# ---------------------------------------------------------------------------


class TestPutObjectFailurePropagation:
    def test_upload_file_exception_becomes_error_json(self, monkeypatch, tmp_path):
        body_path = tmp_path / "f.bin"
        body_path.write_bytes(b"data")

        result, _client = _run_put_object_op(
            monkeypatch,
            body_path=str(body_path),
            fake_client=_FakeS3Client(
                upload_file_error=RuntimeError("simulated R2 outage")
            ),
        )

        assert "error" in result
        assert "simulated R2 outage" in result["error"]
        assert result.get("ok") is not True

    def test_run_r2_op_translates_subprocess_error_into_runtime_error(
        self, monkeypatch
    ):
        """`kk.r2_ops._run_r2_op` (used by both `r2_put_file()` and
        `r2_put_bytes()`) must still raise a `RuntimeError` carrying the
        subprocess's error message -- unchanged protocol/error handling,
        just proven end-to-end against the new op body."""

        class _FakeCompletedProcess:
            stdout = json.dumps({"error": "simulated R2 outage"})
            stderr = ""
            returncode = 1

        monkeypatch.setattr(
            r2_ops_module.subprocess,
            "run",
            lambda *a, **kw: _FakeCompletedProcess(),
        )

        with pytest.raises(RuntimeError, match="simulated R2 outage"):
            r2_ops_module._run_r2_op({"op": "put_object"}, timeout=5)


# ---------------------------------------------------------------------------
# E. r2_put_file()/r2_put_bytes() still hand a body_path (not raw bytes)
#    to the subprocess -- covers both the large-video and the
#    async-image-staging caller categories via the same shared helpers.
# ---------------------------------------------------------------------------


@pytest.fixture
def fake_r2_app(monkeypatch):
    fake_app = MagicMock()
    fake_app.config = {
        "R2_ACCOUNT_ID": "dummy-account",
        "R2_BUCKET_NAME": "dummy-bucket",
        "R2_ACCESS_KEY_ID": "AKIADUMMYDUMMYDUMMY",
        "R2_SECRET_ACCESS_KEY": "dummysecretdummysecretdummysecretdummy1",
    }
    monkeypatch.setattr(r2_ops_module, "current_app", fake_app)
    return fake_app


class TestR2OpsHelpersRemainPathBased:
    def test_r2_put_file_sends_body_path_never_body(
        self, monkeypatch, tmp_path, fake_r2_app
    ):
        """Large video uploads (and the async-image-staging upload) call
        this helper directly with an on-disk path -- must still be handed
        straight through as `body_path`, never read into `body` bytes."""
        video_path = tmp_path / "clip.mp4"
        video_path.write_bytes(b"\x00" * (1024 * 1024))  # stand-in for a
        # large (e.g. up to ~100MB in production) video file.

        captured: dict = {}

        def fake_run_r2_op(payload, *, timeout):
            captured.update(payload)
            return {"ok": True, "key": payload["key"], "bytes": 999}

        monkeypatch.setattr(r2_ops_module, "_run_r2_op", fake_run_r2_op)

        r2_ops_module.r2_put_file(
            key="car_videos/abc.mp4",
            file_path=str(video_path),
            content_type="video/mp4",
        )

        assert captured["op"] == "put_object"
        assert captured["body_path"] == str(video_path)
        assert "body" not in captured

    def test_r2_put_bytes_also_funnels_through_body_path(
        self, monkeypatch, fake_r2_app
    ):
        """`r2_put_bytes()` stages its bytes to a temp file first, then
        reaches the exact same path-based `put_object` op -- so it also
        benefits from the streaming fix, with no change to its own
        signature/behavior."""
        captured: dict = {}
        seen_temp_path: dict = {}

        def fake_run_r2_op(payload, *, timeout):
            captured.update(payload)
            seen_temp_path["path"] = payload.get("body_path")
            # Prove the temp file genuinely exists on disk at call time
            # (i.e. this really is a path-based op, not an in-memory one).
            assert os.path.isfile(payload["body_path"])
            with open(payload["body_path"], "rb") as fh:
                assert fh.read() == b"async-staging-bytes"
            return {"ok": True, "key": payload["key"], "bytes": 19}

        monkeypatch.setattr(r2_ops_module, "_run_r2_op", fake_run_r2_op)

        r2_ops_module.r2_put_bytes(
            key="car_photos/_staging/def.jpg",
            body=b"async-staging-bytes",
            content_type="image/jpeg",
        )

        assert captured["op"] == "put_object"
        assert "body" not in captured
        # The temp file must be cleaned up after the call.
        assert not os.path.isfile(seen_temp_path["path"])
