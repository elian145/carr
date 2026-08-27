"""Attach must not let a user hot-link another seller's R2 object (S6).

The R2 bucket is public-read, so `car_photos/<key>.jpg` URLs are guessable
from any listing a scraper can see. `_allowed_attach_media_url` only checks
the URL shape; `_http_url_owned_by_user` is what actually restricts attach to
media the caller already owns.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from kk import media_processing
from kk.routes import media as media_routes


def _configure_app(monkeypatch):
    monkeypatch.setattr(
        media_routes,
        "current_app",
        MagicMock(config={"R2_PUBLIC_URL": "https://cdn.example.com"}),
    )


def _configure_secret(monkeypatch, secret: str = "unit-test-secret"):
    monkeypatch.setattr(
        media_processing,
        "current_app",
        MagicMock(config={"SECRET_KEY": secret}),
    )


def test_allowed_attach_media_url_requires_https(monkeypatch):
    _configure_app(monkeypatch)
    assert media_routes._allowed_attach_media_url(
        "http://cdn.example.com/car_photos/abc.jpg"
    ) is False


def test_allowed_attach_media_url_requires_known_prefix(monkeypatch):
    _configure_app(monkeypatch)
    assert media_routes._allowed_attach_media_url(
        "https://cdn.example.com/other_prefix/abc.jpg"
    ) is False


def test_allowed_attach_media_url_requires_matching_public_base(monkeypatch):
    _configure_app(monkeypatch)
    assert media_routes._allowed_attach_media_url(
        "https://not-our-cdn.example.com/car_photos/abc.jpg"
    ) is False


def test_allowed_attach_media_url_accepts_valid_shape(monkeypatch):
    _configure_app(monkeypatch)
    assert media_routes._allowed_attach_media_url(
        "https://cdn.example.com/car_photos/abc.jpg"
    ) is True


def _mock_query_result(row):
    query = MagicMock()
    query.join.return_value = query
    query.filter.return_value = query
    query.first.return_value = row
    return query


def test_http_url_owned_by_user_true_when_row_found():
    with patch.object(media_routes, "db") as db:
        db.session.query.return_value = _mock_query_result(MagicMock())
        assert media_routes._http_url_owned_by_user(
            "https://cdn.example.com/car_photos/mine.jpg", 42
        ) is True


def test_http_url_owned_by_user_false_for_someone_elses_photo():
    with patch.object(media_routes, "db") as db:
        db.session.query.return_value = _mock_query_result(None)
        assert media_routes._http_url_owned_by_user(
            "https://cdn.example.com/car_photos/not-mine.jpg", 42
        ) is False


def _staged_url(monkeypatch, owner_public_id: str) -> str:
    _configure_secret(monkeypatch)
    tag = media_processing.media_owner_tag(owner_public_id)
    return f"https://cdn.example.com/car_photos/{tag}/staged.jpg"


def test_allowed_attach_media_url_accepts_owner_prefixed_key(monkeypatch):
    url = _staged_url(monkeypatch, "seller-a")
    _configure_app(monkeypatch)
    assert media_routes._allowed_attach_media_url(url) is True


def test_staged_url_accepted_for_the_seller_who_uploaded_it(monkeypatch):
    url = _staged_url(monkeypatch, "seller-a")
    _configure_app(monkeypatch)
    assert media_routes._http_url_staged_by_user(url, "seller-a") is True


def test_staged_url_rejected_for_a_different_seller(monkeypatch):
    url = _staged_url(monkeypatch, "seller-a")
    _configure_app(monkeypatch)
    assert media_routes._http_url_staged_by_user(url, "seller-b") is False


def test_untagged_url_is_not_treated_as_staged(monkeypatch):
    _configure_secret(monkeypatch)
    _configure_app(monkeypatch)
    assert media_routes._http_url_staged_by_user(
        "https://cdn.example.com/car_photos/abc.jpg", "seller-a"
    ) is False


def test_staged_url_rejected_when_no_secret_key_is_configured(monkeypatch):
    url = _staged_url(monkeypatch, "seller-a")
    _configure_secret(monkeypatch, secret="")
    _configure_app(monkeypatch)
    assert media_routes._http_url_staged_by_user(url, "seller-a") is False


def test_staged_url_rejected_when_public_base_is_not_configured(monkeypatch):
    url = _staged_url(monkeypatch, "seller-a")
    monkeypatch.setattr(media_routes, "current_app", MagicMock(config={}))
    assert media_routes._http_url_staged_by_user(url, "seller-a") is False
