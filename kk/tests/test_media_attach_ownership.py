"""Attach must not let a user hot-link another seller's R2 object (S6).

The R2 bucket is public-read, so `car_photos/<key>.jpg` URLs are guessable
from any listing a scraper can see. `_allowed_attach_media_url` only checks
the URL shape; `_http_url_owned_by_user` is what actually restricts attach to
media the caller already owns.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from kk.routes import media as media_routes


def _configure_app(monkeypatch):
    monkeypatch.setattr(
        media_routes,
        "current_app",
        MagicMock(config={"R2_PUBLIC_URL": "https://cdn.example.com"}),
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
