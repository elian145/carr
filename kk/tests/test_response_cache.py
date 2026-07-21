"""Unit tests for API response cache (M-10)."""

from __future__ import annotations

from kk.response_cache import (
    cache_delete_prefix,
    cache_get,
    cache_set,
    catalog_cache_key,
    debug_reset_memory_cache,
    filter_facets_cache_key,
    invalidate_catalog_cache,
    invalidate_filter_facets_cache,
)


def setup_function():
    debug_reset_memory_cache()


def test_memory_cache_roundtrip():
    key = catalog_cache_key("brands")
    assert cache_get(key) is None
    cache_set(key, {"brands": [{"name": "Toyota"}]}, ttl_s=60)
    assert cache_get(key) == {"brands": [{"name": "Toyota"}]}


def test_invalidate_catalog_clears_prefix():
    k1 = catalog_cache_key("brands")
    k2 = catalog_cache_key("models", "name:toyota")
    cache_set(k1, {"brands": []}, ttl_s=60)
    cache_set(k2, {"models": []}, ttl_s=60)
    invalidate_catalog_cache()
    assert cache_get(k1) is None
    assert cache_get(k2) is None


def test_invalidate_facets_only():
    facets = filter_facets_cache_key()
    brands = catalog_cache_key("brands")
    cache_set(facets, {"brands": ["A"]}, ttl_s=60)
    cache_set(brands, {"brands": []}, ttl_s=60)
    invalidate_filter_facets_cache()
    assert cache_get(facets) is None
    assert cache_get(brands) == {"brands": []}


def test_cache_delete_prefix():
    cache_set("api_resp:demo:a", {"x": 1}, ttl_s=60)
    cache_set("api_resp:demo:b", {"x": 2}, ttl_s=60)
    cache_delete_prefix("api_resp:demo:")
    assert cache_get("api_resp:demo:a") is None
    assert cache_get("api_resp:demo:b") is None
