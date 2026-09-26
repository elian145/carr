"""H-03 follow-up: presigned-upload / chat-attachment content validation.

Background (see the H-03 investigation): the presigned-PUT listing-media
flow (`POST /api/media/r2/sign-upload` -> client PUTs directly to R2 ->
`POST /api/cars/<id>/images/attach`) never lets the server see the uploaded
bytes, so it cannot run the same magic-byte check the validated multipart
upload endpoints (`/api/cars/<id>/images`, `/api/cars/<id>/videos`,
`/api/process-car-images`) already perform via
``validate_file_upload_security()``. Investigation also found that this
flow's only Flutter caller (``signR2ImageUpload`` / ``uploadToSignedUpload``
in ``lib/services/api/api_listings.dart``) is itself never invoked anywhere
in the shipped app.

Separately, chat attachments (`send_image`, `send_video`, `send_audio`,
`send_media_group`) ARE multipart uploads the server does see in full — but
before this fix, `_upload_chat_attachment()` only checked the filename
extension, never the actual bytes.

This file adds regression coverage for both fixes plus the presigned-PUT
gating decision:

  A. kk/security.py::sniff_bytes() — the extracted, reusable magic-byte
     check (unit tests, no Flask app needed).
  B. kk/security.py::validate_file_upload_security() — proves the extraction
     did not change behavior for the already-validated multipart paths.
  C. kk/routes/chat.py::_upload_chat_attachment() — real HTTP-level tests
     proving send_image/send_video/send_audio/send_media_group now reject
     content that doesn't match its claimed extension, while continuing to
     accept genuine media (no regression for the real, currently-used flow).
  D. tools/r2_s3_op.py — proves the presigned PUT URL still cryptographically
     binds Content-Type + Content-Length (the control that makes this flow
     safe from Content-Type spoofing even while disabled/if ever
     re-enabled).
  E. kk/routes/media.py::r2_sign_upload() — proves the endpoint is disabled
     by default (404) and, if explicitly re-enabled via env var, still
     signs the Content-Type/Content-Length the caller declared.
  F. Combined guarantee — with the presigned-upload endpoint disabled by
     default, there is no way to get unvalidated bytes into a
     `car_photos/`/`car_videos/` key in the first place, so `attach()`
     (whose ownership checks are covered separately in
     test_media_attach_ownership.py) can never be handed a freshly-staged,
     content-unvalidated object.

No real Cloudflare credentials are used anywhere in this file.
"""

from __future__ import annotations

import io
import json
import os
import struct
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from unittest.mock import MagicMock, patch
from urllib.parse import parse_qs, urlparse

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))


# ---------------------------------------------------------------------------
# Shared fake byte payloads
# ---------------------------------------------------------------------------

JPEG_HEADER = b"\xff\xd8\xff\xe0" + b"\x00" * 28
PNG_HEADER = b"\x89PNG\r\n\x1a\n" + b"\x00" * 24
MP4_HEADER = b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 16
# Issue-3 fix (real-device evidence: `POST /api/cars/<id>/videos` -> HTTP
# 400 for genuinely valid .mov files): three real shapes a `.mov` file's
# first bytes can legitimately take.
#   1. The "canonical" QuickTime ftyp brand `"qt  "` (already accepted
#      before this fix).
MOV_QT_BRAND_HEADER = b"\x00\x00\x00\x14ftypqt  " + b"\x00" * 16
#   2. An MP4-family ftyp brand (e.g. "isom") with a `.mov` extension --
#      MOV and MP4 are the SAME underlying ISO-BMFF container format, and
#      real export/picker pipelines can legitimately produce this. Was
#      INCORRECTLY rejected before this fix.
MOV_ISOM_BRAND_HEADER = b"\x00\x00\x00\x14ftypisom" + b"\x00" * 16
#   3. A "classic" pre-ftyp QuickTime movie that starts directly with a
#      top-level atom (here: `moov`) instead of an ISO-BMFF `ftyp` box at
#      all -- the exact durable-storage shape
#      `sell_draft_media/<draftId>/video_XXXXXXXX.mov` real devices were
#      observed producing. Was INCORRECTLY rejected before this fix.
MOV_CLASSIC_ATOM_HEADER = b"\x00\x00\x00\x08moov" + b"\x00" * 24
WEBM_HEADER = b"\x1a\x45\xdf\xa3" + b"\x00" * 28
WAV_HEADER = b"RIFF\x00\x00\x00\x00WAVEfmt " + b"\x00" * 16
MP3_HEADER = b"ID3\x03\x00\x00\x00" + b"\x00" * 24
OGG_HEADER = b"OggS" + b"\x00" * 28
AMR_HEADER = b"#!AMR\n" + b"\x00" * 26
M4A_HEADER = b"\x00\x00\x00\x18ftypM4A " + b"\x00" * 16
# Not a valid image/video/audio of any kind under any extension.
HTML_PAYLOAD = b"<html><body><script>alert(1)</script></body></html>\x00\x00"


