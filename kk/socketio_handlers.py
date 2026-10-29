from __future__ import annotations

import logging
import os
import threading
import time
from collections import deque

logger = logging.getLogger(__name__)

from flask import request
from flask_jwt_extended import decode_token
from flask_jwt_extended.exceptions import RevokedTokenError
from flask_jwt_extended.internal_utils import verify_token_not_blocklisted
from flask_socketio import ConnectionRefusedError  # socketio.exceptions one, NOT the builtin
from flask_socketio import disconnect as sio_disconnect
from flask_socketio import emit, join_room, leave_room

from .auth import phone_verification_error_payload
from .localization import get_background_locale, translate
from .chat_realtime import (
    emit_message_to_participants,
    mark_messages_read_for_viewer,
    resolve_allowed_chat_receiver,
    resolve_car_for_chat,
    resolve_conversation_peer,
    room_for_conversation,
    user_can_access_chat_room,
)
from .models import Message, Notification, User, db
from .push import send_push
from .security import validate_input_sanitization
from .time_utils import utcnow


def _allow_socket_query_token() -> bool:
    """Query-string JWTs are for local/test clients only (S-06)."""
    env = (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "").strip().lower()
    if env in ("development", "testing", "test"):
        return True
    return (os.environ.get("ALLOW_SOCKET_QUERY_TOKEN") or "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )


# ---------------------------------------------------------------------------
# F-36: socket authentication lifetime.
#
# A Socket.IO connection is authenticated ONCE (at connect) with an access
# token that expires (default 30 min). Previously:
#   * a (re)connect that presented an expired/invalid token was silently
#     accepted as an anonymous guest ("authenticated": false) and the client
#     could not tell; and
#   * a connection that was open when its token expired kept receiving that
#     account's private events for as long as the transport stayed up, while
#     every client event was refused with a bare "Unauthorized".
# Now an invalid/expired/revoked token REFUSES the connection with an explicit
# reason, every live connection is bound to the exact account (and expiry) it
# authenticated with, the token is re-validated (expiry + revocation) on every
# event, and a connection is torn down -- with an explicit `auth_expired` event
# so the client can refresh its token and reconnect -- the moment its token
# expires.
# ---------------------------------------------------------------------------
_SOCKET_AUTH: dict[str, dict] = {}
_SOCKET_AUTH_LOCK = threading.Lock()
_EXPIRY_POLL_SECONDS = 30.0


def _now() -> float:
    """Wall clock used for every socket-token expiry decision (patched in tests)."""
    return time.time()


def _bound_socket(sid: str | None) -> dict | None:
    if not sid:
        return None
    with _SOCKET_AUTH_LOCK:
        return _SOCKET_AUTH.get(sid)


def _extract_raw_token() -> tuple[str | None, str | None]:
    """Return ``(raw_token, source)``; ``raw_token`` is ``None`` for a guest."""
    header = (request.headers.get("Authorization") or "").strip()
    if header:
        parts = header.split(None, 1)
        if len(parts) == 2 and parts[0].lower() == "bearer" and parts[1].strip():
            return parts[1].strip(), "header"
        return "", "header"  # present but malformed -> invalid, not guest
    raw = (request.args.get("token") or "").strip()
    if raw:
        if not _allow_socket_query_token():
            logger.warning(
                "Rejected Socket.IO connect with query-string JWT "
                "(use Authorization header; set ALLOW_SOCKET_QUERY_TOKEN=1 only for controlled tests)"
            )
            return None, "query_blocked"
        return raw, "query"
    return None, None


def _verify_access_token(raw: str | None) -> tuple[dict | None, str | None]:
    """Validate an access token for a socket. Returns ``(claims, error_code)``.

    ``error_code`` is ``token_expired`` / ``token_revoked`` / ``invalid_token``.
    Expiry is judged by [_now] so a long-lived connection is checked against
    the same clock the expiry timer uses.
    """
    if not raw:
        return None, "invalid_token"
    try:
        claims = decode_token(raw, allow_expired=True)
    except Exception:
        return None, "invalid_token"
    if claims.get("type") not in (None, "access"):
        return None, "invalid_token"
    exp = claims.get("exp")
    if not isinstance(exp, (int, float)):
        return None, "invalid_token"
    if float(exp) <= _now():
        return None, "token_expired"
    try:
        verify_token_not_blocklisted({}, claims)
    except RevokedTokenError:
        return None, "token_revoked"
    except Exception:
        return None, "invalid_token"  # fail closed
    return claims, None


def _load_active_user(identity) -> User | None:
    if not identity:
        return None
    try:
        u = User.query.filter_by(public_id=str(identity)).first()
        if not u or not u.is_active:
            return None
        return u
    except Exception:
        return None


def _socket_current_user(*, optional: bool = False) -> User | None:
    """
    Resolve the current user for Socket.IO events.

    A connected socket is bound (at connect) to ONE account and ONE token. That
    token is re-validated (expiry, revocation, account still active) on every
    event; a connection whose token has expired is closed here as well as by
    the expiry timer.

    Token sources accepted at connect:
    - Authorization: Bearer <access_jwt> header (preferred; used by Flutter)
    - `?token=<access_jwt>` query param only in development/testing, or when
      ALLOW_SOCKET_QUERY_TOKEN=1 is explicitly set (never implied in production)
    """
    sid = getattr(request, "sid", None)
    rec = _bound_socket(sid)
    if rec is not None:
        claims, err = _verify_access_token(rec["token"])
        user = _load_active_user(claims.get("sub")) if claims else None
        if err is not None or user is None or user.public_id != rec["user_public_id"]:
            _expire_socket(sid, err or "invalid_token")
            return None
        return user

    # Not bound (guest / never authenticated): only a valid token presented on
    # this very request can identify anyone.
    raw, _src = _extract_raw_token()
    if not raw:
        return None
    claims, err = _verify_access_token(raw)
    if err is not None:
        return None
    return _load_active_user(claims.get("sub"))


def _bind_socket(sid: str, user: User, claims: dict, raw: str) -> None:
    with _SOCKET_AUTH_LOCK:
        _SOCKET_AUTH[sid] = {
            "user_public_id": user.public_id,
            "exp": float(claims["exp"]),
            "token": raw,
            # Used ONLY to evict the typing-authorization cache below (never
            # to authorize anything): the internal id, and the token's jti.
            "user_id": user.id,
            "jti": str(claims.get("jti") or ""),
            # Typing-event fast path state. It lives INSIDE the binding record,
            # so it disappears with the socket (disconnect, token expiry,
            # account switch / reconnect = a new sid = an empty cache).
            "authz": {},
            "typing_state": {},
            "typing_times": deque(),
        }


def _unbind_socket(sid: str | None) -> dict | None:
    if not sid:
        return None
    with _SOCKET_AUTH_LOCK:
        return _SOCKET_AUTH.pop(sid, None)


def _expire_socket(sid: str | None, reason: str) -> bool:
    """Tell the client its authentication ended and close the connection."""
    rec = _unbind_socket(sid)
    if rec is None:
        return False
    try:
        emit("auth_expired", {"code": reason}, to=sid)
    except Exception:
        logger.debug("auth_expired emit failed", exc_info=True)
    try:
        sio_disconnect(sid=sid, namespace="/")
    except Exception:
        logger.debug("socket disconnect failed", exc_info=True)
    return True


def enforce_socket_expiry(sid: str) -> bool:
    """Close ``sid`` if the token it authenticated with has expired.

    Returns True when the socket was closed. Safe to call from a background task
    (no request context is needed). Exposed for the expiry timer and for tests.
    """
    rec = _bound_socket(sid)
    if rec is None:
        return False
    if rec["exp"] > _now():
        return False
    if _unbind_socket(sid) is None:
        return False
    from .extensions import socketio as _sio

    try:
        _sio.emit("auth_expired", {"code": "token_expired"}, to=sid)
    except Exception:
        logger.debug("auth_expired emit failed", exc_info=True)
    try:
        _sio.server.disconnect(sid, namespace="/")
    except Exception:
        logger.debug("socket disconnect failed", exc_info=True)
    return True


def _watch_socket_expiry(socketio, sid: str) -> None:
    """Background timer: close the socket as soon as its token expires."""
    while True:
        rec = _bound_socket(sid)
        if rec is None:
            return
        remaining = rec["exp"] - _now()
        if remaining <= 0:
            enforce_socket_expiry(sid)
            return
        socketio.sleep(min(remaining + 0.25, _EXPIRY_POLL_SECONDS))


# ---------------------------------------------------------------------------
# Typing events: authorize a conversation once, not on every keystroke burst.
#
# Measured on staging (20 sockets, NullPool, ~100-290 ms per new DB connection):
# every ``typing_start`` / ``typing_stop`` re-ran the full authorization chain
# (token blocklist + user + listing + membership + peer + block lookups: ~8 SQL
# statements on a freshly opened DB connection) and pushed /api/cars p95 from
# ~0.6 s to ~3.1 s.
#
# A typing indicator is ephemeral and carries no message content, so after the
# FIRST full validation of a (listing, peer) conversation for a socket, the
# result is reused for a short, bounded time:
#
#   * the cache lives inside the socket's own binding record (``_SOCKET_AUTH``),
#     so it dies with the socket: disconnect, token expiry, reconnect and
#     account switching (a new token = a new socket) always start empty;
#   * it only ever holds results that the full server-side check produced --
#     never a client-supplied user, room or conversation;
#   * every event still checks (in memory) that the socket is bound and that
#     its token has not expired;
#   * entries expire after ``CHAT_TYPING_AUTHZ_TTL_SECONDS`` (default 15 s) and
#     are evicted at once, in this process, when a committed change could
#     remove the permission: a block / unblock, a logout or token revocation,
#     a deactivated / deleted account, a password change (token cutoff), or a
#     deactivated / re-owned / deleted listing. The TTL is the backstop for
#     other workers and for bulk SQL updates that bypass the ORM;
#   * negative results are never cached, and a per-socket rate limit applies
#     BEFORE any database work, so spam cannot be used to hit the database;
#   * duplicate states are dropped (a second ``typing_start`` shortly after one
#     was relayed, or a ``typing_stop`` when stopped is already known);
#   * ``send_message`` / ``join_chat`` keep their full per-event validation.
#
# ``CHAT_TYPING_AUTHZ_TTL_SECONDS=0`` restores the previous behaviour exactly
# (full validation per event, no de-duplication, no rate limit).
# ---------------------------------------------------------------------------
_TYPING_AUTHZ_TTL_DEFAULT = 15.0
_TYPING_AUTHZ_TTL_MAX = 120.0
_TYPING_REFRESH_SECONDS = 5.0  # a repeated typing_start is relayed at most this often
_TYPING_RATE_MAX = 30  # typing events per socket ...
_TYPING_RATE_WINDOW = 10.0  # ... per this many seconds, before any DB work
_TYPING_CACHE_MAX_ENTRIES = 16
_TYPING_STATE_MAX_ENTRIES = 64
_TYPING_KEY_MAX_LEN = 128

_EVICT_GEN = 0  # bumped on every eviction (see _remember_authz)


def _mono() -> float:
    """Monotonic clock for cache TTLs / rate limits (patched in tests)."""
    return time.monotonic()


def _typing_authz_ttl() -> float:
    raw = (os.environ.get("CHAT_TYPING_AUTHZ_TTL_SECONDS") or "").strip()
    if not raw:
        return _TYPING_AUTHZ_TTL_DEFAULT
    try:
        val = float(raw)
    except ValueError:
        return _TYPING_AUTHZ_TTL_DEFAULT
    if val != val or val <= 0:  # NaN, zero or negative: feature off
        return 0.0
    return min(val, _TYPING_AUTHZ_TTL_MAX)


def _evict_generation() -> int:
    return _EVICT_GEN


def _typing_fast_path(sid, car_raw: str, peer_raw: str, typing: bool, ttl: float):
    """In-memory decision for a typing event; NO database access.

    Returns ``("emit", entry)`` (relay it), ``("drop", None)`` (rate limited or
    duplicate) or ``("miss", None)`` (run the full validation).
    """
    if not sid:
        return "miss", None
    now = _mono()
    with _SOCKET_AUTH_LOCK:
        rec = _SOCKET_AUTH.get(sid)
        if rec is None or rec["exp"] <= _now():
            # Unbound / guest, or expired: the full path decides (and closes).
            return "miss", None
        times = rec["typing_times"]
        while times and now - times[0] > _TYPING_RATE_WINDOW:
            times.popleft()
        if len(times) >= _TYPING_RATE_MAX:
            return "drop", None
        times.append(now)
        cache = rec["authz"]
        entry = cache.get((car_raw, peer_raw))
        if entry is None:
            return "miss", None
        if (
            now - entry["at"] > ttl
            or entry["me"] != rec["user_public_id"]
            or entry["me_id"] != rec["user_id"]
        ):
            cache.pop((car_raw, peer_raw), None)
            return "miss", None
        state = rec["typing_state"].get(entry["state_key"])
        if state is not None:
            last, at = state
            if typing and last is True and now - at < _TYPING_REFRESH_SECONDS:
                return "drop", None
            if (not typing) and last is False:
                return "drop", None
        _set_typing_state_locked(rec, entry["state_key"], typing, now)
        return "emit", dict(entry)


def _set_typing_state_locked(rec: dict, state_key, typing: bool, now: float) -> None:
    states = rec["typing_state"]
    states.pop(state_key, None)
    states[state_key] = (typing, now)
    while len(states) > _TYPING_STATE_MAX_ENTRIES:
        states.pop(next(iter(states)))


def _remember_authz(sid, me, car, peer, room, raw_key, gen: int, ttl: float, typing=None) -> None:
    """Store the result of a FULL authorization (never client input as such)."""
    if ttl <= 0 or not sid or me is None or car is None or peer is None:
        return
    car_raw, peer_raw = raw_key
    if len(car_raw) > _TYPING_KEY_MAX_LEN or len(peer_raw) > _TYPING_KEY_MAX_LEN:
        return
    if not peer_raw and car.seller_id == me.id:
        # A seller who did not name the buyer is resolved dynamically ("the
        # only counterpart"); it must be re-resolved every time.
        return
    now = _mono()
    entry = {
        "at": now,
        "me": me.public_id,
        "me_id": me.id,
        "car_id": car.id,
        "car_public_id": car.public_id,
        "peer_id": peer.id,
        "peer_public_id": peer.public_id,
        "room": room,
        "user_name": f"{me.first_name} {me.last_name}".strip(),
        "state_key": (car.public_id, peer.public_id),
    }
    with _SOCKET_AUTH_LOCK:
        if gen != _EVICT_GEN:
            return  # something changed while we were validating: do not cache
        rec = _SOCKET_AUTH.get(sid)
        if rec is None or rec["user_public_id"] != me.public_id or rec["user_id"] != me.id:
            return
        cache = rec["authz"]
        cache.pop(raw_key, None)
        while len(cache) >= _TYPING_CACHE_MAX_ENTRIES:
            cache.pop(next(iter(cache)))
        cache[raw_key] = entry
        if typing is not None:
            _set_typing_state_locked(rec, entry["state_key"], typing, now)


def evict_typing_authz(*, user_ids=(), car_ids=(), jtis=()) -> int:
    """Drop cached typing authorizations affected by a committed change.

    ``user_ids`` evicts every socket of those users and every cached
    conversation whose peer is one of them; ``car_ids`` evicts the cached
    conversations of those listings; ``jtis`` evicts the sockets that
    authenticated with those tokens. Returns the number of sockets touched.
    """
    global _EVICT_GEN
    users, cars, tokens = set(user_ids), set(car_ids), set(jtis)
    touched = 0
    with _SOCKET_AUTH_LOCK:
        _EVICT_GEN += 1
        for rec in _SOCKET_AUTH.values():
            cache = rec.get("authz")
            if not cache:
                continue
            if rec.get("user_id") in users or (rec.get("jti") and rec["jti"] in tokens):
                cache.clear()
                touched += 1
                continue
            stale = [
                k
                for k, e in cache.items()
                if e["peer_id"] in users or e["car_id"] in cars
            ]
            for k in stale:
                cache.pop(k, None)
            touched += 1 if stale else 0
    return touched


_AUTHZ_EVICT_KEY = "_kk_typing_authz_evict"
_AUTHZ_LISTENERS_INSTALLED = False


def _install_authz_invalidation_listeners() -> None:
    """Evict cached typing authorizations when a commit could revoke them.

    Collected per session while it flushes and applied only AFTER the commit
    (a rolled-back change evicts nothing; an eviction can never run before the
    change it reacts to is visible to other threads).
    """
    global _AUTHZ_LISTENERS_INSTALLED
    if _AUTHZ_LISTENERS_INSTALLED:
        return
    _AUTHZ_LISTENERS_INSTALLED = True

    from sqlalchemy import event, inspect as sa_inspect
    from sqlalchemy.orm import Session, object_session

    from .models import BlockedUser, Car, TokenBlacklist

    def _pending(target) -> dict | None:
        sess = object_session(target)
        if sess is None:
            return None
        return sess.info.setdefault(_AUTHZ_EVICT_KEY, {"u": set(), "c": set(), "j": set()})

    def _changed(target, *names) -> bool:
        state = sa_inspect(target)
        return any(state.attrs[n].history.has_changes() for n in names)

    def _add(target, kind, value) -> None:
        pend = _pending(target)
        if pend is not None and value is not None and value != "":
            pend[kind].add(value)

    def block_changed(_mapper, _conn, target):
        _add(target, "u", target.blocker_id)
        _add(target, "u", target.blocked_id)

    def user_changed(_mapper, _conn, target):
        if _changed(target, "is_active", "tokens_invalid_before", "public_id"):
            _add(target, "u", target.id)

    def user_deleted(_mapper, _conn, target):
        _add(target, "u", target.id)

    def token_revoked(_mapper, _conn, target):
        _add(target, "u", target.user_id)
        _add(target, "j", target.jti)

    def car_changed(_mapper, _conn, target):
        if _changed(target, "is_active", "status", "seller_id"):
            _add(target, "c", target.id)

    def car_deleted(_mapper, _conn, target):
        _add(target, "c", target.id)

    def message_deleted(_mapper, _conn, target):
        _add(target, "c", target.car_id)

    event.listen(BlockedUser, "after_insert", block_changed)
    event.listen(BlockedUser, "after_delete", block_changed)
    event.listen(User, "after_update", user_changed)
    event.listen(User, "after_delete", user_deleted)
    event.listen(TokenBlacklist, "after_insert", token_revoked)
    event.listen(Car, "after_update", car_changed)
    event.listen(Car, "after_delete", car_deleted)
    event.listen(Message, "after_delete", message_deleted)

    @event.listens_for(Session, "after_commit")
    def _apply_evictions(session):
        pend = session.info.pop(_AUTHZ_EVICT_KEY, None)
        if pend and (pend["u"] or pend["c"] or pend["j"]):
            evict_typing_authz(user_ids=pend["u"], car_ids=pend["c"], jtis=pend["j"])

    @event.listens_for(Session, "after_rollback")
    def _discard_evictions(session):
        session.info.pop(_AUTHZ_EVICT_KEY, None)


def register_socketio_handlers(socketio) -> None:
    """
    Register Socket.IO handlers on the given SocketIO instance.

    create_app() can be called multiple times in tests; re-register handlers when
    SocketIO is bound to a new Flask app instance.
    """
    app = getattr(socketio, "app", None)
    app_id = id(app) if app is not None else None
    if app_id is not None and getattr(socketio, "_kk_handlers_app_id", None) == app_id:
        return
    if app_id is not None:
        setattr(socketio, "_kk_handlers_app_id", app_id)
    _install_authz_invalidation_listeners()

    @socketio.on("connect")
    def _connect(auth=None):  # type: ignore[no-redef]
        """
        Accept an anonymous connection (no credentials at all). A connection
        that PRESENTS a token is accepted only when that token is a valid,
        unexpired, unrevoked access token of an active account (F-36): an
        expired / invalid token is refused with an explicit reason so the client
        can refresh and reconnect, rather than being silently downgraded to a
        guest. Authenticated sockets join a per-user room and are bound to that
        account until the token expires.
        """
        raw, src = _extract_raw_token()
        if raw is None:
            if src == "query_blocked":
                # A token WAS presented, through a source we forbid (query
                # string). Refuse it explicitly instead of silently treating
                # the client as a guest; no credentials at all stay a guest.
                logger.info("Socket.IO connect refused: token_in_query")
                raise ConnectionRefusedError("token_in_query")
            emit("connected", {"authenticated": False, "user_id": None})
            return
        claims, err = _verify_access_token(raw)
        user = _load_active_user(claims.get("sub")) if claims else None
        if err is not None or user is None:
            code = err or "invalid_token"
            logger.info("Socket.IO connect refused: %s", code)
            raise ConnectionRefusedError(code)
        sid = request.sid
        _bind_socket(sid, user, claims, raw)
        join_room(f"user:{user.public_id}")
        emit(
            "connected",
            {
                "authenticated": True,
                "user_id": user.public_id,
                "expires_at": int(claims["exp"]),
            },
        )
        socketio.start_background_task(_watch_socket_expiry, socketio, sid)

    @socketio.on("disconnect")
    def _disconnect(*_args):  # type: ignore[no-redef]
        _unbind_socket(getattr(request, "sid", None))
        return

    @socketio.on("join_chat")
    def _join_chat(payload):  # type: ignore[no-redef]
        gen = _evict_generation()
        me = _socket_current_user(optional=False)
        if not me:
            emit("error", {"message": "Unauthorized"})
            return

        data = validate_input_sanitization(payload or {})
        car_id_raw = str(data.get("car_id") or "").strip()
        peer_public = str(data.get("peer_id") or data.get("receiver_id") or "").strip()
        if not car_id_raw:
            emit("error", {"message": "car_id required"})
            return

        car = resolve_car_for_chat(car_id_raw)
        if not car or not car.is_active:
            emit("error", {"message": "Listing not found"})
            return

        if not user_can_access_chat_room(me, car):
            # Soft denial: avoid noisy client snackbars for first-time buyers who
            # open a conversation before their first message. They still receive
            # realtime replies via their personal user room after sending.
            logger.info(
                "join_chat denied for user %s on car %s (not a participant)",
                me.public_id,
                car.public_id,
            )
            emit(
                "joined_chat",
                {
                    "ok": False,
                    "code": "chat_access_denied",
                    "car_id": car.public_id,
                    "room": None,
                },
            )
            return

        # F-25/F-05: a conversation room belongs to exactly ONE (listing,
        # seller, buyer) conversation; the other participant must be named
        # unless it is unambiguous (a buyer's counterpart is the seller).
        peer, peer_code = resolve_conversation_peer(me, car, peer_public)
        if peer is None:
            emit(
                "joined_chat",
                {
                    "ok": False,
                    "code": peer_code or "peer_not_allowed",
                    "car_id": car.public_id,
                    "room": None,
                },
            )
            return

        room = room_for_conversation(car.public_id, me.public_id, peer.public_id)
        join_room(room)
        # The full check above authorized this conversation: let this socket's
        # typing events reuse it for a short, bounded time.
        _remember_authz(
            getattr(request, "sid", None),
            me,
            car,
            peer,
            room,
            (car_id_raw, peer_public),
            gen,
            _typing_authz_ttl(),
        )
        emit(
            "joined_chat",
            {
                "ok": True,
                "car_id": car.public_id,
                "room": room,
                "peer_id": peer.public_id,
            },
        )
        # Opening the conversation marks THIS peer's inbound messages read.
        try:
            mark_messages_read_for_viewer(car, me, peer=peer)
        except Exception:
            db.session.rollback()
            logger.exception("join_chat mark-read failed for car %s", car.public_id)

    @socketio.on("leave_chat")
    def _leave_chat(payload):  # type: ignore[no-redef]
        _socket_current_user(optional=True)
        data = validate_input_sanitization(payload or {})
        room = str(data.get("room") or "").strip()
        if room:
            leave_room(room)
        emit("left_chat", {"room": room})

    def _emit_typing(payload, typing: bool) -> None:
        """F-25: a typing indicator goes ONLY to the other participant of the
        (listing, seller, buyer) conversation it belongs to -- never to every
        socket that joined the listing."""
        sid = getattr(request, "sid", None)
        ttl = _typing_authz_ttl()
        data = validate_input_sanitization(payload or {})
        car_id_raw = str(data.get("car_id") or "").strip()
        peer_public = str(data.get("peer_id") or data.get("receiver_id") or "").strip()

        if ttl > 0 and car_id_raw:
            # Fast path: no database access at all (see the block comment above
            # _typing_fast_path). A miss -- or anything unusual -- falls through
            # to the full validation below, which is the source of truth.
            action, hit = _typing_fast_path(sid, car_id_raw, peer_public, typing, ttl)
            if action == "drop":
                return
            if action == "emit":
                emit(
                    "typing",
                    {
                        "user_id": hit["me"],
                        "user_name": hit["user_name"],
                        "car_id": hit["car_public_id"],
                        "peer_id": hit["peer_public_id"],
                        "typing": typing,
                    },
                    room=hit["room"],
                    include_self=False,
                )
                return

        gen = _evict_generation()
        me = _socket_current_user(optional=False)
        if not me:
            return
        if not car_id_raw:
            return
        car = resolve_car_for_chat(car_id_raw)
        if not car or not user_can_access_chat_room(me, car):
            return
        peer, _code = resolve_conversation_peer(me, car, peer_public)
        if peer is None:
            return
        room = room_for_conversation(car.public_id, me.public_id, peer.public_id)
        _remember_authz(
            sid, me, car, peer, room, (car_id_raw, peer_public), gen, ttl, typing=typing
        )
        emit(
            "typing",
            {
                "user_id": me.public_id,
                "user_name": f"{me.first_name} {me.last_name}".strip(),
                "car_id": car.public_id,
                "peer_id": peer.public_id,
                "typing": typing,
            },
            room=room,
            include_self=False,
        )

    @socketio.on("typing_start")
    def _typing_start(payload):  # type: ignore[no-redef]
        _emit_typing(payload, True)

    @socketio.on("typing_stop")
    def _typing_stop(payload):  # type: ignore[no-redef]
        _emit_typing(payload, False)

    @socketio.on("send_message")
    def _send_message(payload):  # type: ignore[no-redef]
        me = _socket_current_user(optional=False)
        if not me:
            emit("error", {"message": "Unauthorized"})
            return

        verify_err = phone_verification_error_payload(me)
        if verify_err:
            emit("error", verify_err)
            return

        data = validate_input_sanitization(payload or {})
        car_id_raw = str(data.get("car_id") or "").strip()
        content = str(data.get("content") or "").strip()
        receiver_public = str(data.get("receiver_id") or "").strip()
        listing_preview = data.get("listing_preview")
        reply_to_public = str(data.get("reply_to_message_id") or "").strip()

        if not car_id_raw:
            emit("error", {"message": "car_id required"})
            return
        if not content:
            emit("error", {"message": "content required"})
            return
        if len(content) > 4000:
            emit("error", {"message": "content too long"})
            return

        car = resolve_car_for_chat(car_id_raw)
        if not car or not car.is_active:
            emit("error", {"message": "Listing not found"})
            return

        receiver = resolve_allowed_chat_receiver(me, car, receiver_public)
        if receiver is None:
            emit("error", {"message": "receiver_id required or not allowed"})
            return

        reply_to = None
        if reply_to_public:
            reply_to = Message.query.filter_by(public_id=reply_to_public, car_id=car.id).first()
            # F-05: the replied-to message must belong to THIS conversation.
            if reply_to is None or {reply_to.sender_id, reply_to.receiver_id} != {
                me.id,
                receiver.id,
            }:
                emit("error", {"message": "Reply target not found"})
                return

        msg = Message(
            sender_id=me.id,
            receiver_id=receiver.id,
            car_id=car.id,
            reply_to_id=reply_to.id if reply_to else None,
            reply_to=reply_to,
            content=content,
            message_type="text",
            listing_preview=listing_preview if isinstance(listing_preview, dict) else None,
            is_read=False,
            created_at=utcnow(),
        )
        db.session.add(msg)

        # Lightweight notification for the receiver (best-effort).
        notif = None
        try:
            notif = Notification(
                user_id=receiver.id,
                # MI-03: background notification -- no request context here,
                # so this uses the receiver's stored locale (> English).
                title=translate(
                    "new_message_title", get_background_locale(getattr(receiver, "locale", None))
                ),
                message=content[:200],
                notification_type="message",
                is_read=False,
                data={"car_id": car.public_id, "sender_id": me.public_id},
            )
            db.session.add(notif)
        except Exception:
            notif = None

        try:
            db.session.commit()
            db.session.refresh(msg)
        except Exception:
            db.session.rollback()
            emit("error", {"message": "Failed to send message"})
            return

        payload_out = msg.to_dict()

        # After the first successful message the sender becomes a participant and
        # may join the listing typing room.
        room = room_for_conversation(car.public_id, me.public_id, receiver.public_id)
        join_room(room)
        emit(
            "joined_chat",
            {
                "ok": True,
                "car_id": car.public_id,
                "room": room,
                "peer_id": receiver.public_id,
            },
        )

        # Deliver message content only to the two participants (not the shared car room).
        emit_message_to_participants(
            "new_message",
            payload_out,
            message=msg,
            sender=me,
            receiver=receiver,
        )

        if notif is not None:
            try:
                emit(
                    "new_notification",
                    notif.to_dict(),
                    room=f"user:{receiver.public_id}",
                )
            except Exception:
                pass

        # FCM push notification (best-effort).
        try:
            db.session.refresh(receiver)
            fcm_token = getattr(receiver, "firebase_token", None)
            if fcm_token:
                sender_name = f"{me.first_name} {me.last_name}".strip() or "Someone"
                ok = send_push(
                    fcm_token,
                    title=translate(
                        "new_message_push_title",
                        get_background_locale(getattr(receiver, "locale", None)),
                        name=sender_name,
                    ),
                    body=content[:200],
                    data={"car_id": car.public_id, "sender_id": me.public_id, "type": "chat_message"},
                    user_id=receiver.id,
                )
                if not ok:
                    logger.info(
                        "FCM send failed for receiver %s (check FIREBASE_SERVICE_ACCOUNT / APNs)",
                        receiver.public_id,
                    )
            else:
                logger.info(
                    "FCM skipped: receiver %s has no firebase_token (re-login on device to register)",
                    receiver.public_id,
                )
        except Exception:
            pass

        emit("message_sent", {"success": True, "message": payload_out})
