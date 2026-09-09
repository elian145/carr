"""BE-13: verify the carr-worker start command sets a memory-safe concurrency,
and (BE-13 region fix) that the Frankfurt duplicate services exist with the
correct region and identical commands to their Oregon counterparts.

Production evidence (concurrency): with no explicit ``--concurrency``, Celery
defaulted to ``multiprocessing.cpu_count()`` (observed: 16) on a 512 MB Render
instance -- far more prefork children than the instance can hold, since each
child rebuilds the full Flask app and, for image tasks, loads OpenCV/NumPy/
Pillow/boto3.

Production evidence (region): carr-redis lives in Frankfurt while carr-worker
and carr-beat were created in Oregon; Render's internal Redis hostname is only
reachable within the same region, so carr-worker-fra / carr-beat-fra were
added as new, region-pinned services (region is immutable on an existing
Render service, so the originals could not be edited in place).

This is a static config check (parses ``render.yaml`` / ``Procfile``); it does
not invoke Celery, Render's API, or run any task.
"""

from __future__ import annotations

import os
import re

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

_EXPECTED_WORKER_FLAGS = (
    "--concurrency=2",
    "--max-tasks-per-child=50",
    "--max-memory-per-child=200000",
)

_EXPECTED_WORKER_COMMAND = (
    "celery -A kk.tasks.celery_app.celery_app worker --loglevel=info "
    "--concurrency=2 --max-tasks-per-child=50 --max-memory-per-child=200000"
)

_EXPECTED_BEAT_COMMAND = "celery -A kk.tasks.celery_app.celery_app beat --loglevel=info"


def _read(rel_path: str) -> str:
    with open(os.path.join(_REPO_ROOT, rel_path), "r", encoding="utf-8") as fp:
        return fp.read()


def _render_yaml_service_block(text: str, service_name: str) -> str:
    """
    Isolate one service's YAML block by its exact ``name:`` value.

    Anchored so ``carr-worker`` does not also match as a text-prefix of
    ``carr-worker-fra`` (a plain ``\\b`` word boundary is not enough here,
    since ``-`` is already a non-word character and would satisfy ``\\b``
    right at the start of the ``-fra`` suffix). Requiring the name to be
    followed by end-of-line makes the match exact.
    """
    escaped = re.escape(service_name)
    pattern = rf"name:\s*{escaped}[ \t]*\r?\n(.*?)(?=\n[ \t]*-\s*type:|\Z)"
    m = re.search(pattern, text, flags=re.DOTALL)
    assert m, f"service block for name={service_name!r} not found in render.yaml"
    return m.group(1)


def _render_yaml_start_command(block: str) -> str:
    m = re.search(r"startCommand:\s*(.+)", block)
    assert m, "startCommand not found in service block"
    return m.group(1).strip()


def _render_yaml_region(block: str) -> str | None:
    m = re.search(r"^\s*region:\s*(\S+)", block, flags=re.MULTILINE)
    return m.group(1).strip() if m else None


# ---------------------------------------------------------------------------
# Oregon (original) services -- commands must be exactly as fixed by BE-13.
# ---------------------------------------------------------------------------


def test_render_yaml_carr_worker_start_command_has_memory_safe_flags():
    text = _read("render.yaml")
    block = _render_yaml_service_block(text, "carr-worker")
    start_cmd = _render_yaml_start_command(block)

    assert start_cmd == _EXPECTED_WORKER_COMMAND, f"unexpected carr-worker startCommand: {start_cmd!r}"
    for flag in _EXPECTED_WORKER_FLAGS:
        assert flag in start_cmd, f"missing {flag!r} in carr-worker startCommand: {start_cmd!r}"


def test_render_yaml_carr_beat_start_command_is_unchanged():
    text = _read("render.yaml")
    block = _render_yaml_service_block(text, "carr-beat")
    start_cmd = _render_yaml_start_command(block)

    assert start_cmd == _EXPECTED_BEAT_COMMAND, (
        f"carr-beat startCommand must remain unchanged (BE-13 only touches the worker): {start_cmd!r}"
    )


def test_procfile_worker_line_has_memory_safe_flags():
    text = _read("Procfile")

    m = re.search(r"^worker:\s*(.+)$", text, flags=re.MULTILINE)
    assert m, "worker: line not found in Procfile"
    worker_cmd = m.group(1).strip()

    assert worker_cmd == _EXPECTED_WORKER_COMMAND, f"unexpected Procfile worker command: {worker_cmd!r}"
    for flag in _EXPECTED_WORKER_FLAGS:
        assert flag in worker_cmd, f"missing {flag!r} in Procfile worker command: {worker_cmd!r}"


