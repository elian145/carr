"""iOS TestFlight build number: the ``IOS_BUILD_NUMBER_OVERRIDE`` escape hatch.

The ``ios-testflight`` workflow in ``codemagic.yaml`` derives CFBundleVersion
from ``CM_BUILD_ID`` (legacy) or ``compute_build_number.py`` (monotonic, capped
at 2.1e9 because it is shared with Android). Neither can produce a number
above an App Store Connect history that already holds 14-digit builds, so an
explicit owner override was added. These tests run the REAL shell snippet taken
from the workflow with bash, so what is tested is what Codemagic executes.

Covered: valid / invalid / missing / oversized override values, the untouched
legacy and monotonic behavior when the override is unset, the exact value that
reaches ``flutter build ipa --build-number`` (and that Flutter's own iOS
sanitizer leaves it unchanged), and that nothing else in the CI config or the
numbering script was touched.

YAML/shell only: nothing here triggers a (paid) Codemagic build.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
TARGET = "55755081085631"
STEP_NAME = "Build IPA for TestFlight"
START_MARK = "# Apple requires CFBundleVersion"
END_MARK = 'echo "iOS build number (CFBundleVersion):'


def _workflows() -> dict:
    text = (REPO_ROOT / "codemagic.yaml").read_text(encoding="utf-8")
    return yaml.safe_load(text)["workflows"]


def _build_step_script() -> str:
    for step in _workflows()["ios-testflight"]["scripts"]:
        if step["name"] == STEP_NAME:
            return step["script"].replace("\r\n", "\n")
    raise AssertionError(f"step {STEP_NAME!r} not found in ios-testflight")


def _snippet() -> str:
    """The build-number part of the build step, verbatim."""
    lines = _build_step_script().splitlines()
    start = next(i for i, ln in enumerate(lines) if START_MARK in ln)
    end = next(i for i, ln in enumerate(lines) if END_MARK in ln)
    return "\n".join(lines[start : end + 1])


def _find_bash() -> str | None:
    candidates: list[str] = []
    if sys.platform == "win32":
        for base in (
            os.environ.get("ProgramFiles", r"C:\Program Files"),
            os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
        ):
            candidates.append(str(Path(base) / "Git" / "bin" / "bash.exe"))
    else:
        found = shutil.which("bash")
        if found:
            candidates.append(found)
    for cand in candidates:
        if not Path(cand).is_file():
            continue
        try:
            out = subprocess.run(
                [cand, "-c", "echo ok"], capture_output=True, text=True, timeout=30
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if out.returncode == 0 and out.stdout.strip() == "ok":
            return cand
    return None


BASH = _find_bash()
needs_bash = pytest.mark.skipif(BASH is None, reason="no working bash available")

_SCRUBBED = (
    "IOS_BUILD_NUMBER_OVERRIDE",
    "USE_MONOTONIC_BUILD_NUMBER",
    "BUILD_NUMBER_OFFSET",
    "PROJECT_BUILD_NUMBER",
    "CM_BUILD_NUMBER",
    "CM_BUILD_ID",
)


@pytest.fixture(scope="module")
def shim_dir(tmp_path_factory) -> Path:
    """``python3`` for the monotonic branch (not on PATH on every machine)."""
    d = tmp_path_factory.mktemp("py3shim")
    exe = Path(sys.executable).as_posix()
    shim = d / "python3"
    shim.write_text(f'#!/bin/sh\nexec "{exe}" "$@"\n', encoding="utf-8", newline="\n")
    shim.chmod(0o755)
    return d


def _run(shim_dir: Path, **env_vars: str):
    """Runs the workflow's build-number snippet the way Codemagic does
    (``set -euo pipefail``, repo root as cwd). Returns the CompletedProcess."""
    env = {k: v for k, v in os.environ.items() if k not in _SCRUBBED}
    env["PATH"] = str(shim_dir) + os.pathsep + env.get("PATH", "")
    env.update(env_vars)
    script = "set -euo pipefail\n" + _snippet() + '\necho "RESULT=$BUILD_NUM"\n'
    return subprocess.run(
        [BASH, "-c", script],
        cwd=REPO_ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )


def _result(proc: subprocess.CompletedProcess) -> str:
    m = re.search(r"^RESULT=(.*)$", proc.stdout, re.M)
    assert m, f"no RESULT line; stdout={proc.stdout!r} stderr={proc.stderr!r}"
    return m.group(1)


def _legacy_expected(cm_build_id: str) -> str:
    """Existing legacy rule, unchanged: last 18 chars, leading zeros stripped, else 1.

    Quirk kept on purpose: bash's ``${RAW: -18}`` is EMPTY when RAW is shorter
    than 18 characters, so such an id yields build number 1.
    """
    tail = cm_build_id[-18:] if len(cm_build_id) >= 18 else ""
    return tail.lstrip("0") or "1"


# --------------------------------------------------------------------------- #
# Override: valid values
# --------------------------------------------------------------------------- #


@needs_bash
def test_target_value_is_used_exactly(shim_dir):
    p = _run(
        shim_dir,
        IOS_BUILD_NUMBER_OVERRIDE=TARGET,
        CM_BUILD_ID="636132827091714048",
    )
    assert p.returncode == 0, p.stderr
    assert _result(p) == TARGET
    assert (
        f"iOS build number (CFBundleVersion): {TARGET} "
        "(from IOS_BUILD_NUMBER_OVERRIDE)"
    ) in p.stdout


@needs_bash
@pytest.mark.parametrize(
    "value",
    [
        "1",
        "7",
        "55755081085631",
        "123456789012345678",  # 18 digits: the allowed maximum
        "999999999999999999",
    ],
)
def test_valid_overrides_pass_through_verbatim(shim_dir, value):
    p = _run(shim_dir, IOS_BUILD_NUMBER_OVERRIDE=value, CM_BUILD_ID="123")
    assert p.returncode == 0, p.stderr
    assert _result(p) == value


@needs_bash
def test_override_beats_legacy_and_monotonic_sources(shim_dir):
    p = _run(
        shim_dir,
        IOS_BUILD_NUMBER_OVERRIDE=TARGET,
        USE_MONOTONIC_BUILD_NUMBER="1",
        BUILD_NUMBER_OFFSET="1000",
        CM_BUILD_NUMBER="57",
        CM_BUILD_ID="636132827091714048",
    )
    assert p.returncode == 0, p.stderr
    assert _result(p) == TARGET


# --------------------------------------------------------------------------- #
# Override: invalid values fail loudly and never fall back silently
# --------------------------------------------------------------------------- #


@needs_bash
@pytest.mark.parametrize(
    "value",
    [
        "0",
        "0123",
        "055755081085631",
        "12a",
        "abc",
        "-5",
        "+5",
        "1.2",
        "1.2.3",
        " 55755081085631",
        "55755081085631 ",
        "5575 5081",
        "55755081085631\n",
        "0x10",
        "1e5",
    ],
)
def test_invalid_overrides_are_rejected(shim_dir, value):
    p = _run(shim_dir, IOS_BUILD_NUMBER_OVERRIDE=value, CM_BUILD_ID="123456")
    assert p.returncode != 0, f"{value!r} must be rejected: {p.stdout}"
    assert "ERROR: IOS_BUILD_NUMBER_OVERRIDE" in p.stdout
    assert "RESULT=" not in p.stdout  # no silent fallback to CM_BUILD_ID


@needs_bash
@pytest.mark.parametrize(
    "value",
    [
        "1234567890123456789",  # 19 digits: one too many
        "9" * 25,
        "636132827091714048" + "1",
    ],
)
def test_oversized_overrides_are_rejected(shim_dir, value):
    p = _run(shim_dir, IOS_BUILD_NUMBER_OVERRIDE=value, CM_BUILD_ID="123456")
    assert p.returncode != 0
    assert "exceeds 18 digits" in p.stdout
    assert "RESULT=" not in p.stdout


@needs_bash
def test_eighteen_digit_boundary(shim_dir):
    ok = _run(shim_dir, IOS_BUILD_NUMBER_OVERRIDE="1" * 18)
    too_long = _run(shim_dir, IOS_BUILD_NUMBER_OVERRIDE="1" * 19)
    assert ok.returncode == 0 and _result(ok) == "1" * 18
    assert too_long.returncode != 0


# --------------------------------------------------------------------------- #
# Override unset: existing behavior is preserved
# --------------------------------------------------------------------------- #


@needs_bash
@pytest.mark.parametrize(
    "cm_build_id",
    [
        "636132827091714048123",  # 21 digits -> last 18
        "2185241566090",  # shorter than 18 chars: existing quirk -> 1
        "000000000000012345678901",  # leading zeros after truncation stripped
    ],
)
def test_unset_override_keeps_legacy_cm_build_id_behavior(shim_dir, cm_build_id):
    p = _run(shim_dir, CM_BUILD_ID=cm_build_id)
    assert p.returncode == 0, p.stderr
    assert _result(p) == _legacy_expected(cm_build_id)
    assert f"(from CM_BUILD_ID={cm_build_id})" in p.stdout


@needs_bash
def test_empty_override_counts_as_unset(shim_dir):
    p = _run(shim_dir, IOS_BUILD_NUMBER_OVERRIDE="", CM_BUILD_ID="636132827091714048123")
    assert p.returncode == 0, p.stderr
    assert _result(p) == _legacy_expected("636132827091714048123")


@needs_bash
def test_unset_override_keeps_monotonic_behavior(shim_dir):
    p = _run(
        shim_dir,
        USE_MONOTONIC_BUILD_NUMBER="1",
        BUILD_NUMBER_OFFSET="1000",
        CM_BUILD_NUMBER="57",
        CM_BUILD_ID="636132827091714048",
    )
    assert p.returncode == 0, p.stderr
    assert _result(p) == "1057"


@needs_bash
def test_monotonic_cap_is_unchanged(shim_dir):
    """The override exists precisely because this cap stays in force."""
    p = _run(
        shim_dir,
        USE_MONOTONIC_BUILD_NUMBER="1",
        BUILD_NUMBER_OFFSET=TARGET,
        CM_BUILD_NUMBER="1",
    )
    assert p.returncode != 0
    assert "RESULT=" not in p.stdout


# --------------------------------------------------------------------------- #
# What reaches Flutter / Apple, and scope of the change
# --------------------------------------------------------------------------- #


def test_validated_value_is_what_flutter_build_ipa_receives():
    script = _build_step_script()
    assert 'flutter build ipa --release \\\n' in script
    assert '--build-number="$BUILD_NUM"' in script
    # Nothing between the override and the build rewrites BUILD_NUM.
    after = script.split(END_MARK, 1)[1].split("flutter build ipa", 1)[0]
    assert "BUILD_NUM=" not in after


@needs_bash
def test_whole_build_step_hands_the_exact_value_to_flutter(tmp_path):
    """Runs the ENTIRE build step with a stub ``flutter`` that records its
    arguments: the requested value must arrive as ``--build-number=<value>``."""
    home = tmp_path / "home"
    home.mkdir()
    (home / "export_options.plist").write_text("<plist/>", encoding="utf-8")
    work = tmp_path / "work"
    (work / "build" / "ios" / "ipa").mkdir(parents=True)
    (work / "build" / "ios" / "ipa" / "Runner.ipa").write_text("x", encoding="utf-8")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    args_file = tmp_path / "flutter_args.txt"
    stub = bin_dir / "flutter"
    stub.write_text(
        f'#!/bin/sh\nprintf "%s\\n" "$@" > "{args_file.as_posix()}"\n',
        encoding="utf-8",
        newline="\n",
    )
    stub.chmod(0o755)

    env = {k: v for k, v in os.environ.items() if k not in _SCRUBBED}
    env["PATH"] = str(bin_dir) + os.pathsep + env.get("PATH", "")
    env.update(
        HOME=home.as_posix(),
        IOS_BUILD_NUMBER_OVERRIDE=TARGET,
        CM_BUILD_ID="636132827091714048",
        API_BASE="https://example.invalid",
    )
    proc = subprocess.run(
        [BASH, "-c", _build_step_script()],
        cwd=work,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert proc.returncode == 0, proc.stdout + proc.stderr
    args = args_file.read_text(encoding="utf-8").splitlines()
    assert args[:3] == ["build", "ipa", "--release"]
    assert f"--build-number={TARGET}" in args
    assert sum(a.startswith("--build-number=") for a in args) == 1
    assert "--build-name" not in " ".join(args)


def _flutter_ios_sanitize(build_number: str) -> str:
    """Mirror of flutter_tools' validatedBuildNumberForPlatform (iOS branch)."""
    tmp = re.sub(r"[^\d.]", "", build_number)
    segments = [s for s in tmp.split(".") if s] or ["0"]
    return ".".join(segments)