# ---------------------------------------------------------------------------
# A. kk/security.py — sniff_bytes() unit tests
# ---------------------------------------------------------------------------


class TestSniffBytes:
    def test_valid_jpeg_accepted(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(JPEG_HEADER, "jpg") is True
        assert sniff_bytes(JPEG_HEADER, ".jpeg") is True

    def test_html_disguised_as_jpeg_rejected(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "jpg") is False

    def test_valid_png_accepted(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(PNG_HEADER, "png") is True

    def test_html_disguised_as_png_rejected(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "png") is False

    def test_valid_mp4_accepted(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(MP4_HEADER, "mp4") is True

    def test_html_disguised_as_mp4_rejected(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "mp4") is False

    # -- Issue-3 fix: .mov content validation (real-device HTTP 400) -------

    def test_valid_mov_with_qt_brand_accepted(self):
        """The canonical QuickTime ftyp brand -- already worked before the
        fix; guards against a future change accidentally narrowing this
        back."""
        from kk.security import sniff_bytes

        assert sniff_bytes(MOV_QT_BRAND_HEADER, "mov") is True

    def test_valid_mov_with_mp4_family_brand_accepted(self):
        """Real-device root cause: a `.mov` file whose ftyp major_brand is
        an MP4-family code (e.g. "isom") instead of the exact "qt  " code
        -- MOV and MP4 share the same ISO-BMFF container format, so this is
        a genuinely valid, playable .mov file that must not be rejected."""
        from kk.security import sniff_bytes

        assert sniff_bytes(MOV_ISOM_BRAND_HEADER, "mov") is True

    def test_valid_classic_pre_ftyp_mov_accepted(self):
        """Real-device root cause: a "classic" QuickTime movie that predates
        the ftyp box entirely and starts directly with a top-level atom
        (`moov`) -- the exact shape seen in durable storage paths like
        `sell_draft_media/<draftId>/video_XXXXXXXX.mov`."""
        from kk.security import sniff_bytes

        assert sniff_bytes(MOV_CLASSIC_ATOM_HEADER, "mov") is True

    def test_html_disguised_as_mov_rejected(self):
        """Still narrow/safe: arbitrary non-video content disguised with a
        `.mov` extension has neither a real ISO-BMFF ftyp box with an
        MP4/QuickTime brand nor one of the specific classic atom names at
        the exact expected offset, so it is still rejected."""
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "mov") is False

    def test_mp4_family_ftyp_with_unrelated_atom_name_still_rejected(self):
        """A ftyp box whose brand is neither QuickTime nor a known MP4-
        family brand must still be rejected -- proves the fix only widened
        acceptance to genuine MP4/QuickTime container brands, not to any
        arbitrary 4-byte value."""
        from kk.security import sniff_bytes

        bogus_brand_header = b"\x00\x00\x00\x14ftypzzzz" + b"\x00" * 16
        assert sniff_bytes(bogus_brand_header, "mov") is False

    # -- Spoofability follow-up: classic-atom acceptance must validate the --
    # -- atom's SIZE field too, not just match the 4-byte type name. -------

    def test_classic_atom_with_impossibly_small_size_is_rejected(self):
        """`moov` at the right offset is not enough on its own -- the size
        field immediately before it must also be a structurally plausible
        atom size. An atom can never be smaller than its own 8-byte
        `size+type` header, so a declared size of 3 is impossible for a
        genuine atom and must be rejected even though the type name
        matches exactly."""
        from kk.security import sniff_bytes

        random_bytes_with_moov_type = (
            struct.pack(">I", 3) + b"moov" + bytes(range(16))
        )
        assert sniff_bytes(random_bytes_with_moov_type, "mov") is False

    def test_classic_atom_with_invalid_length_and_mdat_type_is_rejected(self):
        """Same structural-size check, for a different atom type (`mdat`)
        and a different impossible size (5) -- proves this isn't special-
        cased to just `moov`."""
        from kk.security import sniff_bytes

        invalid_length_mdat = struct.pack(">I", 5) + b"mdat" + bytes(range(16))
        assert sniff_bytes(invalid_length_mdat, "mov") is False

    def test_classic_atom_size_zero_extends_to_eof_is_accepted(self):
        """Size 0 is a legitimate, well-defined ISO-BMFF/QuickTime meaning
        ("this atom extends to the end of the file") -- commonly used for
        a trailing `mdat` -- and must still be accepted."""
        from kk.security import sniff_bytes

        size_zero_mdat = struct.pack(">I", 0) + b"mdat" + bytes(range(16))
        assert sniff_bytes(size_zero_mdat, "mov") is True

    def test_classic_atom_valid_64_bit_extended_size_is_accepted(self):
        """Size == 1 is the ISO-BMFF escape code for a 64-bit extended size
        in the next 8 bytes -- a real, legal atom shape (used for atoms
        too large for a 32-bit size field) -- and must be accepted when
        that 64-bit value is itself plausible."""
        from kk.security import sniff_bytes

        valid_extended_size_moov = (
            struct.pack(">I", 1)
            + b"moov"
            + struct.pack(">Q", 5_000_000_000)
            + bytes(range(8))
        )
        assert sniff_bytes(valid_extended_size_moov, "mov") is True

    def test_classic_atom_malformed_64_bit_extended_size_is_rejected(self):
        """Size == 1 (extended-size escape code) but the 64-bit value that
        follows is itself impossibly small (< 16, the minimum possible
        length of an extended-size atom header) -- structurally invalid,
        must be rejected."""
        from kk.security import sniff_bytes

        malformed_extended_size_moov = (
            struct.pack(">I", 1)
            + b"moov"
            + struct.pack(">Q", 4)
            + bytes(range(8))
        )
        assert sniff_bytes(malformed_extended_size_moov, "mov") is False

    def test_classic_atom_truncated_extended_size_header_is_rejected(self):
        """Size == 1 (extended-size escape code) but the header is too
        short to even contain the 8-byte extended size field at all --
        must be rejected, not treated as a match."""
        from kk.security import sniff_bytes

        truncated_extended_size_moov = struct.pack(">I", 1) + b"moov" + b"\x00\x00"
        assert sniff_bytes(truncated_extended_size_moov, "mov") is False

    def test_truncated_ftyp_box_missing_brand_bytes_is_rejected(self):
        """A `ftyp` box header cut off before its 4-byte major_brand field
        is fully present must fail closed (no brand to validate at all),
        not be coincidentally treated as a classic atom either (`ftyp` is
        not itself a recognized classic QuickTime atom type)."""
        from kk.security import sniff_bytes

        truncated_ftyp = b"\x00\x00\x00\x14ftypqt"
        assert sniff_bytes(truncated_ftyp, "mov") is False

    def test_random_payload_renamed_mov_is_rejected(self):
        """A payload with no recognizable ISO-BMFF/QuickTime structure at
        all, merely renamed with a `.mov` extension, must still be
        rejected -- the classic-atom/ftyp widening does not turn this into
        an "accept everything" check."""
        from kk.security import sniff_bytes

        random_payload = bytes((i * 37 + 11) % 256 for i in range(32))
        assert sniff_bytes(random_payload, "mov") is False

    def test_valid_webm_accepted(self):
        """Same EBML container check backs both video .webm and audio .webm."""
        from kk.security import sniff_bytes

        assert sniff_bytes(WEBM_HEADER, "webm") is True

    def test_html_disguised_as_webm_rejected(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "webm") is False

    def test_valid_wav_accepted(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(WAV_HEADER, "wav") is True

    def test_html_disguised_as_wav_rejected(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "wav") is False

    def test_valid_mp3_accepted(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(MP3_HEADER, "mp3") is True

    def test_html_disguised_as_mp3_rejected(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "mp3") is False

    def test_valid_ogg_accepted(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(OGG_HEADER, "ogg") is True

    def test_html_disguised_as_ogg_rejected(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "ogg") is False

    def test_valid_amr_accepted(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(AMR_HEADER, "amr") is True

    def test_html_disguised_as_amr_rejected(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "amr") is False

    def test_valid_m4a_accepted(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(M4A_HEADER, "m4a") is True

    def test_html_disguised_as_m4a_rejected(self):
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "m4a") is False

    def test_unknown_extension_defaults_to_accept(self):
        """Behavior-preserving: extensions with no signature check configured
        are not newly rejected by this refactor (size/extension allow-lists
        elsewhere still gate what's accepted)."""
        from kk.security import sniff_bytes

        assert sniff_bytes(HTML_PAYLOAD, "txt") is True

    def test_heic_extension_accepts_transcoded_jpeg_bytes(self):
        """Mobile pipelines sometimes transcode HEIC -> JPEG but keep the
        original .heic filename extension; this leniency must be preserved
        by the extraction."""
        from kk.security import sniff_bytes

        assert sniff_bytes(JPEG_HEADER, "heic") is True


# ---------------------------------------------------------------------------
# B. kk/security.py — validate_file_upload_security() unchanged behavior
# ---------------------------------------------------------------------------


class TestValidateFileUploadSecurityUnchanged:
    def _file(self, name: str, content: bytes):
        from werkzeug.datastructures import FileStorage

        return FileStorage(stream=io.BytesIO(content), filename=name)

    def test_valid_jpeg_passes(self):
        from kk.security import validate_file_upload

        ok, msg = validate_file_upload(
            self._file("photo.jpg", JPEG_HEADER + b"rest-of-jpeg-file"),
            allowed_extensions={"jpg", "jpeg", "png"},
        )
        assert ok is True, msg

    def test_html_disguised_as_jpeg_still_rejected(self):
        from kk.security import validate_file_upload

        ok, msg = validate_file_upload(
            self._file("photo.jpg", HTML_PAYLOAD),
            allowed_extensions={"jpg", "jpeg", "png"},
        )
        assert ok is False
        assert "does not match its extension" in msg

    def test_disallowed_extension_still_rejected_before_sniffing(self):
        from kk.security import validate_file_upload

        ok, msg = validate_file_upload(
            self._file("payload.exe", JPEG_HEADER),
            allowed_extensions={"jpg", "jpeg", "png"},
        )
        assert ok is False
        assert "not allowed" in msg

    def test_oversized_file_still_rejected_before_sniffing(self):
        from kk.security import validate_file_upload

        big = JPEG_HEADER + (b"\x00" * (2 * 1024 * 1024))
        ok, msg = validate_file_upload(
            self._file("photo.jpg", big),
            allowed_extensions={"jpg", "jpeg", "png"},
            max_size_mb=1,
        )
        assert ok is False
        assert "too large" in msg.lower()


# ---------------------------------------------------------------------------
# Shared Flask app fixtures for the HTTP-level tests (C, E, F below)
# ---------------------------------------------------------------------------

FAKE_CHAT_BUCKET_CONFIG = {
    "R2_ACCOUNT_ID": "test-account-id",
    "R2_CHAT_BUCKET_NAME": "carzo-chat-media-test",
    "R2_CHAT_ACCESS_KEY_ID": "test-chat-access-key",
    "R2_CHAT_SECRET_ACCESS_KEY": "test-chat-secret-key",
}


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_h03_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "h03.db")

    from kk.app_factory import create_app

    app, socketio, *_ = create_app()
    app.config.update(FAKE_CHAT_BUCKET_CONFIG)
    from kk.models import Car, Message, User, db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, socketio, app.test_client(), db, User, Car, Message

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[2]


@pytest.fixture(autouse=True)
def _mock_chat_r2_put(monkeypatch):
    """Never touch real network/subprocess R2 calls in this file. Content
    validation runs BEFORE r2_chat_put_bytes is ever called, so mocking it
    does not weaken what these tests actually exercise."""
    from kk import r2_ops

    monkeypatch.setattr(r2_ops, "r2_chat_put_bytes", MagicMock())


def _unique_phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _make_user(app_ctx, *, username: str, phone: str) -> str:
    app, _socketio, _client, db, User, *_ = app_ctx
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
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.public_id


def _login(client, username: str, password: str = "Aa123456!") -> str:
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(scope="module")
def seller_ctx(app_ctx):
    username = f"h03_seller_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


@pytest.fixture(scope="module")
def buyer_ctx(app_ctx):
    username = f"h03_buyer_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


def _make_car(app_ctx, seller_public_id: str) -> str:
    app, _socketio, _client, db, User, Car, *_ = app_ctx
    with app.app_context():
        seller = User.query.filter_by(public_id=seller_public_id).first()
        car = Car(
            seller_id=seller.id,
            brand="toyota",
            model="corolla",
            year=2021,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="sedan",
            price=15.0,
            location="Erbil",
            is_active=True,
        )
        db.session.add(car)
        db.session.commit()
        return car.public_id


def _open_thread(client, app_ctx, seller_ctx, buyer_ctx):
    """Create a fresh car + establish a message thread; return
    (car_public_id, seller_token, buyer_public_id)."""
    seller_username, seller_public = seller_ctx
    buyer_username, buyer_public = buyer_ctx
    car_public = _make_car(app_ctx, seller_public)
    seller_token = _login(client, seller_username)
    buyer_token = _login(client, buyer_username)
    resp = client.post(
        f"/api/chat/{car_public}/send",
        headers=_auth(buyer_token),
        json={"content": "hi", "receiver_id": seller_public},
    )
    assert resp.status_code == 201, resp.data
    return car_public, seller_token, buyer_public


# ---------------------------------------------------------------------------
# C. kk/routes/chat.py — real content validation on chat attachment uploads
# ---------------------------------------------------------------------------


class TestChatAttachmentContentValidation:
    def test_send_image_rejects_html_disguised_as_jpeg(
        self, app_ctx, client, seller_ctx, buyer_ctx
    ):
        car_public, seller_token, buyer_public = _open_thread(
            client, app_ctx, seller_ctx, buyer_ctx
        )
        resp = client.post(
            f"/api/chat/{car_public}/send_image",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(HTML_PAYLOAD), "photo.jpg"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.data
        assert "Unsupported image format" in resp.get_json()["message"]

    def test_send_image_accepts_real_jpeg(self, app_ctx, client, seller_ctx, buyer_ctx):
        car_public, seller_token, buyer_public = _open_thread(
            client, app_ctx, seller_ctx, buyer_ctx
        )
        with patch("kk.chat_realtime.send_push"):
            resp = client.post(
                f"/api/chat/{car_public}/send_image",
                headers=_auth(seller_token),
                data={
                    "receiver_id": buyer_public,
                    "file": (io.BytesIO(JPEG_HEADER + b"rest-of-file"), "photo.jpg"),
                },
                content_type="multipart/form-data",
            )
        assert resp.status_code == 201, resp.data

    def test_send_video_rejects_html_disguised_as_mp4(
        self, app_ctx, client, seller_ctx, buyer_ctx
    ):
        car_public, seller_token, buyer_public = _open_thread(
            client, app_ctx, seller_ctx, buyer_ctx
        )
        resp = client.post(
            f"/api/chat/{car_public}/send_video",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(HTML_PAYLOAD), "clip.mp4"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.data
        assert "Unsupported video format" in resp.get_json()["message"]

    def test_send_video_accepts_real_mp4(self, app_ctx, client, seller_ctx, buyer_ctx):
        car_public, seller_token, buyer_public = _open_thread(
            client, app_ctx, seller_ctx, buyer_ctx
        )
        with patch("kk.chat_realtime.send_push"):
            resp = client.post(
                f"/api/chat/{car_public}/send_video",
                headers=_auth(seller_token),
                data={
                    "receiver_id": buyer_public,
                    "file": (io.BytesIO(MP4_HEADER + b"rest-of-file"), "clip.mp4"),
                },
                content_type="multipart/form-data",
            )
        assert resp.status_code == 201, resp.data

    def test_send_audio_rejects_html_disguised_as_m4a(
        self, app_ctx, client, seller_ctx, buyer_ctx
    ):
        car_public, seller_token, buyer_public = _open_thread(
            client, app_ctx, seller_ctx, buyer_ctx
        )
        resp = client.post(
            f"/api/chat/{car_public}/send_audio",
            headers=_auth(seller_token),
            data={
                "receiver_id": buyer_public,
                "file": (io.BytesIO(HTML_PAYLOAD), "voice.m4a"),
            },
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.data
        assert "Unsupported audio format" in resp.get_json()["message"]

    def test_send_audio_accepts_real_m4a(self, app_ctx, client, seller_ctx, buyer_ctx):
        car_public, seller_token, buyer_public = _open_thread(
            client, app_ctx, seller_ctx, buyer_ctx
        )
        with patch("kk.chat_realtime.send_push"):
            resp = client.post(
                f"/api/chat/{car_public}/send_audio",
                headers=_auth(seller_token),
                data={
                    "receiver_id": buyer_public,
                    "file": (io.BytesIO(M4A_HEADER + b"rest-of-file"), "voice.m4a"),
                },
                content_type="multipart/form-data",
            )
        assert resp.status_code == 201, resp.data

    def test_send_media_group_rejects_one_bad_file_among_valid_ones(
        self, app_ctx, client, seller_ctx, buyer_ctx
    ):
        car_public, seller_token, buyer_public = _open_thread(
            client, app_ctx, seller_ctx, buyer_ctx
        )
        files = [
            (io.BytesIO(JPEG_HEADER + b"a"), "a.jpg"),
            (io.BytesIO(HTML_PAYLOAD), "b.jpg"),
        ]
        resp = client.post(
            f"/api/chat/{car_public}/send_media_group",
            headers=_auth(seller_token),
            data={"receiver_id": buyer_public, "attachments": files},
            content_type="multipart/form-data",
        )
        assert resp.status_code == 400, resp.data

    def test_send_media_group_accepts_all_valid_files(
        self, app_ctx, client, seller_ctx, buyer_ctx
    ):
        car_public, seller_token, buyer_public = _open_thread(
            client, app_ctx, seller_ctx, buyer_ctx
        )
        files = [
            (io.BytesIO(JPEG_HEADER + b"a"), "a.jpg"),
            (io.BytesIO(MP4_HEADER + b"b"), "b.mp4"),
        ]
        with patch("kk.chat_realtime.send_push"):
            resp = client.post(
                f"/api/chat/{car_public}/send_media_group",
                headers=_auth(seller_token),
                data={"receiver_id": buyer_public, "attachments": files},
                content_type="multipart/form-data",
            )
        assert resp.status_code == 201, resp.data
        assert len(resp.get_json()["message"]["attachments"]) == 2


# ---------------------------------------------------------------------------
# D. tools/r2_s3_op.py — presign_put still signs Content-Type + Content-Length
# ---------------------------------------------------------------------------


class TestPresignPutSignsContentTypeAndLength:
    def test_signed_headers_include_content_type_and_length(self):
        """This is the control that keeps the presigned-PUT flow safe from
        Content-Type spoofing even while disabled by default (and if ever
        re-enabled): R2 must reject a PUT whose actual Content-Type /
        Content-Length don't match what the server signed. Regression
        guard — if a future change to tools/r2_s3_op.py stops passing these
        as signed Params, this test catches it. Uses dummy, non-network
        credentials; this is a pure local signing computation."""
        script = str(_REPO_ROOT / "tools" / "r2_s3_op.py")
        payload = {
            "op": "presign_put",
            "account_id": "dummy-account",
            "bucket": "dummy-bucket",
            "access_key": "AKIADUMMYDUMMYDUMMY",
            "secret_key": "dummysecretdummysecretdummysecretdummy1",
            "key": "car_photos/test.jpg",
            "content_type": "image/jpeg",
            "content_length": 12345,
            "expires_in": 900,
        }
        proc = subprocess.run(
            [sys.executable, script],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert proc.stdout.strip(), proc.stderr
        result = json.loads(proc.stdout)
        assert result.get("ok") is True, result

        url = result["upload_url"]
        signed_headers = parse_qs(urlparse(url).query)["X-Amz-SignedHeaders"][0]
        assert "content-type" in signed_headers
        assert "content-length" in signed_headers
        assert "host" in signed_headers


# ---------------------------------------------------------------------------
# E. kk/routes/media.py — presigned-upload endpoint disabled by default
# ---------------------------------------------------------------------------


class TestPresignedUploadFeatureFlag:
    def test_sign_upload_returns_404_by_default(self, app_ctx, client, seller_ctx):
        os.environ.pop("R2_PRESIGNED_UPLOAD_ENABLED", None)
        username, _public_id = seller_ctx
        token = _login(client, username)
        resp = client.post(
            "/api/media/r2/sign-upload",
            headers=_auth(token),
            json={
                "filename": "photo.jpg",
                "content_type": "image/jpeg",
                "content_length": 1000,
            },
        )
        assert resp.status_code == 404, resp.data

    def test_sign_upload_binds_content_type_and_length_when_explicitly_enabled(
        self, app_ctx, client, seller_ctx, monkeypatch
    ):
        """If an operator explicitly re-enables this path, the endpoint must
        still request Content-Type + Content-Length signing from
        r2_presign_put(). This is a wiring smoke test (r2_presign_put is
        mocked; no real R2 call is made)."""
        app = app_ctx[0]
        monkeypatch.setitem(app.config, "R2_ACCOUNT_ID", "acc")
        monkeypatch.setitem(app.config, "R2_BUCKET_NAME", "bucket")
        monkeypatch.setitem(app.config, "R2_ACCESS_KEY_ID", "key")
        monkeypatch.setitem(app.config, "R2_SECRET_ACCESS_KEY", "secret")
        monkeypatch.setenv("R2_PRESIGNED_UPLOAD_ENABLED", "1")

        username, _public_id = seller_ctx
        token = _login(client, username)

        captured = {}

        def _fake_presign_put(*, key, content_type, expires_in, content_length=None, timeout=30):
            captured["content_type"] = content_type
            captured["content_length"] = content_length
            return "https://example.test/fake-presigned-put"

        from kk import r2_ops

        monkeypatch.setattr(r2_ops, "r2_presign_put", _fake_presign_put)

        resp = client.post(
            "/api/media/r2/sign-upload",
            headers=_auth(token),
            json={
                "filename": "photo.jpg",
                "content_type": "image/jpeg",
                "content_length": 1000,
            },
        )
        assert resp.status_code == 200, resp.data
        assert captured["content_type"] == "image/jpeg"
        assert captured["content_length"] == 1000


# ---------------------------------------------------------------------------
# F. Combined guarantee: attach() can never receive presign-staged,
#    content-unvalidated bytes while the presign endpoint is disabled
#    (default). attach()'s own ownership checks are covered separately in
#    test_media_attach_ownership.py; this test covers the remaining half of
#    the chain — that a staged key can never be created in the first place.
# ---------------------------------------------------------------------------


class TestAttachProtectedByDisabledPresignPath:
    def test_no_way_to_obtain_a_staged_upload_url_when_presign_disabled(
        self, app_ctx, client, seller_ctx
    ):
        """H-03: attach_car_images() performs no content validation of its
        own (unchanged by this fix) — it only checks that a URL is either
        already owned (existing CarImage row) or carries the caller's own
        owner-tag prefix. With sign-upload disabled by default, there is no
        way for ANY client (official app or a raw API caller) to ever cause
        unvalidated bytes to exist under a fresh `car_photos/`/`car_videos/`
        key: every path that can populate those keys today
        (`/api/cars/<id>/images`, `/api/cars/<id>/videos`,
        `/api/process-car-images`) runs sniff_bytes()/validate_file_upload
        before writing to R2. This proves the first link in the presign
        chain (obtaining a presigned PUT URL at all) is unreachable by
        default."""
        os.environ.pop("R2_PRESIGNED_UPLOAD_ENABLED", None)
        username, _public_id = seller_ctx
        token = _login(client, username)
        resp = client.post(
            "/api/media/r2/sign-upload",
            headers=_auth(token),
            json={
                "filename": "photo.jpg",
                "content_type": "image/jpeg",
                "content_length": 1000,
                "asset": "image",
            },
        )
        assert resp.status_code == 404
        body = resp.get_json() or {}
        assert "upload_url" not in body
        assert "key" not in body
