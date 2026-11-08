"""Documentation / deployment-configuration guard for the release runbooks.

Static checks only: no Flask app, no database, no network, no Render API and no secrets.
They keep four things honest against the source they describe, so the runbooks cannot
silently drift again:

* ``render.yaml`` declares every environment variable that makes a Flask-initialising
  service boot (``carr`` and the Celery worker), never as a literal value;
* ``docs/ROLLBACK.md`` describes the *actual* Alembic head and every revision added on top
  of production's assumed previous head, with the data-loss hazards;
* release docs name the real Android production package and keep the iOS identifier;
* ``docs/RELEASE_DEPLOY_ORDER.md`` matches the commands in ``render.yaml`` and the order
  in which services must be deployed.

When one of these fails, update the document (or the blueprint) together with the code.
"""

from __future__ import annotations

import inspect
import re
from pathlib import Path

import yaml
from alembic.config import Config
from alembic.script import ScriptDirectory

REPO_ROOT = Path(__file__).resolve().parents[2]
DOCS = REPO_ROOT / "docs"

# Production's last revision before the release candidate (assumed; the runbooks tell the
# owner to verify it with ``flask db current`` before deploying).
PRODUCTION_BASE_REVISION = "v0w1x2y3z4a5"

ANDROID_PROD_PACKAGE = "com.carnetiq.app"
LEGACY_PACKAGE = "com.carzo.app"  # iOS bundle id, Android namespace, legacy Android client

# Variables the R2 persistence checks in kk/config.py require (asserted below to still be
# mentioned there, so this list cannot drift from the code).
R2_LISTING_VARS = (
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
    "R2_PUBLIC_URL",
)
R2_CHAT_VARS = (
    "R2_CHAT_BUCKET_NAME",
    "R2_CHAT_ACCESS_KEY_ID",
    "R2_CHAT_SECRET_ACCESS_KEY",
)


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _flat(path: Path) -> str:
    """Document text with markdown emphasis/code ticks removed and whitespace collapsed."""
    text = _read(path).replace("*", "").replace("`", "")
    return re.sub(r"\s+", " ", text)


def _render() -> dict:
    return yaml.safe_load(_read(REPO_ROOT / "render.yaml"))


def _service(name: str) -> dict:
    matches = [s for s in _render()["services"] if s["name"] == name]
    assert len(matches) == 1, f"expected exactly one service named {name!r} in render.yaml"
    return matches[0]


def _env_keys(service: dict) -> dict[str, dict]:
    return {e["key"]: e for e in service.get("envVars", [])}


def _boot_required_secrets() -> tuple[str, ...]:
    """The variables ``validate_required_secrets`` rejects an empty value for."""
    from kk.config import validate_required_secrets

    src = inspect.getsource(validate_required_secrets)
    m = re.search(r"for key in \(([^)]*)\)", src)
    assert m, "validate_required_secrets no longer iterates a literal tuple; update this guard"
    keys = tuple(re.findall(r"'([A-Z0-9_]+)'|\"([A-Z0-9_]+)\"", m.group(1)))
    flat = tuple(a or b for a, b in keys)
    assert flat, "no required keys parsed from validate_required_secrets"
    return flat


def _alembic_script() -> ScriptDirectory:
    cfg = Config()
    cfg.set_main_option("script_location", str(REPO_ROOT / "migrations"))
    return ScriptDirectory.from_config(cfg)


# ---------------------------------------------------------------------------
# render.yaml: environment declarations
# ---------------------------------------------------------------------------


def test_boot_required_names_are_what_this_guard_assumes():
    """If kk/config.py changes the required set, this guard and render.yaml must follow."""
    assert set(_boot_required_secrets()) == {
        "SECRET_KEY",
        "JWT_SECRET_KEY",
        "DATABASE_URL",
        "SUPPORT_EMAIL",
    }
    config_src = _read(REPO_ROOT / "kk" / "config.py")
    for name in (*R2_LISTING_VARS, *R2_CHAT_VARS, "REDIS_URL"):
        assert name in config_src, f"{name} is no longer referenced by kk/config.py"