def test_flutter_leaves_the_target_cfbundleversion_unchanged():
    # ios/Runner/Info.plist: CFBundleVersion = $(FLUTTER_BUILD_NUMBER)
    plist = (REPO_ROOT / "ios" / "Runner" / "Info.plist").read_text(encoding="utf-8")
    assert re.search(
        r"<key>CFBundleVersion</key>\s*<string>\$\(FLUTTER_BUILD_NUMBER\)</string>",
        plist,
    )
    assert _flutter_ios_sanitize(TARGET) == TARGET
    assert len(TARGET) <= 18 and TARGET.isdigit() and not TARGET.startswith("0")


def test_override_exists_only_in_the_ios_testflight_workflow():
    workflows = _workflows()
    assert "IOS_BUILD_NUMBER_OVERRIDE" in str(workflows["ios-testflight"])
    for name, wf in workflows.items():
        if name == "ios-testflight":
            continue
        assert "IOS_BUILD_NUMBER_OVERRIDE" not in str(wf), name
    ios_only = (REPO_ROOT / "ios-codemagic.yaml").read_text(encoding="utf-8")
    assert "IOS_BUILD_NUMBER_OVERRIDE" not in ios_only
    numbering = (REPO_ROOT / "scripts" / "compute_build_number.py").read_text(
        encoding="utf-8"
    )
    assert "IOS_BUILD_NUMBER_OVERRIDE" not in numbering
    assert "MAX_CODE = 2_100_000_000" in numbering  # untouched


def test_override_is_not_pinned_in_the_yaml():
    """The value is supplied per build in Codemagic, never committed."""
    wf = _workflows()["ios-testflight"]
    assert "IOS_BUILD_NUMBER_OVERRIDE" not in (wf.get("environment", {}).get("vars") or {})
    assert TARGET not in (REPO_ROOT / "codemagic.yaml").read_text(encoding="utf-8")


def test_codemagic_yaml_is_valid_and_keeps_all_workflows():
    workflows = _workflows()
    assert {
        "ios-sideloadly",
        "ios-testflight",
        "android_release_unsigned",
        "android-dev-debug",
        "android-prod-release",
    } <= set(workflows)
    assert workflows["ios-testflight"]["publishing"]["app_store_connect"][
        "submit_to_testflight"
    ] is True
