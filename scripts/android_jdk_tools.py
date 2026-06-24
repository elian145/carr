"""Shared helpers for Android JDK tools and signing.properties."""
from __future__ import annotations

import glob
import os
import re
import shutil
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def find_jdk_tool(tool: str) -> str | None:
    """Locate keytool, jarsigner, etc. on PATH or Android Studio JBR."""
    found = shutil.which(tool)
    if found:
        return found

    java_home = os.environ.get("JAVA_HOME", "").strip()
    if java_home:
        for name in (f"{tool}.exe", tool):
            candidate = Path(java_home) / "bin" / name
            if candidate.is_file():
                return str(candidate)

    program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
    local_app_data = os.environ.get("LOCALAPPDATA", "")
    candidates: list[Path] = []
    for android_root in (
        Path(program_files) / "Android",
        Path(local_app_data) / "Programs" / "Android",
    ):
        if android_root.is_dir():
            candidates.extend(android_root.glob(f"Android Studio*/jbr/bin/{tool}.exe"))

    candidates.extend(
        Path(p)
        for p in glob.glob(str(Path(program_files) / "Java" / "*" / "bin" / f"{tool}.exe"))
    )

    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)

    keytool = shutil.which("keytool")
    if keytool:
        sibling = Path(keytool).parent / f"{tool}.exe"
        if sibling.is_file():
            return str(sibling)
        sibling = Path(keytool).parent / tool
        if sibling.is_file():
            return str(sibling)

    return None


def load_signing_properties() -> tuple[dict[str, str], Path] | tuple[None, None]:
    for rel in ("signing.properties", "android/signing.properties"):
        path = REPO_ROOT / rel
        if not path.is_file():
            continue
        props: dict[str, str] = {}
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            props[key.strip()] = value.strip()
        return props, path
    return None, None


def resolve_keystore(store_file: str) -> Path | None:
    p = Path(store_file)
    if p.is_file():
        return p
    candidate = REPO_ROOT / store_file
    if candidate.is_file():
        return candidate
    return None


def parse_sha256_lines(text: str) -> list[str]:
    return [fp.strip().upper() for fp in re.findall(r"SHA256:\s*([0-9A-Fa-f:]+)", text)]