def test_flask_initialising_services_declare_every_boot_required_variable():
    """``carr`` and the worker both call ``create_app()`` (the worker via
    ``get_celery_flask_app``), so both must declare everything boot validation needs.

    A missing declaration is how the Frankfurt worker once lacked ``SUPPORT_EMAIL`` and
    would have exited at boot with "Missing required environment variables".
    """
    required = {
        *_boot_required_secrets(),
        "APP_ENV",
        "REDIS_URL",
        *R2_LISTING_VARS,
        *R2_CHAT_VARS,
    }
    for name in ("carr", "carr-worker-fra"):
        declared = set(_env_keys(_service(name)))
        missing = sorted(required - declared)
        assert not missing, f"render.yaml service {name!r} does not declare: {missing}"


def test_push_credentials_are_declared_on_services_that_send_push():
    for name in ("carr", "carr-worker-fra"):
        declared = set(_env_keys(_service(name)))
        assert {"FIREBASE_SERVICE_ACCOUNT_BASE64", "FIREBASE_EXPECTED_PROJECT_ID"} <= declared, name


def test_celery_worker_tasks_do_build_the_flask_app():
    """Justifies the worker's declarations: if tasks stop calling create_app(), revisit."""
    src = _read(REPO_ROOT / "kk" / "tasks" / "celery_app.py")
    assert "create_app" in src and "get_celery_flask_app" in src


def test_beat_declares_only_what_it_needs_and_does_not_build_the_app():
    declared = set(_env_keys(_service("carr-beat-fra")))
    assert {"APP_ENV", "REDIS_URL"} <= declared
    # Beat must not need app-boot variables; if it did, the docs would be wrong.
    assert not (declared & set(_boot_required_secrets()))


def test_render_env_vars_never_carry_literal_secret_values():
    """Convention: secrets and dashboard-managed values are ``sync: false`` so a Blueprint
    sync can never overwrite a live value and nothing sensitive reaches Git."""
    literal_allowed = {
        ("carr-admin", "NODE_VERSION"),
        ("carr-admin", "NODE_ENV"),
        ("carr-worker-fra", "APP_ENV"),
        ("carr-beat-fra", "APP_ENV"),
    }
    for service in _render()["services"]:
        for env in service.get("envVars", []):
            key = env["key"]
            if "fromService" in env:
                assert (service["name"], key) == ("carr-admin", "NEXT_PUBLIC_API_BASE")
                continue
            if "value" in env:
                assert (service["name"], key) in literal_allowed, (
                    f"{service['name']}.{key} has a literal value in render.yaml; "
                    "use `sync: false` and set it in the dashboard"
                )
                if key == "APP_ENV":
                    assert env["value"] == "production"
            else:
                assert env.get("sync") is False, f"{service['name']}.{key} must be `sync: false`"


def test_carr_app_env_is_dashboard_managed_and_not_overwritten_by_sync():
    assert _env_keys(_service("carr"))["APP_ENV"].get("sync") is False
    assert "value" not in _env_keys(_service("carr"))["APP_ENV"]


# ---------------------------------------------------------------------------
# Deployment commands
# ---------------------------------------------------------------------------


def test_deployment_commands_match_the_runbook():
    carr = _service("carr")
    assert carr["startCommand"] == "bash start_render.sh"
    assert carr["healthCheckPath"] == "/health"

    script = _read(REPO_ROOT / "start_render.sh")
    assert "set -e" in script
    assert script.index("python -m flask db upgrade") < script.index("exec gunicorn")
    assert 'exec gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"' in script

    worker = _service("carr-worker-fra")["startCommand"]
    beat = _service("carr-beat-fra")["startCommand"]
    assert worker.startswith("celery -A kk.tasks.celery_app.celery_app worker ")
    assert beat == "celery -A kk.tasks.celery_app.celery_app beat --loglevel=info"

    order_doc = _read(DOCS / "RELEASE_DEPLOY_ORDER.md")
    assert worker in order_doc, "RELEASE_DEPLOY_ORDER.md worker command differs from render.yaml"
    assert beat in order_doc, "RELEASE_DEPLOY_ORDER.md beat command differs from render.yaml"
    assert "python -m flask db upgrade" in order_doc


def test_celery_app_import_path_used_by_render_resolves():
    from kk.tasks.celery_app import celery_app

    assert celery_app.main
    assert "retention-cleanup" in celery_app.conf.beat_schedule


