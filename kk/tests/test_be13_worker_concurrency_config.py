"""BE-13: verify the carr-worker start command sets a memory-safe concurrency.

Production evidence: with no explicit ``--concurrency``, Celery defaulted to
``multiprocessing.cpu_count()`` (observed: 16) on a 512 MB Render instance --
far more prefork children than the instance can hold, since each child
rebuilds the full Flask app and, for image tasks, loads OpenCV/NumPy/Pillow/
boto3. This is a static config check (parses ``render.yaml`` / ``Procfile``);
it does not invoke Celery or run any task.
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


def _read(rel_path: str) -> str:
    with open(os.path.join(_REPO_ROOT, rel_path), "r", encoding="utf-8") as fp:
        return fp.read()


def test_render_yaml_carr_worker_start_command_has_memory_safe_flags():
    text = _read("render.yaml")

    # Isolate the carr-worker service block: from "name: carr-worker" up to the
    # next "  - type:" service entry (carr-beat).
    m = re.search(
        r"name:\s*carr-worker\b(.*?)(?=\n\s*-\s*type:|\Z)",
        text,
        flags=re.DOTALL,
    )
    assert m, "carr-worker service block not found in render.yaml"
    block = m.group(1)

    start_cmd_match = re.search(r"startCommand:\s*(.+)", block)
    assert start_cmd_match, "carr-worker startCommand not found in render.yaml"
    start_cmd = start_cmd_match.group(1).strip()

    assert start_cmd.startswith(
        "celery -A kk.tasks.celery_app.celery_app worker --loglevel=info"
    ), f"unexpected carr-worker startCommand: {start_cmd!r}"
    for flag in _EXPECTED_WORKER_FLAGS:
        assert flag in start_cmd, f"missing {flag!r} in carr-worker startCommand: {start_cmd!r}"


def test_render_yaml_carr_beat_start_command_is_unchanged():
    text = _read("render.yaml")

    m = re.search(
        r"name:\s*carr-beat\b(.*?)(?=\n\s*-\s*type:|\Z)",
        text,
        flags=re.DOTALL,
    )
    assert m, "carr-beat service block not found in render.yaml"
    block = m.group(1)

    start_cmd_match = re.search(r"startCommand:\s*(.+)", block)
    assert start_cmd_match, "carr-beat startCommand not found in render.yaml"
    start_cmd = start_cmd_match.group(1).strip()

    assert start_cmd == "celery -A kk.tasks.celery_app.celery_app beat --loglevel=info", (
        f"carr-beat startCommand must remain unchanged (BE-13 only touches the worker): {start_cmd!r}"
    )


def test_procfile_worker_line_has_memory_safe_flags():
    text = _read("Procfile")

    m = re.search(r"^worker:\s*(.+)$", text, flags=re.MULTILINE)
    assert m, "worker: line not found in Procfile"
    worker_cmd = m.group(1).strip()

    assert worker_cmd.startswith(
        "celery -A kk.tasks.celery_app.celery_app worker --loglevel=info"
    ), f"unexpected Procfile worker command: {worker_cmd!r}"
    for flag in _EXPECTED_WORKER_FLAGS:
        assert flag in worker_cmd, f"missing {flag!r} in Procfile worker command: {worker_cmd!r}"


def test_procfile_beat_line_is_unchanged():
    text = _read("Procfile")

    m = re.search(r"^beat:\s*(.+)$", text, flags=re.MULTILINE)
    assert m, "beat: line not found in Procfile"
    beat_cmd = m.group(1).strip()

    assert beat_cmd == "celery -A kk.tasks.celery_app.celery_app beat --loglevel=info", (
        f"Procfile beat command must remain unchanged (BE-13 only touches the worker): {beat_cmd!r}"
    )
