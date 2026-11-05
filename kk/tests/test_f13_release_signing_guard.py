"""F-13: Android release builds must never be silently debug-signed.

Pure-python (no Android SDK / Gradle): runs ``scripts/verify_android_release_signing.py``
against the real repo files (must pass) and against mutated temp copies
(negative controls that MUST fail).
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "verify_android_release_signing.py"
GRADLE_REL = "android/app/build.gradle.kts"

sys.path.insert(0, str(REPO_ROOT / "scripts"))
import verify_android_release_signing as v  # noqa: E402


def _run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        timeout=60,
    )


@pytest.fixture()
def tree(tmp_path: Path) -> Path:
    """Temp copy of the files the verifier inspects (never touches the repo)."""
    root = tmp_path / "repo"
    for rel in (GRADLE_REL, "codemagic.yaml", "ios-codemagic.yaml"):
        src = REPO_ROOT / rel
        if src.is_file():
            dst = root / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
    wf_src = REPO_ROOT / ".github" / "workflows"
    wf_dst = root / ".github" / "workflows"
    wf_dst.mkdir(parents=True, exist_ok=True)
    for f in wf_src.glob("*.y*ml"):
        shutil.copyfile(f, wf_dst / f.name)
    return root


def _mutate(root: Path, rel: str, old: str, new: str) -> None:
    p = root / rel
    text = p.read_text(encoding="utf-8").replace("\r\n", "\n")
    assert old in text, f"mutation anchor not found in {rel}: {old!r}"
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def _assert_fails(root: Path, needle: str) -> None:
    cp = _run("--root", str(root))
    assert cp.returncode == 1, cp.stdout + cp.stderr
    assert "VERIFICATION FAILED" in cp.stderr
    assert needle in cp.stderr, cp.stderr


# ---------------------------------------------------------------- positive
def test_real_repo_passes() -> None:
    cp = _run()
    assert cp.returncode == 0, cp.stdout + cp.stderr
    assert cp.stdout.startswith("OK")


def test_real_repo_in_process_no_errors() -> None:
    assert v.verify(REPO_ROOT) == []


def test_unmutated_temp_copy_passes(tree: Path) -> None:
    assert _run("--root", str(tree)).returncode == 0


def test_codemagic_workflows_are_split_as_expected() -> None:
    wfs = v.split_codemagic_workflows((REPO_ROOT / "codemagic.yaml").read_text(encoding="utf-8"))
    assert {"android_release_unsigned", "android-prod-release", "android-dev-debug"} <= set(wfs)
    assert v.LEGACY_BYPASS not in "".join(wfs.values())
    assert v.UNSIGNED_OPT_IN in wfs["android_release_unsigned"]
    assert v.UNSIGNED_OPT_IN not in wfs["android-prod-release"]


def test_codemagic_yaml_parses_when_pyyaml_available() -> None:
    yaml = pytest.importorskip("yaml")
    data = yaml.safe_load((REPO_ROOT / "codemagic.yaml").read_text(encoding="utf-8"))
    unsigned = data["workflows"]["android_release_unsigned"]
    assert "ALLOW_DEBUG_RELEASE_SIGNING" not in unsigned["environment"]["vars"]
    assert unsigned["environment"]["vars"]["CARNET_UNSIGNED_RELEASE"] == "true"
    names = [s["name"] for s in unsigned["scripts"]]
    assert names.index("Analyze") < names.index("Build APK")
    assert all("UNSIGNED" in a for a in unsigned["artifacts"])


# ------------------------------------------------- negative: Gradle config
def test_neg_debug_fallback_reintroduced(tree: Path) -> None:
    _mutate(
        tree,
        GRADLE_REL,
        "} else {\n                null\n            }",
        '} else {\n                signingConfigs.getByName("debug")\n            }',
    )
    _assert_fails(tree, "debug")


def test_neg_debug_fallback_index_style(tree: Path) -> None:
    _mutate(
        tree,
        GRADLE_REL,
        "} else {\n                null\n            }",
        '} else {\n                signingConfigs["debug"]\n            }',
    )
    _assert_fails(tree, "debug")


def test_neg_release_always_debug_signed(tree: Path) -> None:
    _mutate(
        tree,
        GRADLE_REL,
        "signingConfig = if (hasReleaseSigning && !unsignedReleaseRequested) {",
        'signingConfig = signingConfigs.getByName("debug")\n            val unused = if (hasReleaseSigning && !unsignedReleaseRequested) {',
    )
    _assert_fails(tree, "debug")


def test_neg_release_fallback_to_other_config(tree: Path) -> None:
    _mutate(
        tree,
        GRADLE_REL,
        "} else {\n                null\n            }",
        '} else {\n                signingConfigs.getByName("someOtherConfig")\n            }',
    )
    _assert_fails(tree, "someOtherConfig")


def test_neg_release_without_signing_config(tree: Path) -> None:
    _mutate(tree, GRADLE_REL, "signingConfig = if", "val notSigning = if")
    _assert_fails(tree, "signingConfig")


def test_neg_guard_removed(tree: Path) -> None:
    text = (tree / GRADLE_REL).read_text(encoding="utf-8").replace("\r\n", "\n")
    start = text.index("gradle.taskGraph.whenReady {")
    end = text.index("kotlin {\n    compilerOptions")
    (tree / GRADLE_REL).write_text(text[:start] + text[end:], encoding="utf-8")
    _assert_fails(tree, "whenReady")


def test_neg_guard_only_covers_prod_release(tree: Path) -> None:
    _mutate(tree, GRADLE_REL, 'it.name.contains("release", ignoreCase = true)', 'it.name.contains("ProdRelease", ignoreCase = true)')
    _assert_fails(tree, "guard")


def test_neg_guard_case_sensitive(tree: Path) -> None:
    _mutate(tree, GRADLE_REL, 'it.name.contains("release", ignoreCase = true)', 'it.name.contains("release")')
    _assert_fails(tree, "ignoreCase")


def test_neg_guard_no_longer_throws(tree: Path) -> None:
    _mutate(tree, GRADLE_REL, "throw GradleException(", "println(")
    _assert_fails(tree, "GradleException")


def test_neg_guard_dead_condition(tree: Path) -> None:
    _mutate(tree, GRADLE_REL, "if (releaseTasks.isNotEmpty() && !unsignedReleaseRequested) {", "if (false && releaseTasks.isNotEmpty()) {")
    _assert_fails(tree, "guard")


def test_neg_guard_reads_bypass_env_in_guard(tree: Path) -> None:
    _mutate(
        tree,
        GRADLE_REL,
        "if (releaseTasks.isNotEmpty() && !unsignedReleaseRequested) {",
        'if (releaseTasks.isNotEmpty() && !unsignedReleaseRequested && System.getenv("ALLOW_DEBUG_RELEASE_SIGNING") != "true") {',
    )
    _assert_fails(tree, "ALLOW_DEBUG_RELEASE_SIGNING")


def test_neg_guard_checks_only_one_task_name_pattern(tree: Path) -> None:
    _mutate(tree, GRADLE_REL, "allTasks.filter {", "allTasks.take(0).filter {")
    # structure still present => must still be considered fine by the static check
    # only if allTasks is referenced; replacing it entirely must fail:
    _mutate(tree, GRADLE_REL, "allTasks.take(0).filter {", "emptyList<Task>().filter {")
    _assert_fails(tree, "allTasks")


def test_neg_new_bypass_property_in_gradle(tree: Path) -> None:
    _mutate(
        tree,
        GRADLE_REL,
        "val unsignedReleaseRequested =",
        'val skipSigningCheck = System.getenv("SKIP_RELEASE_SIGNING_CHECK") == "1"\nval unsignedReleaseRequested =',
    )
    _assert_fails(tree, "SKIP_RELEASE_SIGNING_CHECK")


# ------------------------------------------------------- negative: CI files
def test_neg_codemagic_bypass_env_reintroduced(tree: Path) -> None:
    _mutate(
        tree,
        "codemagic.yaml",
        '        CARNET_UNSIGNED_RELEASE: "true"\n',
        '        CARNET_UNSIGNED_RELEASE: "true"\n        ALLOW_DEBUG_RELEASE_SIGNING: "true"\n',
    )
    _assert_fails(tree, "ALLOW_DEBUG_RELEASE_SIGNING")


def test_neg_bypass_in_github_workflow(tree: Path) -> None:
    wf = tree / ".github" / "workflows" / "flutter_ci.yml"
    wf.write_text(wf.read_text(encoding="utf-8") + "\n# ALLOW_DEBUG_RELEASE_SIGNING: true\n", encoding="utf-8")
    _assert_fails(tree, "flutter_ci.yml")


def test_neg_opt_in_leaks_into_prod_release_workflow(tree: Path) -> None:
    _mutate(
        tree,
        "codemagic.yaml",
        '        FLAVOR: prod\n        # IMPORTANT: Do NOT include /api in API_BASE.',
        '        FLAVOR: prod\n        CARNET_UNSIGNED_RELEASE: "true"\n        # IMPORTANT: Do NOT include /api in API_BASE.',
    )
    _assert_fails(tree, "android-prod-release")


def test_neg_unsigned_workflow_without_opt_in(tree: Path) -> None:
    _mutate(tree, "codemagic.yaml", '        CARNET_UNSIGNED_RELEASE: "true"\n', "")
    _assert_fails(tree, "CARNET_UNSIGNED_RELEASE")


def test_neg_unsigned_workflow_missing_verify_step(tree: Path) -> None:
    _mutate(
        tree,
        "codemagic.yaml",
        "      - name: Verify Android release-signing safeguards\n        script: python scripts/verify_android_release_signing.py\n",
        "",
    )
    _assert_fails(tree, "verify_android_release_signing.py")


def test_neg_unsigned_workflow_missing_analyze(tree: Path) -> None:
    _mutate(
        tree,
        "codemagic.yaml",
        "      - name: Analyze\n        script: flutter analyze --no-fatal-warnings --no-fatal-infos\n      - name: Build APK\n",
        "      - name: Build APK\n",
    )
    _assert_fails(tree, "flutter analyze")


def test_neg_unsigned_workflow_verify_after_build(tree: Path) -> None:
    _mutate(
        tree,
        "codemagic.yaml",
        "      - name: Verify Android release-signing safeguards\n        script: python scripts/verify_android_release_signing.py\n",
        "",
    )
    _mutate(
        tree,
        "codemagic.yaml",
        "      - name: Assert APK is unsigned and mark it UNSIGNED\n",
        "      - name: late verify\n        script: python scripts/verify_android_release_signing.py\n"
        "      - name: Assert APK is unsigned and mark it UNSIGNED\n",
    )
    _assert_fails(tree, "BEFORE")


def test_neg_unsigned_workflow_artifact_not_marked(tree: Path) -> None:
    _mutate(
        tree,
        "codemagic.yaml",
        "      - build/app/outputs/flutter-apk/carnet-prod-release-UNSIGNED.apk",
        "      - build/app/outputs/flutter-apk/app-prod-release.apk",
    )
    _assert_fails(tree, "UNSIGNED")


def test_neg_unsigned_workflow_no_unsigned_assertion(tree: Path) -> None:
    _mutate(tree, "codemagic.yaml", "--assert-unsigned-apk", "--noop")
    _assert_fails(tree, "--assert-unsigned-apk")


def test_neg_unsigned_workflow_builds_bundle(tree: Path) -> None:
    _mutate(tree, "codemagic.yaml", "flutter build apk --release --flavor prod", "flutter build appbundle --release --flavor prod")
    _assert_fails(tree, "app bundle")


def test_neg_new_unsigned_looking_release_workflow(tree: Path) -> None:
    cm = tree / "codemagic.yaml"
    text = cm.read_text(encoding="utf-8").replace("\r\n", "\n")
    extra = (
        "\n  android-sneaky-release:\n    name: sneaky\n    scripts:\n"
        "      - name: Build\n        script: flutter build apk --release --flavor dev\n"
    )
    marker = "\n  android-dev-debug:"
    assert marker in text
    cm.write_text(text.replace(marker, extra + marker, 1), encoding="utf-8")
    _assert_fails(tree, "android-sneaky-release")


def test_neg_github_workflow_release_build_without_signing(tree: Path) -> None:
    (tree / ".github" / "workflows" / "sneaky.yml").write_text(
        "name: x\non: push\njobs:\n  b:\n    runs-on: ubuntu-latest\n    steps:\n"
        "      - run: flutter build appbundle --release --flavor dev\n",
        encoding="utf-8",
    )
    _assert_fails(tree, "sneaky.yml")


def test_neg_missing_files(tmp_path: Path) -> None:
    cp = _run("--root", str(tmp_path))
    assert cp.returncode == 1
    assert "not found" in cp.stderr


# ------------------------------------------------ unsigned-APK assertion
def _fake_apk(path: Path, extra: dict[str, bytes] | None = None, trailer: bytes = b"") -> Path:
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("AndroidManifest.xml", b"fake")
        z.writestr("classes.dex", b"fake")
        for name, data in (extra or {}).items():
            z.writestr(name, data)
    if trailer:
        with open(path, "ab") as fh:
            fh.write(trailer)
    return path


def test_assert_unsigned_apk_accepts_unsigned(tmp_path: Path) -> None:
    apk = _fake_apk(tmp_path / "u.apk")
    cp = _run("--assert-unsigned-apk", str(apk))
    assert cp.returncode == 0, cp.stderr
    assert "unsigned" in cp.stdout


@pytest.mark.parametrize("entry", ["META-INF/CERT.RSA", "META-INF/CERT.SF", "META-INF/ANDROIDD.EC", "META-INF/X.DSA"])
def test_assert_unsigned_apk_rejects_v1_signature(tmp_path: Path, entry: str) -> None:
    apk = _fake_apk(tmp_path / "s.apk", {entry: b"sig"})
    cp = _run("--assert-unsigned-apk", str(apk))
    assert cp.returncode == 1
    assert "not unsigned" in cp.stderr


def test_assert_unsigned_apk_rejects_v2_signing_block(tmp_path: Path) -> None:
    apk = _fake_apk(tmp_path / "s2.apk", trailer=b"\x00" * 8 + b"APK Sig Block 42")
    cp = _run("--assert-unsigned-apk", str(apk))
    assert cp.returncode == 1
    assert "Signing Block" in cp.stderr


def test_assert_unsigned_apk_rejects_missing_and_corrupt(tmp_path: Path) -> None:
    assert _run("--assert-unsigned-apk", str(tmp_path / "nope.apk")).returncode == 1
    bad = tmp_path / "bad.apk"
    bad.write_bytes(b"not a zip")
    assert _run("--assert-unsigned-apk", str(bad)).returncode == 1
