"""
Realtime chat authorization and delivery helpers.

Listing chat historically used a shared Socket.IO room per car (`chat:{public_id}`).
That allowed any authenticated client that joined the room to observe other parties'
messages. Authorization and delivery now follow these rules:

1. Only the listing seller or an existing message participant may join a
   conversation room, and a conversation is the (listing, seller, buyer) triple:
   the room name carries BOTH participants (see `room_for_conversation`), so a
   seller talking to several buyers about one listing has one isolated room per
   buyer. Typing indicators are emitted only into that room (F-25).
2. Message payloads are emitted only to the sender and receiver personal rooms
   (`user:{public_id}`), which authenticated sockets join on connect.
3. A listing seller must always say WHICH buyer a send / history request /
   read receipt is for. Nothing falls back to "the most recent buyer", and
   history / read receipts never span two buyers (F-05).
"""

from __future__ import annotations

import logging

from sqlalchemy import and_, or_

from .extensions import socketio
from .localization import get_background_locale, translate
from .models import BlockedUser, Car, Message, Notification, User, db
from .push import send_push

logger = logging.getLogger(__name__)


def room_for_car_public_id(car_public_id: str) -> str:
    return f"chat:{car_public_id}"


def room_for_user_public_id(user_public_id: str) -> str:
    return f"user:{user_public_id}"


def room_for_conversation(
    car_public_id: str, user_a_public_id: str, user_b_public_id: str
) -> str:
    """Room shared by exactly ONE (listing, participant, participant) conversation.

    The pair is sorted so both participants derive the same name. Two buyers of
    the same listing therefore never share a room with each other.
    """
    lo, hi = sorted([str(user_a_public_id), str(user_b_public_id)])
    return f"chat:{car_public_id}:{lo}:{hi}"


def resolve_car_for_chat(car_id_raw: str) -> Car | None:
    raw = (car_id_raw or "").strip()
    if not raw:
        return None
    from .listing_visibility import not_a_working_copy

    car = Car.query.filter_by(public_id=raw).first()
    if car:
        return not_a_working_copy(car)
    if raw.isdigit():
        try:
            return not_a_working_copy(Car.query.filter_by(id=int(raw)).first())
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
        # D-01 revisit: car.seller_id is now nullable (the seller may have
        # deleted their account, leaving this listing scrubbed/deactivated
        # but present for chat history -- see kk/models.py::Car.seller_id).
        # There is no one left to start a *new* thread with; fall through
        # to "no receiver" rather than calling Session.get(User, None).
        if car.seller_id is not None and car.seller_id != me.id:
            receiver = db.session.get(User, car.seller_id)
        elif car.seller_id is None:
            receiver = None
        else:
            # F-05: the seller did not say which buyer this is for. The old
            # behaviour ("whoever wrote last") silently routed a reply meant
            # for buyer A to buyer B. Only an UNAMBIGUOUS thread (exactly one
            # counterpart on this listing) may be inferred.
            receiver = resolve_unique_counterpart(car, me)
    if receiver is None or receiver.id == me.id:
        return None
    if not chat_receiver_allowed(me, car, receiver):
        return None
    if chat_users_blocked(me.id, receiver.id):
        return None
    return receiver


def conversation_peer_keys(car: Car, user: User) -> set:
    """Distinct counterparts ``user`` has on ``car``.

    Live counterparts are keyed by their user id (int); a counterpart whose
    account was deleted is keyed ``"deleted-user:<marker>"`` (see
    ``Message.deleted_counterpart_marker``) or ``"deleted-legacy"`` for rows
    written before the marker existed.
    """
    rows = (
        db.session.query(
            Message.sender_id,
            Message.receiver_id,
            Message.deleted_counterpart_marker,
        )
        .filter(
            Message.car_id == car.id,
            or_(Message.sender_id == user.id, Message.receiver_id == user.id),
        )
        .distinct()
        .all()
    )
    keys: set = set()
    for sender_id, receiver_id, marker in rows:
        other = receiver_id if sender_id == user.id else sender_id
        if other is not None:
            if other != user.id:
                keys.add(int(other))
        elif marker is not None:
            keys.add(f"deleted-user:{int(marker)}")
        else:
            keys.add("deleted-legacy")
    return keys


def resolve_unique_counterpart(car: Car, user: User) -> User | None:
    """The single live counterpart of ``user`` on ``car``, else ``None``."""
    keys = conversation_peer_keys(car, user)
    if len(keys) != 1:
        return None
    (only,) = tuple(keys)
    if not isinstance(only, int):
        return None
    return db.session.get(User, only)


