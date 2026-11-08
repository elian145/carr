#!/usr/bin/env python
"""C-1 live load check against REAL gunicorn (gthread, 32 threads). Linux/macOS only.

Reproduces the attacks the WSGI edge guard (kk/socket_edge_guard.py) must stop and
proves ``/health`` + REST stay responsive, orphan Engine.IO sessions are reaped
and valid chat sessions / reconnects still work.

    APP_ENV=testing SMS_PROVIDER=console python scripts/c1_edge_load_check.py

Uses only a throwaway SQLite database under a temp dir. Never touches a real
database; exits non-zero if any check fails. Needs the app's runtime
requirements (gunicorn, python-socketio, requests).
"""
from __future__ import annotations

import base64
import http.client
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = int(os.environ.get("C1_LOAD_PORT", "58011"))
THREADS = int(os.environ.get("GUNICORN_THREADS", "32"))
DEADLINE = float(os.environ.get("SOCKETIO_AUTH_DEADLINE_SECONDS", "10"))
RESULTS: list[tuple[str, bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    RESULTS.append((name, bool(ok), detail))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail else ""), flush=True)


# ---------------------------------------------------------------- http helpers
def http_get(path: str, timeout: float = 4.0, headers: dict | None = None):
    t0 = time.monotonic()
    try:
        c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=timeout)
        c.request("GET", path, headers=headers or {})
        r = c.getresponse()
        r.read()
        c.close()
        return r.status, time.monotonic() - t0
    except Exception:
        return 0, time.monotonic() - t0


class HealthMonitor:
    """Polls /health and /api/cars while an attack is in progress."""

    def __init__(self):
        self.lat: list[float] = []
        self.fail = 0
        self._stop = threading.Event()
        self._t = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        paths = ["/health", "/api/cars?limit=1"]
        i = 0
        while not self._stop.is_set():
            status, dt = http_get(paths[i % 2])
            i += 1
            self.lat.append(dt)
            if status != 200:
                self.fail += 1
            time.sleep(0.2)

    def __enter__(self):
        self._t.start()
        return self

    def __exit__(self, *a):
        self._stop.set()
        self._t.join(10)

    def summary(self) -> str:
        mx = max(self.lat) if self.lat else -1
        return f"requests={len(self.lat)} failures={self.fail} max_latency={mx:.2f}s"


# ------------------------------------------------------------- raw ws helpers
def ws_connect(token: str | None = None, timeout: float = 6.0):
    s = socket.create_connection(("127.0.0.1", PORT), timeout=timeout)
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET /socket.io/?EIO=4&transport=websocket HTTP/1.1\r\nHost: 127.0.0.1:{PORT}\r\n"
        f"Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
    )
    if token:
        req += f"Authorization: Bearer {token}\r\n"
    s.sendall((req + "\r\n").encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = s.recv(4096)
        if not chunk:
            break
        buf += chunk
    status = int(buf.split(b" ", 2)[1]) if buf.startswith(b"HTTP/") else 0
    rest = buf.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in buf else b""
    return s, status, rest


def ws_read(s, buf: bytes):
    def need(n):
        nonlocal buf
        while len(buf) < n:
            c = s.recv(4096)
            if not c:
                raise EOFError
            buf += c

    need(2)
    ln, off = buf[1] & 0x7F, 2
    if ln == 126:
        need(4)
        ln, off = struct.unpack(">H", buf[2:4])[0], 4
    elif ln == 127:
        need(10)
        ln, off = struct.unpack(">Q", buf[2:10])[0], 10
    need(off + ln)
    return buf[0] & 0xF, buf[off : off + ln], buf[off + ln :]


def ws_send(s, text: str):
    data, mask = text.encode(), os.urandom(4)
    s.sendall(bytes([0x81, 0x80 | len(data)]) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))


def legit_ws_session(token: str) -> tuple[bool, str]:
    """Full Engine.IO + Socket.IO CONNECT over a raw websocket with a valid token."""
    try:
        s, status, rest = ws_connect(token)
        if status != 101:
            return False, f"upgrade status {status}"
        buf = rest
        _, payload, buf = ws_read(s, buf)  # engine.io OPEN
        if not payload.startswith(b"0"):
            return False, f"unexpected first packet {payload[:20]!r}"
        ws_send(s, "40")
        for _ in range(6):
            _, payload, buf = ws_read(s, buf)
            if payload.startswith(b"40"):
                s.close()
                return True, "connected"
            if payload.startswith(b"44"):
                s.close()
                return False, f"connect_error {payload[:60]!r}"
        s.close()
        return False, "no CONNECT ack"
    except Exception as e:  # noqa: BLE001
        return False, f"{type(e).__name__}: {e}"


