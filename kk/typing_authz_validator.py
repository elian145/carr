"""Fast, single-statement validation of a socket typing event on ONE warm database connection.

Why this exists (measured on staging, see ``kk/socketio_handlers.py``):

* Production runs SQLAlchemy with ``NullPool``: every database checkout is a brand-new
  connection (TCP + authentication + a backend process on a small Postgres, 100-290 ms).
* A typing authorization that is older than ``CHAT_TYPING_AUTHZ_TTL_SECONDS`` (15 s, a hard
  upper bound that must not grow) has to be re-validated against the database. A user who
  types every ~8 s therefore needs a database validation for every second typing event, and
  each one used to cost one NEW connection plus ~7 statements (token blocklist, user,
  listing, membership, peer, prior thread, block lookups) -- about 25% more connection
  churn on top of the normal API traffic.

What this does NOT do: it does not extend any cache lifetime, it does not skip any rule and
it does not replace the ORM chain. It answers the SAME questions in ONE ``SELECT`` that runs
on a single dedicated, long-lived connection (opened lazily, per process, serialised by a
lock). The statement only returns facts; the decisions are made here with the very same
helper functions the ORM chain uses (``listing_status_key`` / ``listing_is_public``) and the
same rules, and the result can ONLY ever *allow*:

* anything unusual -- no such listing, a revoked / inactive / cut-off token, no
  membership, no allowed peer, a block, a seller who did not name the buyer, a database
  hiccup, a busy connection -- returns "defer" and the caller runs the original ORM chain,
  which stays the single authority for every denial (and for closing sockets);
* the connection uses ``AUTOCOMMIT``: every statement sees the latest committed data and
  nothing is ever held open inside a transaction.

Redis revocation -- exact semantics (identical to the existing loader
``check_if_token_revoked`` in ``kk/routes/auth.py``):

* The caller first looks up ``bl:jti:<jti>`` in Redis; a hit means revoked and the event is
  deferred to the ORM chain (which denies it).
* An error in that Redis lookup is IGNORED, as the existing loader does. It is NOT a denial
  and this module does NOT claim fail-closed behaviour for revocation. The database is
  still consulted: this statement checks ``token_blacklist`` and the user's ``is_active`` /
  ``tokens_invalid_before`` cutoff, so a token revoked in the database is still refused.
* Limitation (pre-existing, unchanged): a token revoked ONLY in Redis, while Redis is
  unreachable, cannot be detected by either path until Redis is reachable again.
* While Redis is unavailable the typing authorization cache stores nothing (every event is
  re-validated); that is about caching only, not about revocation.

Enable / disable: ``CHAT_TYPING_AUTHZ_FAST_VALIDATOR``
  * ``off`` -- the DEFAULT (also for an unset or unrecognised value): exactly the previous
    behaviour. This path only ever runs after it has been switched on explicitly.
  * ``auto`` -- on for PostgreSQL only (SQLite keeps the plain ORM path).
  * ``on`` -- any file-backed database (used by the parity tests).
"""

from __future__ import annotations

import logging
import os
import threading
import time
from datetime import datetime, timezone
from types import SimpleNamespace

logger = logging.getLogger(__name__)

ENV_MODE = "CHAT_TYPING_AUTHZ_FAST_VALIDATOR"
LOCK_WAIT_SECONDS = 2.0  # waiting longer than this for the shared connection -> defer
RETRY_AFTER_SECONDS = 5.0  # after a failure the ORM path is used for this long
QUICK_FAIL_SECONDS = 2.0  # only a FAST failure (a connection the server already dropped) is retried; a slow one is not
IDLE_RECYCLE_SECONDS = 300.0  # a connection unused this long is replaced before use (NAT / pooler idle cut-offs)
MAX_KEY_LEN = 128  # longer client-supplied ids are not real ids: the ORM chain decides
_INT4_MAX = 2**31 - 1

_ON = {"1", "true", "yes", "on"}
_OFF = {"0", "false", "no", "off"}


class ValidatorUnavailable(Exception):
    """The dedicated connection could not answer (busy, down, error). Never a denial."""


class ValidatorBusy(ValidatorUnavailable):
    """The shared connection stayed busy for ``LOCK_WAIT_SECONDS``."""


_LOCK = threading.Lock()  # serialises use of the single dedicated connection
_STATE_LOCK = threading.Lock()
_STATE: dict = {"engine": None, "key": None, "pid": None, "down_until": 0.0, "stmt": None, "warned": False, "last_used": 0.0}
_COUNTERS = {"queries": 0, "connects": 0, "errors": 0}


