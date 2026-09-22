"""Data Safety audit fix: dealer account deletion must not leave personal
DealerProfile/DealerApplication data (or their storage objects) behind.

Background (see kk/routes/auth.py::_scrub_dealer_records_for_deletion() for
the full rationale): the pre-existing account-deletion implementation
already hard-deletes the User, scrubs/deactivates Car listings, deletes
listing media, deletes the user's own profile picture, de-identifies
messages/reports, and does all of it in one transaction (covered by
test_d01_fk_ondelete.py::TestDeleteAccountHttp). It did NOT touch
DealerProfile / DealerApplication / DealerDecision at all -- those rows
just sat there, orphaned (user_id/reviewer_id set NULL by the DB), still
holding the deleted account's phone numbers, emails, exact location,
socials, cover photo, business registration number, uploaded verification
documents, and verification photo.

This file proves the fix:
  * A dealer account can still be deleted (hard User delete, 200 response).
  * DealerApplication's audit trail (status, business name, decisions)
    survives, but every personal/contact/document field on it -- and on
    every historical DealerDecision.application_snapshot copy of those
    same fields -- is scrubbed.
  * DealerProfile (the live public-page mirror, unreachable via any route
    once the User is gone) is deleted outright, not merely de-identified.
  * Verification documents/photo storage objects are deleted (no
    documented retention reason exists for them).
  * The whole thing remains one transaction: a mid-scrub failure rolls back
    everything, including the User row.
  * Ordinary (non-dealer) account deletion is unaffected.
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

_PASSWORD = "Aa123456!"


@pytest.fixture(scope="module")
def app_ctx():
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_dealer_pii_", ignore_cleanup_errors=True
    )
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ["DB_PATH"] = os.path.join(tmp.name, "dealer_pii.db")
    os.environ["UPLOAD_FOLDER"] = os.path.join(tmp.name, "uploads")
    os.environ["PRIVATE_UPLOAD_FOLDER"] = os.path.join(tmp.name, "private_uploads")
    for key in (
        "R2_PUBLIC_URL",
        "R2_ACCOUNT_ID",
        "R2_BUCKET_NAME",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
    ):
        os.environ.pop(key, None)

    from kk.app_factory import create_app

    app, _socketio, *_ = create_app()
    from kk.models import db

    with app.app_context():
        db.drop_all()
        db.create_all()

    yield app, app.test_client(), db

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _login(client, username: str) -> str:
    r = client.post(
        "/api/auth/login", json={"username": username, "password": _PASSWORD}
    )
    assert r.status_code == 200, r.data
    return r.get_json()["access_token"]


def _make_user(app, db, *, username=None, **extra):
    from kk.models import User

    username = username or f"u_{uuid.uuid4().hex[:10]}"
    with app.app_context():
        user = User(
            username=username,
            phone_number=_phone(),
            first_name="First",
            last_name="Last",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
            **extra,
        )
        user.set_password(_PASSWORD)
        db.session.add(user)
        db.session.commit()
        return user.id, user.public_id, username


def _write_verification_photo(app, filename: str) -> str:
    folder = os.path.join(
        app.config["PRIVATE_UPLOAD_FOLDER"], "dealer_verification"
    )
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, filename)
    with open(path, "wb") as fh:
        fh.write(b"fake-verification-photo-bytes")
    return path


def _make_dealer(app, db, seller_id: int, *, with_decision: bool = True):
    """Create a fully-populated DealerApplication (+ DealerProfile +
    DealerDecision) for `seller_id`, mirroring what a real approved dealer
    application looks like."""
    from kk.models import DealerApplication, DealerDecision, DealerProfile

    shop_name = f"Shop-{seller_id}"
    verification_filename = f"verif-{uuid.uuid4().hex[:12]}.jpg"
    _write_verification_photo(app, verification_filename)

    with app.app_context():
        application = DealerApplication(
            user_id=seller_id,
            status="approved",
            dealership_name=shop_name,
            dealership_phone="07700000000",
            dealership_phones=["07700000000", "07711111111"],
            dealership_location="Erbil, Downtown Street 12",
            dealership_description="Family-run shop, ask for Ahmed personally",
            business_registration_number="REG-12345",
            document_urls=[
                "https://cdn.example.com/dealer_docs/reg-cert.pdf",
                "https://foreign-host.example.net/external-doc.pdf",
            ],
            verification_photo_filename=verification_filename,
            submitted_at=None,
            reviewed_at=None,
        )
        db.session.add(application)
        db.session.flush()
        application_id = application.id

        if with_decision:
            db.session.add(
                DealerDecision(
                    application_id=application_id,
                    decision="approved",
                    reason="Looks legitimate",
                    application_snapshot=application.snapshot(),
                )
            )

        profile = DealerProfile(
            user_id=seller_id,
            dealership_name=shop_name,
            dealership_phone="07700000000",
            dealership_phones=["07700000000", "07711111111"],
            dealership_emails=["shop@example.com"],
            dealership_location="Erbil, Downtown Street 12",
            dealership_description="Family-run shop, ask for Ahmed personally",
            dealership_cover_picture="uploads/dealer_covers/shared-cover.jpg",
            dealership_latitude=36.19,
            dealership_longitude=44.01,
            dealership_socials={"facebook": "https://facebook.com/shop"},
        )
        db.session.add(profile)
        db.session.commit()
        application_id = application.id
        decision_ids = [d.id for d in application.decisions]

    return {
        "shop_name": shop_name,
        "application_id": application_id,
        "decision_ids": decision_ids,
        "verification_filename": verification_filename,
        "verification_path": os.path.join(
            app.config["PRIVATE_UPLOAD_FOLDER"], "dealer_verification", verification_filename
        ),
    }


class TestDealerAccountDeletionScrubsPII:
    def test_dealer_account_is_hard_deleted(self, app_ctx, client, monkeypatch):
        app, _c, db = app_ctx
        from kk.models import User

        monkeypatch.setattr(
            "kk.routes.media._delete_media_storage_object", lambda url: None
        )

        seller_id, seller_pub, seller_name = _make_user(app, db)
        _make_dealer(app, db, seller_id)

        token = _login(client, seller_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data

        with app.app_context():
            assert db.session.get(User, seller_id) is None
            assert User.query.filter_by(public_id=seller_pub).first() is None

    def test_dealer_application_contact_and_document_fields_are_scrubbed(
        self, app_ctx, client, monkeypatch
    ):
        app, _c, db = app_ctx
        from kk.models import DealerApplication

        deleted_urls: list[str] = []
        monkeypatch.setattr(
            "kk.routes.media._delete_media_storage_object",
            lambda url: deleted_urls.append(url),
        )

        seller_id, _sp, seller_name = _make_user(app, db)
        ctx = _make_dealer(app, db, seller_id)

        token = _login(client, seller_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data

        with app.app_context():
            appn = db.session.get(DealerApplication, ctx["application_id"])
            # Audit trail survives.
            assert appn is not None
            assert appn.user_id is None
            assert appn.status == "approved"
            assert appn.dealership_name == ctx["shop_name"]

            # Personal/contact/document data does not survive.
            assert appn.dealership_phone == ""
            assert not appn.dealership_phones
            assert appn.dealership_location == ""
            assert appn.dealership_description is None
            assert appn.business_registration_number is None
            assert appn.document_urls == []
            assert appn.verification_photo_filename is None

        # Every stored document_urls entry is queued for best-effort storage
        # cleanup via the same `_delete_media_storage_object()` helper used
        # for listing photos/videos and the dealer cover picture -- it is
        # that helper (mocked here) that safely no-ops on a foreign/
        # third-party URL it doesn't own (see `_storage_key_from_url()`),
        # not this scrub step, so both URLs are queued here.
        assert "https://cdn.example.com/dealer_docs/reg-cert.pdf" in deleted_urls
        assert "https://foreign-host.example.net/external-doc.pdf" in deleted_urls

    def test_dealer_decision_snapshot_history_is_scrubbed_too(
        self, app_ctx, client, monkeypatch
    ):
        """The live application row being clean is not enough -- every
        historical DealerDecision.application_snapshot copy of the same
        contact/document data must be scrubbed too, or the "deleted" PII
        would just keep surviving inside the audit JSON blob."""
        app, _c, db = app_ctx
        from kk.models import DealerDecision

        monkeypatch.setattr(
            "kk.routes.media._delete_media_storage_object", lambda url: None
        )

        seller_id, _sp, seller_name = _make_user(app, db)
        ctx = _make_dealer(app, db, seller_id)
        assert ctx["decision_ids"], "fixture must create at least one decision"

        # Sanity: before deletion, the snapshot really does carry the PII.
        with app.app_context():
            before = db.session.get(DealerDecision, ctx["decision_ids"][0])
            assert before.application_snapshot["dealership_phone"] == "07700000000"
            assert before.application_snapshot["business_registration_number"] == "REG-12345"

        token = _login(client, seller_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data

        with app.app_context():
            decision = db.session.get(DealerDecision, ctx["decision_ids"][0])
            assert decision is not None
            snap = decision.application_snapshot
            # Non-personal audit fields survive.
            assert snap["dealership_name"] == ctx["shop_name"]
            assert snap["has_verification_photo"] is True
            # Personal/contact/document fields do not.
            assert snap["dealership_phone"] == ""
            assert snap["dealership_phones"] == []
            assert snap["dealership_location"] == ""
            assert snap["dealership_description"] is None
            assert snap["business_registration_number"] is None
            assert snap["document_urls"] == []

    def test_dealer_profile_row_and_cover_photo_are_removed(
        self, app_ctx, client, monkeypatch
    ):
        app, _c, db = app_ctx
        from kk.models import DealerProfile

        deleted_urls: list[str] = []
        monkeypatch.setattr(
            "kk.routes.media._delete_media_storage_object",
            lambda url: deleted_urls.append(url),
        )

        seller_id, _sp, seller_name = _make_user(app, db)
        ctx = _make_dealer(app, db, seller_id)

        token = _login(client, seller_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data

        with app.app_context():
            profile = DealerProfile.query.filter_by(
                dealership_name=ctx["shop_name"]
            ).first()
            assert profile is None, "DealerProfile must not survive deletion"

        assert "uploads/dealer_covers/shared-cover.jpg" in deleted_urls

    def test_dealer_verification_photo_file_is_deleted_from_disk(
        self, app_ctx, client, monkeypatch
    ):
        app, _c, db = app_ctx

        monkeypatch.setattr(
            "kk.routes.media._delete_media_storage_object", lambda url: None
        )

        seller_id, _sp, seller_name = _make_user(app, db)
        ctx = _make_dealer(app, db, seller_id)
        assert os.path.isfile(ctx["verification_path"])

        token = _login(client, seller_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data

        assert not os.path.isfile(
            ctx["verification_path"]
        ), "verification photo must be deleted from private storage"

    def test_deletion_stays_transactional_on_mid_scrub_failure(
        self, app_ctx, client, monkeypatch
    ):
        """If dealer scrubbing raises partway through, the whole delete must
        roll back -- User, DealerApplication, and DealerProfile must all be
        left exactly as they were (matches
        test_d01_fk_ondelete.py::test_failure_mid_delete_leaves_no_partial_state)."""
        app, _c, db = app_ctx
        from kk.models import DealerApplication, DealerProfile, User
        import kk.routes.auth as auth_module

        seller_id, _sp, seller_name = _make_user(app, db)
        ctx = _make_dealer(app, db, seller_id)

        def _boom(*_a, **_kw):
            raise RuntimeError("simulated mid-scrub failure")

        monkeypatch.setattr(
            auth_module, "_scrub_dealer_records_for_deletion", _boom
        )

        token = _login(client, seller_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(token),
        )
        assert resp.status_code == 500, resp.data

        with app.app_context():
            user = db.session.get(User, seller_id)
            assert user is not None, "user must not be deleted on failure"

            appn = db.session.get(DealerApplication, ctx["application_id"])
            assert appn is not None
            assert appn.dealership_phone == "07700000000", (
                "application must be untouched on rollback"
            )

            profile = DealerProfile.query.filter_by(
                dealership_name=ctx["shop_name"]
            ).first()
            assert profile is not None, "profile must survive a rolled-back delete"

        assert os.path.isfile(ctx["verification_path"]), (
            "verification photo must not be removed when the DB transaction "
            "rolls back (storage cleanup only ever runs after commit)"
        )


class TestOrdinaryAccountDeletionStillWorks:
    def test_non_dealer_account_deletion_is_unaffected(self, app_ctx, client):
        """A plain (never a dealer) account must still delete cleanly --
        the new dealer-scrub step must be a safe no-op when there is no
        DealerApplication/DealerProfile row at all."""
        app, _c, db = app_ctx
        from kk.models import User

        seller_id, seller_pub, seller_name = _make_user(app, db)

        token = _login(client, seller_name)
        resp = client.post(
            "/api/auth/delete-account",
            json={"password": _PASSWORD},
            headers=_auth(token),
        )
        assert resp.status_code == 200, resp.data
        assert resp.get_json()["message"] == "Account deleted successfully"

        with app.app_context():
            assert db.session.get(User, seller_id) is None
            assert User.query.filter_by(public_id=seller_pub).first() is None
