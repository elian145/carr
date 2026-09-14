#!/usr/bin/env python3
"""
F-02: unit tests for build_prod_android.validate_api_base().

Pure function tests — no Flutter build, no network, no filesystem I/O beyond
importing the module. Run with:

  python -m pytest scripts/test_build_prod_android_validate.py -q
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_prod_android import ApiBaseValidationError, validate_api_base  # noqa: E402


def test_valid_https_is_accepted():
    assert validate_api_base("https://carr-5hrm.onrender.com") == "https://carr-5hrm.onrender.com"


def test_trailing_slash_is_stripped():
    assert validate_api_base("https://carr-5hrm.onrender.com/") == "https://carr-5hrm.onrender.com"


def test_surrounding_whitespace_is_trimmed():
    assert validate_api_base("  https://carr-5hrm.onrender.com  ") == "https://carr-5hrm.onrender.com"


def test_none_is_rejected_as_missing():
    with pytest.raises(ApiBaseValidationError, match="Missing API_BASE"):
        validate_api_base(None)


def test_empty_string_is_rejected_as_missing():
    with pytest.raises(ApiBaseValidationError, match="Missing API_BASE"):
        validate_api_base("")


def test_whitespace_only_is_rejected_as_missing():
    with pytest.raises(ApiBaseValidationError, match="Missing API_BASE"):
        validate_api_base("   ")


def test_http_is_rejected_as_insecure():
    with pytest.raises(ApiBaseValidationError, match="Insecure API_BASE"):
        validate_api_base("http://carr-5hrm.onrender.com")


def test_non_http_scheme_is_rejected_as_insecure_not_missing():
    with pytest.raises(ApiBaseValidationError, match="Insecure API_BASE"):
        validate_api_base("ftp://example.com")