def counters() -> dict:
    """Copy of the validator's own counters (queries run, connections opened, errors)."""
    return dict(_COUNTERS)


def reset_for_tests() -> None:
    with _STATE_LOCK:
        eng = _STATE.get("engine")
        _STATE.update(engine=None, key=None, pid=None, down_until=0.0, warned=False, last_used=0.0)
        for k in _COUNTERS:
            _COUNTERS[k] = 0
    if eng is not None:
        try:
            eng.dispose()
        except Exception:  # noqa: BLE001
            pass


def mode() -> str:
    raw = (os.environ.get(ENV_MODE) or "off").strip().lower()
    if raw in _ON:
        return "on"
    if raw == "auto":
        return "auto"
    return "off"  # unset, explicit off, or anything unrecognised: the previous behaviour


def enabled(app_url) -> bool:
    """Is the fast validator usable for the application database ``app_url``?"""
    m = mode()
    if m == "off":
        return False
    try:
        backend = app_url.get_backend_name()
        database = app_url.database
    except Exception:  # noqa: BLE001
        return False
    if backend == "sqlite":
        if database in (None, "", ":memory:"):
            return False  # a second connection would see a different (empty) database
        return m == "on"
    if backend == "postgresql":
        return True
    return m == "on"


def _create_engine(url):
    import sqlalchemy as sa
    from sqlalchemy.pool import StaticPool

    backend = url.get_backend_name()
    kwargs: dict = {"poolclass": StaticPool}
    if backend == "postgresql":
        connect_args = {
            "connect_timeout": 5,
            "keepalives": 1,
            "keepalives_idle": 30,
            "keepalives_interval": 10,
            "keepalives_count": 3,
            "tcp_user_timeout": 5000,  # a black-holed connection errors out instead of hanging a request thread
        }
        if url.get_driver_name() == "psycopg":
            connect_args["prepare_threshold"] = None  # no server-side prepared statements (pgbouncer-safe)
        kwargs["connect_args"] = connect_args
        kwargs["isolation_level"] = "AUTOCOMMIT"
    elif backend == "sqlite":
        kwargs["connect_args"] = {"check_same_thread": False, "timeout": 5}
        kwargs["isolation_level"] = "AUTOCOMMIT"
    eng = sa.create_engine(url, **kwargs)

    @sa.event.listens_for(eng, "connect")
    def _count_connect(dbapi_conn, record):  # noqa: ARG001
        _COUNTERS["connects"] += 1

    return eng


def _engine(app_url):
    key = app_url.render_as_string(hide_password=False)
    pid = os.getpid()
    with _STATE_LOCK:
        if _STATE["engine"] is not None and _STATE["key"] == key and _STATE["pid"] == pid:
            return _STATE["engine"]
        # after a fork the parent's connection must not be touched: drop the reference, never dispose it
        old = _STATE["engine"] if _STATE["pid"] == pid else None
        _STATE.update(engine=None, key=None, pid=None)
    if old is not None:
        try:
            old.dispose()
        except Exception:  # noqa: BLE001
            pass
    eng = _create_engine(app_url)
    with _STATE_LOCK:
        _STATE.update(engine=eng, key=key, pid=pid)
    return eng


def _drop_engine() -> None:
    with _STATE_LOCK:
        eng = _STATE["engine"]
        _STATE.update(engine=None, key=None, pid=None)
    if eng is not None:
        try:
            eng.dispose()
        except Exception:  # noqa: BLE001
            pass


