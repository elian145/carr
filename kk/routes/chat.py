from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import and_, func, or_

from ..auth import get_current_user
from ..models import Car, Message, User, db
from ..security import rate_limit, validate_input_sanitization

bp = Blueprint("chat", __name__)


def _get_car_by_any_id(car_id: str):
    raw = (car_id or "").strip()
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


@bp.route("/api/chats", methods=["GET"])
@jwt_required()
def list_chats():
    """
    Return a lightweight list of recent conversations for the current user.

    This is a compatibility endpoint (legacy backend previously exposed it).
    """
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        # Pull recent messages for this user and de-dupe by (car_id, other_user_id).
        q = (
            Message.query.filter(or_(Message.sender_id == me.id, Message.receiver_id == me.id))
            .order_by(Message.created_at.desc())
            .limit(500)
            .all()
        )
        seen = set()
        chats = []
        for m in q:
            other_id = m.receiver_id if m.sender_id == me.id else m.sender_id
            key = (m.car_id or 0, int(other_id))
            if key in seen:
                continue
            seen.add(key)

            other = db.session.get(User, other_id)
            car = db.session.get(Car, m.car_id) if m.car_id else None

            unread = (
                Message.query.filter(
                    Message.receiver_id == me.id,
                    Message.is_read == False,  # noqa: E712
                    Message.sender_id == other_id,
                    Message.car_id == m.car_id,
                ).count()
                if m.car_id
                else 0
            )

            chats.append(
                {
                    # No Conversation model exists; use numeric car_id as a stable conversation_id.
                    "conversation_id": int(m.car_id or 0),
                    "car_id": car.public_id if car else None,
                    "other_user": {
                        "id": other.public_id if other else None,
                        "name": (f"{other.first_name} {other.last_name}".strip() if other else None),
                    },
                    "last_message": {
                        "id": m.public_id,
                        "content": m.content,
                        "created_at": m.created_at.isoformat() if m.created_at else None,
                        "sender_id": m.sender.public_id if m.sender else None,
                    },
                    "unread_count": int(unread or 0),
                }
            )

        return jsonify(chats), 200
    except Exception:
        return jsonify({"message": "Failed to load chats"}), 500


@bp.route("/api/chat/<int:conversation_id>/messages", methods=["GET"])
@jwt_required()
def get_messages(conversation_id: int):
    """Fetch messages for a conversation (conversation_id == numeric car.id)."""
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        car_id = int(conversation_id)
        msgs = (
            Message.query.filter(
                Message.car_id == car_id,
                or_(Message.sender_id == me.id, Message.receiver_id == me.id),
            )
            .order_by(Message.created_at.asc())
            .all()
        )

        # Mark messages to me as read (best-effort).
        try:
            Message.query.filter(
                Message.car_id == car_id,
                Message.receiver_id == me.id,
                Message.is_read == False,  # noqa: E712
            ).update({"is_read": True})
            db.session.commit()
        except Exception:
            db.session.rollback()

        return jsonify([m.to_dict() for m in msgs]), 200
    except Exception:
        return jsonify({"message": "Failed to load messages"}), 500


@bp.route("/api/chat/<int:conversation_id>/send", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=120, window_minutes=10, per_ip=False)
def send_message(conversation_id: int):
    """Send a message in a conversation (conversation_id == numeric car.id)."""
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        data = validate_input_sanitization(request.get_json(silent=True) or {})
        content = str(data.get("content") or "").strip()
        if not content:
            return jsonify({"message": "content required"}), 400
        if len(content) > 4000:
            return jsonify({"message": "content too long"}), 400

        car_id = int(conversation_id)
        car = db.session.get(Car, car_id)
        if not car:
            return jsonify({"message": "Listing not found"}), 404

        receiver_public = (data.get("receiver_id") or data.get("receiverId") or "").strip()
        receiver = None
        if receiver_public:
            receiver = User.query.filter_by(public_id=receiver_public).first()

        # Infer receiver when not provided.
        if receiver is None:
            if car.seller_id != me.id:
                receiver = db.session.get(User, car.seller_id)
            else:
                # Seller sending message: infer receiver from latest message in this car thread.
                last = (
                    Message.query.filter(
                        Message.car_id == car_id,
                        or_(Message.sender_id == me.id, Message.receiver_id == me.id),
                    )
                    .order_by(Message.created_at.desc())
                    .first()
                )
                if last:
                    other_id = last.receiver_id if last.sender_id == me.id else last.sender_id
                    receiver = db.session.get(User, other_id)

        if receiver is None:
            return jsonify({"message": "receiver_id required"}), 400
        if receiver.id == me.id:
            return jsonify({"message": "Invalid receiver"}), 400

        msg = Message(
            sender_id=me.id,
            receiver_id=receiver.id,
            car_id=car_id,
            content=content,
            message_type="text",
            is_read=False,
        )
        db.session.add(msg)
        db.session.commit()
        return jsonify({"success": True, "message": msg.to_dict()}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to send message"}), 500


@bp.route("/api/chat/unread_count", methods=["GET"])
@jwt_required()
def unread_count():
    """Return total unread messages for the current user."""
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401
        n = (
            db.session.query(func.count(Message.id))
            .filter(Message.receiver_id == me.id, Message.is_read == False)  # noqa: E712
            .scalar()
        )
        return jsonify({"unread_count": int(n or 0)}), 200
    except Exception:
        return jsonify({"message": "Failed to load unread count"}), 500

