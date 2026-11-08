from __future__ import annotations

import logging
import os
import threading
import time

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
from .realtime_limits import ConnectionRegistry, EventRateLimiter, load_limits
from .socket_account_admission import BAD_TOKENS, ESTABLISHED_KEY, REFUSED_KEY
from .push import send_push
from .security import _client_ip, validate_input_sanitization
from .time_utils import utcnow


#: how long a token / account the connect handler proved dead stays classified as
#: "restricted" at the edge (N-2); the token's own expiry caps it for tokens.
_BAD_TOKEN_TTL_SECONDS = 600.0
_BAD_ACCOUNT_TTL_SECONDS = 60.0


def _mark_refused(raw: str | None, code: str | None, claims: dict | None = None) -> None:
    """N-2: a refused connect keeps its transport only briefly (the orphan reaper
    uses ``REFUSED_KEY``) and a replayed revoked / dead-account token is charged
    to the small restricted edge bucket instead of the account's live budget."""
    try:
        request.environ[REFUSED_KEY] = True
        if code == "token_revoked" and raw:
            decoded = decode_token(raw, allow_expired=True)  # signature already checked
            ttl = _BAD_TOKEN_TTL_SECONDS
            exp = decoded.get("exp")
            if isinstance(exp, (int, float)):
                ttl = max(1.0, min(ttl, float(exp) - _now()))
            BAD_TOKENS.add_token(decoded.get("jti"), raw, ttl)
        elif code == "invalid_token" and claims:  # signed + live token, account gone/inactive
            BAD_TOKENS.add_account(str(claims.get("sub") or ""), _BAD_ACCOUNT_TTL_SECONDS)
    except Exception:  # pragma: no cover - bookkeeping must never break connect
        logger.debug("mark_refused failed", exc_info=True)


def _allow_anonymous() -> bool:
    """Anonymous (token-less) sockets are off unless explicitly enabled."""
    return (os.environ.get("SOCKETIO_ALLOW_ANONYMOUS") or "").strip().lower() in (
        "1",
        "true",
        "yes",
        "on",
    )


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
# ---------------------------------------------------------------------------
# C-1: resource limits (see kk/realtime_limits.py for the rationale).
#
# Replaced by every register_socketio_handlers() call, so each Flask app (and
# each test app) starts with an empty registry. Per-process by design.
# ---------------------------------------------------------------------------
_REGISTRY: ConnectionRegistry = ConnectionRegistry(load_limits())
_LIMITER: EventRateLimiter = EventRateLimiter()

# (max events, window seconds). send_message mirrors the REST limit
# (kk/routes/chat.py: 120 per 10 minutes per user) plus a short per-socket burst
# limit; the rest only stop one socket from hammering DB-backed handlers.
_LIMIT_SEND_BURST = (20, 10.0)
_LIMIT_SEND_USER = (120, 600.0)
_LIMIT_JOIN = (30, 60.0)
_LIMIT_LEAVE = (60, 60.0)
_LIMIT_TYPING = (20, 10.0)
# A listing preview is display metadata; refuse anything bigger than this.
_MAX_LISTING_PREVIEW_BYTES = 4096


def _payload_dict(payload) -> dict:
    """Event payloads are client controlled: only a JSON object is meaningful."""
    return payload if isinstance(payload, dict) else {}


def _listing_preview_ok(preview) -> bool:
    if not isinstance(preview, dict):
        return False
    try:
        import json

        return len(json.dumps(preview, ensure_ascii=False, default=str)) <= _MAX_LISTING_PREVIEW_BYTES
    except Exception:
        return False


def _throttled(
    event: str,
    limit: tuple[int, float],
    *,
    user_public_id: str | None = None,
    silent: bool = False,
) -> bool:
    """True (after telling the client, unless ``silent``) when the event must be dropped."""
    sid = getattr(request, "sid", None) or "?"
    key = f"user:{user_public_id}:{event}" if user_public_id else f"sid:{sid}:{event}"
    ok, retry_after = _LIMITER.allow(key, limit[0], limit[1])
    if ok:
        return False
    if not silent:
        try:
            emit(
                "error",
                {
                    "message": "Too many requests. Please slow down.",
                    "code": "rate_limited",
                    "event": event,
                    "retry_after": retry_after,
                },
            )
        except Exception:
            logger.debug("rate_limited emit failed", exc_info=True)
    return True


