"""Release build numbering + toolchain pinning lint."""
from __future__ import annotations

import importlib.util
import os
import re

import pytest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
spec = importlib.util.spec_from_file_location(
    "compute_build_number", os.path.join(ROOT, "scripts", "compute_build_number.py")
)
cbn = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cbn)


def _read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        return fh.read()


def test_counter_plus_offset_is_monotonic():
    a = cbn.compute({"PROJECT_BUILD_NUMBER": "41", "BUILD_NUMBER_OFFSET": "1000"}, 7)
    b = cbn.compute({"PROJECT_BUILD_NUMBER": "42", "BUILD_NUMBER_OFFSET": "1000"}, 7)
    assert (a, b) == (1041, 1042)


def test_never_below_pubspec_floor():
    assert cbn.compute({"CM_BUILD_NUMBER": "2"}, 7) == 7


@pytest.mark.parametrize(
    "env",
    [
        {},
        {"CM_BUILD_ID": "65f0c0ffee65f0c0ffee65f0"},  # hex id is never used
        {"PROJECT_BUILD_NUMBER": "12a"},
        {"PROJECT_BUILD_NUMBER": "5", "BUILD_NUMBER_OFFSET": "-1"},
        {"PROJECT_BUILD_NUMBER": "2100000001"},
    ],
)
def test_invalid_inputs_rejected(env):
    with pytest.raises(ValueError):
        cbn.compute(env, 7)


def test_pubspec_build_number_parses():
    assert cbn.pubspec_build_number() >= 1


def test_flutter_toolchain_is_pinned_everywhere():
    pins = set()
    for rel in (".github/workflows/flutter_ci.yml", "codemagic.yaml"):
        text = _read(rel)
        assert not re.search(r"^\s*(channel|flutter):\s*stable\s*$", text, re.M), (
            f"{rel}: Flutter must be pinned to an exact version, not 'stable'"
        )
        pins |= set(re.findall(r"(?:flutter-version|flutter):\s*['\"]?(\d+\.\d+\.\d+)['\"]?", text))
    assert len(pins) == 1, f"inconsistent Flutter pins: {pins}"
    assert _read(".flutter-version").strip() in pins


def test_node_and_python_pins_consistent():
    node_ci = re.search(r"node-version:\s*['\"]?(\d+)", _read(".github/workflows/admin_web_ci.yml"))
    node_render = re.search(r"NODE_VERSION\s*\n\s*value:\s*['\"]?(\d+)", _read("render.yaml"))
    assert node_ci and node_render and node_ci.group(1) == node_render.group(1)
    assert _read("admin-web/.nvmrc").strip().split(".")[0] == node_ci.group(1)
    pyver = _read(".python-version").strip()
    assert re.fullmatch(r"\d+\.\d+\.\d+", pyver), ".python-version must be an exact x.y.z"
    # Docker and backend CI run the exact version Render builds with.
    assert f"python:{pyver}-" in _read("Dockerfile")
    ci = set(re.findall(r'python-version:\s*"([\d.]+)"', _read(".github/workflows/backend_ci.yml")))
    assert ci == {pyver}