def test_procfile_beat_line_is_unchanged():
    text = _read("Procfile")

    m = re.search(r"^beat:\s*(.+)$", text, flags=re.MULTILINE)
    assert m, "beat: line not found in Procfile"
    beat_cmd = m.group(1).strip()

    assert beat_cmd == _EXPECTED_BEAT_COMMAND, (
        f"Procfile beat command must remain unchanged (BE-13 only touches the worker): {beat_cmd!r}"
    )


# ---------------------------------------------------------------------------
# Frankfurt (BE-13 region fix) services -- must exist, be pinned to
# region: frankfurt, and run the exact same command as their Oregon
# counterparts (region is the only intended behavioral difference).
# ---------------------------------------------------------------------------


def test_render_yaml_carr_worker_fra_is_pinned_to_frankfurt():
    text = _read("render.yaml")
    block = _render_yaml_service_block(text, "carr-worker-fra")

    assert _render_yaml_region(block) == "frankfurt", (
        "carr-worker-fra must explicitly set region: frankfurt "
        "(carr-redis lives in Frankfurt; Render's internal Redis hostname "
        "is only reachable within the same region)"
    )


def test_render_yaml_carr_beat_fra_is_pinned_to_frankfurt():
    text = _read("render.yaml")
    block = _render_yaml_service_block(text, "carr-beat-fra")

    assert _render_yaml_region(block) == "frankfurt", (
        "carr-beat-fra must explicitly set region: frankfurt "
        "(carr-redis lives in Frankfurt; Render's internal Redis hostname "
        "is only reachable within the same region)"
    )


def test_render_yaml_carr_worker_fra_command_matches_carr_worker():
    text = _read("render.yaml")
    worker_cmd = _render_yaml_start_command(_render_yaml_service_block(text, "carr-worker"))
    worker_fra_cmd = _render_yaml_start_command(_render_yaml_service_block(text, "carr-worker-fra"))

    assert worker_fra_cmd == worker_cmd == _EXPECTED_WORKER_COMMAND, (
        "carr-worker-fra must run the exact same command as carr-worker "
        f"(carr-worker={worker_cmd!r}, carr-worker-fra={worker_fra_cmd!r})"
    )


def test_render_yaml_carr_beat_fra_command_matches_carr_beat():
    text = _read("render.yaml")
    beat_cmd = _render_yaml_start_command(_render_yaml_service_block(text, "carr-beat"))
    beat_fra_cmd = _render_yaml_start_command(_render_yaml_service_block(text, "carr-beat-fra"))

    assert beat_fra_cmd == beat_cmd == _EXPECTED_BEAT_COMMAND, (
        "carr-beat-fra must run the exact same command as carr-beat "
        f"(carr-beat={beat_cmd!r}, carr-beat-fra={beat_fra_cmd!r})"
    )


def _render_yaml_top_level_service_names(text: str) -> list[str]:
    """
    Names of top-level Blueprint services only.

    Deliberately requires the exact 4-space indentation used by every
    top-level service's own ``name:`` key in this file, so this does not
    also pick up nested references such as ``carr-admin``'s
    ``fromService: {name: carr}`` (indented further, under ``envVars``).
    """
    return re.findall(r"^ {4}name:\s*(\S+)\s*$", text, flags=re.MULTILINE)


def test_render_yaml_carr_and_carr_admin_are_not_duplicated():
    """BE-13's region fix must not touch/duplicate carr or carr-admin."""
    names = _render_yaml_top_level_service_names(_read("render.yaml"))

    assert names.count("carr") == 1, f"expected exactly one service literally named 'carr', got names={names!r}"
    assert names.count("carr-admin") == 1, (
        f"expected exactly one service literally named 'carr-admin', got names={names!r}"
    )


def test_render_yaml_defines_exactly_the_expected_six_services():
    """
    BE-13 region fix adds exactly two new services (carr-worker-fra,
    carr-beat-fra) and must not add/remove/duplicate anything else.
    """
    names = _render_yaml_top_level_service_names(_read("render.yaml"))

    assert names == [
        "carr",
        "carr-admin",
        "carr-worker",
        "carr-worker-fra",
        "carr-beat",
        "carr-beat-fra",
    ], f"unexpected render.yaml service list/order: {names!r}"


def test_render_yaml_has_no_redis_service_definition():
    """carr-redis is provisioned separately in the Render dashboard, not via this Blueprint."""
    text = _read("render.yaml")

    assert "carr-redis" not in _render_yaml_top_level_service_names(text), (
        "carr-redis must not be defined as a Blueprint service in render.yaml (it exists outside the Blueprint)"
    )
    assert not re.search(r"^\s*-\s*type:\s*(redis|keyvalue)\b", text, flags=re.MULTILINE), (
        "render.yaml must not define a redis/keyvalue resource"
    )