def conversation_clause(car: Car, me: User, peer_ref: str | None):
    """SQLAlchemy clause selecting ONE conversation of ``me`` on ``car``.

    ``peer_ref`` is the counterpart's public id, ``"deleted-user:<n>"`` or
    ``"deleted-legacy"``. Returns ``None`` when the reference does not name a
    counterpart (the caller treats that as an empty conversation, never as
    "all conversations").
    """
    ref = (peer_ref or "").strip()
    if not ref:
        return None
    base = Message.car_id == car.id
    if ref.startswith("deleted-user:"):
        try:
            marker = int(ref.split(":", 1)[1])
        except ValueError:
            return None
        gone = or_(
            and_(Message.sender_id == me.id, Message.receiver_id.is_(None)),
            and_(Message.receiver_id == me.id, Message.sender_id.is_(None)),
        )
        return and_(base, gone, Message.deleted_counterpart_marker == marker)
    if ref == "deleted-legacy":
        gone = or_(
            and_(Message.sender_id == me.id, Message.receiver_id.is_(None)),
            and_(Message.receiver_id == me.id, Message.sender_id.is_(None)),
        )
        return and_(base, gone, Message.deleted_counterpart_marker.is_(None))
    peer = User.query.filter_by(public_id=ref).first()
    if peer is None or peer.id == me.id:
        return None
    return and_(
        base,
        or_(
            and_(Message.sender_id == me.id, Message.receiver_id == peer.id),
            and_(Message.sender_id == peer.id, Message.receiver_id == me.id),
        ),
    )


def resolve_conversation_peer(
    me: User, car: Car, peer_public: str | None
) -> tuple[User | None, str | None]:
    """Resolve WHO the other participant of a realtime conversation is.

    Returns ``(peer, None)`` or ``(None, code)`` with ``code`` one of
    ``peer_required`` (a seller with several buyers did not say which one) and
    ``peer_not_allowed``.
    """
    raw = (peer_public or "").strip()
    if not raw and car.seller_id == me.id and resolve_unique_counterpart(car, me) is None:
        return None, "peer_required"
    peer = resolve_allowed_chat_receiver(me, car, raw)
    if peer is None:
        return None, "peer_not_allowed"
    return peer, None


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
            if message.sender_id is None:
                resolved_sender = None
            else:
                resolved_sender = message.sender or db.session.get(
                    User, message.sender_id
                )
        if resolved_receiver is None:
            if message.receiver_id is None:
                resolved_receiver = None
            else:
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
        # MI-03/batch-2: this is a background/no-request-context delivery
        # path (REST fallback for the socket flow in socketio_handlers.py,
        # which already localizes this same title) -- use the receiver's
        # stored locale, never the sender's or the current request's.
        notif = Notification(
            user_id=receiver.id,
            title=translate(
                "new_message_title", get_background_locale(getattr(receiver, "locale", None))
            ),
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
                title=translate(
                    "new_message_push_title",
                    get_background_locale(getattr(receiver, "locale", None)),
                    name=sender_name,
                ),
                body=(msg.content or "")[:200],
                data={
                    "car_id": car.public_id if car else None,
                    "sender_id": sender.public_id,
                    "type": "chat_message",
                },
                user_id=receiver.id,
            )
    except Exception:
        logger.exception(
            "deliver_message: push send failed for message %s", msg.public_id
        )

    return payload


def mark_messages_read_for_viewer(
    car: Car, viewer: User, peer: User | None = None
) -> dict:
    """
    Mark unread inbound messages as read and notify counterparties (M-14).

    F-05: read state is per CONVERSATION. When ``peer`` is given only that
    peer's messages are marked (and only that peer is notified). A listing
    seller who did not say which buyer is meant gets a no-op unless exactly one
    buyer exists, so opening one buyer's thread can never mark (or announce a
    read of) another buyer's messages.

    Returns a small summary dict for logging / responses.
    """
    if car is None or viewer is None:
        return {"marked": 0, "message_ids": []}

    conditions = [
        Message.car_id == car.id,
        Message.receiver_id == viewer.id,
        Message.is_read.is_(False),
        Message.is_deleted.is_(False),
    ]
    if peer is not None:
        conditions.append(Message.sender_id == peer.id)
    elif getattr(car, "seller_id", None) == viewer.id:
        only = resolve_unique_counterpart(car, viewer)
        if only is None:
            return {"marked": 0, "message_ids": []}
        conditions.append(Message.sender_id == only.id)

    unread = (
        Message.query.filter(*conditions)
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
