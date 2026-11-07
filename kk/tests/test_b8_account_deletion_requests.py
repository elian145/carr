"""B8-2: web account-deletion requests must be durable before success is shown.

Before this change ``POST /api/account-deletion-request`` only emailed support
and swallowed every failure, so a provider outage (``send_email`` returns
``False`` when delivery fails) silently lost the request while the user saw
"Request received". The request is now committed to ``account_deletion_request``
first; the email is a best-effort, retried notification.
"""

from __future__ import annotations

import os
import sys
import tempfile
import uuid
from pathlib import Path
from unittest.mock import patch

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PASSWORD = "Aa123456!"
_SUPPORT = "support@example.test"
URL = "/api/account-deletion-request"


@pytest.fixture(scope="module")
def env():
    tmp = tempfile.TemporaryDirectory(prefix="carlist_b8_del_", ignore_cleanup_errors=True)
    saved = {k: os.environ.get(k) for k in ("APP_ENV", "DB_PATH", "UPLOAD_FOLDER", "PRIVATE_UPLOAD_FOLDER")}
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ["DB_PATH"] = os.path.join(tmp.name, "b8del.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ["PRIVATE_UPLOAD_FOLDER"] = os.path.join(tmp.name, "private_uploads")

    from kk.app_factory import create_app
    from kk.models import db

    app, _socketio, *_ = create_app()
    with app.app_context():
        db.drop_all()
        db.create_all()
    yield app, db
    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    for k, v in saved.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
    tmp.cleanup()


@pytest.fixture(autouse=True)
def _support_email(monkeypatch):
    import kk.routes.misc as misc

    monkeypatch.setattr(
        misc, "_trust_config_payload", lambda: {"support_email": _SUPPORT}
    )


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _rows(env, phone=None):
    from kk.account_deletion_requests import phone_key_for
    from kk.models import AccountDeletionRequest

    app, db = env
    with app.app_context():
        q = AccountDeletionRequest.query
        if phone is not None:
            q = q.filter_by(phone_key=phone_key_for(phone))
        return [r.to_admin_dict() | {"_ip_hash": r.ip_hash, "_phone_key": r.phone_key} for r in q.all()]


def _post(env, phone, **extra):
    app, _db = env
    return app.test_client().post(URL, json={"phone": phone, **extra})


def _mk_admin(env, role):
    from kk.models import User
    from kk.tests.admin_auth_helpers import attach_admin_account, login_with_admin_scope

    app, db = env
    username = f"adm_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="A",
            last_name="D",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            is_admin=True,
            admin_role=role,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        attach_admin_account(db, user, password=_PASSWORD)
    c = app.test_client()
    return {"Authorization": f"Bearer {login_with_admin_scope(c, f'dash_{username}', _PASSWORD)}"}


# --------------------------------------------------------------------------
# Success + durability
# --------------------------------------------------------------------------


def test_successful_submission_is_stored_pending_and_notified(env):
    phone = _phone()
    with patch("kk.email_service.send_email", return_value=True) as send:
        resp = _post(env, phone, email="u@example.com", details="please delete")
    assert resp.status_code == 200
    assert resp.get_json()["message"].startswith("Request received.")
    (row,) = _rows(env, phone)
    assert row["status"] == "pending"
    assert row["phone"] == phone and row["email"] == "u@example.com"
    assert row["notified"] is True and row["notify_attempts"] == 1
    send.assert_called_once()
    assert send.call_args.kwargs["to_email"] == _SUPPORT
    assert row["id"] in send.call_args.kwargs["text_body"]


def test_raw_ip_is_never_stored(env):
    phone = _phone()
    with patch("kk.email_service.send_email", return_value=True):
        env[0].test_client().post(
            URL, json={"phone": phone}, environ_overrides={"REMOTE_ADDR": "203.0.113.77"}
        )
    (row,) = _rows(env, phone)
    assert row["_ip_hash"] and "203.0.113.77" not in str(row)


# --------------------------------------------------------------------------
# Email-provider outage: the request must not be lost
# --------------------------------------------------------------------------


@pytest.mark.parametrize("mode", ["returns_false", "raises"])
def test_email_provider_outage_still_stores_request_and_marks_unnotified(env, mode):
    phone = _phone()
    kwargs = {"return_value": False} if mode == "returns_false" else {"side_effect": RuntimeError("smtp down")}
    with patch("kk.email_service.send_email", **kwargs):
        resp = _post(env, phone)
    assert resp.status_code == 200  # durable => honest success
    (row,) = _rows(env, phone)
    assert row["status"] == "pending"
    assert row["notified"] is False
    assert row["notify_attempts"] == 1
    assert row["last_notify_error"]


def test_missing_support_email_still_stores_request(env, monkeypatch):
    import kk.routes.misc as misc

    monkeypatch.setattr(misc, "_trust_config_payload", lambda: {"support_email": ""})
    phone = _phone()
    with patch("kk.email_service.send_email") as send:
        resp = _post(env, phone)
    assert resp.status_code == 200
    send.assert_not_called()
    (row,) = _rows(env, phone)
    assert row["status"] == "pending" and row["last_notify_error"] == "support_email_not_configured"


def test_database_outage_is_never_reported_as_success(env):
    app, db = env
    phone = _phone()
    from sqlalchemy.exc import OperationalError

    def boom():
        raise OperationalError("INSERT", {}, Exception("db down"))

    with patch("kk.email_service.send_email", return_value=True) as send, patch.object(
        db.session, "commit", side_effect=boom
    ):
        resp = _post(env, phone)
    assert resp.status_code == 503
    assert "Request received" not in resp.get_data(as_text=True)
    send.assert_not_called()
    assert _rows(env, phone) == []


# --------------------------------------------------------------------------
# Retry behaviour
# --------------------------------------------------------------------------


def test_duplicate_submission_retries_a_failed_notification_then_stops(env):
    phone = _phone()
    with patch("kk.email_service.send_email", return_value=False):
        assert _post(env, phone).status_code == 200
    assert _rows(env, phone)[0]["notified"] is False

    with patch("kk.email_service.send_email", return_value=True) as send:
        assert _post(env, phone).status_code == 200  # retry succeeds
        assert _post(env, phone).status_code == 200  # already notified: no resend
    assert send.call_count == 1
    (row,) = _rows(env, phone)
    assert row["notified"] is True and row["notify_attempts"] == 2


def test_operator_retry_endpoint_resends_only_unnotified_pending_requests(env):
    ok_phone, down_phone = _phone(), _phone()
    with patch("kk.email_service.send_email", return_value=True):
        _post(env, ok_phone)
    with patch("kk.email_service.send_email", return_value=False):
        _post(env, down_phone)

    app, _db = env
    headers = _mk_admin(env, "moderator")
    with patch("kk.email_service.send_email", return_value=True) as send:
        resp = app.test_client().post(
            "/api/admin/account-deletion-requests/retry-notifications", headers=headers
        )
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["sent"] >= 1 and body["failed"] == 0
    assert _rows(env, down_phone)[0]["notified"] is True
    assert _rows(env, ok_phone)[0]["notify_attempts"] == 1  # not re-sent
    assert send.call_count == body["attempted"]


# --------------------------------------------------------------------------
# De-duplication and no account enumeration
# --------------------------------------------------------------------------


def test_repeat_requests_for_same_phone_never_create_duplicates(env):
    with patch("kk.email_service.send_email", return_value=True):
        for spelling in ("07709990001", "+964 770 999 0001", "009647709990001", "٠٧٧٠٩٩٩٠٠٠١"):
            assert _post(env, spelling).status_code == 200
    assert len(_rows(env, "07709990001")) == 1


def test_concurrent_duplicate_loses_the_unique_index_race_gracefully(env):
    """Two requests pass the pending lookup simultaneously; the partial unique
    index rejects the second insert and it resolves to the winner."""
    from kk import account_deletion_requests as adr

    app, db = env
    phone = _phone()
    with app.app_context(), patch("kk.email_service.send_email", return_value=True):
        first, created1 = adr.submit_request(
            phone=phone, email="", details="", ip=None, support_email=_SUPPORT
        )
        real_find = adr._find_pending
        calls = {"n": 0}

        def blind_first(key):
            calls["n"] += 1
            return None if calls["n"] == 1 else real_find(key)

        with patch.object(adr, "_find_pending", side_effect=blind_first):
            second, created2 = adr.submit_request(
                phone=phone, email="", details="", ip=None, support_email=_SUPPORT
            )
        assert created1 is True and created2 is False
        assert second.public_id == first.public_id
    assert len(_rows(env, phone)) == 1


def test_response_is_identical_for_new_duplicate_and_existing_account(env):
    from kk.models import User

    app, db = env
    known = _phone()
    with app.app_context():
        u = User(
            username=f"known_{uuid.uuid4().hex[:8]}",
            phone_number=known,
            first_name="K",
            last_name="N",
            is_active=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        u.set_password(_PASSWORD)
        db.session.add(u)
        db.session.commit()
    unknown = _phone()
    with patch("kk.email_service.send_email", return_value=True):
        r_known = _post(env, known)
        r_unknown = _post(env, unknown)
        r_dup = _post(env, known)
    assert r_known.status_code == r_unknown.status_code == r_dup.status_code == 200
    assert r_known.get_json() == r_unknown.get_json() == r_dup.get_json()


def test_new_request_allowed_after_previous_one_is_completed(env):
    app, _db = env
    phone = _phone()
    headers = _mk_admin(env, "moderator")
    with patch("kk.email_service.send_email", return_value=True):
        _post(env, phone)
        (row,) = _rows(env, phone)
        done = app.test_client().post(
            f"/api/admin/account-deletion-requests/{row['id']}/complete",
            headers=headers,
            json={"note": "deleted"},
        )
        assert done.status_code == 200
        assert _post(env, phone).status_code == 200


def test_invalid_phone_is_still_rejected_without_storing(env):
    resp = _post(env, "123")
    assert resp.status_code == 400


# --------------------------------------------------------------------------
# Operator access: status visibility + authorization
# --------------------------------------------------------------------------


def test_admin_queue_requires_authorization(env):
    app, _db = env
    c = app.test_client()
    phone = _phone()
    with patch("kk.email_service.send_email", return_value=True):
        _post(env, phone)
    (row,) = _rows(env, phone)

    paths = [
        ("get", "/api/admin/account-deletion-requests"),
        ("post", f"/api/admin/account-deletion-requests/{row['id']}/complete"),
        ("post", "/api/admin/account-deletion-requests/retry-notifications"),
    ]
    for method, path in paths:
        assert getattr(c, method)(path).status_code in (401, 422), path

    # Roles without PII/user permissions cannot read the queue.
    for role in ("support", "marketing"):
        h = _mk_admin(env, role)
        assert c.get(paths[0][1], headers=h).status_code == 403, role
    marketing = _mk_admin(env, "marketing")
    assert c.post(paths[1][1], headers=marketing).status_code == 403
    assert c.post(paths[2][1], headers=marketing).status_code == 403


def test_operator_sees_pending_and_completed_status_and_completion_scrubs_contact_data(env):
    app, _db = env
    c = app.test_client()
    phone = _phone()
    with patch("kk.email_service.send_email", return_value=False):
        _post(env, phone, email="scrub@example.com", details="my details")
    headers = _mk_admin(env, "moderator")

    listed = c.get("/api/admin/account-deletion-requests?status=pending", headers=headers)
    assert listed.status_code == 200
    mine = [r for r in listed.get_json()["requests"] if r["phone"] == phone]
    assert len(mine) == 1
    assert mine[0]["status"] == "pending" and mine[0]["notified"] is False
    req_id = mine[0]["id"]

    done = c.post(
        f"/api/admin/account-deletion-requests/{req_id}/complete",
        headers=headers,
        json={"note": "account removed"},
    )
    assert done.status_code == 200 and done.get_json()["changed"] is True
    again = c.post(f"/api/admin/account-deletion-requests/{req_id}/complete", headers=headers)
    assert again.status_code == 200 and again.get_json()["changed"] is False

    (row,) = [r for r in _rows(env) if r["id"] == req_id]
    assert row["status"] == "completed" and row["completed_at"]
    assert row["completion_note"] == "account removed"
    assert row["phone"].startswith("***") and phone not in str(row)
    assert row["email"] is None and row["details"] is None
    assert phone[-4:] == row["phone"][-4:]

    completed = c.get("/api/admin/account-deletion-requests?status=completed", headers=headers)
    assert any(r["id"] == req_id for r in completed.get_json()["requests"])
    pending = c.get("/api/admin/account-deletion-requests?status=pending", headers=headers)
    assert all(r["id"] != req_id for r in pending.get_json()["requests"])

    assert c.post(
        "/api/admin/account-deletion-requests/does-not-exist/complete", headers=headers
    ).status_code == 404
    assert c.get("/api/admin/account-deletion-requests?status=bogus", headers=headers).status_code == 400


def test_public_page_and_post_urls_are_unchanged(env):
    app, _db = env
    c = app.test_client()
    page = c.get("/delete-account")
    assert page.status_code == 200
    assert 'action="/api/account-deletion-request"' in page.get_data(as_text=True)
    assert c.get(URL).status_code == 405
