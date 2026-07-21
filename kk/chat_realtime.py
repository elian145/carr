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
from .models import BlockedUser, Car, Message, User, db

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
    if receiver.id == car.seller_id and me.id != car.seller_id:
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
