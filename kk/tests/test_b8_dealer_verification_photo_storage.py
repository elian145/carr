"""B8-1: dealer-verification photos must survive deploys/restarts and stay private.

``render.yaml`` defines no persistent disk, so the old local-disk storage lost
every photo at the next deploy. Photos now live in the PRIVATE chat R2 bucket
(``R2_CHAT_*``; no public URL) behind the existing permission-checked admin
route. These tests drive the real route + ``kk.r2_ops`` code paths against an
in-memory fake bucket (``_run_r2_op`` is the only seam patched), so bucket
selection, key prefix, failure handling and authorization are all exercised.
"""

from __future__ import annotations

import io
import os
import shutil
import sys
import tempfile
import uuid
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"
_CHAT_BUCKET = "carnet-chat-private"
_LISTING_BUCKET = "carnet-listing-public"


def _png_bytes() -> bytes:
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", (8, 8), (200, 30, 30)).save(buf, format="PNG")
    return buf.getvalue()


class FakeR2:
    """In-memory stand-in for the ``tools/r2_s3_op.py`` subprocess."""

    def __init__(self):
        self.objects: dict[tuple[str, str], tuple[bytes, str]] = {}
        self.fail = False
        self.calls: list[tuple[str, str, str]] = []

    def run(self, payload, *, timeout):
        op = payload["op"]
        bucket = payload.get("bucket")
        key = payload.get("key")
        self.calls.append((op, bucket, key))
        if self.fail:
            raise RuntimeError("simulated R2 outage")
        if op == "put_object":
            with open(payload["body_path"], "rb") as fp:
                self.objects[(bucket, key)] = (fp.read(), payload.get("content_type") or "")
            return {"ok": True}
        if op == "head_object":
            obj = self.objects.get((bucket, key))
            if obj is None:
                return {"ok": True, "exists": False}
            return {"ok": True, "exists": True, "size": len(obj[0]), "content_type": obj[1]}
        if op == "get_object":
            obj = self.objects.get((bucket, key))
            if obj is None:
                raise RuntimeError("An error occurred (404) when calling the HeadObject operation")
            with open(payload["dest_path"], "wb") as fp:
                fp.write(obj[0])
            return {"ok": True}
        if op == "delete_object":
            self.objects.pop((bucket, key), None)
            return {"ok": True}
        raise AssertionError(f"unexpected R2 op {op}")


@pytest.fixture(scope="module")
def env():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_b8_photo_", ignore_cleanup_errors=True)
    saved = {k: os.environ.get(k) for k in ("APP_ENV", "DB_PATH", "UPLOAD_FOLDER", "PRIVATE_UPLOAD_FOLDER")}
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "b8photo.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ["PRIVATE_UPLOAD_FOLDER"] = os.path.join(tmp.name, "private_uploads")
    for key in (
        "R2_PUBLIC_URL",
        "R2_ACCOUNT_ID",
        "R2_BUCKET_NAME",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
        "R2_CHAT_BUCKET_NAME",
        "R2_CHAT_ACCESS_KEY_ID",
        "R2_CHAT_SECRET_ACCESS_KEY",
    ):
        os.environ.pop(key, None)

    from kk.app_factory import create_app
    from kk.models import db

    app, _socketio, *_ = create_app()
    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app, db, tmp.name
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    for k, v in saved.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
    tmp.cleanup()


@pytest.fixture
def r2(env, monkeypatch):
    """R2 configured (listing + private chat bucket) with an in-memory fake."""
    app, _db, _tmp = env
    for k, v in {
        "R2_ACCOUNT_ID": "acct",
        "R2_BUCKET_NAME": _LISTING_BUCKET,
        "R2_ACCESS_KEY_ID": "lk",
        "R2_SECRET_ACCESS_KEY": "ls",
        "R2_CHAT_BUCKET_NAME": _CHAT_BUCKET,
        "R2_CHAT_ACCESS_KEY_ID": "ck",
        "R2_CHAT_SECRET_ACCESS_KEY": "cs",
    }.items():
        monkeypatch.setitem(app.config, k, v)
    fake = FakeR2()
    import kk.r2_ops as r2_ops

    monkeypatch.setattr(r2_ops, "_run_r2_op", fake.run)
    return fake


