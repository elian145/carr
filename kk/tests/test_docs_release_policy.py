"""Docs guard for the release-policy documents (batch 7, docs only).

Pure text/constant checks - no Flask app, no database, no network. They keep two documents
honest against the code they describe:

* ``docs/F19_ADMIN_TOKEN_SEPARATION.md``
* ``docs/RELEASE_POLICY_FORCE_UPDATE.md``

If a constant, env var name or test name referenced by the documents changes, these tests fail
and the document has to be updated together with the code.
"""

from __future__ import annotations

import inspect
import re
from datetime import timedelta
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
DOCS = REPO_ROOT / "docs"
F19_DOC = DOCS / "F19_ADMIN_TOKEN_SEPARATION.md"
FU_DOC = DOCS / "RELEASE_POLICY_FORCE_UPDATE.md"
INTERNAL_BLOCKERS_DOC = DOCS / "PUBLIC_RELEASE_BLOCKERS.md"
TESTS_DIR = Path(__file__).resolve().parent


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _flat(path: Path) -> str:
    """Document text with markdown emphasis/code ticks removed and whitespace collapsed."""
    text = _read(path).replace("*", "").replace("`", "")
    return re.sub(r"\s+", " ", text)


def _test_names(*module_names: str) -> set[str]:
    names: set[str] = set()
    for module in module_names:
        names |= set(re.findall(r"^def (test_\w+)\(", _read(TESTS_DIR / module), re.M))
    return names


def _cited_test_names(path: Path) -> set[str]:
    return set(re.findall(r"`(test_[a-z0-9_]+)`", _read(path)))


# --------------------------------------------------------------------------
# F-19 document
# --------------------------------------------------------------------------
def test_f19_doc_states_the_policy_and_the_auth_hunk_status():
    text = _flat(F19_DOC)
    assert "stays DISABLED until production configuration and staged compatibility tests are ready" in text
    assert "is already part of the base" in text
    assert "kk/routes/auth.py" in text
    assert (
        "The admin/user token boundary MUST be verified in staging before public launch" in text
    )
    for section in (
        "Signing-key provisioning",
        "Acceptance / rejection matrix",
        "Staged roll-out",
        "Rollback",
        "Pre-launch checklist",
        "Rotation",
    ):
        assert section in text, section


def test_auth_hunk_really_is_in_the_base():
    """The doc claims the issuing hunk is part of the base: prove it from the source."""
    source = _read(REPO_ROOT / "kk" / "routes" / "auth.py")
    assert "from ..admin_tokens import issue_admin_token" in source
    assert 'issue_admin_token(identity, "access", claims)' in source
    assert 'issue_admin_token(identity, "refresh", claims)' in source


@pytest.mark.parametrize(
    "env_name, getter",
    [
        ("ADMIN_JWT_PRIVATE_KEY", "admin_jwt_private_key_pem"),
        ("ADMIN_JWT_PUBLIC_KEY", "admin_jwt_public_key_pem"),
    ],
)
def test_f19_pem_env_names_documented_and_read_by_code(monkeypatch, env_name, getter):
    import kk.config as config

    assert f"`{env_name}`" in _read(F19_DOC)
    monkeypatch.setenv(env_name, "line1\\nline2")
    assert getattr(config, getter)() == "line1\nline2"  # literal \n documented as accepted


def test_f19_enforce_env_name_documented_and_read_by_code(monkeypatch):
    import kk.config as config

    assert "`ADMIN_JWT_ENFORCE`" in _read(F19_DOC)
    monkeypatch.delenv("ADMIN_JWT_ENFORCE", raising=False)
    assert config.admin_jwt_enforce_enabled() is False
    monkeypatch.setenv("ADMIN_JWT_ENFORCE", "1")
    assert config.admin_jwt_enforce_enabled() is True


def test_f19_admin_route_constants_match_the_doc():
    from kk import admin_tokens

    text = _read(F19_DOC)
    assert admin_tokens.ADMIN_TOKEN_ALGORITHM == "ES256"
    assert "ES256" in text
    for path in admin_tokens.ADMIN_ROUTE_EXACT:
        assert path in text, path
    for prefix in admin_tokens.ADMIN_ROUTE_PREFIXES:
        assert prefix in text, prefix


def test_f19_token_ttl_defaults_and_clamps_match_the_doc(monkeypatch):
    import kk.config as config

    flat = _flat(F19_DOC)
    assert "JWT_ACCESS_TOKEN_MINUTES (default 30, clamped 15-60)" in flat
    assert "JWT_REFRESH_TOKEN_DAYS (default 30, clamped 1-90)" in flat

    monkeypatch.delenv("JWT_ACCESS_TOKEN_MINUTES", raising=False)
    monkeypatch.delenv("JWT_REFRESH_TOKEN_DAYS", raising=False)
    assert config._access_token_expires() == timedelta(minutes=30)
    assert config._refresh_token_expires() == timedelta(days=30)
    monkeypatch.setenv("JWT_ACCESS_TOKEN_MINUTES", "1")
    assert config._access_token_expires() == timedelta(minutes=15)
    monkeypatch.setenv("JWT_ACCESS_TOKEN_MINUTES", "9999")
    assert config._access_token_expires() == timedelta(minutes=60)
    monkeypatch.setenv("JWT_REFRESH_TOKEN_DAYS", "0")
    assert config._refresh_token_expires() == timedelta(days=1)
    monkeypatch.setenv("JWT_REFRESH_TOKEN_DAYS", "9999")
    assert config._refresh_token_expires() == timedelta(days=90)


