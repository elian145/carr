"""
Realtime chat authorization and delivery helpers.

Listing chat historically used a shared Socket.IO room per car (`chat:{public_id}`).
That allowed any authenticated client that joined the room to observe other parties'
messages. Authorization and delivery now follow these rules:

1. Only the listing seller or an existing message participant may join the car room
   (used for typing indicators).
2. Message payloads are emitted only to the sender and receiver personal rooms
   (`user:{public_id}`), which authenticated sockets join on connect.
"""

from __future__ import annotations

import logging

from sqlalchemy import and_, or_

from .extensions import socketio
from .models import BlockedUser, Car, Message, Notification, User, db
from .push import send_push

logger = logging.getLogger(__name__)


def room_for_car_public_id(car_public_id: str) -> str:
    return f"chat:{car_public_id}"


def room_for_user_public_id(user_public_id: str) -> str:
    return f"user:{user_public_id}"


def resolve_car_for_chat(car_id_raw: str) -> Car | None:
    raw = (car_id_raw or "").strip()
    if not raw:
        return None
    car = Car.query.filter_by(public_id=raw).first()
    if car:
        return car
    if raw.isdigit():
        try:
            return Car.query.filter_by(id=int(raw)).first()
        except Exception:
            return None
    return None


def chat_users_blocked(user_a_id: int, user_b_id: int) -> bool:
    return (
        BlockedUser.query.filter(
            or_(
                and_(
                    BlockedUser.blocker_id == user_a_id,
                    BlockedUser.blocked_id == user_b_id,
                ),
                and_(
                    BlockedUser.blocker_id == user_b_id,
                    BlockedUser.blocked_id == user_a_id,
                ),
            )
        ).first()
        is not None
    )


def chat_receiver_allowed(me: User, car: Car, receiver: User) -> bool:
    """Buyer may message seller; otherwise an existing thread on this listing is required."""
    from .listing_visibility import listing_is_public

    if receiver.id == car.seller_id and me.id != car.seller_id:
        # First contact is only allowed on public listings (not under review).
        if listing_is_public(car):
            return True
    prior = (
        Message.query.filter(
            Message.car_id == car.id,
            or_(
                and_(Message.sender_id == me.id, Message.receiver_id == receiver.id),
                and_(Message.sender_id == receiver.id, Message.receiver_id == me.id),
            ),
        )
        .limit(1)
        .first()
    )
    return prior is not None


def resolve_allowed_chat_receiver(
    me: User, car: Car, receiver_public: str | None
) -> User | None:
    """
    Resolve a chat peer for this listing.

    Rejects arbitrary ``receiver_id`` targets and either-direction blocks.
    """
    receiver = None
    raw = (receiver_public or "").strip()
    if raw:
        receiver = User.query.filter_by(public_id=raw).first()
    if receiver is None:
        if car.seller_id != me.id:
            receiver = db.session.get(User, car.seller_id)
        else:
            last = (
                Message.query.filter(
                    Message.car_id == car.id,
                    or_(Message.sender_id == me.id, Message.receiver_id == me.id),
                )
                .order_by(Message.created_at.desc())
                .first()
            )
            if last:
                other_id = last.receiver_id if last.sender_id == me.id else last.sender_id
                receiver = db.session.get(User, other_id)
    if receiver is None or receiver.id == me.id:
        return None
    if not chat_receiver_allowed(me, car, receiver):
        return None
    if chat_users_blocked(me.id, receiver.id):
        return None
    return receiver


def user_can_access_chat_room(user: User, car: Car) -> bool:
    """
    True when the user may join the listing chat room / emit typing events.

    Allowed:
    - Listing seller
    - Anyone who has already sent or received a message for this listing
    """
    if not user or not car:
        return False
    if car.seller_id == user.id:
        return True
    return (
        Message.query.filter(
            Message.car_id == car.id,
            or_(Message.sender_id == user.id, Message.receiver_id == user.id),
        )
        .limit(1)
        .first()
        is not None
    )


def emit_to_user_rooms(event_name: str, payload: dict, *users: User | None) -> None:
    """Emit a Socket.IO event to each unique authenticated user room."""
    seen: set[str] = set()
    for user in users:
        if user is None:
            continue
        public_id = (getattr(user, "public_id", None) or "").strip()
        if not public_id or public_id in seen:
            continue
        seen.add(public_id)
        try:
            socketio.emit(event_name, payload, room=room_for_user_public_id(public_id))
        except Exception:
            logger.exception(
                "Failed to emit %s to user room %s", event_name, public_id
            )


