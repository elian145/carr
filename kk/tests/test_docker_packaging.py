"""F-31 / PRODUCTION_AUDIT C-08: the Docker image must ship the R2 helper script.

kk/r2_ops.py runs ``<repo>/tools/r2_s3_op.py`` (a sibling of ``kk/``). The old
.dockerignore excluded all of ``tools/`` so every R2 upload failed in the image.
"""
from __future__ import annotations

import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HELPER = "tools/r2_s3_op.py"


def _read(name: str) -> str:
    with open(os.path.join(ROOT, name), encoding="utf-8") as fh:
        return fh.read()


def _dockerignore_lines() -> list[str]:
    return [
        ln.strip()
        for ln in _read(".dockerignore").splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    ]


def test_helper_exists_where_r2_ops_looks():
    assert os.path.isfile(os.path.join(ROOT, HELPER))
    assert "r2_s3_op.py" in _read("kk/r2_ops.py")


def test_dockerignore_does_not_exclude_helper():
    lines = _dockerignore_lines()
    # A bare `tools/` (or `tools`) would drop the helper again.
    assert "tools/" not in lines and "tools" not in lines
    # Last matching rule wins in .dockerignore: helper must be re-included.
    verdict = None
    for ln in lines:
        neg = ln.startswith("!")
        pat = ln[1:] if neg else ln
        if pat in (HELPER, "tools/*", "tools/**", "**/r2_s3_op.py"):
            verdict = not neg  # True => excluded
    assert verdict is False, "tools/r2_s3_op.py is excluded from the Docker build context"


def test_dockerfile_copies_helper_next_to_kk():
    df = _read("Dockerfile")
    assert re.search(r"^COPY\s+tools/r2_s3_op\.py\s+/app/tools/r2_s3_op\.py\s*$", df, re.M)
    assert re.search(r"^COPY\s+kk\s+/app/kk\s*$", df, re.M)
