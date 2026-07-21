"""Unit tests for listing free-text search helpers (M-13)."""

from __future__ import annotations

from kk.listing_search import normalize_search_query


def test_normalize_search_query_strips_and_truncates():
    assert normalize_search_query(None) == ""
    assert normalize_search_query("  Toyota   Camry ") == "Toyota Camry"
    assert normalize_search_query("bmw!!! x5") == "bmw x5"
    long = "a" * 200
    assert len(normalize_search_query(long)) == 120


def test_normalize_search_query_keeps_useful_punctuation():
    assert normalize_search_query("mercedes-benz c-class") == "mercedes-benz c-class"
