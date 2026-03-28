from __future__ import annotations

from datetime import datetime

from flask import current_app, request
from flask_jwt_extended import decode_token, get_jwt_identity, verify_jwt_in_request
from flask_socketio import emit, join_room, leave_room

from .models import Car, Message, Notification, User, db
from .push import send_push
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

    @socketio.on("typing_start")
    def _typing_start(payload):  # type: ignore[no-redef]
        me = _socket_current_user(optional=False)
        if not me:
            return
        data = validate_input_sanitization(payload or {})
        car_id_raw = str(data.get("car_id") or "").strip()
        if not car_id_raw:
            return
        car = Car.query.filter_by(public_id=car_id_raw).first()
        if not car and car_id_raw.isdigit():
            try:
                car = Car.query.filter_by(id=int(car_id_raw)).first()
            except Exception:
                car = None
        if not car:
            return
        room = _room_for_car_public_id(car.public_id)
        emit(
            "typing",
            {
                "user_id": me.public_id,
                "user_name": f"{me.first_name} {me.last_name}".strip(),
                "car_id": car.public_id,
                "typing": True,
            },
            room=room,
            include_self=False,
        )

    @socketio.on("typing_stop")
    def _typing_stop(payload):  # type: ignore[no-redef]
        me = _socket_current_user(optional=False)
        if not me:
            return
        data = validate_input_sanitization(payload or {})
        car_id_raw = str(data.get("car_id") or "").strip()
        if not car_id_raw:
            return
        car = Car.query.filter_by(public_id=car_id_raw).first()
        if not car and car_id_raw.isdigit():
            try:
                car = Car.query.filter_by(id=int(car_id_raw)).first()
            except Exception:
                car = None
        if not car:
            return
        room = _room_for_car_public_id(car.public_id)
        emit(
            "typing",
            {
                "user_id": me.public_id,
                "user_name": f"{me.first_name} {me.last_name}".strip(),
                "car_id": car.public_id,
                "typing": False,
            },
            room=room,
            include_self=False,
        )

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

        reply_to = None
        if reply_to_public:
            reply_to = Message.query.filter_by(public_id=reply_to_public, car_id=car.id).first()
            if reply_to is None or me.id not in (reply_to.sender_id, reply_to.receiver_id):
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
            db.session.refresh(msg)
        except Exception:
            db.session.rollback()
            emit("error", {"message": "Failed to send message"})
            return

        payload_out = msg.to_dict()
        room = _room_for_car_public_id(car.public_id)

        emit("new_message", payload_out, room=room)

        try:
            emit("new_notification", notif.to_dict(), room=f"user:{receiver.public_id}")
        except Exception:
            pass

        # FCM push notification (best-effort).
        try:
            fcm_token = getattr(receiver, "firebase_token", None)
            if fcm_token:
                sender_name = f"{me.first_name} {me.last_name}".strip() or "Someone"
                send_push(
                    fcm_token,
                    title=f"New message from {sender_name}",
                    body=content[:200],
                    data={"car_id": car.public_id, "sender_id": me.public_id, "type": "chat_message"},
                )
        except Exception:
            pass

        emit("message_sent", {"success": True, "message": payload_out})