def test_f19_doc_cites_only_existing_tests():
    cited = _cited_test_names(F19_DOC)
    assert cited, "the matrix must cite tests"
    known = _test_names("test_f19_admin_token_separation.py")
    assert not (cited - known), sorted(cited - known)


def test_f19_cited_admin_web_test_titles_exist():
    mjs = _read(REPO_ROOT / "admin-web" / "scripts" / "test_f19_verify_admin_jwt.mjs")
    flat = _flat(F19_DOC)
    for title in (
        "ES256: valid admin token verifies with ONLY the public key",
        "ES256: wrong key, tampered payload, truncated/DER signature, expired, not admin are rejected",
        "ES256 without a configured public key is never trusted",
        "migrated state (public key, no secret): HS256 tokens",
        "alg=none / unknown algs are rejected in every configuration",
        "legacy HS256 behaviour is unchanged when only JWT_SECRET_KEY is configured",
        "production with ONLY the public key",
        "production with NEITHER secret nor public key fails closed",
        "production legacy (secret only) still works; dual (secret + public key) accepts both",
    ):
        assert title in mjs, title
        assert title in flat, title


def test_render_yaml_declares_admin_keys_as_dashboard_only_and_has_no_floor_env():
    lines = _read(REPO_ROOT / "render.yaml").splitlines()
    declared: dict[str, list[str]] = {}
    for idx, line in enumerate(lines):
        match = re.match(r"^\s*-\s*key:\s*(\S+)\s*$", line)
        if not match:
            continue
        following = [
            ln.strip() for ln in lines[idx + 1 : idx + 3] if ln.strip() and not ln.strip().startswith("#")
        ]
        declared.setdefault(match.group(1), []).append(following[0] if following else "")
    for name in ("ADMIN_JWT_PRIVATE_KEY", "ADMIN_JWT_PUBLIC_KEY", "ADMIN_JWT_ENFORCE"):
        assert name in declared, name
        assert all(v == "sync: false" for v in declared[name]), (name, declared[name])
    # Release policy: no force-update floor is ever declared as a value in the blueprint.
    for forbidden in ("MIN_APP_VERSION", "MIN_ANDROID_BUILD", "MIN_IOS_BUILD"):
        assert forbidden not in declared, forbidden


def test_no_private_key_material_in_docs_or_blueprint():
    pem = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----\s*[A-Za-z0-9+/=]{40,}")
    for path in list(DOCS.glob("*.md")) + [REPO_ROOT / "render.yaml"]:
        assert not pem.search(_read(path)), path.name


# --------------------------------------------------------------------------
# Force-update document
# --------------------------------------------------------------------------
def test_force_update_doc_states_the_policy():
    text = _flat(FU_DOC)
    assert "The mandatory floors stay UNSET for the initial release" in text
    assert "a valid latest_app_version (env LATEST_APP_VERSION) must be set" in text
    assert "Never activate an iOS hard floor without a working App Store URL" in text
    assert "Server-side version enforcement (X-App-Version / HTTP 426) is deferred until after v1" in text
    assert "leave MIN_APP_VERSION, MIN_ANDROID_BUILD, MIN_IOS_BUILD unset" in text
    assert "falls back" in text or "takes over" in text  # the env-fallback gotcha


def test_force_update_doc_setting_and_env_names_match_the_code():
    from kk import app_settings

    doc = _read(FU_DOC)
    settings_source = inspect.getsource(app_settings)
    keys = (
        "min_app_version",
        "min_android_build",
        "min_ios_build",
        "force_update_message",
        "recommended_app_version",
        "recommended_android_build",
        "recommended_ios_build",
        "latest_app_version",
        "soft_update_message",
        "android_store_url",
        "ios_store_url",
    )
    for key in keys:
        assert key in app_settings.SETTING_KEYS, key
        assert f"`{key}`" in doc, key
    envs = (
        "MIN_APP_VERSION",
        "MIN_ANDROID_BUILD",
        "MIN_IOS_BUILD",
        "FORCE_UPDATE_MESSAGE",
        "RECOMMENDED_APP_VERSION",
        "RECOMMENDED_ANDROID_BUILD",
        "RECOMMENDED_IOS_BUILD",
        "LATEST_APP_VERSION",
        "SOFT_UPDATE_MESSAGE",
        "ANDROID_STORE_URL",
        "IOS_STORE_URL",
    )
    for env in envs:
        assert re.search(rf'_env\(\s*"{env}"', settings_source), env
        assert env in doc, env


