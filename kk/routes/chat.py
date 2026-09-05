from __future__ import annotations

from datetime import datetime
import json
import os
import secrets

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import func, or_
from sqlalchemy.orm import joinedload, selectinload
from werkzeug.exceptions import RequestEntityTooLarge

from ..auth import get_current_user, phone_verification_required_response
from ..chat_realtime import (
    deliver_message,
    emit_message_to_participants,
    mark_messages_read_for_viewer,
    resolve_allowed_chat_receiver,
)
from ..models import BlockedUser, Car, Message, User, UserReport, db
from ..push import fcm_is_configured, fcm_send_error_hint, last_fcm_send_error, send_push
from ..security import rate_limit, validate_input_sanitization
from ..time_utils import utcnow
from .media import _pick_primary_listing_url

bp = Blueprint("chat", __name__)

_CHAT_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
_CHAT_VIDEO_EXTENSIONS = {".mp4", ".mov", ".avi", ".mkv", ".webm"}
_CHAT_AUDIO_EXTENSIONS = {".m4a", ".aac", ".mp3", ".wav", ".ogg", ".webm", ".amr", ".3gp"}
_CHAT_ATTACHMENT_EXTENSIONS = _CHAT_IMAGE_EXTENSIONS | _CHAT_VIDEO_EXTENSIONS


def _resolve_chat_receiver(me: User, car: Car, receiver_public: str | None) -> User | None:
    return resolve_allowed_chat_receiver(me, car, receiver_public)


def _count_buyer_message_metric(car: Car, sender: User) -> None:
    try:
        from ..listing_metrics import record_buyer_message

        record_buyer_message(car, sender)
    except Exception:
        pass


def _first_car_image_rel_path(car: Car | None) -> str | None:
    """Primary listing photo path/URL for chat list avatars (same rules as car list API)."""
    if not car:
        return None
    raw = _pick_primary_listing_url(car)
    if not raw and car.images:
        raw = car.images[0].image_url
    if not raw:
        return None
    raw = str(raw).strip()
    if raw.startswith("http://") or raw.startswith("https://"):
        return raw
    norm = raw.lstrip("/").replace("\\", "/")
    if norm.startswith("uploads/"):
        return norm
    if norm.startswith("car_photos/"):
        return f"uploads/{norm}"
    return norm


def _upload_chat_attachment(file_storage, *, allowed_extensions: set[str], subdir: str, content_types: dict[str, str]) -> str:
    """Store one chat attachment and return a stable reference for the DB.

    C-10: chat media lives in a PRIVATE R2 bucket (R2_CHAT_*), never the
    public listing-media bucket. This returns a bare object key (e.g.
    "chat_uploads/<hex>.jpg") — NOT a URL. A public URL is never constructed
    for chat media. Readers must resolve the key to a short-lived presigned
    GET URL only after confirming the requester is authorized to see the
    owning message (see Message.to_dict() / _resolve_chat_media_ref()).

    Falls back to local disk (unchanged pre-C-10 behavior, still returned as
    a "/static/..." path) only when the private chat bucket isn't configured
    (e.g. local dev without R2_CHAT_* set).
    """
    ext = os.path.splitext(file_storage.filename or "")[1].lower()
    if ext not in allowed_extensions:
        raise ValueError("Unsupported attachment format")

    r2_chat_bucket = current_app.config.get("R2_CHAT_BUCKET_NAME")
    r2_account = current_app.config.get("R2_ACCOUNT_ID")
    r2_chat_key = current_app.config.get("R2_CHAT_ACCESS_KEY_ID")
    r2_chat_secret = current_app.config.get("R2_CHAT_SECRET_ACCESS_KEY")

    if r2_chat_bucket and r2_account and r2_chat_key and r2_chat_secret:
        from ..r2_ops import r2_chat_put_bytes

        obj_key = f"{subdir}/{secrets.token_hex(16)}{ext}"
        file_storage.seek(0)
        body = file_storage.read()
        r2_chat_put_bytes(
            key=obj_key,
            body=body,
            content_type=content_types.get(ext, "application/octet-stream"),
        )
        # Bare key only — no public URL exists for this bucket.
        return obj_key

    upload_dir = os.path.join(current_app.root_path, "static", subdir)
    os.makedirs(upload_dir, exist_ok=True)
    safe_name = f"{secrets.token_hex(16)}{ext}"
    path = os.path.join(upload_dir, safe_name)
    file_storage.seek(0)
    file_storage.save(path)
    return f"/static/{subdir}/{safe_name}"


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


