#!/usr/bin/env python3
"""Split auth/profile methods from api_service.dart into api/api_auth.dart."""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SRC = REPO / "lib/services/api_service.dart"
PART = REPO / "lib/services/api/api_auth.dart"

# 1-based inclusive: auth + profile block in api_service.dart
START, END = 413, 859

PRIVATE_MEMBERS = [
    "_httpClient",
    "_getHeaders",
    "_handleResponse",
    "_defaultTimeout",
    "_uploadTimeout",
    "_saveAccessToken",
    "_saveRefreshToken",
    "_makeAuthenticatedRequest",
    "_sendAuthenticatedMultipart",
    "_refreshToken",
    "_accessToken",
    "_ensureTokenLoaded",
]


def transform_body(text: str) -> str:
    # String interpolation: '$baseUrl/...' -> '${ApiService.baseUrl}/...'
    text = re.sub(r"(['\"])\$baseUrl/", r"\1${ApiService.baseUrl}/", text)
    text = re.sub(r"(?<![.\w\$])baseUrl(?=\.endsWith)", "ApiService.baseUrl", text)
    text = re.sub(
        r"(?<![.\w\$])baseUrl(?=\s*:)",
        "ApiService.baseUrl",
        text,
    )
    text = re.sub(r"(?<![.\w\$])baseUrl(?=\s*\+)", "ApiService.baseUrl", text)
    for name in PRIVATE_MEMBERS:
        text = re.sub(rf"(?<![.\w\.]){re.escape(name)}(?![\w])", f"ApiService.{name}", text)
    text = re.sub(r"(?<![.\w\.])clearTokens\(", "ApiService.clearTokens(", text)
    return text


def parse_methods(lines: list[str]) -> list[tuple[str, str, list[str]]]:
    methods: list[tuple[str, str, list[str]]] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.startswith("  static Future"):
            i += 1
            continue
        m = re.search(r"static Future(?:<.+?>)?\s+(\w+)\s*[\(\{]", line)
        if not m:
            i += 1
            continue
        name = m.group(1)
        sig_lines = [line]
        i += 1
        while i < len(lines) and "{" not in "".join(sig_lines):
            sig_lines.append(lines[i])
            i += 1
        depth = "".join(sig_lines).count("{") - "".join(sig_lines).count("}")
        body_lines: list[str] = []
        while i < len(lines) and depth > 0:
            body_lines.append(lines[i])
            depth += lines[i].count("{") - lines[i].count("}")
            i += 1
        methods.append((name, "\n".join(sig_lines), body_lines))
    return methods


def build_delegator(name: str, sig: str) -> str:
    sig = sig.strip()
    # Arrow delegator: preserve signature, forward args.
    inner = re.sub(r"\s*async\s*\{\s*$", "", sig, flags=re.MULTILINE).strip()
    m = re.search(r"\((.*)\)\s*$", inner, re.DOTALL)
    if not m:
        return f"  {inner} => _ApiServiceAuth.{name}();"
    params = m.group(1).strip()
    if not params:
        return f"  {inner} => _ApiServiceAuth.{name}();"
    if params.startswith("{"):
        names = re.findall(
            r"(?:required\s+)?(?:[\w<>,\[\]\?\s]+\s+)?(\w+)\s*:", params, re.DOTALL
        )
        args = ", ".join(f"{n}: {n}" for n in names)
    else:
        names = []
        for chunk in params.split(","):
            chunk = chunk.strip()
            if not chunk:
                continue
            names.append(chunk.split()[-1])
        args = ", ".join(names)
    return f"  {inner} => _ApiServiceAuth.{name}({args});"


def main() -> int:
    all_lines = SRC.read_text(encoding="utf-8").splitlines()
    block = all_lines[START - 1 : END]
    methods = parse_methods(block)
    if len(methods) < 10:
        raise SystemExit(f"Expected many methods, got {len(methods)}: aborting")

    part_lines = [
        "part of '../api_service.dart';",
        "",
        "/// Auth, profile, and dealer admin HTTP (split from [ApiService]).",
        "abstract final class _ApiServiceAuth {",
        "  _ApiServiceAuth._();",
        "",
    ]
    delegators = ["  // Authentication & profile → api/api_auth.dart"]

    for name, sig, body in methods:
        body_text = transform_body("\n".join(body))
        part_lines.append(f"  {sig.strip()}")
        for ln in body_text.splitlines():
            part_lines.append(f"  {ln}" if ln.strip() else ln)
        part_lines.append("")
        delegators.append(build_delegator(name, sig))

    part_lines.append("}")
    PART.parent.mkdir(parents=True, exist_ok=True)
    PART.write_text("\n".join(part_lines) + "\n", encoding="utf-8")

    before = "\n".join(all_lines[: START - 1])
    after = "\n".join(all_lines[END:])
    new_main = before + "\n" + "\n".join(delegators) + "\n" + after

    if "part 'api/api_auth.dart';" not in new_main:
        new_main = new_main.replace(
            "export 'api_exception.dart';\n",
            "export 'api_exception.dart';\n\npart 'api/api_auth.dart';\n",
        )

    SRC.write_text(new_main, encoding="utf-8")
    print(f"Extracted {len(methods)} methods -> {PART.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
