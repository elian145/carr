#!/usr/bin/env python3
"""Patch Runner target signing for unsigned CI device builds."""
from __future__ import annotations

import re
from pathlib import Path

PBX = Path(__file__).resolve().parent.parent / "ios" / "Runner.xcodeproj" / "project.pbxproj"


def patch_block(block: str) -> str:
    if "CODE_SIGN_ENTITLEMENTS = Runner/" not in block:
        return block
    block = block.replace("CODE_SIGN_STYLE = Automatic;", "CODE_SIGN_STYLE = Manual;")
    inserts = [
        "CODE_SIGNING_ALLOWED = NO;",
        "CODE_SIGNING_REQUIRED = NO;",
        'DEVELOPMENT_TEAM = "";',
        'CODE_SIGN_IDENTITY = "";',
    ]
    for line in inserts:
        if line.split("=")[0].strip() not in block:
            block = block.replace(
                "CODE_SIGN_STYLE = Manual;",
                "CODE_SIGN_STYLE = Manual;\n\t\t\t\t" + line,
                1,
            )
    return block


def main() -> None:
    text = PBX.read_text(encoding="utf-8")
    pattern = re.compile(
        r"\t\t[0-9A-F]+ /\* (?:Debug|Release|Profile) \*/ = \{[\s\S]*?name = (?:Debug|Release|Profile);\n\t\t\};"
    )
    patched = pattern.sub(lambda m: patch_block(m.group(0)), text)
    if patched != text:
        PBX.write_text(patched, encoding="utf-8")
        print("Patched Runner signing in project.pbxproj")
    else:
        print("No Runner signing changes needed in project.pbxproj")


if __name__ == "__main__":
    main()