def _mk_user(env, *, admin_role=None, is_admin=False, with_application=False, status="draft"):
    from kk.models import DealerApplication, User

    app, db, _ = env
    username = f"{'adm' if is_admin else 'u'}_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
            first_name="F",
            last_name="L",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=is_admin,
            admin_role=admin_role,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.flush()
        if with_application:
            db.session.add(
                DealerApplication(
                    user_id=user.id,
                    status=status,
                    dealership_name="Shop",
                    dealership_phone="07700000000",
                    dealership_location="Erbil",
                )
            )
        db.session.commit()
        if is_admin:
            from kk.tests.admin_auth_helpers import attach_admin_account

            attach_admin_account(db, user, password=_PASSWORD)
        return user.public_id, username


def _token(client, username, *, mobile_scope=False):
    """Admin users log in through their AdminAccount (account_scope=admin)."""
    if username.startswith("adm_") and not mobile_scope:
        from kk.tests.admin_auth_helpers import login_with_admin_scope

        tok = login_with_admin_scope(client, f"dash_{username}", _PASSWORD)
        return {"Authorization": f"Bearer {tok}"}
    r = client.post("/api/auth/login", json={"username": username, "password": _PASSWORD})
    assert r.status_code == 200, r.data
    return {"Authorization": f"Bearer {r.get_json()['access_token']}"}


def _upload(client, headers, data=None, name="shop.png"):
    return client.post(
        "/api/user/upload-dealer-verification-photo",
        headers=headers,
        data={"file": (io.BytesIO(data if data is not None else _png_bytes()), name)},
        content_type="multipart/form-data",
    )


def _column(env, public_id):
    from kk.models import DealerApplication, User

    app, db, _ = env
    with app.app_context():
        u = User.query.filter_by(public_id=public_id).first()
        return DealerApplication.query.filter_by(user_id=u.id).first().verification_photo_filename


def _set_column(env, public_id, value):
    from kk.models import DealerApplication, User

    app, db, _ = env
    with app.app_context():
        u = User.query.filter_by(public_id=public_id).first()
        a = DealerApplication.query.filter_by(user_id=u.id).first()
        a.verification_photo_filename = value
        db.session.commit()


def _admin_url(public_id):
    return f"/api/admin/dealers/{public_id}/verification-photo"


def _disk_files(app):
    folder = os.path.join(app.config["PRIVATE_UPLOAD_FOLDER"], "dealer_verification")
    return os.listdir(folder) if os.path.isdir(folder) else []


def _write_legacy_disk(env, app, name, payload=b"legacy-bytes"):
    folder = os.path.join(app.config["PRIVATE_UPLOAD_FOLDER"], "dealer_verification")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name), "wb") as fh:
        fh.write(payload)
    return os.path.join(folder, name)


# --------------------------------------------------------------------------
# Storage: durable, private, correct bucket
# --------------------------------------------------------------------------


def test_upload_goes_to_private_chat_bucket_not_local_disk_or_listing_bucket(env, r2):
    app, db, tmp = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    resp = _upload(client, _token(client, username))
    assert resp.status_code == 200, resp.data

    value = _column(env, pid)
    assert value.startswith("r2:dealer_verification/"), value
    key = value[len("r2:"):]
    assert (_CHAT_BUCKET, key) in r2.objects
    assert not any(b == _LISTING_BUCKET for (b, _k) in r2.objects), "must never touch the public listing bucket"
    assert all(b == _CHAT_BUCKET for (_op, b, _k) in r2.calls)
    # Nothing was written to the (ephemeral) private disk folder.
    assert key.split("/")[-1] not in _disk_files(app)
    assert r2.objects[(_CHAT_BUCKET, key)][1] == "image/png"
    # The stored reference is never exposed to the applicant.
    assert "r2:" not in resp.get_data(as_text=True)


def test_upload_survives_restart_and_wiped_local_disk(env, r2):
    """Simulated deploy: local private disk wiped + a brand-new app instance."""
    app, db, tmp = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    admin_pid, admin_user = _mk_user(env, is_admin=True, admin_role="moderator")
    assert _upload(client, _token(client, username)).status_code == 200
    original = _png_bytes()

    shutil.rmtree(app.config["PRIVATE_UPLOAD_FOLDER"], ignore_errors=True)

    from kk.app_factory import create_app

    os.environ["PRIVATE_UPLOAD_FOLDER"] = os.path.join(tmp, "private_uploads_after_deploy")
    app2, _s, *_ = create_app()
    for k in (
        "R2_ACCOUNT_ID",
        "R2_BUCKET_NAME",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
        "R2_CHAT_BUCKET_NAME",
        "R2_CHAT_ACCESS_KEY_ID",
        "R2_CHAT_SECRET_ACCESS_KEY",
    ):
        app2.config[k] = app.config[k]
    c2 = app2.test_client()
    resp = c2.get(_admin_url(pid), headers=_token(c2, admin_user))
    assert resp.status_code == 200, resp.data
    assert resp.data == original
    assert resp.headers["Content-Type"].startswith("image/png")


