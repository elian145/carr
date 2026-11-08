"""F-20: Firebase dev/stage isolation lint (logic tested on synthetic configs)."""
from __future__ import annotations

import importlib.util
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
spec = importlib.util.spec_from_file_location(
    "verify_firebase_isolation", os.path.join(ROOT, "scripts", "verify_firebase_isolation.py")
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def _write(root, flavor, pid, *, number=None, packages=None, app_ids=None, key=None):
    d = root / "android" / "app" / "src" / flavor
    d.mkdir(parents=True, exist_ok=True)
    pkgs = packages or [mod.FLAVOR_APP_IDS[flavor]]
    clients = [
        {
            "client_info": {
                "mobilesdk_app_id": (app_ids or {}).get(p, f"1:{pid}:android:{p}"),
                "android_client_info": {"package_name": p},
            },
            "api_key": [{"current_key": key or f"key-{pid}"}],
        }
        for p in pkgs
    ]
    info = {"project_id": pid, "project_number": number or f"num-{pid}"}
    (d / "google-services.json").write_text(json.dumps({"project_info": info, "client": clients}))


def test_isolated_projects_pass_strict(tmp_path):
    for f, pid in (("prod", "p-prod"), ("dev", "p-dev"), ("stage", "p-stage")):
        _write(tmp_path, f, pid)
    assert mod.check(str(tmp_path)) == ([], [])
    assert mod.main(["--strict", "--root", str(tmp_path)]) == 0


def test_shared_prod_project_is_flagged(tmp_path):
    for f in ("prod", "dev", "stage"):
        _write(tmp_path, f, "p-prod")
    errors, violations = mod.check(str(tmp_path))
    assert errors == [] and len(violations) == 2
    assert mod.main(["--strict", "--root", str(tmp_path)]) == 1
    assert mod.main(["--root", str(tmp_path)]) == 0  # warn-only until owner acts


def test_missing_config_always_fails(tmp_path):
    _write(tmp_path, "prod", "p-prod")
    assert mod.main(["--root", str(tmp_path)]) == 1


def test_repo_configs_are_readable():
    errors, _violations = mod.check(ROOT)
    assert errors == []


def _isolated(tmp_path):
    for f, pid in (("prod", "p-prod"), ("dev", "p-dev"), ("stage", "p-stage")):
        _write(tmp_path, f, pid)


def test_flavor_without_its_own_package_client_is_an_error(tmp_path):
    _isolated(tmp_path)
    _write(tmp_path, "dev", "p-dev", packages=["com.carzo.app"])
    errors, _ = mod.check(str(tmp_path))
    assert any("dev google-services.json has no client" in e for e in errors)
    assert mod.main(["--root", str(tmp_path)]) == 1


def test_non_prod_must_not_carry_prod_package_app_id_key_or_project_number(tmp_path):
    _isolated(tmp_path)
    prod_pkg = mod.FLAVOR_APP_IDS["prod"]
    prod_app = "1:p-prod:android:" + prod_pkg
    _write(tmp_path, "dev", "p-dev", packages=[mod.FLAVOR_APP_IDS["dev"], prod_pkg])
    _write(tmp_path, "stage", "p-stage", number="num-p-prod",
           app_ids={mod.FLAVOR_APP_IDS["stage"]: prod_app}, key="key-p-prod")
    errors, violations = mod.check(str(tmp_path))
    assert errors == []
    text = "\n".join(violations)
    assert "dev config contains the production package" in text
    assert "stage flavor has the production Firebase project number" in text
    assert "stage config reuses a production Firebase app id" in text
    assert "stage config reuses a production Firebase API key" in text
    assert "key-p-prod" not in text  # key values are never printed
    assert mod.main(["--strict", "--root", str(tmp_path)]) == 1


def test_flavor_app_ids_match_gradle_flavors():
    gradle = open(os.path.join(ROOT, "android", "app", "build.gradle.kts"), encoding="utf-8").read()
    assert 'applicationId = "com.carzo.app"' in gradle
    assert 'applicationIdSuffix = ".dev"' in gradle and 'applicationIdSuffix = ".stage"' in gradle
    assert 'applicationId = "com.carnetiq.app"' in gradle
    assert mod.FLAVOR_APP_IDS == {
        "dev": "com.carzo.app.dev", "stage": "com.carzo.app.stage", "prod": "com.carnetiq.app",
    }


def test_repo_state_is_only_the_known_shared_project_warning():
    """Current repo: dev/stage share carzo-prod (F-20, owner action). Nothing deeper may be wrong."""
    errors, violations = mod.check(ROOT)
    assert errors == []
    assert violations and all("production Firebase project 'carzo-prod'" in v for v in violations)


# --------------------------------------------------------------------------
# Expected-project pinning + fail-closed release verification (F-20 follow-up)
# --------------------------------------------------------------------------

import plistlib  # noqa: E402

import pytest  # noqa: E402


def _write_plist(root, *, pid="p-prod", bundle=None):
    d = root / "ios" / "Runner"
    d.mkdir(parents=True, exist_ok=True)
    (d / "GoogleService-Info.plist").write_bytes(
        plistlib.dumps({"PROJECT_ID": pid, "BUNDLE_ID": bundle or mod.IOS_BUNDLE_ID})
    )


def _write_expected(root, **ids):
    d = root / "scripts"
    d.mkdir(parents=True, exist_ok=True)
    (d / "firebase_expected_projects.json").write_text(
        json.dumps({f: {"project_id": v} for f, v in ids.items()})
    )


@pytest.fixture(autouse=True)
def _no_ambient_firebase_env(monkeypatch):
    for k in (*mod.ENV_OVERRIDE.values(), "CARNET_FIREBASE_STRICT"):
        monkeypatch.delenv(k, raising=False)


def test_expected_ids_env_overrides_file_and_placeholders_are_unset(tmp_path, monkeypatch):
    _write_expected(tmp_path, prod="p-prod", dev="REPLACE_WITH_DEV_FIREBASE_PROJECT_ID", stage="")
    assert mod.load_expected(str(tmp_path)) == {"prod": "p-prod", "dev": "", "stage": ""}
    monkeypatch.setenv("CARNET_FIREBASE_DEV_PROJECT_ID", "p-dev")
    monkeypatch.setenv("CARNET_FIREBASE_PROD_PROJECT_ID", "  ")  # blank env falls back to the file
    assert mod.load_expected(str(tmp_path)) == {"prod": "p-prod", "dev": "p-dev", "stage": ""}


def test_missing_expected_file_means_nothing_configured(tmp_path):
    assert mod.load_expected(str(tmp_path)) == {"prod": "", "dev": "", "stage": ""}


def test_release_fails_closed_when_expected_id_is_not_configured(tmp_path):
    _isolated(tmp_path)
    _write_plist(tmp_path)
    for flavor in ("prod", "dev", "stage"):
        errors, _ = mod.check(str(tmp_path), {}, release=True, flavors=(flavor,))
        assert any("fail-closed" in e for e in errors), flavor
    assert mod.main(["--release", "--flavor", "prod", "--root", str(tmp_path)]) == 1


def test_release_requires_a_flavor():
    with pytest.raises(SystemExit):
        mod.main(["--release"])


def test_release_prod_passes_when_config_matches_expected(tmp_path):
    _isolated(tmp_path)
    _write_plist(tmp_path)
    _write_expected(tmp_path, prod="p-prod")
    assert mod.main(["--release", "--flavor", "prod", "--root", str(tmp_path)]) == 0


def test_release_prod_rejects_android_or_ios_project_mismatch(tmp_path):
    _isolated(tmp_path)
    _write_plist(tmp_path)
    _write_expected(tmp_path, prod="p-other")
    errors, _ = mod.check(str(tmp_path), mod.load_expected(str(tmp_path)), release=True,
                          flavors=("prod",), platforms=("android", "ios"))
    assert any("prod google-services.json project 'p-prod' != expected 'p-other'" in e for e in errors)
    assert any("iOS GoogleService-Info.plist project 'p-prod' != expected prod 'p-other'" in e for e in errors)


def test_ios_bundle_id_mismatch_is_an_error(tmp_path):
    _isolated(tmp_path)
    _write_plist(tmp_path, bundle="com.someone.else")
    errors, _ = mod.check(str(tmp_path), {"prod": "p-prod"}, release=True, flavors=("prod",),
                          platforms=("ios",))
    assert any("BUNDLE_ID 'com.someone.else'" in e for e in errors)


def test_missing_or_corrupt_ios_plist_fails_release_but_not_android_lint(tmp_path):
    _isolated(tmp_path)
    errors, _ = mod.check(str(tmp_path), {"prod": "p-prod"}, release=True, flavors=("prod",),
                          platforms=("ios",))
    assert any("unreadable" in e for e in errors)
    (tmp_path / "ios" / "Runner").mkdir(parents=True)
    (tmp_path / "ios" / "Runner" / "GoogleService-Info.plist").write_text("not a plist")
    errors, _ = mod.check(str(tmp_path), {"prod": "p-prod"}, release=True, flavors=("prod",),
                          platforms=("ios",))
    assert any("unreadable" in e for e in errors)
    assert mod.check(str(tmp_path)) == ([], [])  # android-only lint ignores iOS


def test_release_of_a_non_prod_flavor_cannot_use_the_prod_project(tmp_path):
    # shared project: every dev/stage release verification fails even with IDs "configured".
    for f in ("prod", "dev", "stage"):
        _write(tmp_path, f, "p-prod")
    _write_expected(tmp_path, prod="p-prod", dev="p-dev", stage="p-stage")
    for flavor in ("dev", "stage"):
        rc = mod.main(["--release", "--flavor", flavor, "--platform", "android", "--root", str(tmp_path)])
        assert rc == 1, flavor
    errors, violations = mod.check(str(tmp_path), mod.load_expected(str(tmp_path)), release=True,
                                   flavors=("dev",))
    assert any("!= expected 'p-dev'" in e for e in errors)
    assert any("uses the production Firebase project" in v for v in violations)


def test_release_of_isolated_dev_passes_on_android_but_never_on_ios(tmp_path):
    _isolated(tmp_path)
    _write_plist(tmp_path)
    _write_expected(tmp_path, prod="p-prod", dev="p-dev", stage="p-stage")
    root = str(tmp_path)
    assert mod.main(["--release", "--flavor", "dev", "--platform", "android", "--root", root]) == 0
    assert mod.main(["--release", "--flavor", "stage", "--platform", "android", "--root", root]) == 0
    assert mod.main(["--release", "--flavor", "dev", "--platform", "ios", "--root", root]) == 1


def test_pinned_id_mismatch_is_an_error_even_in_warn_only_lint(tmp_path):
    _isolated(tmp_path)
    _write_expected(tmp_path, prod="p-prod", dev="p-not-dev", stage="p-stage")
    errors, _ = mod.check(str(tmp_path), mod.load_expected(str(tmp_path)))
    assert errors == ["dev google-services.json project 'p-dev' != expected 'p-not-dev'"]
    assert mod.main(["--root", str(tmp_path)]) == 1


def test_prod_config_must_not_use_a_pinned_dev_or_stage_project(tmp_path):
    for f in ("prod", "dev", "stage"):
        _write(tmp_path, f, "p-shared")
    errors, _ = mod.check(str(tmp_path), {"dev": "p-shared"}, flavors=("prod",))
    assert any("prod google-services.json uses the dev Firebase project" in e for e in errors)


def test_strict_env_var_turns_shared_project_warning_into_failure(tmp_path, monkeypatch):
    for f in ("prod", "dev", "stage"):
        _write(tmp_path, f, "p-prod")
    assert mod.main(["--root", str(tmp_path)]) == 0
    monkeypatch.setenv("CARNET_FIREBASE_STRICT", "1")
    assert mod.main(["--root", str(tmp_path)]) == 1


def test_repo_prod_release_verification_passes():
    """The committed prod android + iOS configs satisfy the committed expected IDs."""
    expected = mod.load_expected(ROOT, env={})
    assert expected["prod"], "scripts/firebase_expected_projects.json must pin the prod project"
    errors, violations = mod.check(ROOT, expected, release=True, flavors=("prod",),
                                   platforms=("android", "ios"))
    assert (errors, violations) == ([], [])


def test_repo_dev_stage_release_currently_fails_closed():
    """Documents the open owner action (F-20): dev/stage releases are blocked until separate projects exist."""
    expected = mod.load_expected(ROOT, env={})
    for flavor in ("dev", "stage"):
        errors, violations = mod.check(ROOT, expected, release=True, flavors=(flavor,))
        assert any("fail-closed" in e for e in errors), flavor
        assert violations, flavor


def test_expected_projects_file_has_no_secrets_and_is_marked_placeholder():
    raw = open(os.path.join(ROOT, mod.EXPECTED_FILE), encoding="utf-8").read()
    assert "AIza" not in raw and "private_key" not in raw
    data = json.loads(raw)
    for flavor in ("dev", "stage"):
        assert data[flavor]["project_id"].startswith(mod.PLACEHOLDER_PREFIX)

def test_release_workflows_run_the_fail_closed_guard():
    text = open(os.path.join(ROOT, "codemagic.yaml"), encoding="utf-8").read()
    assert text.count("verify_firebase_isolation.py --release --flavor prod --platform ios") == 2
    assert 'verify_firebase_isolation.py --release --flavor prod --platform android' in text
    assert 'verify_firebase_isolation.py --release --flavor "$FLAVOR" --platform android' in text
    ci = open(os.path.join(ROOT, ".github", "workflows", "backend_ci.yml"), encoding="utf-8").read()
    assert "verify_firebase_isolation.py --release --flavor prod --platform all" in ci
    ready = open(os.path.join(ROOT, "scripts", "verify_publish_ready.py"), encoding="utf-8").read()
    assert "verify_firebase_isolation.py" in ready and '"--release"' in ready