def _evict_socket(
    socketio,
    sid: str,
    event: str = "connection_replaced",
    code: str = "too_many_connections",
) -> None:
    """Drop a socket that lost its slot.

    ``connection_replaced`` -- an older socket of a user over their cap.
    ``connection_released`` -- an idle socket (no joined conversation) given up
    to free a worker thread; the client must NOT auto-reconnect and simply
    reconnects when its user opens a conversation.
    """
    _unbind_socket(sid)
    _REGISTRY.release(sid)
    _LIMITER.forget_prefix(f"sid:{sid}:")
    try:
        socketio.emit(event, {"code": code}, to=sid)
    except Exception:
        logger.debug("%s emit failed", event, exc_info=True)
    try:
        socketio.server.disconnect(sid, namespace="/")
    except Exception:
        logger.debug("evicted socket disconnect failed", exc_info=True)


_SWEEP_INTERVAL_SECONDS = 15.0
_SWEEPER_REGISTRY: ConnectionRegistry | None = None


def release_idle_sockets(socketio, registry: ConnectionRegistry | None = None) -> list[str]:
    """Release every socket past its idle allowance. Returns the released sids."""
    reg = registry or _REGISTRY
    released = []
    for sid in reg.idle_sids():
        _evict_socket(socketio, sid, "connection_released", "idle")
        released.append(sid)
    return released


def _sweep_idle_loop(socketio, registry: ConnectionRegistry) -> None:
    while registry is _REGISTRY:
        socketio.sleep(_SWEEP_INTERVAL_SECONDS)
        if registry is not _REGISTRY:
            return
        try:
            n = len(release_idle_sockets(socketio, registry))
            if n:
                logger.info("Socket.IO released %d idle socket(s)", n)
        except Exception:
            logger.exception("Socket.IO idle sweep failed")