def test_only_carr_runs_migrations():
    for name in ("carr-worker-fra", "carr-beat-fra", "carr-admin"):
        assert "db upgrade" not in _service(name)["startCommand"]
        assert "db upgrade" not in _service(name).get("buildCommand", "")


def test_service_order_in_deploy_doc_is_api_then_worker_then_beat_then_admin():
    text = _read(DOCS / "RELEASE_DEPLOY_ORDER.md")
    steps = {
        "carr": text.index("**Deploy `carr` first.**"),
        "worker": text.index("**Deploy `carr-worker-fra`.**"),
        "beat": text.index("**Deploy `carr-beat-fra` after the worker is healthy.**"),
        "admin": text.index("**Deploy `carr-admin` last of the web services**"),
    }
    assert steps["carr"] < steps["worker"] < steps["beat"] < steps["admin"]
    assert "flask db current" in text
    assert "Keep exactly **one** beat instance" in text


def test_post_deploy_commands_and_flags_exist():
    doc = _read(DOCS / "RELEASE_DEPLOY_ORDER.md")
    script = _read(REPO_ROOT / "scripts" / "verify_production_host.py")
    for flag in ("--require-app-links", "--require-upload-persistence"):
        assert flag in doc
        assert flag in script, f"{flag} no longer exists in scripts/verify_production_host.py"
    for path in ("/health", "/health/push"):
        assert path in doc
    misc = _read(REPO_ROOT / "kk" / "routes" / "misc.py")
    assert '"/health"' in misc and '"/health/push"' in misc


def test_deploy_docs_list_boot_requirements():
    for rel in ("DEPLOYMENT.md", "RENDER_SETUP.md"):
        text = _read(REPO_ROOT / rel)
        for name in ("SUPPORT_EMAIL", "REDIS_URL", "DATABASE_URL"):
            assert name in text, f"{rel} must mention {name}"
    flat = _flat(DOCS / "RELEASE_DEPLOY_ORDER.md")
    for name in (*R2_LISTING_VARS, *R2_CHAT_VARS, "SUPPORT_EMAIL", "REDIS_URL"):
        assert name in flat, f"RELEASE_DEPLOY_ORDER.md must list {name}"


# ---------------------------------------------------------------------------
# ROLLBACK.md vs the real migration chain
# ---------------------------------------------------------------------------


def test_alembic_has_one_head_and_rollback_doc_names_it():
    script = _alembic_script()
    heads = script.get_heads()
    assert len(heads) == 1, f"expected a single Alembic head, got {heads}"
    head = heads[0]
    doc = _read(DOCS / "ROLLBACK.md")
    assert f"`{head}`" in doc, f"docs/ROLLBACK.md does not mention the current head {head}"
    assert f"{head} (head)" in doc, "docs/ROLLBACK.md must state what `flask db current` prints"


def test_rollback_doc_covers_every_revision_above_the_production_base():
    script = _alembic_script()
    head = script.get_current_head()
    revisions = [
        r
        for r in script.iterate_revisions(head, PRODUCTION_BASE_REVISION)
        if r.revision != PRODUCTION_BASE_REVISION
    ]
    assert revisions, "no revisions above the production base; update PRODUCTION_BASE_REVISION"
    doc = _read(DOCS / "ROLLBACK.md")
    assert PRODUCTION_BASE_REVISION in doc
    for rev in revisions:
        assert rev.revision in doc, f"docs/ROLLBACK.md omits revision {rev.revision}"
        source = Path(rev.path).read_text(encoding="utf-8")
        for table in re.findall(r"create_table\(\s*[\"'](\w+)[\"']", source):
            assert table in doc, f"docs/ROLLBACK.md omits table {table} from {rev.revision}"
        for obj in re.findall(r"CREATE (?:FUNCTION|TRIGGER)\s+(\w+)", source):
            assert obj in doc, f"docs/ROLLBACK.md omits {obj} from {rev.revision}"


