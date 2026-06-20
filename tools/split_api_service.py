#!/usr/bin/env python3
"""Regenerate ApiService part files from the monolith (future use).

Current layout keeps implementation in lib/services/api_service.dart.
Run after editing line ranges below when splitting auth/listings/chat modules.

Suggested parts (library + part of):
  - api/api_http.dart      — tokens, _handleResponse, _makeAuthenticatedRequest
  - api/api_auth.dart      — register/login/phone/password/profile
  - api/api_listings.dart  — cars, favorites, saved searches, my listings
  - api/api_chat.dart      — chat HTTP fallbacks, attachments
  - api/api_admin.dart     — reports, blocks, push, getChats

ApiException lives in lib/services/api_exception.dart (already extracted).
"""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "lib/services/api_service.dart"

# Placeholder: run `python tools/split_api_service.py --dry-run` to print sizes.
if __name__ == "__main__":
    lines = SRC.read_text(encoding="utf-8").splitlines()
    print(f"api_service.dart: {len(lines)} lines")
    print("ApiException: extracted to lib/services/api_exception.dart")
