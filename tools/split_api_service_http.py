#!/usr/bin/env python3
"""Extract HTTP/token core from api_service.dart into api/api_http.dart."""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "lib/services/api_service.dart"
PART = REPO / "lib/services/api/api_http.dart"

# initializeTokens .. _makeAuthenticatedRequest
START, END = 48, 414

STATE_MEMBERS = [
    "_accessToken",
    "_refreshToken",
    "_httpClient",
    "_defaultTimeout",
    "_uploadTimeout",
]


def transform_body(text: str) -> str:
    text = re.sub(r"(['\"])\$baseUrl/", r"\1${ApiService.baseUrl}/", text)
    text = re.sub(r"\$baseUrl\$", r"${ApiService.baseUrl}$", text)
    text = re.sub(r"(?<![.\w\$])baseUrl(?=\.endsWith)", "ApiService.baseUrl", text)
    text = re.sub(r"(?<![.\w\$])baseUrl(?=\s*:)", "ApiService.baseUrl", text)
    text = re.sub(r"(?<![.\w\$])baseUrl(?=\s*\+)", "ApiService.baseUrl", text)
    for name in STATE_MEMBERS:
        text = re.sub(
            rf"(?<![.\w\.]){re.escape(name)}(?![\w])",
            f"ApiService.{name}",
            text,
        )
    return text


def main() -> int:
    lines = SRC.read_text(encoding="utf-8").splitlines()
    body = lines[START - 1 : END]
    transformed = transform_body("\n".join(body))

    part_lines = [
        "part of '../api_service.dart';",
        "",
        "/// Token storage and authenticated HTTP core (split from [ApiService]).",
        "abstract final class _ApiServiceHttp {",
        "  _ApiServiceHttp._();",
        "",
    ]
    for ln in transformed.splitlines():
        part_lines.append(f"  {ln}" if ln.strip() else ln)
    part_lines.append("}")

    PART.write_text("\n".join(part_lines) + "\n", encoding="utf-8")
    print(f"Wrote {PART.relative_to(REPO)} ({len(body)} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