def test_force_update_doc_caps_and_defaults_match_the_code():
    from kk import app_settings

    flat = _flat(FU_DOC)
    assert app_settings.MAX_VERSION_MAJOR == 99
    assert re.search(r"major <= 99(?!\d)", flat)
    assert app_settings.BUILD_SETTING_LIMITS["min_android_build"] == 2_100_000_000
    assert "2,100,000,000" in flat
    assert app_settings.BUILD_SETTING_LIMITS["min_ios_build"] == 10**18 - 1
    assert "999,999,999,999,999,999" in flat
    assert app_settings._STORE_URL_MAX_LEN == 2048 and "2048" in flat
    for scheme in app_settings._STORE_URL_SCHEMES:
        assert scheme in flat, scheme

    # Android store URL default is in the doc; the iOS one has no default.
    assert app_settings._DEFAULT_ANDROID_STORE_URL in _read(FU_DOC)
    served = app_settings.public_version_gate_settings({})
    assert served["android_store_url"] == app_settings._DEFAULT_ANDROID_STORE_URL
    assert served["ios_store_url"] == ""
    assert served["min_app_version"] == "" and served["min_android_build"] is None
    assert '"ios_store_url": _env("IOS_STORE_URL", "")' in _read(REPO_ROOT / "kk" / "app_settings.py")


def test_force_update_doc_accepted_formats_match_the_parsers():
    from kk.app_settings import parse_version

    assert parse_version("0.0.0") == (0, 0, 0)  # documented "no gate" override value
    assert parse_version("99.0.0") == (99, 0, 0)
    for rejected in ("100.0.0", "v2.0.0", "1.0.0-beta", "1.0.0+7", "1.x"):
        assert parse_version(rejected) is None, rejected


def test_force_update_doc_missing_ios_url_is_not_blocked_by_write_validation():
    """The doc says validation does not look at the store URL: keep that statement true."""
    from kk import app_settings

    source = inspect.getsource(app_settings._validate_version_gate_patch)
    # The only store-URL handling is syntactic validation of the URL itself.
    assert "ios_store_url" not in source  # nothing cross-checks the iOS URL against a floor
    assert "STORE_URL_SETTING_KEYS" in source


def test_force_update_doc_client_constants_match_the_dart_gate():
    dart = _read(REPO_ROOT / "lib" / "services" / "app_version_gate.dart")
    flat = _flat(FU_DOC)

    def duration(name: str) -> tuple[str, int]:
        match = re.search(rf"static const Duration {name} = Duration\((\w+): (\d+)\);", dart)
        assert match, name
        return match.group(1), int(match.group(2))

    assert duration("staleMax") == ("hours", 24)
    assert duration("cacheTtl") == ("minutes", 15)
    assert duration("failureBackoff") == ("seconds", 30)
    assert duration("minResumeGap") == ("seconds", 10)
    assert re.search(r"static const int maxVersionMajor = 99;", dart)
    assert "24 hours" in flat and "15 minutes" in flat and "30 seconds" in flat
    assert "at least 10 s apart" in flat


def test_force_update_doc_cites_only_existing_tests():
    cited = _cited_test_names(FU_DOC)
    assert cited
    known = _test_names("test_fu_server_config.py", "test_fu_codemagic_ios_build_name.py")
    assert not (cited - known), sorted(cited - known)


def test_server_side_enforcement_is_still_deferred():
    """Doc says no 426 / header enforcement exists. If that changes, rewrite the doc."""
    for path in (REPO_ROOT / "kk").rglob("*.py"):
        if "tests" in path.parts:
            continue
        assert not re.search(r"\b426\b", _read(path)), f"{path.name}: HTTP 426 now exists - update the doc"
    misc = _read(REPO_ROOT / "kk" / "routes" / "misc.py")
    assert "Diagnostics only" in misc
    lib_headers = [
        p
        for p in (REPO_ROOT / "lib").rglob("*.dart")
        if "X-App-Version" in _read(p)
    ]
    assert lib_headers == [], "client now sends X-App-Version: update the force-update doc"


# --------------------------------------------------------------------------
# Internal blockers list (must stay out of the public repository)
# --------------------------------------------------------------------------
def test_public_release_blockers_list_is_not_tracked_in_the_public_repository():
    """The unresolved-blockers list is internal until its wording has been reviewed."""
    assert not INTERNAL_BLOCKERS_DOC.exists(), (
        "docs/PUBLIC_RELEASE_BLOCKERS.md must stay out of the public repository "
        "until the owner has reviewed its wording"
    )


def test_f04_flag_defaults_to_off_as_documented(monkeypatch):
    import kk.saved_search_alert_jobs as jobs

    monkeypatch.delenv(jobs.FLAG_ENV, raising=False)
    assert jobs.durability_mode() == "off"
    monkeypatch.setenv(jobs.FLAG_ENV, "garbage")
    assert jobs.durability_mode() == "off"
    assert "SAVED_SEARCH_ALERT_DURABILITY" not in _read(REPO_ROOT / "render.yaml").replace("#", "")
