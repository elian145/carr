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

from sqlalchemy import or_

from .extensions import socketio
from .models import Car, Message, User, db

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
