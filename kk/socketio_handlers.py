from __future__ import annotations

from datetime import datetime

from flask import current_app, request
from flask_jwt_extended import decode_token, get_jwt_identity, verify_jwt_in_request
from flask_socketio import emit, join_room, leave_room

from .models import Car, Message, Notification, User, db
from .security import validate_input_sanitization
from .time_utils import utcnow


def _room_for_car_public_id(car_public_id: str) -> str:
    return f"chat:{car_public_id}"


def _socket_current_user(*, optional: bool = False) -> User | None:
    """
    Resolve the current user for Socket.IO events.

    Supports:
    - Authorization header (preferred)
    - `?token=<access_jwt>` query param (dev/test only; Flutter has a dev flag)
    """
    identity = None
    try:
        verify_jwt_in_request(optional=optional)
        identity = get_jwt_identity()
    except Exception:
        identity = None

    if not identity:
        raw = (request.args.get("token") or "").strip()
        if raw:
            try:
                decoded = decode_token(raw)
                # Accept only access tokens here.
                if decoded.get("type") in (None, "access"):
                    identity = decoded.get("sub")
            except Exception:
                identity = None

    if not identity:
        return None

    try:
        u = User.query.filter_by(public_id=str(identity)).first()
        if not u or not u.is_active:
            return None
        return u
    except Exception:
        return None


def register_socketio_handlers(socketio) -> None:
    """
    Register Socket.IO handlers on the given SocketIO instance.

    IMPORTANT: `create_app()` can be called multiple times in tests; this function
    must be idempotent.
    """
    if getattr(socketio, "_kk_handlers_registered", False):
        return
    setattr(socketio, "_kk_handlers_registered", True)

    @socketio.on("connect")
    def _connect():  # type: ignore[no-redef]
        """
        Accept the connection even if unauthenticated (client can connect first,
        then login). For authenticated sockets, join a per-user room.
        """
        me = _socket_current_user(optional=True)
        user_id = me.public_id if me else None
        if user_id:
            join_room(f"user:{user_id}")
        emit("connected", {"authenticated": bool(user_id), "user_id": user_id})

    @socketio.on("disconnect")
    def _disconnect():  # type: ignore[no-redef]
        return

    @socketio.on("join_chat")
    def _join_chat(payload):  # type: ignore[no-redef]
        me = _socket_current_user(optional=False)
        if not me:
            emit("error", {"message": "Unauthorized"})
            return

        data = validate_input_sanitization(payload or {})
        car_id_raw = str(data.get("car_id") or "").strip()
        if not car_id_raw:
            emit("error", {"message": "car_id required"})
            return

        car = Car.query.filter_by(public_id=car_id_raw).first()
        if not car and car_id_raw.isdigit():
            try:
                car = Car.query.filter_by(id=int(car_id_raw)).first()
            except Exception:
                car = None

        if not car or not car.is_active:
            emit("error", {"message": "Listing not found"})
            return

        room = _room_for_car_public_id(car.public_id)
        join_room(room)
        emit("joined_chat", {"car_id": car.public_id, "room": room})

    @socketio.on("leave_chat")
    def _leave_chat(payload):  # type: ignore[no-redef]
        _socket_current_user(optional=True)
        data = validate_input_sanitization(payload or {})
        room = str(data.get("room") or "").strip()
        if room:
            leave_room(room)
        emit("left_chat", {"room": room})

    @socketio.on("send_message")
    def _send_message(payload):  # type: ignore[no-redef]
        me = _socket_current_user(optional=False)
        if not me:
            emit("error", {"message": "Unauthorized"})
            return

        data = validate_input_sanitization(payload or {})
        car_id_raw = str(data.get("car_id") or "").strip()
        content = str(data.get("content") or "").strip()
        receiver_public = str(data.get("receiver_id") or "").strip()

        if not car_id_raw:
            emit("error", {"message": "car_id required"})
            return
        if not content:
            emit("error", {"message": "content required"})
            return
        if len(content) > 4000:
            emit("error", {"message": "content too long"})
            return

        car = Car.query.filter_by(public_id=car_id_raw).first()
        if not car and car_id_raw.isdigit():
            try:
                car = Car.query.filter_by(id=int(car_id_raw)).first()
            except Exception:
                car = None
        if not car or not car.is_active:
            emit("error", {"message": "Listing not found"})
            return

        receiver = None
        if receiver_public:
            receiver = User.query.filter_by(public_id=receiver_public).first()

        # Infer receiver
        if receiver is None:
            if car.seller_id != me.id:
                receiver = db.session.get(User, car.seller_id)
            else:
                emit("error", {"message": "receiver_id required"})
                return

        if receiver is None or receiver.id == me.id:
            emit("error", {"message": "Invalid receiver"})
            return

        msg = Message(
            sender_id=me.id,
            receiver_id=receiver.id,
            car_id=car.id,
            content=content,
            message_type="text",
            is_read=False,
            created_at=utcnow(),
        )
        db.session.add(msg)

        # Lightweight notification for the receiver (best-effort).
        try:
            notif = Notification(
                user_id=receiver.id,
                title="New message",
                message=content[:200],
                notification_type="message",
                is_read=False,
                data={"car_id": car.public_id, "sender_id": me.public_id},
            )
            db.session.add(notif)
        except Exception:
            pass

        try:
            db.session.commit()
        except Exception:
            db.session.rollback()
            emit("error", {"message": "Failed to send message"})
            return

        payload_out = msg.to_dict()
        room = _room_for_car_public_id(car.public_id)

        # Broadcast to everyone in the chat room.
        emit("new_message", payload_out, room=room)

        # Also push to per-user rooms (for notifications outside the active chat).
        try:
            emit("new_notification", notif.to_dict(), room=f"user:{receiver.public_id}")
        except Exception:
            pass

        # Ack to sender.
        emit("message_sent", {"success": True, "message": payload_out})

