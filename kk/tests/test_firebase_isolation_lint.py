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