def _upload_chat_media_item(file_storage) -> dict[str, str]:
    ext = os.path.splitext(file_storage.filename or "")[1].lower()
    if ext in _CHAT_IMAGE_EXTENSIONS:
        return {
            "type": "image",
            "url": _upload_chat_attachment(
                file_storage,
                allowed_extensions=_CHAT_IMAGE_EXTENSIONS,
                subdir="chat_uploads",
                content_types={
                    ".jpg": "image/jpeg",
                    ".jpeg": "image/jpeg",
                    ".png": "image/png",
                    ".gif": "image/gif",
                    ".webp": "image/webp",
                },
            ),
        }
    if ext in _CHAT_VIDEO_EXTENSIONS:
        return {
            "type": "video",
            "url": _upload_chat_attachment(
                file_storage,
                allowed_extensions=_CHAT_VIDEO_EXTENSIONS,
                subdir="chat_videos",
                content_types={
                    ".mp4": "video/mp4",
                    ".mov": "video/quicktime",
                    ".avi": "video/x-msvideo",
                    ".mkv": "video/x-matroska",
                    ".webm": "video/webm",
                },
            ),
        }
    if ext in _CHAT_AUDIO_EXTENSIONS:
        return {
            "type": "audio",
            "url": _upload_chat_attachment(
                file_storage,
                allowed_extensions=_CHAT_AUDIO_EXTENSIONS,
                subdir="chat_audio",
                content_types={
                    ".m4a": "audio/mp4",
                    ".aac": "audio/aac",
                    ".mp3": "audio/mpeg",
                    ".wav": "audio/wav",
                    ".ogg": "audio/ogg",
                    ".webm": "audio/webm",
                    ".amr": "audio/amr",
                    ".3gp": "audio/3gpp",
                },
            ),
        }
    raise ValueError("Unsupported attachment format")


def _default_media_group_content(count: int) -> str:
    return f"[{max(count, 1)} attachments]"


