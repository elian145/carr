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


def _write(root, flavor, pid):
    d = root / "android" / "app" / "src" / flavor
    d.mkdir(parents=True, exist_ok=True)
    (d / "google-services.json").write_text(json.dumps({"project_info": {"project_id": pid}}))


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
