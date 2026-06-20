#!/usr/bin/env python3
"""Extract chat and admin blocks from api_service.dart into part files."""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "lib/services/api_service.dart"
CHAT_PART = REPO / "lib/services/api/api_chat.dart"
ADMIN_PART = REPO / "lib/services/api/api_admin.dart"

CHAT_RANGES = [(770, 1041), (1177, 1217)]
ADMIN_RANGE = (1043, 1175)

PRIVATE_MEMBERS = [
    "_httpClient",
    "_getHeaders",
    "_handleResponse",
    "_defaultTimeout",
    "_uploadTimeout",
    "_makeAuthenticatedRequest",
    "_sendAuthenticatedMultipart",
    "_refreshAccessToken",
    "_accessToken",
    "_ensureTokenLoaded",
]


def transform_body(text: str) -> str:
    text = re.sub(r"(['\"])\$baseUrl/", r"\1${ApiService.baseUrl}/", text)
    text = re.sub(r"\$baseUrl\$", r"${ApiService.baseUrl}$", text)
    text = re.sub(r"(?<![.\w\$])baseUrl(?=\.endsWith)", "ApiService.baseUrl", text)
    text = re.sub(r"(?<![.\w\$])baseUrl(?=\s*:)", "ApiService.baseUrl", text)
    text = re.sub(r"(?<![.\w\$])baseUrl(?=\s*\+)", "ApiService.baseUrl", text)
    for name in PRIVATE_MEMBERS:
        text = re.sub(
            rf"(?<![.\w\.]){re.escape(name)}(?![\w])",
            f"ApiService.{name}",
            text,
        )
    text = re.sub(r"(?<![.\w\.])clearTokens\(", "ApiService.clearTokens(", text)
    return text


def extract_ranges(lines: list[str], ranges: list[tuple[int, int]]) -> list[str]:
    out: list[str] = []
    for start, end in ranges:
        out.extend(lines[start - 1 : end])
    return out


def write_part(
    path: Path,
    class_name: str,
    doc: str,
    body_lines: list[str],
) -> None:
    transformed = transform_body("\n".join(body_lines))
    part = [
        "part of '../api_service.dart';",
        "",
        doc,
        f"abstract final class {class_name} {{",
        f"  {class_name}._();",
        "",
    ]
    for ln in transformed.splitlines():
        part.append(f"  {ln}" if ln.strip() else ln)
    part.append("}")
    path.write_text("\n".join(part) + "\n", encoding="utf-8")


def main() -> int:
    lines = SRC.read_text(encoding="utf-8").splitlines()
    chat_body = extract_ranges(lines, CHAT_RANGES)
    admin_body = lines[ADMIN_RANGE[0] - 1 : ADMIN_RANGE[1]]

    write_part(
        CHAT_PART,
        "_ApiServiceChat",
        "/// Chat HTTP + attachments (split from [ApiService]).",
        chat_body,
    )
    write_part(
        ADMIN_PART,
        "_ApiServiceAdmin",
        "/// Push, moderation, reports, blocks (split from [ApiService]).",
        admin_body,
    )
    print(f"Wrote {CHAT_PART.relative_to(REPO)} ({len(chat_body)} lines)")
    print(f"Wrote {ADMIN_PART.relative_to(REPO)} ({len(admin_body)} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