def _statement():
    """The one SELECT. Built once per process (it needs the models)."""
    stmt = _STATE.get("stmt")
    if stmt is not None:
        return stmt
    import sqlalchemy as sa

    from .models import BlockedUser, Car, Message, TokenBlacklist, User

    U, C, M, B, T = User.__table__, Car.__table__, Message.__table__, BlockedUser.__table__, TokenBlacklist.__table__
    me, seller, named, recv = U.alias("me"), U.alias("seller"), U.alias("named"), U.alias("recv")
    p_me = sa.bindparam("me_id", type_=sa.Integer)
    p_car = sa.bindparam("car_raw", type_=sa.String)
    p_car_int = sa.bindparam("car_int", type_=sa.Integer)  # NULL when the id is not numeric: matches nothing
    p_peer = sa.bindparam("peer_raw", type_=sa.String)  # NULL when the client named nobody: matches nothing
    p_jti = sa.bindparam("jti", type_=sa.String)

    # resolve_car_for_chat: public_id first, the numeric id only as a fallback
    car = (
        sa.select(C.c.id, C.c.public_id, C.c.seller_id, C.c.status)
        .where(sa.or_(C.c.public_id == p_car, C.c.id == p_car_int))
        .order_by(sa.case((C.c.public_id == p_car, 0), else_=1))
        .limit(1)
        .cte("car_pick")
    )
    # resolve_allowed_chat_receiver: the named user, else (not the seller) the listing's seller
    recv_id = sa.func.coalesce(named.c.id, sa.case((car.c.seller_id != me.c.id, car.c.seller_id), else_=None))
    member = sa.exists().where(M.c.car_id == car.c.id).where(sa.or_(M.c.sender_id == me.c.id, M.c.receiver_id == me.c.id))
    prior = (
        sa.exists()
        .where(M.c.car_id == car.c.id)
        .where(
            sa.or_(
                sa.and_(M.c.sender_id == me.c.id, M.c.receiver_id == recv_id),
                sa.and_(M.c.sender_id == recv_id, M.c.receiver_id == me.c.id),
            )
        )
    )
    blocked = sa.exists().where(
        sa.or_(
            sa.and_(B.c.blocker_id == me.c.id, B.c.blocked_id == recv_id),
            sa.and_(B.c.blocker_id == recv_id, B.c.blocked_id == me.c.id),
        )
    )
    revoked = sa.exists().where(T.c.jti == p_jti)
    stmt = (
        sa.select(
            me.c.id.label("me_id"),
            me.c.public_id.label("me_public_id"),
            me.c.is_active.label("me_active"),
            me.c.first_name.label("me_first_name"),
            me.c.last_name.label("me_last_name"),
            me.c.tokens_invalid_before.label("me_cutoff"),
            car.c.id.label("car_id"),
            car.c.public_id.label("car_public_id"),
            car.c.seller_id.label("car_seller_id"),
            car.c.status.label("car_status"),
            seller.c.id.label("seller_uid"),
            seller.c.is_active.label("seller_active"),
            named.c.id.label("named_id"),
            recv.c.id.label("recv_id"),
            recv.c.public_id.label("recv_public_id"),
            member.label("is_member"),
            prior.label("has_prior"),
            blocked.label("is_blocked"),
            revoked.label("jti_revoked"),
        )
        .select_from(
            me.outerjoin(car, sa.true())
            .outerjoin(seller, seller.c.id == car.c.seller_id)
            .outerjoin(named, named.c.public_id == p_peer)
            .outerjoin(recv, recv.c.id == recv_id)
        )
        .where(me.c.id == p_me)
    )
    _STATE["stmt"] = stmt
    return stmt


def _fetch(app_url, params: dict):
    """Run the statement on the dedicated connection. Raises ``ValidatorUnavailable``."""
    if time.monotonic() < _STATE["down_until"]:
        raise ValidatorUnavailable("circuit open")
    if not _LOCK.acquire(timeout=LOCK_WAIT_SECONDS):
        raise ValidatorBusy("dedicated connection busy")
    try:
        last: BaseException | None = None
        if _STATE["last_used"] and time.monotonic() - _STATE["last_used"] > IDLE_RECYCLE_SECONDS:
            _drop_engine()  # long idle: do not trust it (a silently dead connection would cost a timeout)
        for _attempt in (1, 2):  # one retry on a fresh connection (idle connections do get dropped)
            started = time.monotonic()
            try:
                eng = _engine(app_url)
                with eng.connect() as conn:
                    _COUNTERS["queries"] += 1
                    row = conn.execute(_statement(), params).mappings().first()
                _STATE["last_used"] = time.monotonic()
                return row
            except Exception as exc:  # noqa: BLE001
                last = exc
                _COUNTERS["errors"] += 1
                _drop_engine()
                if time.monotonic() - started > QUICK_FAIL_SECONDS:
                    break  # a slow failure is a sick network/database, not a stale connection: do not wait again
        _STATE["down_until"] = time.monotonic() + RETRY_AFTER_SECONDS
        if not _STATE["warned"]:
            _STATE["warned"] = True
            logger.warning("typing authz: fast validator unavailable (%s); using the ORM chain", type(last).__name__)
        raise ValidatorUnavailable(type(last).__name__)
    finally:
        _LOCK.release()


