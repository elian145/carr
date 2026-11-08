#!/usr/bin/env python
"""N-2 live load test: can ONE account monopolize Socket.IO admission? (real gunicorn)

Linux/macOS only (gunicorn needs ``fcntl``); on Windows run it inside WSL:

    wsl -d Ubuntu-24.04 -e bash -c "cd /path/to/repo && python scripts/loadtest_ws_admission.py"

Starts the repo's ``gunicorn.conf.py`` (gthread, GUNICORN_THREADS=32) against a
throwaway SQLite database, creates an *attacker* and a *victim* account and
measures, while the attacker abuses the realtime edge with valid tokens:

  A  many raw websockets that never send the Socket.IO CONNECT packet
  B  many long-poll sessions whose polls stay in flight (stalled handshakes)
  C  expired-token handshakes (F-36 "token_expired" connect) held open
  D  rapid reconnect loop (connect -> CONNECT -> drop -> reconnect)
  E  many fully CONNECTed sockets
  F  a legitimate reconnect (stale socket + new socket of the SAME account)

For every attack it checks that a *different* account can still open a
websocket and a long-poll session, that ``/health`` and a REST endpoint stay
fast, and that the attacker's orphan sessions are eventually closed.

Exit code is non-zero when any check fails. Never touches a real database.
Env: ``N2_LOAD_PORT`` (default 58021), ``GUNICORN_THREADS`` (default 32),
``N2_ATTACK_SOCKETS`` (default 60).
"""
from __future__ import annotations

import http.client
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import c1_edge_load_check as c1  # noqa: E402  (reuses the raw-websocket helpers)

PORT = int(os.environ.get("N2_LOAD_PORT", "58021"))
THREADS = int(os.environ.get("GUNICORN_THREADS", "32"))
ATTACK = int(os.environ.get("N2_ATTACK_SOCKETS", "60"))
#: SOCKETIO_EDGE_MAX_PER_ACCOUNT for 32 threads (edge limit 20 // 3); +1 grace for an
#: eviction that is still unwinding when the sample is taken
ACCOUNT_SHARE = int(os.environ.get("N2_ACCOUNT_SHARE", "7"))
DEADLINE = float(os.environ.get("SOCKETIO_AUTH_DEADLINE_SECONDS", "10"))
c1.PORT = PORT
check = c1.check
RESULTS = c1.RESULTS


def make_user(db, User, tag):
    u = User(
        username=f"n2_{tag}_{uuid.uuid4().hex[:6]}",
        phone_number=f"077{uuid.uuid4().int % 10**8:08d}",
        first_name="N2",
        last_name=tag,
        email=None,
        is_active=True,
        is_verified=True,
        phone_verified=True,
        public_id=f"pub-{uuid.uuid4().hex[:12]}",
    )
    u.set_password("Passw0rd!123")
    db.session.add(u)
    db.session.commit()
    return u.public_id


def open_poll_session_hanging(token):
    """Handshake, then leave a poll request in flight (never read)."""
    try:
        conn = http.client.HTTPConnection("127.0.0.1", PORT, timeout=5)
        conn.request("GET", "/socket.io/?EIO=4&transport=polling",
                     headers={"Authorization": f"Bearer {token}"})
        r = conn.getresponse()
        body = r.read().decode(errors="replace")
        conn.close()
        if r.status != 200:
            return None, r.status
        sid = json.loads(body[1:])["sid"]
        p = http.client.HTTPConnection("127.0.0.1", PORT, timeout=60)
        p.request("GET", f"/socket.io/?EIO=4&transport=polling&sid={sid}",
                  headers={"Authorization": f"Bearer {token}"})
        return p, 200
    except Exception:  # noqa: BLE001
        return None, 0