def legit_polling_session(token: str) -> tuple[bool, str]:
    import socketio

    try:
        sio = socketio.Client(reconnection=False)
        sio.connect(
            f"http://127.0.0.1:{PORT}",
            headers={"Authorization": f"Bearer {token}"},
            transports=["polling"],
            wait_timeout=8,
        )
        ok = sio.connected
        sio.disconnect()
        return ok, "connected" if ok else "not connected"
    except Exception as e:  # noqa: BLE001
        return False, f"{type(e).__name__}: {e}"


def is_closed_by_server(s) -> bool:
    """True only on TCP EOF/reset. Frames (OPEN/ping) are drained and ignored."""
    try:
        s.settimeout(0.5)
        while True:
            if s.recv(4096) == b"":
                return True
    except socket.timeout:
        return False
    except OSError:
        return True


# ------------------------------------------------------------------- scenario
def main() -> int:
    tmp = tempfile.TemporaryDirectory(prefix="c1_load_")
    env = dict(os.environ)
    env.update(
        APP_ENV="testing",
        SMS_PROVIDER="console",
        DB_PATH=os.path.join(tmp.name, "load.db"),
        UPLOAD_FOLDER=os.path.join(tmp.name, "uploads"),
        BIND=f"127.0.0.1:{PORT}",
        GUNICORN_THREADS=str(THREADS),
        WEB_CONCURRENCY="1",
    )
    os.environ.update(env)
    sys.path.insert(0, ROOT)

    from flask_jwt_extended import create_access_token

    from kk.app_factory import create_app
    from kk.models import User, db

    app, *_ = create_app()
    with app.app_context():
        db.create_all()
        u = User(
            username=f"load_{uuid.uuid4().hex[:6]}",
            phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
            first_name="Load",
            last_name="Test",
            email=None,
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        u.set_password("Passw0rd!123")
        db.session.add(u)
        db.session.commit()
        token = create_access_token(identity=u.public_id)
        db.session.remove()
        db.engine.dispose()

    log = open(os.path.join(tmp.name, "gunicorn.log"), "w+")
    proc = subprocess.Popen(
        [sys.executable, "-m", "gunicorn", "kk.wsgi:app", "-c", "gunicorn.conf.py"],
        cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
    )
    held: list[socket.socket] = []
    try:
        for _ in range(80):
            if http_get("/health", 2)[0] == 200:
                break
            time.sleep(0.5)
        else:
            check("gunicorn starts and /health answers", False)
            return 1
        check("gunicorn starts and /health answers", True, f"threads={THREADS}")

        # --- baseline: valid sessions work
        ok, d = legit_ws_session(token)
        check("baseline: valid raw-websocket chat session connects", ok, d)
        ok, d = legit_polling_session(token)
        check("baseline: valid long-polling chat session connects", ok, d)

        # --- Attack A: anonymous raw websockets + anonymous polling sessions
        def anon_ws(_):
            s, st, _r = ws_connect(None)
            return s, st

        def anon_poll(_):
            return http_get("/socket.io/?EIO=4&transport=polling")[0]

        with HealthMonitor() as mon:
            with ThreadPoolExecutor(40) as ex:
                ws_res = list(ex.map(anon_ws, range(300)))
                poll_res = list(ex.map(anon_poll, range(300)))
            held += [s for s, _ in ws_res]
            ok_ws, d = legit_ws_session(token)
            ok_poll, d2 = legit_polling_session(token)
        check("A: 300 anonymous raw websockets all refused with 401 (none upgraded)",
              all(st == 401 for _, st in ws_res), f"statuses={sorted({st for _, st in ws_res})}")
        check("A: 300 anonymous polling handshakes all refused with 401",
              all(st == 401 for st in poll_res), f"statuses={sorted(set(poll_res))}")
        check("A: /health and REST stayed up during anonymous flood",
              mon.fail == 0 and max(mon.lat or [99]) < 2.0, mon.summary())
        check("A: valid sessions still connect during the flood", ok_ws and ok_poll, f"{d}; {d2}")
        for s in held:
            s.close()
        held.clear()

        # --- Attack B: authenticated websockets that never send CONNECT (over capacity)
        def auth_ws(_):
            s, st, _r = ws_connect(token)
            return s, st

        with HealthMonitor() as mon:
            with ThreadPoolExecutor(40) as ex:
                res = list(ex.map(auth_ws, range(100)))
            held += [s for s, _ in res]
            statuses = [st for _, st in res]
            accepted = statuses.count(101)
            time.sleep(3)
            rest_status, rest_dt = http_get("/api/cars?limit=1")
            health_status, health_dt = http_get("/health")
        limit = THREADS - 2
        check("B: sessions beyond the thread ceiling get 503 server_busy, not a thread",
              accepted <= limit and statuses.count(503) >= 100 - limit and set(statuses) <= {101, 503},
              f"accepted={accepted} limit<={limit} busy={statuses.count(503)}")
        check("B: /health and REST answer while the ceiling is saturated",
              health_status == 200 and rest_status == 200 and mon.fail == 0 and max(mon.lat) < 3.0,
              f"{mon.summary()} health={health_dt:.2f}s rest={rest_dt:.2f}s")
        t0 = time.monotonic()
        while time.monotonic() - t0 < DEADLINE + 15:
            time.sleep(2)
            closed = sum(1 for s, st in res if st == 101 and is_closed_by_server(s))
            if closed >= accepted:
                break
        check("B: orphan sessions (no CONNECT) are reaped and threads returned",
              closed >= accepted, f"closed={closed}/{accepted} after {time.monotonic() - t0:.0f}s")
        ok, d = legit_ws_session(token)
        check("B: after reaping, a valid websocket session connects again", ok, d)
        for s, _ in res:
            s.close()
        held.clear()

        # --- Attack C: authenticated long-poll sessions left hanging
        def poll_orphan(_):
            try:
                c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=5)
                c.request("GET", "/socket.io/?EIO=4&transport=polling",
                          headers={"Authorization": f"Bearer {token}"})
                r = c.getresponse()
                body = r.read().decode(errors="replace")
                c.close()
                if r.status != 200:
                    return None, r.status
                sid = json.loads(body[1:])["sid"]
                p = http.client.HTTPConnection("127.0.0.1", PORT, timeout=60)
                p.request("GET", f"/socket.io/?EIO=4&transport=polling&sid={sid}",
                          headers={"Authorization": f"Bearer {token}"})
                return p, 200  # request sent, response never read: thread stays pinned
            except Exception:  # noqa: BLE001
                return None, 0

        with HealthMonitor() as mon:
            with ThreadPoolExecutor(30) as ex:
                polls = list(ex.map(poll_orphan, range(60)))
            time.sleep(3)
            health_status, health_dt = http_get("/health")
        check("C: /health and REST answer while long-poll sessions hang",
              health_status == 200 and mon.fail == 0 and max(mon.lat) < 3.0,
              f"{mon.summary()} health={health_dt:.2f}s sessions_started={sum(1 for p, s in polls if s == 200)}")
        time.sleep(DEADLINE + 8)
        for p, _ in polls:
            if p is not None:
                p.close()
        ok_poll, d = legit_polling_session(token)
        ok_ws, d2 = legit_ws_session(token)
        check("C: after reaping, valid polling and websocket sessions connect", ok_poll and ok_ws, f"{d}; {d2}")

        # --- reconnect + REST fallback
        ok1, _ = legit_polling_session(token)
        ok2, _ = legit_polling_session(token)
        check("reconnect: two consecutive valid sessions succeed", ok1 and ok2)
        st, dt = http_get("/api/cars?limit=1")
        check("REST fallback answers", st == 200, f"{dt:.2f}s")
    finally:
        for s in held:
            try:
                s.close()
            except Exception:  # noqa: BLE001
                pass
        proc.terminate()
        try:
            proc.wait(15)
        except subprocess.TimeoutExpired:
            proc.kill()
        failed = [r for r in RESULTS if not r[1]]
        if failed:
            log.seek(0)
            print("--- gunicorn log tail ---\n" + "".join(log.readlines()[-25:]))
        log.close()
        tmp.cleanup()
    failed = [r for r in RESULTS if not r[1]]
    print(f"\n{len(RESULTS) - len(failed)}/{len(RESULTS)} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