def _max_upload_mb() -> int:
    raw = int(current_app.config.get("MAX_CONTENT_LENGTH") or 0)
    if raw <= 0:
        return 0
    return max(1, raw // (1024 * 1024))


def _resolve_reply_target(me: User, car: Car, reply_public_id: str | None) -> Message | None:
    raw = (reply_public_id or "").strip()
    if not raw:
        return None
    msg = Message.query.filter_by(public_id=raw, car_id=car.id).first()
    if not msg:
        return None
    if me.id not in (msg.sender_id, msg.receiver_id):
        return None
    return msg


def _message_for_user(message_public_id: str, me: User) -> Message | None:
    raw = (message_public_id or "").strip()
    if not raw:
        return None
    msg = Message.query.filter_by(public_id=raw).first()
    if not msg:
        return None
    if me.id not in (msg.sender_id, msg.receiver_id):
        return None
    return msg


def _emit_message_update(msg: Message, event_name: str, payload: dict) -> None:
    """Emit edit/delete events only to the two conversation participants."""
    try:
        emit_message_to_participants(event_name, payload, message=msg)
    except Exception:
        pass


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

        blocked_ids = {
            b.blocked_id
            for b in BlockedUser.query.filter_by(blocker_id=me.id).all()
        }

        q = (
            Message.query.options(joinedload(Message.sender))
            .filter(or_(Message.sender_id == me.id, Message.receiver_id == me.id))
            .order_by(Message.created_at.desc())
            .limit(500)
            .all()
        )
        seen = set()
        conversation_rows = []
        other_ids = set()
        car_ids = set()
        for m in q:
            other_id = m.receiver_id if m.sender_id == me.id else m.sender_id
            if other_id in blocked_ids:
                continue
            key = (m.car_id or 0, int(other_id))
            if key in seen:
                continue
            seen.add(key)
            conversation_rows.append((m, other_id))
            other_ids.add(int(other_id))
            if m.car_id:
                car_ids.add(int(m.car_id))

        users_by_id = {
            u.id: u
            for u in User.query.filter(User.id.in_(other_ids)).all()
        } if other_ids else {}
        cars_by_id = {
            c.id: c
            for c in Car.query.options(selectinload(Car.images))
            .filter(Car.id.in_(car_ids))
            .all()
        } if car_ids else {}

        unread_by_key: dict[tuple[int, int], int] = {}
        if car_ids and other_ids:
            unread_rows = (
                db.session.query(
                    Message.car_id,
                    Message.sender_id,
                    func.count(Message.id),
                )
                .filter(
                    Message.receiver_id == me.id,
                    Message.is_read == False,  # noqa: E712
                    Message.car_id.in_(car_ids),
                    Message.sender_id.in_(other_ids),
                )
                .group_by(Message.car_id, Message.sender_id)
                .all()
            )
            for car_id, sender_id, cnt in unread_rows:
                unread_by_key[(int(car_id or 0), int(sender_id))] = int(cnt or 0)

        chats = []
        for m, other_id in conversation_rows:
            other = users_by_id.get(int(other_id))
            car = cars_by_id.get(int(m.car_id)) if m.car_id else None
            unread = unread_by_key.get((int(m.car_id or 0), int(other_id)), 0) if m.car_id else 0

            car_title = None
            car_image_url = None
            if car:
                car_title = getattr(car, "title", None) or ""
                if not car_title.strip():
                    car_title = f"{car.brand} {car.model} {car.year}".strip()
                car_image_url = _first_car_image_rel_path(car)

            chats.append(
                {
                    "conversation_id": int(m.car_id or 0),
                    "car_id": car.public_id if car else None,
                    "car_title": car_title,
                    "car_brand": car.brand if car else None,
                    "car_model": car.model if car else None,
                    "car_trim": getattr(car, "trim", None) if car else None,
                    "car_year": car.year if car else None,
                    "car_image_url": car_image_url,
                    "other_user": {
                        "id": other.public_id if other else None,
                        "name": (f"{other.first_name} {other.last_name}".strip() if other else None),
                    },
                    "last_message": {
                        "id": m.public_id,
                        "content": m.content,
                        "message_type": m.message_type,
                        "created_at": m.created_at.isoformat() if m.created_at else None,
                        "sender_id": m.sender.public_id if m.sender else None,
                    },
                    "unread_count": int(unread or 0),
                }
            )

        return jsonify(chats), 200
    except Exception:
        return jsonify({"message": "Failed to load chats"}), 500


@bp.route("/api/chat/<conversation_id>/messages", methods=["GET"])
@jwt_required()
def get_messages(conversation_id: str):
    """Fetch messages for a conversation with optional pagination.

    Query params:
        page (int, default 1): Page number (1-indexed).
        per_page (int, default 50): Messages per page (max 200).
        before (str, optional): ISO timestamp – fetch only messages created before this.
    """
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        car = _get_car_by_any_id(str(conversation_id))
        if not car:
            return jsonify({"message": "Listing not found"}), 404

        page = max(int(request.args.get("page", 1)), 1)
        per_page = min(max(int(request.args.get("per_page", 50)), 1), 200)

        blocked_ids = [
            b.blocked_id
            for b in BlockedUser.query.filter_by(blocker_id=me.id).all()
        ]

        base_q = Message.query.filter(
            Message.car_id == car.id,
            or_(Message.sender_id == me.id, Message.receiver_id == me.id),
        )
        if blocked_ids:
            base_q = base_q.filter(~Message.sender_id.in_(blocked_ids))

        before_raw = (request.args.get("before") or "").strip()
        if before_raw:
            try:
                before_dt = datetime.fromisoformat(before_raw.replace("Z", "+00:00"))
                base_q = base_q.filter(Message.created_at < before_dt)
            except Exception:
                pass

        total = base_q.count()
        msgs = (
            base_q.options(
                joinedload(Message.sender),
                joinedload(Message.receiver),
                joinedload(Message.car),
                joinedload(Message.reply_to).joinedload(Message.sender),
            )
            .order_by(Message.created_at.asc())
            .offset((page - 1) * per_page)
            .limit(per_page)
            .all()
        )

        # Mark messages to me as read and notify senders (read receipts).
        try:
            mark_messages_read_for_viewer(car, me)
        except Exception:
            db.session.rollback()

        return jsonify({
            "messages": [m.to_dict() for m in msgs],
            "page": page,
            "per_page": per_page,
            "total": total,
            "has_more": (page * per_page) < total,
        }), 200
    except Exception:
        return jsonify({"message": "Failed to load messages"}), 500


@bp.route("/api/chat/<conversation_id>/send", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=120, window_minutes=10, per_ip=False)
def send_message(conversation_id: str):
    """Send a message in a conversation (conversation_id == car public_id or numeric id)."""
    try:
        me = get_current_user()
        verify_err = phone_verification_required_response(me)
        if verify_err:
            return verify_err

        data = validate_input_sanitization(request.get_json(silent=True) or {})
        content = str(data.get("content") or "").strip()
        listing_preview = data.get("listing_preview")
        reply_to_public = str(data.get("reply_to_message_id") or "").strip()
        if not content:
            return jsonify({"message": "content required"}), 400
        if len(content) > 4000:
            return jsonify({"message": "content too long"}), 400

        car = _get_car_by_any_id(str(conversation_id))
        if not car:
            return jsonify({"message": "Listing not found"}), 404

        receiver_public = (data.get("receiver_id") or data.get("receiverId") or "").strip()
        receiver = _resolve_chat_receiver(me, car, receiver_public)

        if receiver is None:
            return jsonify({"message": "receiver_id required or not allowed"}), 400

        reply_to = _resolve_reply_target(me, car, reply_to_public)
        if reply_to_public and reply_to is None:
            return jsonify({"message": "Reply target not found"}), 404

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
        )
        db.session.add(msg)
        db.session.commit()
        db.session.refresh(msg)

        _count_buyer_message_metric(car, me)

        # Message is durably committed above; delivery side effects (Socket.IO,
        # Notification row, FCM push) are best-effort and independently
        # failure-isolated — they can never turn this successful send into a 500.
        # Reuse the payload deliver_message() already serialized (C-10 perf:
        # avoids re-presigning the same attachment(s) a second time for the
        # HTTP response).
        payload = deliver_message(msg, sender=me, receiver=receiver)

        return jsonify({"success": True, "message": payload}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to send message"}), 500


@bp.route("/api/chat/<conversation_id>/send_image", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=30, window_minutes=10, per_ip=False)
def send_image_message(conversation_id: str):
    """Send an image message. The image file is uploaded to R2 (or stored locally)."""
    try:
        me = get_current_user()
        verify_err = phone_verification_required_response(me)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(str(conversation_id))
        if not car:
            return jsonify({"message": "Listing not found"}), 404

        file = None
        for key in ("file", "image", "attachment"):
            if key in request.files:
                file = request.files[key]
                break
        if not file or not file.filename:
            return jsonify({"message": "No image file provided"}), 400

        receiver_public = (
            request.form.get("receiver_id") or request.form.get("receiverId") or ""
        ).strip()
        reply_to_public = (
            request.form.get("reply_to_message_id")
            or request.form.get("replyToMessageId")
            or ""
        ).strip()
        receiver = _resolve_chat_receiver(me, car, receiver_public)
        if receiver is None:
            return jsonify({"message": "receiver_id required or not allowed"}), 400

        reply_to = _resolve_reply_target(me, car, reply_to_public)
        if reply_to_public and reply_to is None:
            return jsonify({"message": "Reply target not found"}), 404

        try:
            attachment_url = _upload_chat_attachment(
                file,
                allowed_extensions=_CHAT_IMAGE_EXTENSIONS,
                subdir="chat_uploads",
                content_types={
                    ".jpg": "image/jpeg",
                    ".jpeg": "image/jpeg",
                    ".png": "image/png",
                    ".gif": "image/gif",
                    ".webp": "image/webp",
                },
            )
        except ValueError:
            return jsonify({"message": "Unsupported image format"}), 400

        content = (request.form.get("content") or "").strip() or "[Image]"

        msg = Message(
            sender_id=me.id,
            receiver_id=receiver.id,
            car_id=car.id,
            reply_to_id=reply_to.id if reply_to else None,
            reply_to=reply_to,
            content=content,
            message_type="image",
            attachment_url=attachment_url,
            is_read=False,
        )
        db.session.add(msg)
        db.session.commit()
        db.session.refresh(msg)
        _count_buyer_message_metric(car, me)

        # Message is durably committed above; delivery side effects (Socket.IO,
        # Notification row, FCM push) are best-effort and independently
        # failure-isolated — they can never turn this successful send into a 500.
        # Reuse the payload deliver_message() already serialized (C-10 perf:
        # avoids re-presigning the same attachment a second time for the
        # HTTP response).
        payload = deliver_message(msg, sender=me, receiver=receiver)

        return jsonify({"success": True, "message": payload}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to send image message"}), 500


@bp.route("/api/chat/<conversation_id>/send_video", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=20, window_minutes=10, per_ip=False)
def send_video_message(conversation_id: str):
    """Send a video message. The video file is uploaded to R2 (or stored locally)."""
    try:
        me = get_current_user()
        verify_err = phone_verification_required_response(me)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(str(conversation_id))
        if not car:
            return jsonify({"message": "Listing not found"}), 404

        file = None
        for key in ("file", "video", "attachment"):
            if key in request.files:
                file = request.files[key]
                break
        if not file or not file.filename:
            return jsonify({"message": "No video file provided"}), 400

        receiver_public = (
            request.form.get("receiver_id") or request.form.get("receiverId") or ""
        ).strip()
        reply_to_public = (
            request.form.get("reply_to_message_id")
            or request.form.get("replyToMessageId")
            or ""
        ).strip()
        receiver = _resolve_chat_receiver(me, car, receiver_public)
        if receiver is None:
            return jsonify({"message": "receiver_id required or not allowed"}), 400

        reply_to = _resolve_reply_target(me, car, reply_to_public)
        if reply_to_public and reply_to is None:
            return jsonify({"message": "Reply target not found"}), 404

        try:
            attachment_url = _upload_chat_attachment(
                file,
                allowed_extensions=_CHAT_VIDEO_EXTENSIONS,
                subdir="chat_videos",
                content_types={
                    ".mp4": "video/mp4",
                    ".mov": "video/quicktime",
                    ".avi": "video/x-msvideo",
                    ".mkv": "video/x-matroska",
                    ".webm": "video/webm",
                },
            )
        except ValueError:
            return jsonify({"message": "Unsupported video format"}), 400

        content = (request.form.get("content") or "").strip() or "[Video]"

        msg = Message(
            sender_id=me.id,
            receiver_id=receiver.id,
            car_id=car.id,
            reply_to_id=reply_to.id if reply_to else None,
            reply_to=reply_to,
            content=content,
            message_type="video",
            attachment_url=attachment_url,
            is_read=False,
        )
        db.session.add(msg)
        db.session.commit()
        db.session.refresh(msg)
        _count_buyer_message_metric(car, me)

        # Message is durably committed above; delivery side effects (Socket.IO,
        # Notification row, FCM push) are best-effort and independently
        # failure-isolated — they can never turn this successful send into a 500.
        # Reuse the payload deliver_message() already serialized (C-10 perf:
        # avoids re-presigning the same attachment a second time for the
        # HTTP response).
        payload = deliver_message(msg, sender=me, receiver=receiver)

        return jsonify({"success": True, "message": payload}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to send video message"}), 500


@bp.route("/api/chat/<conversation_id>/send_audio", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=30, window_minutes=10, per_ip=False)
def send_audio_message(conversation_id: str):
    """Send a voice message. The audio file is uploaded to R2 (or stored locally)."""
    try:
        me = get_current_user()
        verify_err = phone_verification_required_response(me)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(str(conversation_id))
        if not car:
            return jsonify({"message": "Listing not found"}), 404

        file = None
        for key in ("file", "audio", "attachment", "voice"):
            if key in request.files:
                file = request.files[key]
                break
        if not file or not file.filename:
            return jsonify({"message": "No audio file provided"}), 400

        receiver_public = (
            request.form.get("receiver_id") or request.form.get("receiverId") or ""
        ).strip()
        reply_to_public = (
            request.form.get("reply_to_message_id")
            or request.form.get("replyToMessageId")
            or ""
        ).strip()
        receiver = _resolve_chat_receiver(me, car, receiver_public)
        if receiver is None:
            return jsonify({"message": "receiver_id required or not allowed"}), 400

        reply_to = _resolve_reply_target(me, car, reply_to_public)
        if reply_to_public and reply_to is None:
            return jsonify({"message": "Reply target not found"}), 404

        try:
            attachment_url = _upload_chat_attachment(
                file,
                allowed_extensions=_CHAT_AUDIO_EXTENSIONS,
                subdir="chat_audio",
                content_types={
                    ".m4a": "audio/mp4",
                    ".aac": "audio/aac",
                    ".mp3": "audio/mpeg",
                    ".wav": "audio/wav",
                    ".ogg": "audio/ogg",
                    ".webm": "audio/webm",
                    ".amr": "audio/amr",
                    ".3gp": "audio/3gpp",
                },
            )
        except ValueError:
            return jsonify({"message": "Unsupported audio format"}), 400

        content = (request.form.get("content") or "").strip() or "[Voice message]"

        msg = Message(
            sender_id=me.id,
            receiver_id=receiver.id,
            car_id=car.id,
            reply_to_id=reply_to.id if reply_to else None,
            reply_to=reply_to,
            content=content,
            message_type="audio",
            attachment_url=attachment_url,
            is_read=False,
        )
        db.session.add(msg)
        db.session.commit()
        db.session.refresh(msg)
        _count_buyer_message_metric(car, me)

        # Message is durably committed above; delivery side effects (Socket.IO,
        # Notification row, FCM push) are best-effort and independently
        # failure-isolated — they can never turn this successful send into a 500.
        # Reuse the payload deliver_message() already serialized (C-10 perf:
        # avoids re-presigning the same attachment a second time for the
        # HTTP response).
        payload = deliver_message(msg, sender=me, receiver=receiver)

        return jsonify({"success": True, "message": payload}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to send audio message"}), 500


@bp.route("/api/chat/<conversation_id>/send_media_group", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=20, window_minutes=10, per_ip=False)
def send_media_group_message(conversation_id: str):
    """Send multiple images/videos/audio as one grouped chat message."""
    try:
        me = get_current_user()
        verify_err = phone_verification_required_response(me)
        if verify_err:
            return verify_err

        car = _get_car_by_any_id(str(conversation_id))
        if not car:
            return jsonify({"message": "Listing not found"}), 404

        files = request.files.getlist("attachments")
        if not files:
            for key in ("files", "media", "attachment", "file", "image", "video"):
                if key in request.files:
                    files.extend(request.files.getlist(key))
        files = [file for file in files if file and file.filename]
        if not files:
            return jsonify({"message": "No attachments provided"}), 400
        if len(files) > 10:
            return jsonify({"message": "You can send up to 10 attachments at once"}), 400

        receiver_public = (
            request.form.get("receiver_id") or request.form.get("receiverId") or ""
        ).strip()
        reply_to_public = (
            request.form.get("reply_to_message_id")
            or request.form.get("replyToMessageId")
            or ""
        ).strip()
        receiver = _resolve_chat_receiver(me, car, receiver_public)
        if receiver is None:
            return jsonify({"message": "receiver_id required or not allowed"}), 400

        reply_to = _resolve_reply_target(me, car, reply_to_public)
        if reply_to_public and reply_to is None:
            return jsonify({"message": "Reply target not found"}), 404

        listing_preview = None
        listing_preview_raw = (request.form.get("listing_preview") or "").strip()
        if listing_preview_raw:
            try:
                parsed = json.loads(listing_preview_raw)
                if isinstance(parsed, dict):
                    listing_preview = parsed
            except Exception:
                listing_preview = None

        attachments = []
        for file in files:
            try:
                attachments.append(_upload_chat_media_item(file))
            except ValueError:
                return jsonify({"message": "Unsupported attachment format"}), 400

        content = (request.form.get("content") or "").strip()
        if not content:
            if len(attachments) == 1 and attachments[0].get("type") == "audio":
                content = "[Voice message]"
            else:
                content = _default_media_group_content(len(attachments))

        if len(attachments) == 1:
            message_type = attachments[0].get("type") or "image"
        else:
            message_type = "media_group"

        msg = Message(
            sender_id=me.id,
            receiver_id=receiver.id,
            car_id=car.id,
            reply_to_id=reply_to.id if reply_to else None,
            reply_to=reply_to,
            content=content,
            message_type=message_type,
            attachment_url=attachments[0]["url"] if attachments else None,
            attachments=attachments,
            listing_preview=listing_preview,
            is_read=False,
        )
        db.session.add(msg)
        db.session.commit()
        db.session.refresh(msg)
        _count_buyer_message_metric(car, me)

        # Message is durably committed above; delivery side effects (Socket.IO,
        # Notification row, FCM push) are best-effort and independently
        # failure-isolated — they can never turn this successful send into a 500.
        # Reuse the payload deliver_message() already serialized (C-10 perf:
        # avoids re-presigning every attachment a second time for the HTTP
        # response).
        payload = deliver_message(msg, sender=me, receiver=receiver)

        return jsonify({"success": True, "message": payload}), 201
    except RequestEntityTooLarge:
        db.session.rollback()
        max_mb = _max_upload_mb()
        if max_mb > 0:
            return jsonify(
                {
                    "message": f"Selected files are too large. Maximum total upload size is {max_mb}MB.",
                }
            ), 413
        return jsonify({"message": "Selected files are too large."}), 413
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to send media group"}), 500


@bp.route("/api/chat/messages/<message_id>", methods=["PATCH"])
@jwt_required()
def edit_chat_message(message_id: str):
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        msg = _message_for_user(message_id, me)
        if msg is None:
            return jsonify({"message": "Message not found"}), 404
        if msg.sender_id != me.id:
            return jsonify({"message": "You can only edit your own messages"}), 403
        if msg.is_deleted:
            return jsonify({"message": "Deleted messages cannot be edited"}), 400

        data = validate_input_sanitization(request.get_json(silent=True) or {})
        content = str(data.get("content") or "").strip()
        if len(content) > 4000:
            return jsonify({"message": "content too long"}), 400

        # Current attachments that may be edited (removals only), preserved
        # in their original order — this ordered list is the ONLY source of
        # truth for real stored keys/legacy URLs.
        existing_items: list[dict] = []
        if isinstance(msg.attachments, list):
            existing_items.extend([x for x in msg.attachments if isinstance(x, dict)])
        if not existing_items and msg.attachment_url and msg.message_type in ("image", "video", "audio"):
            existing_items.append({"type": msg.message_type, "url": msg.attachment_url})

        existing_normalized: list[dict] = []
        for item in existing_items:
            url = str(item.get("url") or "").strip()
            if not url:
                continue
            typ = str(item.get("type") or "").strip().lower()
            existing_normalized.append({
                "type": typ if typ in ("image", "video", "audio") else "image",
                "url": url,
            })

        keep_raw = data.get("attachments", None)
        keep_items: list[dict] | None = None
        if keep_raw is not None:
            if not isinstance(keep_raw, list):
                return jsonify({"message": "attachments must be a list"}), 400
            if len(keep_raw) > 10:
                return jsonify({"message": "You can keep up to 10 attachments"}), 400
            if len(keep_raw) > len(existing_normalized):
                return jsonify({"message": "Invalid attachment sequence"}), 400

            # C-10: for chat media in the private bucket, the client only
            # ever sees a short-lived PRESIGNED `url` (never the stable
            # stored key), so the submitted `url`/`key` value is NEVER
            # trustworthy for matching and is deliberately ignored here.
            # Instead: the Flutter composer only ever *removes* items from
            # the attachment list it was shown (never reorders or adds
            # new ones — see `_editingKeepAttachments`), so the submission
            # is always an order-preserving SUBSEQUENCE of this message's
            # OWN existing attachments. We recover the real stored
            # key/type by walking `existing_normalized` in order and
            # matching each submitted item to the next not-yet-consumed
            # existing item of the same type (or the next item at all, if
            # no/invalid type was submitted). This can only ever resolve to
            # a key that already legitimately belonged to THIS message —
            # a client can never inject a foreign or guessed key this way,
            # regardless of what `url`/`key`/`type` values it submits.
            keep_items = []
            cursor = 0
            for raw in keep_raw:
                if not isinstance(raw, dict):
                    return jsonify({"message": "Invalid attachment entry"}), 400
                want_type = str(raw.get("type") or "").strip().lower()
                if want_type not in ("image", "video", "audio"):
                    want_type = None  # wildcard: match the next remaining item regardless of type

                match_index = None
                for i in range(cursor, len(existing_normalized)):
                    if want_type is None or existing_normalized[i]["type"] == want_type:
                        match_index = i
                        break
                if match_index is None:
                    return jsonify({"message": "Invalid attachment sequence"}), 400

                matched = existing_normalized[match_index]
                keep_items.append({"type": matched["type"], "url": matched["url"]})
                cursor = match_index + 1

        msg.content = content
        if keep_items is not None:
            msg.attachments = keep_items
            msg.attachment_url = keep_items[0]["url"] if keep_items else None
            if not keep_items:
                if content:
                    msg.message_type = "text"
                else:
                    return jsonify({"message": "Message cannot be empty"}), 400
            elif len(keep_items) == 1:
                msg.message_type = keep_items[0].get("type") or msg.message_type
            else:
                msg.message_type = "media_group"
        else:
            # Backwards-compatible behavior: plain text messages still require content.
            if not content and not existing_normalized:
                return jsonify({"message": "content required"}), 400

        msg.edited_at = utcnow()
        db.session.commit()

        payload = msg.to_dict()
        _emit_message_update(msg, "message_updated", payload)
        return jsonify({"success": True, "message": payload}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to edit message"}), 500


@bp.route("/api/chat/messages/<message_id>", methods=["DELETE"])
@jwt_required()
def delete_chat_message(message_id: str):
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        msg = _message_for_user(message_id, me)
        if msg is None:
            return jsonify({"message": "Message not found"}), 404
        if msg.sender_id != me.id:
            return jsonify({"message": "You can only delete your own messages"}), 403
        if msg.is_deleted:
            return jsonify({"success": True, "message": msg.to_dict()}), 200

        msg.content = ""
        msg.attachment_url = None
        msg.attachments = []
        msg.listing_preview = None
        msg.is_deleted = True
        msg.edited_at = utcnow()
        db.session.commit()

        payload = msg.to_dict()
        _emit_message_update(msg, "message_deleted", payload)
        return jsonify({"success": True, "message": payload}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to delete message"}), 500


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


# ---------- Block / Unblock / Report ----------

@bp.route("/api/users/<user_id>/block", methods=["POST"])
@jwt_required()
def block_user(user_id: str):
    """Block another user. Messages from them will be hidden."""
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        target = User.query.filter_by(public_id=user_id).first()
        if not target:
            return jsonify({"message": "User not found"}), 404
        if target.id == me.id:
            return jsonify({"message": "Cannot block yourself"}), 400

        existing = BlockedUser.query.filter_by(blocker_id=me.id, blocked_id=target.id).first()
        if existing:
            return jsonify({"message": "User already blocked"}), 200

        db.session.add(BlockedUser(blocker_id=me.id, blocked_id=target.id))
        db.session.commit()
        return jsonify({"message": "User blocked"}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to block user"}), 500


@bp.route("/api/users/<user_id>/unblock", methods=["POST"])
@jwt_required()
def unblock_user(user_id: str):
    """Unblock a previously blocked user."""
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        target = User.query.filter_by(public_id=user_id).first()
        if not target:
            return jsonify({"message": "User not found"}), 404

        b = BlockedUser.query.filter_by(blocker_id=me.id, blocked_id=target.id).first()
        if not b:
            return jsonify({"message": "User is not blocked"}), 200

        db.session.delete(b)
        db.session.commit()
        return jsonify({"message": "User unblocked"}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to unblock user"}), 500


@bp.route("/api/users/<user_id>/report", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=10, window_minutes=60, per_ip=False)
def report_user(user_id: str):
    """Report a user for inappropriate behavior."""
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        target = User.query.filter_by(public_id=user_id).first()
        if not target:
            return jsonify({"message": "User not found"}), 404
        if target.id == me.id:
            return jsonify({"message": "Cannot report yourself"}), 400

        data = request.get_json(silent=True) or {}
        reason = str(data.get("reason") or "").strip()
        if not reason:
            return jsonify({"message": "reason is required"}), 400
        if len(reason) > 200:
            reason = reason[:200]
        details = str(data.get("details") or "").strip()[:2000] or None

        db.session.add(UserReport(
            reporter_id=me.id,
            reported_id=target.id,
            reason=reason,
            details=details,
        ))
        db.session.commit()
        return jsonify({"message": "Report submitted. Thank you."}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to submit report"}), 500


@bp.route("/api/users/push_token", methods=["POST"])
@jwt_required()
def register_push_token():
    """Register or update the user's FCM push notification token."""
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        data = request.get_json(silent=True) or {}
        if data.get("enabled") is False:
            me.firebase_token = None
            db.session.commit()
            current_app.logger.info("Push disabled for user %s", me.public_id)
            return jsonify({"message": "Push disabled"}), 200

        token = str(data.get("token") or "").strip()
        if not token:
            return jsonify({"message": "token is required"}), 400

        me.firebase_token = token
        db.session.commit()
        current_app.logger.info(
            "Push token registered for user %s (prefix %s…)",
            me.public_id,
            token[:12],
        )
        return jsonify({"message": "Token registered", "registered": True}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to register token"}), 500


@bp.route("/api/users/push_status", methods=["GET"])
@jwt_required()
def push_status():
    """Whether the current user has an FCM token stored and server can send."""
    me = get_current_user()
    if not me:
        return jsonify({"message": "Unauthorized"}), 401
    token = (getattr(me, "firebase_token", None) or "").strip()
    return jsonify(
        {
            "registered": bool(token),
            "token_prefix": token[:16] if token else None,
            "server_fcm_ready": fcm_is_configured(),
        }
    ), 200


@bp.route("/api/users/push_test", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=10, window_minutes=30, per_ip=False)
def push_test():
    """Send a test FCM notification to the current user's device."""
    me = get_current_user()
    if not me:
        return jsonify({"message": "Unauthorized"}), 401
    token = (getattr(me, "firebase_token", None) or "").strip()
    if not token:
        return jsonify(
            {
                "message": "No push token on server. Open CarNet, allow notifications, log out, log in again.",
            }
        ), 400
    if not fcm_is_configured():
        return jsonify(
            {
                "message": (
                    "Server FCM not configured. On Render set FIREBASE_SERVICE_ACCOUNT_BASE64 "
                    "(or redeploy latest API from main)."
                ),
            }
        ), 503
    ok = send_push(
        token,
        title="CarNet test",
        body="If you see this, push notifications are working.",
        data={"type": "push_test"},
    )
    if not ok:
        hint = fcm_send_error_hint(last_fcm_send_error())
        return jsonify({"message": hint}), 503
    return jsonify({"message": "Test notification sent"}), 200


@bp.route("/api/users/blocked", methods=["GET"])
@jwt_required()
def list_blocked_users():
    """Return a list of blocked user IDs for the current user."""
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

        blocks = BlockedUser.query.filter_by(blocker_id=me.id).all()
        blocked_ids = []
        for b in blocks:
            u = db.session.get(User, b.blocked_id)
            if u:
                blocked_ids.append(u.public_id)
        return jsonify({"blocked_users": blocked_ids}), 200
    except Exception:
        return jsonify({"message": "Failed to load blocked users"}), 500