def raw_ws_connected(token):
    """Open a websocket and complete the Socket.IO CONNECT. Returns (sock, ok)."""
    try:
        s, status, rest = c1.ws_connect(token)
        if status != 101:
            return s, False
        buf = rest
        _, payload, buf = c1.ws_read(s, buf)
        c1.ws_send(s, "40")
        for _ in range(6):
            _, payload, buf = c1.ws_read(s, buf)
            if payload.startswith(b"40"):
                return s, True
            if payload.startswith(b"44"):
                return s, False
        return s, False
    except Exception:  # noqa: BLE001
        return None, False


def victim_ok(token):
    ws_ok, d1 = c1.legit_ws_session(token)
    poll_ok, d2 = c1.legit_polling_session(token)
    return ws_ok and poll_ok, f"ws:{d1}; poll:{d2}"


def close_all(socks):
    for s in socks:
        try:
            if s is not None:
                s.close()
        except Exception:  # noqa: BLE001
            pass


def main() -> int:
    tmp = tempfile.TemporaryDirectory(prefix="n2_load_")
    env = dict(os.environ)
    env.update(
        APP_ENV="testing", SMS_PROVIDER="console",
        DB_PATH=os.path.join(tmp.name, "load.db"),
        UPLOAD_FOLDER=os.path.join(tmp.name, "uploads"),
        BIND=f"127.0.0.1:{PORT}", GUNICORN_THREADS=str(THREADS), WEB_CONCURRENCY="1",
        PYTHONDONTWRITEBYTECODE="1",
    )
    os.environ.update(env)
    sys.path.insert(0, ROOT)

    from datetime import timedelta

    from flask_jwt_extended import create_access_token

    from kk.app_factory import create_app
    from kk.models import User, db

    app, *_ = create_app()
    with app.app_context():
        db.create_all()
        attacker_id = make_user(db, User, "attacker")
        victim_id = make_user(db, User, "victim")
        attacker = create_access_token(identity=attacker_id)
        victim = create_access_token(identity=victim_id)
        expired = create_access_token(identity=attacker_id, expires_delta=timedelta(seconds=-5))
        db.session.remove()
        db.engine.dispose()

    log = open(os.path.join(tmp.name, "gunicorn.log"), "w+")
    proc = subprocess.Popen(
        [sys.executable, "-m", "gunicorn", "kk.wsgi:app", "-c", "gunicorn.conf.py"],
        cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
    )
    held: list = []
    try:
        for _ in range(80):
            if c1.http_get("/health", 2)[0] == 200:
                break
            time.sleep(0.5)
        else:
            check("gunicorn starts and /health answers", False)
            return 1
        check("gunicorn starts and /health answers", True, f"threads={THREADS}")
        ok, d = victim_ok(victim)
        check("baseline: victim connects (ws + polling)", ok, d)

        # ---- A: websockets that never send CONNECT
        with c1.HealthMonitor() as mon:
            with ThreadPoolExecutor(30) as ex:
                res = list(ex.map(lambda _: c1.ws_connect(attacker)[:2], range(ATTACK)))
            held += [s for s, _ in res]
            statuses = [st for _, st in res]
            time.sleep(1)
            ok, d = victim_ok(victim)
            rest_st, rest_dt = c1.http_get("/api/cars?limit=1")
        accepted = statuses.count(101)
        time.sleep(1.5)  # evicted transports unwind
        survivors = sum(1 for s, st in res if st == 101 and not c1.is_closed_by_server(s))
        check("A: one account holds at most its per-account share of the edge limit",
              survivors <= ACCOUNT_SHARE,
              f"still_open={survivors} (handshakes accepted={accepted}/{ATTACK}, older ones recycled) "
              f"statuses={sorted(set(statuses))}")
        check("A: victim account still connects (ws + polling)", ok, d)
        check("A: /health + REST stay fast", mon.fail == 0 and max(mon.lat) < 2.0 and rest_st == 200,
              f"{mon.summary()} rest={rest_dt:.2f}s")
        t0 = time.monotonic()
        while time.monotonic() - t0 < DEADLINE + 15:
            time.sleep(2)
            closed = sum(1 for s, st in res if st == 101 and c1.is_closed_by_server(s))
            if closed >= accepted:
                break
        check("A: attacker's orphan websockets are reaped", closed >= accepted,
              f"closed={closed}/{accepted} after {time.monotonic() - t0:.0f}s")
        close_all(held)
        held.clear()

        # ---- B: stalled long-poll handshakes
        with c1.HealthMonitor() as mon:
            with ThreadPoolExecutor(20) as ex:
                polls = list(ex.map(lambda _: open_poll_session_hanging(attacker), range(ATTACK)))
            held += [p for p, _ in polls]
            time.sleep(1)
            ok, d = victim_ok(victim)
            rest_st, _ = c1.http_get("/api/cars?limit=1")
        started = sum(1 for _, s in polls if s == 200)
        check("B: victim connects while attacker's polls are stalled", ok, f"{d}; attacker_sessions={started}")
        check("B: /health + REST stay fast", mon.fail == 0 and max(mon.lat) < 2.0 and rest_st == 200,
              mon.summary())
        close_all(held)
        held.clear()
        time.sleep(DEADLINE + 3)

        # ---- C: expired-token handshakes (F-36 refresh signal) held open
        with c1.HealthMonitor() as mon:
            with ThreadPoolExecutor(30) as ex:
                res = list(ex.map(lambda _: c1.ws_connect(expired)[:2], range(ATTACK)))
            held += [s for s, _ in res]
            ok, d = victim_ok(victim)
        acc = [st for _, st in res].count(101)
        time.sleep(1.5)
        surv = sum(1 for s, st in res if st == 101 and not c1.is_closed_by_server(s))
        check("C: expired-token holds are tightly bounded (restricted bucket)", surv <= 3,
              f"still_open={surv} (handshakes accepted={acc}/{ATTACK})")
        check("C: victim connects during expired-token flood", ok, d)
        check("C: /health stays fast", mon.fail == 0 and max(mon.lat) < 2.0, mon.summary())
        close_all(held)
        held.clear()
        time.sleep(DEADLINE + 3)

        # ---- D: rapid reconnect loop
        with c1.HealthMonitor() as mon:
            def loop(_):
                s, ok_ = raw_ws_connected(attacker)
                if s is not None:
                    s.close()
                return ok_
            with ThreadPoolExecutor(8) as ex:
                oks = list(ex.map(loop, range(200)))
            ok, d = victim_ok(victim)
        seq = 0
        for _ in range(30):  # a well-behaved client reconnecting back to back
            s_, ok_ = raw_ws_connected(attacker)
            if s_ is not None:
                s_.close()
            seq += 1 if ok_ else 0
        check("D: sequential reconnects of one account all succeed (no self-lockout)", seq == 30,
              f"{seq}/30")
        check("D: victim connects after a 200x reconnect loop", ok, f"{d}; attacker_ok={sum(oks)}")
        check("D: /health stays fast", mon.fail == 0 and max(mon.lat) < 2.0, mon.summary())

        # ---- E: many fully connected sockets
        with c1.HealthMonitor() as mon:
            with ThreadPoolExecutor(10) as ex:
                res = list(ex.map(lambda _: raw_ws_connected(attacker), range(ATTACK // 2)))
            held += [s for s, _ in res]
            ok, d = victim_ok(victim)
        check("E: victim connects while attacker holds connected sockets", ok,
              f"{d}; attacker_connected={sum(1 for _, o in res if o)}")
        check("E: /health stays fast", mon.fail == 0 and max(mon.lat) < 2.0, mon.summary())
        close_all(held)
        held.clear()
        time.sleep(3)

        # ---- F: legitimate reconnect while a stale socket lingers
        stale, ok1 = raw_ws_connected(victim)
        fresh, ok2 = raw_ws_connected(victim)
        check("F: same account reconnects while its stale socket lingers", ok1 and ok2,
              f"first={ok1} second={ok2}")
        close_all([stale, fresh])
        st, dt = c1.http_get("/api/cars?limit=1")
        check("REST fallback answers", st == 200, f"{dt:.2f}s")
    finally:
        close_all(held)
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