def emit_message_to_participants(
    event_name: str,
    payload: dict,
    *,
    message: Message | None = None,
    sender: User | None = None,
    receiver: User | None = None,
) -> None:
    """
    Deliver chat message events only to the two conversation participants.

    Prefer explicit sender/receiver when already loaded; otherwise resolve from
    the Message row.
    """
    resolved_sender = sender
    resolved_receiver = receiver
    if message is not None:
        if resolved_sender is None:
            resolved_sender = message.sender or db.session.get(User, message.sender_id)
        if resolved_receiver is None:
            resolved_receiver = message.receiver or db.session.get(
                User, message.receiver_id
            )
    emit_to_user_rooms(event_name, payload, resolved_sender, resolved_receiver)


def deliver_message(msg: Message, *, sender: User, receiver: User) -> dict:
    """
    Best-effort post-commit delivery for an already-durably-committed chat ``Message``.

    Callers MUST invoke this only after ``msg`` has been added, committed, and
    refreshed. Every side effect here (Socket.IO emit, ``Notification`` row,
    FCM push) is independently failure-isolated:

    - No side effect here may raise out of this function.
    - No side effect here may roll back or otherwise affect the already-committed
      ``Message`` row.
    - A failure in one side effect (e.g. Notification commit) must not prevent
      the other side effects (Socket.IO emit, push) from being attempted, and
      must not leave the SQLAlchemy session broken for the caller.

    Returns the serialized ``msg.to_dict()`` payload built here (the same one
    emitted over Socket.IO), so REST callers can reuse it for their HTTP
    response instead of calling ``msg.to_dict()`` again. This matters for
    chat media (C-10): each private-bucket attachment's ``to_dict()`` call
    generates a fresh presigned GET URL via an R2 subprocess call, so calling
    it twice would presign the same attachment twice for no reason.
    """
    payload = msg.to_dict()

    # 1) Socket.IO: notify both participants. `emit_message_to_participants`
    # already wraps `socketio.emit` in a try/except per room; guard again here
    # so any unexpected error in payload handling can never escape.
    try:
        emit_message_to_participants(
            "new_message",
            payload,
            message=msg,
            sender=sender,
            receiver=receiver,
        )
    except Exception:
        logger.exception(
            "deliver_message: socket delivery failed for message %s", msg.public_id
        )

    # 2) Database Notification row for the receiver — independent, post-commit,
    # own commit boundary. On failure, roll back only this pending Notification
    # insert (never the already-committed Message) and leave the session usable.
    try:
        car = msg.car
        notif = Notification(
            user_id=receiver.id,
            title="New message",
            message=(msg.content or "")[:200],
            notification_type="message",
            is_read=False,
            data={
                "car_id": car.public_id if car else None,
                "sender_id": sender.public_id,
            },
        )
        db.session.add(notif)
        db.session.commit()
    except Exception:
        logger.exception(
            "deliver_message: notification create failed for message %s", msg.public_id
        )
        try:
            db.session.rollback()
        except Exception:
            logger.exception(
                "deliver_message: session rollback after notification failure also failed"
            )

    # 3) FCM push — best-effort. `send_push` itself never raises, but guard the
    # surrounding token lookup/refresh too.
    try:
        db.session.refresh(receiver)
        fcm_token = getattr(receiver, "firebase_token", None)
        if fcm_token:
            sender_name = f"{sender.first_name} {sender.last_name}".strip() or "Someone"
            car = msg.car
            send_push(
                fcm_token,
                title=f"New message from {sender_name}",
                body=(msg.content or "")[:200],
                data={
                    "car_id": car.public_id if car else None,
                    "sender_id": sender.public_id,
                    "type": "chat_message",
                },
            )
    except Exception:
        logger.exception(
            "deliver_message: push send failed for message %s", msg.public_id
        )

    return payload


def mark_messages_read_for_viewer(car: Car, viewer: User) -> dict:
    """
    Mark unread inbound messages as read and notify counterparties (M-14).

    Returns a small summary dict for logging / responses.
    """
    if car is None or viewer is None:
        return {"marked": 0, "message_ids": []}

    unread = (
        Message.query.filter(
            Message.car_id == car.id,
            Message.receiver_id == viewer.id,
            Message.is_read.is_(False),
            Message.is_deleted.is_(False),
        )
        .order_by(Message.created_at.asc())
        .all()
    )
    if not unread:
        return {"marked": 0, "message_ids": []}

    message_ids = [
        (m.public_id or str(m.id)) for m in unread if (m.public_id or m.id)
    ]
    sender_ids = {m.sender_id for m in unread if m.sender_id}
    senders = (
        User.query.filter(User.id.in_(sender_ids)).all() if sender_ids else []
    )

    Message.query.filter(Message.id.in_([m.id for m in unread])).update(
        {"is_read": True},
        synchronize_session=False,
    )
    db.session.commit()

    payload = {
        "car_id": car.public_id,
        "reader_id": viewer.public_id,
        "message_ids": message_ids,
    }
    emit_to_user_rooms("messages_read", payload, *senders)
    return {"marked": len(message_ids), "message_ids": message_ids}