def test_rollback_doc_documents_hazards_exports_and_safe_options():
    flat = _flat(DOCS / "ROLLBACK.md")
    for phrase in (
        "Do not assume v0w1x2y3z4a5 is the right target",
        "Downgrades are data loss",
        "pg_dump",
        "account_deletion_request",
        "admin_audit_log",
        "Option 1 (preferred): roll back the code only",
        "Option 2: downgrade the schema",
        "Option 3 (last resort): restore from backup",
        "Can't locate revision",
        "Suspend carr-beat-fra first",
        "RETENTION_ENABLED",
        "Partial downgrades need matching code",
    ):
        assert phrase in flat, f"docs/ROLLBACK.md lost required content: {phrase!r}"
    # Never present the downgrade as the default.
    assert "Option 1 (preferred)" in flat


def test_no_doc_cites_a_stale_database_head():
    head = _alembic_script().get_current_head()
    stale = []
    for path in [*DOCS.glob("*.md"), REPO_ROOT / "DEPLOYMENT.md", REPO_ROOT / "RENDER_SETUP.md"]:
        for cited in re.findall(r"Database head `([0-9a-z]+)`", _read(path)):
            if cited != head:
                stale.append((path.name, cited))
    assert not stale, f"docs cite a head other than {head}: {stale}"


# ---------------------------------------------------------------------------
# Android / iOS identifiers
# ---------------------------------------------------------------------------


def test_gradle_prod_flavor_is_the_documented_android_package():
    gradle = _read(REPO_ROOT / "android" / "app" / "build.gradle.kts")
    m = re.search(r'create\("prod"\)\s*\{(.*?)\n\s*\}', gradle, flags=re.DOTALL)
    assert m, "prod flavor block not found in build.gradle.kts"
    assert re.search(rf'applicationId\s*=\s*"{re.escape(ANDROID_PROD_PACKAGE)}"', m.group(1))


def test_ios_bundle_identifier_is_preserved():
    pbx = _read(REPO_ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj")
    assert f"PRODUCT_BUNDLE_IDENTIFIER = {LEGACY_PACKAGE};" in pbx
    assert "bundle_identifier: com.carzo.app" in _read(REPO_ROOT / "codemagic.yaml")
    publish = _flat(DOCS / "PUBLISH_READY_CHECKLIST.md")
    assert "iOS bundle identifier is com.carzo.app" in publish


def test_release_docs_name_the_android_production_package():
    for name in ("PUBLISH_READY_CHECKLIST.md", "STORE_SUBMISSION.md", "FIREBASE_API_KEYS.md"):
        assert ANDROID_PROD_PACKAGE in _read(DOCS / name), f"{name} must name {ANDROID_PROD_PACKAGE}"


def test_release_docs_never_call_the_legacy_package_android_production():
    """Any line naming bare ``com.carzo.app`` (not ``.dev``/``.stage``) must be about iOS,
    the legacy client, the Gradle namespace/base id or the Apple bundle id."""
    release_docs = (
        "PUBLISH_READY_CHECKLIST.md",
        "STORE_SUBMISSION.md",
        "FIREBASE_API_KEYS.md",
        "DEPLOY_ENV_CHECKLIST.md",
        "ANDROID_APP_LINKS_SETUP.md",
        "RELEASE_POLICY_FORCE_UPDATE.md",
        "OWNER_ACTIONS.md",
        "REAL_DEVICE_QA.md",
    )
    context = ("ios", "legacy", "namespace", "base/default", "bundle", "apple")
    offenders = []
    for name in release_docs:
        for n, line in enumerate(_read(DOCS / name).splitlines(), 1):
            if re.search(r"com\.carzo\.app(?!\.(?:dev|stage))", line):
                if not any(word in line.lower() for word in context):
                    offenders.append(f"docs/{name}:{n}: {line.strip()[:120]}")
    assert not offenders, "Android production package mis-stated:\n" + "\n".join(offenders)

    prod_line = [
        line for line in _read(REPO_ROOT / "kk" / "PRODUCTION.md").splitlines() if "com.carzo.app" in line
    ]
    assert all("legacy" in line or ANDROID_PROD_PACKAGE in line or ".dev" in line for line in prod_line)


def test_deploy_order_doc_is_linked_from_runbooks():
    assert "RELEASE_DEPLOY_ORDER.md" in _read(DOCS / "ROLLBACK.md")
    assert "RELEASE_DEPLOY_ORDER.md" in _read(REPO_ROOT / "DEPLOYMENT.md")
    assert "RELEASE_DEPLOY_ORDER.md" in _read(REPO_ROOT / "RENDER_SETUP.md")
