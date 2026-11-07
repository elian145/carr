"""Force-update hardening: the iOS build must not hard-code its version name.

``codemagic.yaml`` used to pass ``--build-name="1.0.0"`` to ``flutter build
ipa`` so CFBundleShortVersionString was frozen at 1.0.0 forever and an iOS
``min_app_version`` floor could never be met by a newer release. Without the
flag Flutter takes the name from ``pubspec.yaml`` (same as the Android build).

YAML/text only: nothing here triggers a (paid) Codemagic build.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
_YAMLS = ("codemagic.yaml", "ios-codemagic.yaml")


def _read(rel: str) -> str:
    return (REPO_ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def _code_lines(text: str) -> list[str]:
    return [ln for ln in text.splitlines() if not ln.lstrip().startswith("#")]


@pytest.mark.parametrize("rel", _YAMLS)
def test_no_hardcoded_build_name_in_ios_builds(rel):
    path = REPO_ROOT / rel
    if not path.is_file():
        pytest.skip(f"{rel} not present")
    offenders = [ln for ln in _code_lines(_read(rel)) if "--build-name" in ln]
    assert not offenders, (
        f"{rel} passes --build-name explicitly ({offenders}); the version name "
        "must come from pubspec.yaml so iOS version floors can work"
    )


def test_codemagic_still_builds_ipa_with_build_number():
    code = "\n".join(_code_lines(_read("codemagic.yaml")))
    assert "flutter build ipa --release" in code
    # CFBundleVersion stays CI-derived (must increase per upload).
    assert '--build-number="$BUILD_NUM"' in code


def test_pubspec_version_is_a_valid_semver_name():
    pubspec = _read("pubspec.yaml")
    m = re.search(r"^version:\s*([0-9]+(?:\.[0-9]+){1,3})\+([0-9]+)\s*$", pubspec, re.M)
    assert m, "pubspec.yaml `version:` must be NAME+BUILD with a numeric NAME"
    # And the name is a value the server-side validator accepts as a floor.
    from kk.app_settings import parse_version

    assert parse_version(m.group(1)) is not None
