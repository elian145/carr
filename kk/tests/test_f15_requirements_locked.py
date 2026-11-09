"""F-15: production dependencies must be exactly pinned and hash-locked."""

from __future__ import annotations

import re
from pathlib import Path

KK = Path(__file__).resolve().parents[1]


def _direct_lines():
    for raw in (KK / "requirements.in").read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            yield line


def test_direct_dependencies_are_exactly_pinned():
    for line in _direct_lines():
        assert re.match(r"^[A-Za-z0-9_.\-]+(\[[A-Za-z0-9_,\-]+\])?==[0-9][^=<>~!,; ]*$", line), line


def test_lock_covers_every_direct_dependency_with_hashes():
    text = (KK / "requirements.txt").read_text(encoding="utf-8")
    pinned = {}
    for m in re.finditer(r"^([A-Za-z0-9_.\-]+)==([^\s;\\]+)", text, re.M):
        pinned[m.group(1).lower().replace("_", "-")] = m.group(2)
    for line in _direct_lines():
        name, ver = line.split("==")
        name = name.split("[")[0].lower().replace("_", "-")
        assert pinned.get(name) == ver, f"{name}: lock has {pinned.get(name)}, requirements.in has {ver}"

    # every pinned requirement carries at least one sha256 hash
    blocks = re.split(r"^(?=[A-Za-z0-9_.\-]+==)", text, flags=re.M)[1:]
    assert blocks
    for block in blocks:
        assert "--hash=sha256:" in block, block.splitlines()[0]