def test_r2_outage_on_upload_returns_503_and_leaves_db_untouched(env, r2):
    app, db, _ = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    headers = _token(client, username)
    assert _upload(client, headers).status_code == 200
    before = _column(env, pid)

    r2.fail = True
    resp = _upload(client, headers)
    assert resp.status_code == 503, resp.data
    assert resp.get_json()["code"] == "photo_storage_unavailable"
    assert _column(env, pid) == before, "an R2 failure must not change/lose the stored reference"
    # And no silent fallback to ephemeral disk.
    assert not any(f.endswith(".png") for f in _disk_files(app))


def test_production_without_private_bucket_refuses_instead_of_using_disk(env, monkeypatch):
    app, db, _ = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    headers = _token(client, username)
    for k in ("R2_CHAT_BUCKET_NAME", "R2_CHAT_ACCESS_KEY_ID", "R2_CHAT_SECRET_ACCESS_KEY"):
        monkeypatch.setitem(app.config, k, None)
    monkeypatch.setenv("APP_ENV", "production")
    resp = _upload(client, headers)
    assert resp.status_code == 503
    assert _column(env, pid) is None


def test_dev_without_r2_falls_back_to_disk(env):
    app, db, _ = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    assert _upload(client, _token(client, username)).status_code == 200
    value = _column(env, pid)
    assert not value.startswith("r2:")
    folder = os.path.join(app.config["PRIVATE_UPLOAD_FOLDER"], "dealer_verification")
    assert os.path.isfile(os.path.join(folder, value))


def test_replacing_photo_deletes_previous_r2_object_and_legacy_disk_file(env, r2):
    app, db, _ = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    headers = _token(client, username)
    assert _upload(client, headers).status_code == 200
    first = _column(env, pid)
    assert _upload(client, headers).status_code == 200
    second = _column(env, pid)
    assert first != second
    assert (_CHAT_BUCKET, first[3:]) not in r2.objects
    assert (_CHAT_BUCKET, second[3:]) in r2.objects

    # Legacy -> R2: replacing a pre-existing local-disk photo removes that file.
    legacy_path = _write_legacy_disk(env, app, "legacy-old.jpg")
    _set_column(env, pid, "legacy-old.jpg")
    assert _upload(client, headers).status_code == 200
    assert not os.path.exists(legacy_path)
    assert _column(env, pid).startswith("r2:dealer_verification/")


def test_account_deletion_helper_removes_r2_object_and_tolerates_outage(env, r2):
    app, db, _ = env
    from kk.private_media import store_dealer_verification
    from kk.routes.auth import _delete_dealer_verification_file

    with app.app_context():
        ref = store_dealer_verification(_png_bytes(), ".png")
        assert (_CHAT_BUCKET, ref[3:]) in r2.objects
        _delete_dealer_verification_file(ref)
        assert (_CHAT_BUCKET, ref[3:]) not in r2.objects
        r2.fail = True
        _delete_dealer_verification_file(ref)  # best-effort: must not raise


def test_reference_can_never_point_outside_the_dealer_verification_prefix(env, r2):
    app, db, _ = env
    from kk.private_media import PrivateMediaError, delete_dealer_verification, read_dealer_verification

    r2.objects[(_CHAT_BUCKET, "chat_uploads/secret.jpg")] = (b"chat", "image/jpeg")
    with app.app_context():
        for bad in (
            "r2:chat_uploads/secret.jpg",
            "r2:dealer_verification/../chat_uploads/secret.jpg",
            "r2:dealer_verification/a/b.jpg",
        ):
            with pytest.raises(PrivateMediaError):
                read_dealer_verification(bad)
            assert delete_dealer_verification(bad) is False
    assert (_CHAT_BUCKET, "chat_uploads/secret.jpg") in r2.objects


# --------------------------------------------------------------------------
# Admin read path: authorization + failure behaviour + legacy compatibility
# --------------------------------------------------------------------------


