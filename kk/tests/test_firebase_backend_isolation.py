"""F-20: the backend must not push through the wrong Firebase project (fail closed)."""
from __future__ import annotations

import json
import sys
import types

import pytest

from kk import push


@pytest.fixture(autouse=True)
def _clean(monkeypatch):
    for k in ("FIREBASE_EXPECTED_PROJECT_ID", "FIREBASE_PRODUCTION_PROJECT_ID"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setattr(push, "_firebase_app", None)
    monkeypatch.setattr(push, "_init_attempted", False)


def test_no_isolation_config_means_no_restriction():
    assert push.firebase_project_isolation_error("anything", "development") is None
    assert push.firebase_project_isolation_error(None, "production") is None


def test_expected_project_mismatch_is_refused_in_every_env(monkeypatch):
    monkeypatch.setenv("FIREBASE_EXPECTED_PROJECT_ID", "p-stage")
    for env in ("production", "development", "testing"):
        assert push.firebase_project_isolation_error("p-stage", env) is None
        assert "does not match" in push.firebase_project_isolation_error("p-prod", env)
        assert "<missing>" in push.firebase_project_isolation_error(None, env)


def test_non_production_env_refuses_the_production_project(monkeypatch):
    monkeypatch.setenv("FIREBASE_PRODUCTION_PROJECT_ID", "p-prod")
    assert "must not use the production Firebase project" in push.firebase_project_isolation_error(
        "p-prod", "development"
    )
    assert push.firebase_project_isolation_error("p-prod", "testing") is not None
    assert push.firebase_project_isolation_error("p-dev", "development") is None
    # production itself may (obviously) use the production project
    assert push.firebase_project_isolation_error("p-prod", "production") is None


def test_unset_app_env_defaults_to_production_so_prod_project_is_allowed(monkeypatch):
    monkeypatch.delenv("APP_ENV", raising=False)
    monkeypatch.delenv("FLASK_ENV", raising=False)
    monkeypatch.setenv("FIREBASE_PRODUCTION_PROJECT_ID", "p-prod")
    assert push.firebase_project_isolation_error("p-prod") is None


def _fake_firebase_admin(monkeypatch):
    calls = []
    fa = types.ModuleType("firebase_admin")
    fa.initialize_app = lambda cred: calls.append(cred) or object()
    creds = types.ModuleType("firebase_admin.credentials")
    creds.Certificate = lambda info: ("cert", info["project_id"])
    fa.credentials = creds
    monkeypatch.setitem(sys.modules, "firebase_admin", fa)
    monkeypatch.setitem(sys.modules, "firebase_admin.credentials", creds)
    return calls


def test_ensure_firebase_refuses_prod_project_in_development_and_does_not_initialize(monkeypatch):
    calls = _fake_firebase_admin(monkeypatch)
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("FIREBASE_PRODUCTION_PROJECT_ID", "p-prod")
    monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT", json.dumps({"project_id": "p-prod"}))
    logged = []
    # Not caplog: other modules in the suite reconfigure logging globally.
    monkeypatch.setattr(push.logger, "error", lambda msg, *a, **k: logged.append(msg % a))
    assert push._ensure_firebase() is None
    assert calls == []
    assert any("isolation guard" in m for m in logged)
    assert push.fcm_is_configured() is False


def test_ensure_firebase_initializes_for_the_expected_project(monkeypatch):
    calls = _fake_firebase_admin(monkeypatch)
    monkeypatch.setenv("APP_ENV", "development")
    monkeypatch.setenv("FIREBASE_PRODUCTION_PROJECT_ID", "p-prod")
    monkeypatch.setenv("FIREBASE_EXPECTED_PROJECT_ID", "p-dev")
    monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT", json.dumps({"project_id": "p-dev"}))
    assert push._ensure_firebase() is not None
    assert calls == [("cert", "p-dev")]


def test_ensure_firebase_refuses_wrong_project_for_expected_id(monkeypatch):
    calls = _fake_firebase_admin(monkeypatch)
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FIREBASE_EXPECTED_PROJECT_ID", "p-prod")
    monkeypatch.setenv("FIREBASE_SERVICE_ACCOUNT", json.dumps({"project_id": "p-dev"}))
    assert push._ensure_firebase() is None
    assert calls == []
