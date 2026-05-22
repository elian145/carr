#!/usr/bin/env python3
"""Patch Runner target signing for unsigned CI device builds."""
from __future__ import annotations

import os
import re
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "ios" / "Runner.xcodeproj" / "project.pbxproj"

# Satisfies Flutter's "Development Team" check; signing stays disabled via xcconfig.
DEFAULT_TEAM = os.environ.get("APPLE_TEAM_ID", "LN3R46L4H8").strip() or "LN3R46L4H8"

SIGNING_LINES = [
    "CODE_SIGN_STYLE = Manual;",
    "CODE_SIGNING_ALLOWED = NO;",
    "CODE_SIGNING_REQUIRED = NO;",
    f'DEVELOPMENT_TEAM = {DEFAULT_TEAM};',
    'CODE_SIGN_IDENTITY = "";',
]


def patch_runner_block(block: str) -> str:
    if "PRODUCT_BUNDLE_IDENTIFIER = com.carzo.app;" not in block:
        return block
    if "com.carzo.app.RunnerTests" in block:
        return block
    if "CODE_SIGN_ENTITLEMENTS = Runner/" not in block:
        return block

    for line in SIGNING_LINES:
        key = line.split("=", 1)[0].strip()
        if key in block:
            block = re.sub(
                rf"\t\t\t\t{re.escape(key)} = [^;]*;",
                f"\t\t\t\t{line}",
                block,
                count=1,
            )
        else:
            block = block.replace(
                "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.carzo.app;",
                "\t\t\t\t" + line + "\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.carzo.app;",
                1,
            )
    return block


def main() -> None:
    text = PBX.read_text(encoding="utf-8")
    pattern = re.compile(
        r"\t\t[0-9A-F]+ /\* (?:Debug|Release|Profile) \*/ = \{"
        r"[\s\S]*?\n\t\t\};",
    )
    patched, n = pattern.subn(lambda m: patch_runner_block(m.group(0)), text)
    if n == 0:
        raise SystemExit("ios_ci_prepare_unsigned: no Xcode build configurations matched")
    PBX.write_text(patched, encoding="utf-8")
    print(f"Patched {n} Runner build configuration(s); DEVELOPMENT_TEAM={DEFAULT_TEAM}")


if __name__ == "__main__":
    main()