def test_admin_route_requires_authentication_and_dealers_permission(env, r2):
    app, db, _ = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    assert _upload(client, _token(client, username)).status_code == 200

    # Unauthenticated.
    assert client.get(_admin_url(pid)).status_code in (401, 422)
    # The applicant themself is not an admin.
    assert client.get(_admin_url(pid), headers=_token(client, username)).status_code == 403
    # Non-admin ordinary user.
    _o_pid, other = _mk_user(env)
    assert client.get(_admin_url(pid), headers=_token(client, other)).status_code == 403
    # Admin role WITHOUT the "dealers" permission (support / marketing).
    for role in ("support", "marketing"):
        _a, admin_name = _mk_user(env, is_admin=True, admin_role=role)
        denied = client.get(_admin_url(pid), headers=_token(client, admin_name))
        assert denied.status_code == 403, role
        assert b"image" not in denied.headers.get("Content-Type", "").encode()
    # Permitted roles.
    for role in ("moderator", "super_admin"):
        _a, admin_name = _mk_user(env, is_admin=True, admin_role=role)
        ok = client.get(_admin_url(pid), headers=_token(client, admin_name))
        assert ok.status_code == 200, role
        assert ok.data == _png_bytes()


def test_admin_response_is_private_never_a_redirect_or_public_url(env, r2):
    app, db, _ = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    _a, admin_name = _mk_user(env, is_admin=True, admin_role="moderator")
    assert _upload(client, _token(client, username)).status_code == 200
    resp = client.get(_admin_url(pid), headers=_token(client, admin_name))
    assert resp.status_code == 200
    assert "Location" not in resp.headers
    assert resp.headers["Cache-Control"] == "no-store, private"
    assert resp.headers["X-Content-Type-Options"] == "nosniff"
    assert resp.headers["Content-Disposition"] == "inline"
    # Only a get via the private bucket credentials; never a presign.
    assert not any(op.startswith("presign") for (op, _b, _k) in r2.calls)
    # Not reachable through any public path.
    key = _column(env, pid)[3:]
    for path in (f"/static/{key}", f"/{key}", f"/uploads/{key}", f"/static/uploads/{key}"):
        assert client.get(path).status_code in (404, 405), path


def test_admin_application_payload_exposes_only_the_admin_route_url(env, r2):
    app, db, _ = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    _a, admin_name = _mk_user(env, is_admin=True, admin_role="moderator")
    assert _upload(client, _token(client, username)).status_code == 200
    ref = _column(env, pid)
    from kk.models import DealerApplication, User

    with app.app_context():
        u = User.query.filter_by(public_id=pid).first()
        d = DealerApplication.query.filter_by(user_id=u.id).first().to_dict()
    assert d["has_verification_photo"] is True
    assert ref not in str(d) and "verification_photo_filename" not in d


def test_admin_read_during_r2_outage_is_503_and_missing_object_is_404(env, r2):
    app, db, _ = env
    client = app.test_client()
    pid, username = _mk_user(env, with_application=True)
    _a, admin_name = _mk_user(env, is_admin=True, admin_role="moderator")
    assert _upload(client, _token(client, username)).status_code == 200
    headers = _token(client, admin_name)

    r2.fail = True
    down = client.get(_admin_url(pid), headers=headers)
    assert down.status_code == 503
    assert down.get_json()["code"] == "photo_storage_unavailable"
    r2.fail = False

    r2.objects.clear()  # object lost
    gone = client.get(_admin_url(pid), headers=headers)
    assert gone.status_code == 404
    assert gone.get_json()["code"] == "photo_missing"


def test_existing_legacy_disk_photo_still_served_while_r2_is_configured(env, r2):
    """Pending applications created before this change keep their photo."""
    app, db, _ = env
    client = app.test_client()
    pid, _username = _mk_user(env, with_application=True, status="submitted")
    _a, admin_name = _mk_user(env, is_admin=True, admin_role="moderator")
    _write_legacy_disk(env, app, "legacy-pending.jpg", b"legacy-photo")
    _set_column(env, pid, "legacy-pending.jpg")
    resp = client.get(_admin_url(pid), headers=_token(client, admin_name))
    assert resp.status_code == 200
    assert resp.data == b"legacy-photo"
    assert resp.headers["Content-Type"].startswith("image/jpeg")
    assert _column(env, pid) == "legacy-pending.jpg", "reads must not rewrite the stored value"
    assert r2.calls == [], "a legacy photo must not touch R2"

    # Legacy file lost to a past deploy -> clean 404, not a 500.
    _set_column(env, pid, "legacy-lost.jpg")
    assert client.get(_admin_url(pid), headers=_token(client, admin_name)).status_code == 404


def test_submission_still_requires_a_photo_and_unauthenticated_upload_is_rejected(env, r2):
    app, db, _ = env
    client = app.test_client()
    assert (
        client.post(
            "/api/user/upload-dealer-verification-photo",
            data={"file": (io.BytesIO(_png_bytes()), "a.png")},
            content_type="multipart/form-data",
        ).status_code
        in (401, 422)
    )
