"""Unit tests for ListingReport.to_admin_dict seller resolution (M-11)."""

from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace

from kk.models import ListingReport


def test_listing_report_admin_dict_uses_car_seller_relationship():
    seller = SimpleNamespace(public_id="seller-1", username="seller_user")
    car = SimpleNamespace(
        public_id="car-1",
        seller_id=42,
        seller=seller,
        title="Toyota Camry",
        brand="Toyota",
        model="Camry",
    )
    reporter = SimpleNamespace(public_id="rep-1", username="reporter")
    report = ListingReport()
    report.id = 7
    report.reason = "spam"
    report.details = None
    report.status = "pending"
    report.admin_notes = None
    report.created_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    report.resolved_at = None
    report.reporter = reporter
    report.car = car

    payload = report.to_admin_dict()

    assert payload["type"] == "listing"
    assert payload["listing"]["id"] == "car-1"
    assert payload["listing"]["brand"] == "Toyota"
    assert payload["seller"]["id"] == "seller-1"
    assert payload["seller"]["username"] == "seller_user"
    assert payload["reporter"]["username"] == "reporter"


def test_listing_report_admin_dict_handles_missing_seller():
    car = SimpleNamespace(
        public_id="car-2",
        seller_id=None,
        seller=None,
        title="X",
        brand="Y",
        model="Z",
    )
    report = ListingReport()
    report.id = 8
    report.reason = "other"
    report.details = None
    report.status = "pending"
    report.admin_notes = None
    report.created_at = None
    report.resolved_at = None
    report.reporter = None
    report.car = car

    payload = report.to_admin_dict()
    assert payload["seller"] == {"id": None, "username": None}
