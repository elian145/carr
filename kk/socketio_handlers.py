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
        me = _socket_current_user(optional=False)
        if not me:
            return
        data = validate_input_sanitization(payload or {})
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
