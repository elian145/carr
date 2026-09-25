"""Phase 1 of the server-side video transcode fallback: SECURE DIRECT-TO-R2
SOURCE-VIDEO STAGING.

Scope of this phase (see the architecture audit for the full picture): an
authenticated seller can upload an OVERSIZED SOURCE video directly to
temporary R2 staging without proxying the bytes through Flask/Render.
This is temporary source storage only -- NOT final listing media. The
final-listing-video cap (100MB, ``upload_car_videos()`` ->
``validate_file_upload(max_size_mb=100)``) is untouched and unrelated.

No transcoding is implemented yet, and there is no client caller yet -- this
file only covers the two new backend endpoints
(``POST /api/media/r2/sign-video-source-upload`` /
``POST /api/media/r2/finalize-video-source-upload``) plus the Celery Beat
staging-cleanup sweep for ``car_videos/_staging/``.

Content-validation limitation (documented per the audit, not a gap in these
tests): because the video bytes are PUT directly to R2, this process never
sees them, so neither endpoint can run the magic-byte/codec check that the
multipart upload endpoints run. Signing enforces the CLIENT'S DECLARED
content-type/size (cryptographically bound into the presigned URL);
finalize enforces the object's ACTUAL size and stored content-type
metadata. Neither proves the bytes are a genuinely valid, decodable video --
that only happens later, in the not-yet-built transcode step's ffprobe
validation. These tests therefore only ever assert "staged" / rejected at
the sign+finalize contract level, never "verified playable video".

No real Cloudflare credentials are used anywhere in this file -- every R2
call is mocked.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

import kk.r2_ops as r2_ops_module  # noqa: E402

_PASSWORD = "Aa123456!"
_R2_KEYS = (
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
)

_SIGN_URL = "/api/media/r2/sign-video-source-upload"
_FINALIZE_URL = "/api/media/r2/finalize-video-source-upload"
_MAX_BYTES = 500 * 1024 * 1024


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_vidstage_", ignore_cleanup_errors=True)
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "vidstage.db")
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
    """Fake R2 config for the duration of one test -- monkeypatch reverts
    this automatically afterward."""
    app = app_ctx[0]
    for key in _R2_KEYS:
        monkeypatch.setitem(app.config, key, f"test-{key.lower()}")
    return app


@pytest.fixture(autouse=True)
def _enable_video_source_staging(monkeypatch):
    """The feature is gated off by default (see
    ``_video_source_staging_enabled()``'s docstring -- mirrors the H-03
    precedent for the sibling, still-unwired presigned-upload endpoint).
    Every test in this file exercises the endpoints as if the feature were
    turned on; the "disabled by default" contract itself is covered by
    ``TestFeatureFlagDefaultsOff`` below, which explicitly un-sets this."""
    monkeypatch.setenv("VIDEO_SOURCE_STAGING_ENABLED", "1")


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
    username = f"vidstage_seller_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


@pytest.fixture(scope="module")
def other_seller_ctx(app_ctx):
    username = f"vidstage_other_{uuid.uuid4().hex[:8]}"
    public_id = _make_user(app_ctx, username=username, phone=_unique_phone())
    return username, public_id


def _sign_body(draft_media_id="draft-abc123", content_length=10 * 1024 * 1024, **overrides):
    body = {
        "draft_media_id": draft_media_id,
        "filename": "clip.mov",
        "content_type": "video/quicktime",
        "content_length": content_length,
    }
    body.update(overrides)
    return body


@pytest.fixture(autouse=True)
def _mock_r2_presign_put(monkeypatch):
    """Never touch a real subprocess/network R2 call -- signing itself is
    fully covered elsewhere (test_h03_upload_content_validation.py's
    TestPresignPutSignsContentTypeAndLength); this file only needs to prove
    THIS endpoint calls it correctly and returns a safe response."""

    def _fake_presign_put(*, key, content_type, expires_in, content_length=None, timeout=30):
        return f"https://example-r2-test.invalid/{key}?sig=fake"

    monkeypatch.setattr(r2_ops_module, "r2_presign_put", _fake_presign_put)


# ---------------------------------------------------------------------------
# sign-video-source-upload
# ---------------------------------------------------------------------------


class TestSignVideoSourceUpload:
    def test_unauthenticated_request_rejected(self, client, r2_configured):
        resp = client.post(_SIGN_URL, json=_sign_body())
        assert resp.status_code == 401, resp.data

    def test_zero_size_rejected(self, client, r2_configured, seller_ctx):
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _SIGN_URL, headers=_auth(token), json=_sign_body(content_length=0)
        )
        assert resp.status_code == 400, resp.data

    def test_negative_size_rejected(self, client, r2_configured, seller_ctx):
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _SIGN_URL, headers=_auth(token), json=_sign_body(content_length=-5)
        )
        assert resp.status_code == 400, resp.data

    def test_oversized_source_rejected(self, client, r2_configured, seller_ctx):
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _SIGN_URL,
            headers=_auth(token),
            json=_sign_body(content_length=_MAX_BYTES + 1),
        )
        assert resp.status_code == 400, resp.data
        assert "500" in resp.get_json()["message"] or str(_MAX_BYTES) in resp.get_json()["message"]

    def test_valid_size_at_cap_accepted(self, client, r2_configured, seller_ctx):
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _SIGN_URL,
            headers=_auth(token),
            json=_sign_body(content_length=_MAX_BYTES),
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert body["upload_url"]
        assert body["staging_key"].startswith("car_videos/_staging/")
        assert body["staging_key"].endswith(".src")
        assert body["max_bytes"] == _MAX_BYTES
        # Never leaks R2 credentials.
        assert "access_key" not in body
        assert "secret_key" not in body
        assert "account_id" not in body

    def test_invalid_mime_rejected(self, client, r2_configured, seller_ctx):
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _SIGN_URL,
            headers=_auth(token),
            json=_sign_body(content_type="text/html"),
        )
        assert resp.status_code == 400, resp.data

    @pytest.mark.parametrize(
        "bad_id",
        [
            "",
            "../../etc/passwd",
            "a/b",
            "a\\b",
            "..",
            "a" * 200,  # too long
            "has space",
            "emoji-\U0001f600",
        ],
    )
    def test_malformed_draft_media_id_rejected(self, client, r2_configured, seller_ctx, bad_id):
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _SIGN_URL, headers=_auth(token), json=_sign_body(draft_media_id=bad_id)
        )
        assert resp.status_code == 400, resp.data

    def test_same_owner_same_draft_media_id_yields_same_key(
        self, client, r2_configured, seller_ctx
    ):
        token = _login(client, seller_ctx[0])
        r1 = client.post(
            _SIGN_URL, headers=_auth(token), json=_sign_body(draft_media_id="stable-id-1")
        )
        r2 = client.post(
            _SIGN_URL, headers=_auth(token), json=_sign_body(draft_media_id="stable-id-1")
        )
        assert r1.status_code == 200 and r2.status_code == 200
        assert r1.get_json()["staging_key"] == r2.get_json()["staging_key"]

    def test_different_owner_same_draft_media_id_yields_different_key(
        self, client, r2_configured, seller_ctx, other_seller_ctx
    ):
        token_a = _login(client, seller_ctx[0])
        token_b = _login(client, other_seller_ctx[0])
        ra = client.post(
            _SIGN_URL, headers=_auth(token_a), json=_sign_body(draft_media_id="shared-id")
        )
        rb = client.post(
            _SIGN_URL, headers=_auth(token_b), json=_sign_body(draft_media_id="shared-id")
        )
        assert ra.status_code == 200 and rb.status_code == 200
        key_a = ra.get_json()["staging_key"]
        key_b = rb.get_json()["staging_key"]
        assert key_a != key_b
        # Both still land under the shared temporary-staging prefix.
        assert key_a.startswith("car_videos/_staging/")
        assert key_b.startswith("car_videos/_staging/")

    def test_repeated_calls_after_restart_do_not_create_orphan_keys(
        self, client, r2_configured, seller_ctx
    ):
        """Simulates "app restart, retry the same pick" -- three separate
        sign calls for the same draft_media_id must resolve to exactly one
        staging key, not three."""
        token = _login(client, seller_ctx[0])
        keys = set()
        for _ in range(3):
            resp = client.post(
                _SIGN_URL,
                headers=_auth(token),
                json=_sign_body(draft_media_id="resume-after-restart"),
            )
            assert resp.status_code == 200
            keys.add(resp.get_json()["staging_key"])
        assert len(keys) == 1


# ---------------------------------------------------------------------------
# finalize-video-source-upload
# ---------------------------------------------------------------------------


def _mock_head_object(monkeypatch, *, exists, size=0, content_type="video/quicktime"):
    def _fake_head_object(*, key, timeout=30):
        if not exists:
            return {"exists": False, "size": None, "content_type": None}
        return {"exists": True, "size": size, "content_type": content_type}

    monkeypatch.setattr(r2_ops_module, "r2_head_object", _fake_head_object)


class TestFinalizeVideoSourceUpload:
    def test_missing_object_rejected(self, client, r2_configured, seller_ctx, monkeypatch):
        _mock_head_object(monkeypatch, exists=False)
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL,
            headers=_auth(token),
            json={"draft_media_id": "never-uploaded"},
        )
        assert resp.status_code == 404, resp.data

    def test_oversized_actual_object_rejected(
        self, client, r2_configured, seller_ctx, monkeypatch
    ):
        _mock_head_object(monkeypatch, exists=True, size=_MAX_BYTES + 1)
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL,
            headers=_auth(token),
            json={"draft_media_id": "too-big"},
        )
        assert resp.status_code == 400, resp.data

    def test_empty_actual_object_rejected(self, client, r2_configured, seller_ctx, monkeypatch):
        _mock_head_object(monkeypatch, exists=True, size=0)
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL,
            headers=_auth(token),
            json={"draft_media_id": "empty-object"},
        )
        assert resp.status_code == 400, resp.data

    def test_disallowed_stored_content_type_rejected(
        self, client, r2_configured, seller_ctx, monkeypatch
    ):
        _mock_head_object(monkeypatch, exists=True, size=1024, content_type="text/html")
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL,
            headers=_auth(token),
            json={"draft_media_id": "bad-content-type"},
        )
        assert resp.status_code == 400, resp.data

    def test_valid_staged_object_finalizes_successfully(
        self, client, r2_configured, seller_ctx, monkeypatch
    ):
        _mock_head_object(monkeypatch, exists=True, size=12345, content_type="video/quicktime")
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL,
            headers=_auth(token),
            json={"draft_media_id": "good-video"},
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert body["status"] == "staged"
        assert body["size"] == 12345
        assert body["staging_key"].startswith("car_videos/_staging/")

    def test_finalize_is_idempotent(self, client, r2_configured, seller_ctx, monkeypatch):
        _mock_head_object(monkeypatch, exists=True, size=999, content_type="video/mp4")
        token = _login(client, seller_ctx[0])
        r1 = client.post(
            _FINALIZE_URL, headers=_auth(token), json={"draft_media_id": "idempotent-check"}
        )
        r2 = client.post(
            _FINALIZE_URL, headers=_auth(token), json={"draft_media_id": "idempotent-check"}
        )
        assert r1.status_code == 200 and r2.status_code == 200
        assert r1.get_json() == r2.get_json()

    def test_owner_cannot_finalize_another_owners_staging_key(
        self, client, r2_configured, seller_ctx, other_seller_ctx, monkeypatch
    ):
        """Seller A signs (establishing their real, owner-scoped key for
        this draft_media_id). Seller B then tries to finalize using
        Seller A's exact key, under Seller B's own auth + the SAME
        draft_media_id string. The server must reject this, not silently
        finalize Seller A's object on Seller B's behalf."""
        token_a = _login(client, seller_ctx[0])
        sign_resp = client.post(
            _SIGN_URL,
            headers=_auth(token_a),
            json=_sign_body(draft_media_id="owner-isolated-id"),
        )
        assert sign_resp.status_code == 200
        seller_a_key = sign_resp.get_json()["staging_key"]

        _mock_head_object(monkeypatch, exists=True, size=555, content_type="video/mp4")
        token_b = _login(client, other_seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL,
            headers=_auth(token_b),
            json={"draft_media_id": "owner-isolated-id", "staging_key": seller_a_key},
        )
        assert resp.status_code == 403, resp.data

    def test_malformed_draft_media_id_rejected(self, client, r2_configured, seller_ctx):
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL,
            headers=_auth(token),
            json={"draft_media_id": "../../etc/passwd"},
        )
        assert resp.status_code == 400, resp.data

    def test_unauthenticated_finalize_rejected(self, client, r2_configured):
        resp = client.post(_FINALIZE_URL, json={"draft_media_id": "whatever"})
        assert resp.status_code == 401, resp.data


# ---------------------------------------------------------------------------
# Feature flag default (mirrors the H-03 precedent for the sibling,
# still-unwired presigned-upload endpoint)
# ---------------------------------------------------------------------------


class TestFeatureFlagDefaultsOff:
    def test_sign_endpoint_404s_when_flag_unset(self, client, r2_configured, seller_ctx, monkeypatch):
        monkeypatch.delenv("VIDEO_SOURCE_STAGING_ENABLED", raising=False)
        token = _login(client, seller_ctx[0])
        resp = client.post(_SIGN_URL, headers=_auth(token), json=_sign_body())
        assert resp.status_code == 404, resp.data

    def test_finalize_endpoint_404s_when_flag_unset(
        self, client, r2_configured, seller_ctx, monkeypatch
    ):
        monkeypatch.delenv("VIDEO_SOURCE_STAGING_ENABLED", raising=False)
        token = _login(client, seller_ctx[0])
        resp = client.post(
            _FINALIZE_URL, headers=_auth(token), json={"draft_media_id": "whatever"}
        )
        assert resp.status_code == 404, resp.data


# ---------------------------------------------------------------------------
# video_source_staging_key() / is_valid_draft_media_id() -- pure unit tests
# ---------------------------------------------------------------------------


class TestVideoSourceStagingKeyUnit:
    def test_deterministic_for_same_inputs(self, app_ctx):
        from kk.media_processing import video_source_staging_key

        with app_ctx[0].app_context():
            k1 = video_source_staging_key("pub-owner-1", "draft-1")
            k2 = video_source_staging_key("pub-owner-1", "draft-1")
        assert k1 == k2
        assert k1 is not None

    def test_differs_by_owner(self, app_ctx):
        from kk.media_processing import video_source_staging_key

        with app_ctx[0].app_context():
            k1 = video_source_staging_key("pub-owner-1", "draft-1")
            k2 = video_source_staging_key("pub-owner-2", "draft-1")
        assert k1 != k2

    def test_differs_by_draft_media_id(self, app_ctx):
        from kk.media_processing import video_source_staging_key

        with app_ctx[0].app_context():
            k1 = video_source_staging_key("pub-owner-1", "draft-1")
            k2 = video_source_staging_key("pub-owner-1", "draft-2")
        assert k1 != k2

    @pytest.mark.parametrize(
        "bad_id",
        ["", None, "../x", "a/b", "a\\b", "a" * 200, "has space"],
    )
    def test_returns_none_for_invalid_draft_media_id(self, app_ctx, bad_id):
        from kk.media_processing import video_source_staging_key

        with app_ctx[0].app_context():
            assert video_source_staging_key("pub-owner-1", bad_id) is None

    def test_key_never_contains_path_traversal_segments(self, app_ctx):
        from kk.media_processing import video_source_staging_key

        with app_ctx[0].app_context():
            key = video_source_staging_key("pub-owner-1", "safe-id_123")
        assert key is not None
        assert ".." not in key
        parts = key.split("/")
        assert all(p not in ("..", "") for p in parts)


# ---------------------------------------------------------------------------
# Celery Beat backstop cleanup for car_videos/_staging/
# ---------------------------------------------------------------------------


class TestCleanupStaleVideoStagingObjects:
    def test_noop_when_r2_not_configured(self, app_ctx, monkeypatch):
        from kk.tasks import video_tasks

        app = app_ctx[0]
        monkeypatch.setattr(
            r2_ops_module,
            "r2_cleanup_stale_staging",
            lambda **_kw: pytest.fail("must not call R2 when it is not configured"),
        )
        with app.app_context():
            out = video_tasks.cleanup_stale_video_staging_objects.run()
        assert out["ok"] is True
        assert out["deleted"] == 0

    def test_delegates_to_r2_cleanup_with_video_staging_prefix_and_age(
        self, app_ctx, r2_configured, monkeypatch
    ):
        from kk.tasks import video_tasks

        app = app_ctx[0]
        captured: dict = {}

        def fake_cleanup(*, prefix, older_than_seconds, timeout=60):
            captured["prefix"] = prefix
            captured["older_than_seconds"] = older_than_seconds
            return 3

        monkeypatch.setattr(r2_ops_module, "r2_cleanup_stale_staging", fake_cleanup)

        with app.app_context():
            out = video_tasks.cleanup_stale_video_staging_objects.run()

        assert out == {"ok": True, "deleted": 3}
        assert captured["prefix"] == "car_videos/_staging/"
        # Phase 2 follow-up: raised from 6h to 24h to avoid a race between
        # this sweep and a transcode task that is queued (not yet running)
        # when the sweep runs -- see
        # kk/tasks/video_tasks.py::_VIDEO_SOURCE_STAGING_STALE_AFTER_SECONDS's
        # docstring.
        assert captured["older_than_seconds"] == 24 * 3600

    def test_video_staging_prefix_never_matches_image_staging_prefix(self):
        """Safety check for the cleanup sweep's own targeting: the video
        and image staging prefixes must never overlap, or the video sweep
        (or the image sweep) could delete the other's objects."""
        from kk.media_processing import VIDEO_SOURCE_STAGING_KEY_PREFIX, _ASYNC_STAGING_KEY_PREFIX

        assert VIDEO_SOURCE_STAGING_KEY_PREFIX != _ASYNC_STAGING_KEY_PREFIX
        assert not VIDEO_SOURCE_STAGING_KEY_PREFIX.startswith(_ASYNC_STAGING_KEY_PREFIX)
        assert not _ASYNC_STAGING_KEY_PREFIX.startswith(VIDEO_SOURCE_STAGING_KEY_PREFIX)

    def test_beat_schedule_entry_matches_registered_task_name(self):
        """Same class of bug just fixed for the image-staging sweep --
        guard the new video-staging sweep from day one."""
        from kk.tasks import video_tasks
        from kk.tasks.celery_app import celery_app

        entry = celery_app.conf.beat_schedule["cleanup-stale-video-staging-objects"]
        assert entry["task"] == video_tasks.cleanup_stale_video_staging_objects.name
        assert entry["task"] in celery_app.tasks
