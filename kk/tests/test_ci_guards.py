"""CI false-green guards: skipped PG tests must fail CI, versions must match pins.

Covers scripts/ci_assert_no_skips.py, the CARNET_REQUIRE_PG_TESTS hook in
kk/tests/conftest.py and the structure of .github/workflows (plain-text checks,
no YAML parser, so nothing here can silently skip).
"""
from __future__ import annotations

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / ".github" / "workflows"

_spec = importlib.util.spec_from_file_location(
    "ci_assert_no_skips", ROOT / "scripts" / "ci_assert_no_skips.py"
)
guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guard)


def _junit(path: Path, *, passed=1, skipped=(), failed=0) -> str:
    cases = [f'<testcase classname="m" name="ok{i}"/>' for i in range(passed)]
    cases += [
        f'<testcase classname="m" name="skip{i}"><skipped message="{msg}"/></testcase>'
        for i, msg in enumerate(skipped)
    ]
    cases += [f'<testcase classname="m" name="bad{i}"><failure message="x"/></testcase>' for i in range(failed)]
    path.write_text(
        f'<?xml version="1.0"?><testsuites><testsuite tests="{len(cases)}">{"".join(cases)}</testsuite></testsuites>',
        encoding="utf-8",
    )
    return str(path)


# ---------------------------------------------------------------- skip guard script


def test_guard_passes_when_everything_ran(tmp_path):
    assert guard.main([_junit(tmp_path / "r.xml", passed=3), "--min-tests", "3"]) == 0


def test_guard_fails_on_any_skip(tmp_path, capsys):
    xml = _junit(tmp_path / "r.xml", passed=3, skipped=["CARNET_PG_TEST_URL not set"])
    assert guard.main([xml]) == 1
    assert "CARNET_PG_TEST_URL not set" in capsys.readouterr().out


def test_guard_allow_skip_only_tolerates_matching_reasons(tmp_path):
    ok = _junit(tmp_path / "a.xml", skipped=["CARNET_PG_TEST_URL not set (x)"])
    assert guard.main([ok, "--allow-skip", "CARNET_PG_TEST_URL not set"]) == 0
    other = _junit(tmp_path / "b.xml", skipped=["CARNET_PG_TEST_URL not set", "No ffmpeg build"])
    assert guard.main([other, "--allow-skip", "CARNET_PG_TEST_URL not set"]) == 1


def test_guard_fails_on_too_few_tests_failures_and_missing_report(tmp_path):
    assert guard.main([_junit(tmp_path / "a.xml", passed=2), "--min-tests", "5"]) == 1
    assert guard.main([_junit(tmp_path / "b.xml", passed=2, failed=1)]) == 1
    assert guard.main([str(tmp_path / "missing.xml")]) == 1
    (tmp_path / "bad.xml").write_text("not xml", encoding="utf-8")
    assert guard.main([str(tmp_path / "bad.xml")]) == 1


# ------------------------------------------------- conftest CARNET_REQUIRE_PG_TESTS hook

_PG_SKIP_REASONS = (
    "CARNET_PG_TEST_URL not set (PostgreSQL rehearsal only)",
    "No disposable Postgres (set CARNET_DISPOSABLE_PG_URL)",
    "PHONE_INVENTORY_TEST_PG_URL not set (disposable PG not configured)",
    "needs the disposable local PostgreSQL (CARNET_SEC_PG_URL)",
    "needs the production-head template to start from the previous revision",
)


def _run_pytest_with_real_conftest(tmp_path, require: bool) -> str:
    """Run a throw-away suite (using a copy of the real conftest) and return the junit path."""
    shutil.copy(ROOT / "kk" / "tests" / "conftest.py", tmp_path / "conftest.py")
    body = "import pytest\n" + "".join(
        f"def test_skip_{i}():\n    pytest.skip({reason!r})\n" for i, reason in enumerate(_PG_SKIP_REASONS)
    )
    body += "def test_unrelated_skip_stays_a_skip():\n    pytest.skip('ffmpeg missing')\n"
    (tmp_path / "test_x.py").write_text(body, encoding="utf-8")
    env = {k: v for k, v in os.environ.items() if k != "CARNET_REQUIRE_PG_TESTS"}
    if require:
        env["CARNET_REQUIRE_PG_TESTS"] = "1"
    xml = tmp_path / "out.xml"
    subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", f"--junitxml={xml}", "-c", os.devnull,
         "--rootdir", str(tmp_path), str(tmp_path / "test_x.py")],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    return str(xml)


def test_require_pg_turns_every_known_pg_skip_into_a_failure(tmp_path):
    xml = _run_pytest_with_real_conftest(tmp_path, require=True)
    tests, bad, skips = guard.summarize(xml)
    assert tests == len(_PG_SKIP_REASONS) + 1
    assert bad == len(_PG_SKIP_REASONS), "every PostgreSQL skip reason must fail when PG tests are required"
    assert [s[0].endswith("test_unrelated_skip_stays_a_skip") for s in skips] == [True]