def _shim_status(status):
    return SimpleNamespace(status=status)


def decide(row, *, user_id: int, user_public_id: str, claims: dict, peer_raw: str):
    """Apply the authorization rules to the facts. Returns ``(verdict, reason)``; ``verdict`` is
    ``None`` (defer to the ORM chain, which decides and acts on every denial) unless EVERY rule allows."""
    from .listing_visibility import listing_is_public, listing_status_key

    if row is None or row["me_id"] is None:
        return None, "no_user"
    # the socket is bound to exactly this account (same check as _socket_current_user)
    if row["me_id"] != user_id or row["me_public_id"] != user_public_id or str(claims.get("sub")) != user_public_id:
        return None, "identity"
    if not row["me_active"]:
        return None, "inactive"
    if row["jti_revoked"]:
        return None, "revoked"
    cutoff = row["me_cutoff"]
    if cutoff is not None:  # H-01/H-02: tokens issued before the cutoff are revoked
        iat = claims.get("iat")
        if iat is not None:
            issued_at = datetime.fromtimestamp(int(iat), tz=timezone.utc).replace(tzinfo=None)
            if issued_at < cutoff:
                return None, "cutoff"
    if row["car_id"] is None:
        return None, "no_car"
    if row["car_public_id"] is None:
        return None, "no_public_id"  # legacy listing without a public id: the ORM chain decides
    if listing_status_key(_shim_status(row["car_status"])) == "revision":  # not_a_working_copy
        return None, "working_copy"
    me_id, seller_id = row["me_id"], row["car_seller_id"]
    if seller_id != me_id and not row["is_member"]:  # user_can_access_chat_room
        return None, "no_membership"
    if seller_id == me_id and row["named_id"] is None:
        return None, "dynamic_peer"  # "the only counterpart" is resolved dynamically: ORM chain
    recv_id = row["recv_id"]
    if recv_id is None or recv_id == me_id or row["recv_public_id"] is None:
        return None, "no_peer"
    # chat_receiver_allowed
    allowed = False
    if recv_id == seller_id and me_id != seller_id:
        # ``car.seller`` is the seller's row (None when the listing has no seller); a NULL is_active is NOT active
        seller = SimpleNamespace(is_active=row["seller_active"]) if row["seller_uid"] is not None else None
        allowed = listing_is_public(SimpleNamespace(status=row["car_status"], seller=seller))
    if not allowed:
        allowed = bool(row["has_prior"])
    if not allowed:
        return None, "peer_not_allowed"
    if row["is_blocked"]:  # chat_users_blocked, either direction
        return None, "blocked"
    return (
        SimpleNamespace(
            me=SimpleNamespace(id=me_id, public_id=row["me_public_id"], first_name=row["me_first_name"], last_name=row["me_last_name"]),
            car=SimpleNamespace(id=row["car_id"], public_id=row["car_public_id"], seller_id=seller_id),
            peer=SimpleNamespace(id=recv_id, public_id=row["recv_public_id"]),
        ),
        "allow",
    )


def validate(app_url, *, user_id: int, user_public_id: str, claims: dict, car_raw: str, peer_raw: str):
    """One database round trip. ``(verdict | None, reason)``; raises ``ValidatorUnavailable`` when the
    dedicated connection cannot be used (the caller then runs the ORM chain)."""
    # Client-controlled strings: anything the database could reject (NUL bytes, absurd lengths, an
    # integer outside the column's range) must never reach it as a statement error -- that would
    # look like a broken connection and could be used to switch the fast path off for everyone.
    if len(car_raw) > MAX_KEY_LEN or len(peer_raw or "") > MAX_KEY_LEN or "\x00" in car_raw or "\x00" in (peer_raw or ""):
        return None, "bad_input"
    car_int = None
    if car_raw.isascii() and car_raw.isdigit():
        n = int(car_raw)
        if 0 < n <= _INT4_MAX:  # car.id is a 32-bit integer; a larger number matches no row
            car_int = n
    params = {
        "me_id": int(user_id),
        "car_raw": car_raw,
        "car_int": car_int,
        "peer_raw": peer_raw or None,
        "jti": str(claims.get("jti") or "") or None,  # NULL matches no row (the ORM chain skips an empty jti)
    }
    row = _fetch(app_url, params)
    return decide(row, user_id=user_id, user_public_id=user_public_id, claims=claims, peer_raw=peer_raw)
