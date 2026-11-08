"""Dependency + worker policy after the Gunicorn 26 / Flask-CORS 6.0.5 upgrade.

* Production runs ``gthread`` + Socket.IO ``threading`` (CHAT-1 / C-1).
* Gunicorn >= 26 removed the eventlet worker, so no environment combination may
  select it any more (it must degrade to gthread, never fail at boot).
* The hash-locked ``kk/requirements.txt`` agrees with ``kk/requirements.in`` and
  ``kk/requirements_min.txt`` for the security-relevant pins.
"""

from __future__ import annotations

import re
import runpy
import sys
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parents[2]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

_CONF = _ROOT / "gunicorn.conf.py"
_LOCK = _ROOT / "kk" / "requirements.txt"
_IN = _ROOT / "kk" / "requirements.in"
_MIN = _ROOT / "kk" / "requirements_min.txt"

_ENV_KEYS = (
    "SOCKETIO_ASYNC_MODE",
    "SOCKETIO_ALLOW_EVENTLET",
    "SOCKETIO_MESSAGE_QUEUE",
    "REDIS_URL",
    "WEB_CONCURRENCY",
    "GUNICORN_THREADS",
)


def _conf(monkeypatch, **env) -> dict:
    for k in _ENV_KEYS:
        monkeypatch.delenv(k, raising=False)
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    return runpy.run_path(str(_CONF))


def _lock_pin(name: str) -> str | None:
    m = re.search(rf"(?mi)^{re.escape(name)}==([^\s;\\]+)", _LOCK.read_text("utf-8"))
    return m.group(1) if m else None


def _vt(v: str) -> tuple[int, ...]:
    return tuple(int(p) for p in re.findall(r"\d+", v)[:3])


# ----------------------------------------------------------------- worker policy
def test_default_worker_is_gthread_with_threading(monkeypatch):
    c = _conf(monkeypatch)
    assert c["worker_class"] == "gthread"
    assert c["workers"] == 1
    assert c["threads"] >= 8  # C-1: room for sockets AND REST


@pytest.mark.parametrize(
    "env",
    [
        {"SOCKETIO_ASYNC_MODE": "eventlet"},
        {"SOCKETIO_ASYNC_MODE": "eventlet", "SOCKETIO_ALLOW_EVENTLET": "1"},
        {
            "SOCKETIO_ASYNC_MODE": "eventlet",
            "SOCKETIO_ALLOW_EVENTLET": "1",
            "REDIS_URL": "redis://localhost:6379/0",
        },
        {
            "SOCKETIO_ASYNC_MODE": "eventlet",
            "SOCKETIO_ALLOW_EVENTLET": "true",
            "SOCKETIO_MESSAGE_QUEUE": "redis://localhost:6379/1",
        },
    ],
)
def test_eventlet_can_never_select_the_removed_worker(monkeypatch, capsys, env):
    c = _conf(monkeypatch, **env)
    assert c["worker_class"] == "gthread"
    assert "eventlet" in capsys.readouterr().err.lower()  # operator is told why


def test_app_factory_matches_conf_for_every_eventlet_combo(monkeypatch):
    from kk.app_factory import _socketio_async_mode

    for k in _ENV_KEYS:
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("SOCKETIO_ASYNC_MODE", "eventlet")
    monkeypatch.setenv("SOCKETIO_ALLOW_EVENTLET", "1")
    assert _socketio_async_mode("production", has_message_queue=True) == "threading"
    assert _socketio_async_mode("production", has_message_queue=False) == "threading"


def test_worker_class_and_socketio_mode_never_disagree(monkeypatch):
    """gthread worker <=> Socket.IO threading (the C-1 tested combination)."""
    from kk.app_factory import _socketio_async_mode

    for mode in ("", "eventlet", "gevent", "threading"):
        for allow in ("", "1"):
            for mq in ("", "redis://x/0"):
                env = {}
                if mode:
                    env["SOCKETIO_ASYNC_MODE"] = mode
                if allow:
                    env["SOCKETIO_ALLOW_EVENTLET"] = allow
                if mq:
                    env["SOCKETIO_MESSAGE_QUEUE"] = mq
                c = _conf(monkeypatch, **env)
                sio = _socketio_async_mode("production", has_message_queue=bool(mq))
                if c["worker_class"] == "gthread":
                    assert sio == "threading", (env, sio)
                else:
                    assert c["worker_class"] == "gevent" and sio == "gevent", (env, sio)


# ------------------------------------------------------------- dependency lock
def test_lock_has_no_eventlet_and_nothing_imports_it():
    assert _lock_pin("eventlet") is None
    assert re.search(r"(?mi)^eventlet\b", _IN.read_text("utf-8")) is None
    offenders = []
    for base in ("kk", "tools", "scripts"):
        for f in (_ROOT / base).rglob("*.py"):
            if "tests" in f.parts:
                continue
            if re.search(
                r"(?m)^\s*(import|from)\s+(eventlet|gevent)\b", f.read_text("utf-8", "ignore")
            ):
                offenders.append(str(f.relative_to(_ROOT)))
    assert offenders == []


def test_gunicorn_and_flask_cors_pins_agree_everywhere():
    g, c = _lock_pin("gunicorn"), _lock_pin("flask-cors")
    assert g and _vt(g) >= (26, 0, 0), g  # eventlet worker gone, parser hardening
    assert c and _vt(c) >= (6, 0, 1), c  # 6.0.1 fixes 6.0.0's inverted path sort
    for f in (_IN, _MIN):
        text = f.read_text("utf-8")
        assert re.search(rf"(?mi)^gunicorn=={re.escape(g)}\s*$", text), f.name
        assert re.search(rf"(?mi)^flask-cors=={re.escape(c)}\s*$", text), f.name


def test_every_locked_requirement_is_hash_pinned():
    text = _LOCK.read_text("utf-8")
    entries = re.split(r"(?m)^(?=[A-Za-z0-9_.\-]+(?:\[[^\]]*\])?==)", text)
    pins = [e for e in entries if re.match(r"[A-Za-z0-9_.\-]+(?:\[[^\]]*\])?==", e)]
    assert len(pins) > 50
    missing = [e.split("==")[0] for e in pins if "--hash=sha256:" not in e]
    assert missing == []


def test_installed_gunicorn_matches_lock_when_present():
    md = pytest.importorskip("importlib.metadata")
    try:
        installed = md.version("gunicorn")
    except md.PackageNotFoundError:  # minimal dev env
        pytest.skip("gunicorn not installed")
    assert installed == _lock_pin("gunicorn")