def test_without_require_pg_the_same_skips_stay_skips(tmp_path):
    xml = _run_pytest_with_real_conftest(tmp_path, require=False)
    tests, bad, skips = guard.summarize(xml)
    assert (tests, bad, len(skips)) == (len(_PG_SKIP_REASONS) + 1, 0, len(_PG_SKIP_REASONS) + 1)


def _conftest_pg_markers() -> tuple[str, ...]:
    spec = importlib.util.spec_from_file_location("_carnet_conftest_probe", ROOT / "kk" / "tests" / "conftest.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return tuple(mod._PG_SKIP_MARKERS)


def test_every_repo_pg_skip_reason_is_covered_by_the_require_hook():
    """Any new 'PostgreSQL ... not set / needs ...' skip reason must be added to conftest."""
    for reason in _PG_SKIP_REASONS:
        assert any(m in reason for m in _conftest_pg_markers()), reason


# ----------------------------------------------------------------- workflow structure


def _wf(name: str) -> str:
    return (WORKFLOWS / name).read_text(encoding="utf-8")


def test_postgres_job_asserts_no_skips():
    text = _wf("backend_ci.yml")
    assert "--junitxml=" in text
    assert "scripts/ci_assert_no_skips.py" in text
    assert 'CARNET_REQUIRE_PG_TESTS: "1"' in text


def test_flutter_ci_has_no_failure_swallowing_fallback_and_checks_l10n():
    text = _wf("flutter_ci.yml")
    assert "verify_preflight.py --host" not in text, "host preflight with `|| --skip-host` fallback is a false green"
    assert "verify_preflight.py --skip-host" in text
    assert "flutter gen-l10n" in text and "git diff --exit-code" in text and "lib/l10n" in text


def test_admin_web_ci_audits_dependencies_and_has_lint_test_build():
    text = _wf("admin_web_ci.yml")
    for needle in ("npm run lint", "npm run test:unit", "npm run build", "npm audit"):
        assert needle in text, needle


def test_no_workflow_swallows_failures():
    for wf in WORKFLOWS.glob("*.yml"):
        text = wf.read_text(encoding="utf-8")
        assert "continue-on-error" not in text, wf.name
        for lineno, line in enumerate(text.splitlines(), 1):
            if "|| true" in line:
                # Only the explicit diagnostic "tail the log on failure" step may do this.
                assert "tail -n" in line and "e2e-backend.log" in line, f"{wf.name}:{lineno}: {line.strip()}"


def test_workflow_tool_versions_match_repo_pins():
    py = (ROOT / ".python-version").read_text(encoding="utf-8").strip()
    flutter = (ROOT / ".flutter-version").read_text(encoding="utf-8").strip()
    node = (ROOT / "admin-web" / ".nvmrc").read_text(encoding="utf-8").strip()
    for wf in WORKFLOWS.glob("*.yml"):
        text = wf.read_text(encoding="utf-8")
        for v in re.findall(r'python-version:\s*"?([\d.]+)"?', text):
            assert v == py, f"{wf.name}: python-version {v} != .python-version {py}"
        for v in re.findall(r'flutter-version:\s*"?([\d.]+)"?', text):
            assert v == flutter, f"{wf.name}: flutter-version {v} != .flutter-version {flutter}"
        for v in re.findall(r'node-version:\s*"?([\d.]+)"?', text):
            assert v.split(".")[0] == node.split(".")[0], f"{wf.name}: node {v} != admin-web/.nvmrc {node}"


def test_codemagic_flutter_version_matches_pin():
    flutter = (ROOT / ".flutter-version").read_text(encoding="utf-8").strip()
    for name in ("codemagic.yaml", "ios-codemagic.yaml"):
        text = (ROOT / name).read_text(encoding="utf-8")
        # Any `flutter:` under `environment:` must be the pinned version (never `stable`).
        versions = set(re.findall(r"^\s+flutter:\s*(\S+)\s*$", text, re.M))
        assert versions == {flutter}, (name, versions)


def test_guard_script_is_documented_usage_example_runs(tmp_path):
    xml = _junit(tmp_path / "r.xml", passed=1)
    proc = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "ci_assert_no_skips.py"), xml],
        capture_output=True, text=True, check=False,
    )
    assert proc.returncode == 0, textwrap.dedent(proc.stdout + proc.stderr)


def test_sqlite_job_only_tolerates_pg_and_documented_skips():
    text = _wf("backend_ci.yml")
    allowed = re.findall(r"--allow-skip \"([^\"]+)\"", text)
    markers = _conftest_pg_markers()
    # Every skip reason the require-PG hook knows must be tolerated by the SQLite job ...
    assert set(markers) <= set(allowed), set(markers) - set(allowed)
    # ... and nothing else except the two documented optional/capability cases.
    assert set(allowed) - set(markers) == {"CARNET_REAL_DOLBY_REPRO_PATH", "This ffmpeg build"}
    assert "sqlite-tests.xml" in text and "--min-tests 3500" in text