def _ensure_idle_sweeper(socketio) -> None:
    """Start the (single, per-process) idle sweeper on the first connection."""
    global _SWEEPER_REGISTRY
    lim = _REGISTRY.limits
    if lim.idle_release_s <= 0 and lim.guest_idle_s <= 0:
        return
    if _SWEEPER_REGISTRY is _REGISTRY:
        return
    _SWEEPER_REGISTRY = _REGISTRY
    socketio.start_background_task(_sweep_idle_loop, socketio, _REGISTRY)


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
    global _REGISTRY, _LIMITER
    _REGISTRY = ConnectionRegistry(load_limits())
    _LIMITER = EventRateLimiter()

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
            if not _allow_anonymous():
                # C-1: the app never connects without a token and a guest only
                # pins a worker thread, so anonymous sockets are refused
                # (SOCKETIO_ALLOW_ANONYMOUS=1 re-enables them).
                logger.info("Socket.IO connect refused: authentication_required")
                raise ConnectionRefusedError("authentication_required")
            # Opt-in guests are capped per address and in total.
            admission = _REGISTRY.admit(request.sid, _client_ip(), None)
            if admission.refused:
                logger.info("Socket.IO guest refused: %s", admission.refused)
                _mark_refused(None, admission.refused)
                raise ConnectionRefusedError(admission.refused)
            _ensure_idle_sweeper(socketio)
            emit("connected", {"authenticated": False, "user_id": None})
            return
        claims, err = _verify_access_token(raw)
        user = _load_active_user(claims.get("sub")) if claims else None
        if err is not None or user is None:
            code = err or "invalid_token"
            logger.info("Socket.IO connect refused: %s", code)
            _mark_refused(raw, code, claims)
            raise ConnectionRefusedError(code)
        sid = request.sid
        # C-1: per-user cap (oldest socket is evicted) and a global ceiling that
        # always leaves worker threads for HTTP.
        admission = _REGISTRY.admit(sid, _client_ip(), user.public_id)
        if admission.refused:
            logger.info("Socket.IO connect refused: %s", admission.refused)
            _mark_refused(None, admission.refused)
            raise ConnectionRefusedError(admission.refused)
        try:
            # N-2: from now on the edge treats this session's requests as an
            # established socket (never refused by the account cap, evicted last).
            request.environ[ESTABLISHED_KEY] = True
        except Exception:  # pragma: no cover
            pass
        for old_sid in admission.evict:
            _evict_socket(socketio, old_sid)
        for idle_sid in admission.released:
            _evict_socket(socketio, idle_sid, "connection_released", "capacity")
        _ensure_idle_sweeper(socketio)
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
        sid = getattr(request, "sid", None)
        _unbind_socket(sid)
        _REGISTRY.release(sid)
        if sid:
            _LIMITER.forget_prefix(f"sid:{sid}:")
        return

    @socketio.on("join_chat")
    def _join_chat(payload):  # type: ignore[no-redef]
        if _throttled("join_chat", _LIMIT_JOIN):
            return
        # Opening a conversation counts as activity even when the room cannot be
        # joined yet (a buyer's thread has no messages until the first one).
        _REGISTRY.touch(request.sid)
        me = _socket_current_user(optional=False)
        if not me:
            emit("error", {"message": "Unauthorized"})
            return

        data = validate_input_sanitization(_payload_dict(payload))
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
        _REGISTRY.note_room(request.sid, room, True)
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
        if _throttled("leave_chat", _LIMIT_LEAVE, silent=True):
            return
        _socket_current_user(optional=True)
        data = validate_input_sanitization(_payload_dict(payload))
        room = str(data.get("room") or "").strip()
        if room:
            leave_room(room)
            _REGISTRY.note_room(getattr(request, "sid", None) or "", room, False)
        emit("left_chat", {"room": room})

    def _emit_typing(payload, typing: bool) -> None:
        """F-25: a typing indicator goes ONLY to the other participant of the
        (listing, seller, buyer) conversation it belongs to -- never to every
        socket that joined the listing."""
        if _throttled("typing", _LIMIT_TYPING, silent=True):
            return
        _REGISTRY.touch(request.sid)
        me = _socket_current_user(optional=False)
        if not me:
            return
        data = validate_input_sanitization(_payload_dict(payload))
        car_id_raw = str(data.get("car_id") or "").strip()
        peer_public = str(data.get("peer_id") or data.get("receiver_id") or "").strip()
        if not car_id_raw:
            return
        car = resolve_car_for_chat(car_id_raw)
        if not car or not user_can_access_chat_room(me, car):
            return
        peer, _code = resolve_conversation_peer(me, car, peer_public)
        if peer is None:
            return
        room = room_for_conversation(car.public_id, me.public_id, peer.public_id)
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
        # C-1: per-socket burst limit BEFORE any token/DB work ...
        if _throttled("send_message", _LIMIT_SEND_BURST):
            return
        me = _socket_current_user(optional=False)
        if not me:
            emit("error", {"message": "Unauthorized"})
            return
        # ... and the same per-user budget as the REST send endpoint, shared
        # across all of that user's sockets.
        if _throttled("send_message", _LIMIT_SEND_USER, user_public_id=me.public_id):
            return

        verify_err = phone_verification_error_payload(me)
        if verify_err:
            emit("error", verify_err)
            return

        data = validate_input_sanitization(_payload_dict(payload))
        car_id_raw = str(data.get("car_id") or "").strip()
        content = str(data.get("content") or "").strip()
        receiver_public = str(data.get("receiver_id") or "").strip()
        listing_preview = data.get("listing_preview")
        if not _listing_preview_ok(listing_preview):
            listing_preview = None
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
        _REGISTRY.note_room(request.sid, room, True)
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
