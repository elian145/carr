from __future__ import annotations

from datetime import datetime
import json
import os
import secrets

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import jwt_required
from sqlalchemy import func, or_
from werkzeug.exceptions import RequestEntityTooLarge

from ..auth import get_current_user
from ..extensions import socketio
from ..models import BlockedUser, Car, Message, User, UserReport, db
from ..push import send_push
from ..security import rate_limit, validate_input_sanitization

bp = Blueprint("chat", __name__)

_CHAT_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}
_CHAT_VIDEO_EXTENSIONS = {".mp4", ".mov", ".avi", ".mkv", ".webm"}
_CHAT_ATTACHMENT_EXTENSIONS = _CHAT_IMAGE_EXTENSIONS | _CHAT_VIDEO_EXTENSIONS


def _resolve_chat_receiver(me: User, car: Car, receiver_public: str | None) -> User | None:
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
    return receiver


def _upload_chat_attachment(file_storage, *, allowed_extensions: set[str], subdir: str, content_types: dict[str, str]) -> str:
    ext = os.path.splitext(file_storage.filename or "")[1].lower()
    if ext not in allowed_extensions:
        raise ValueError("Unsupported attachment format")

    r2_bucket = current_app.config.get("R2_BUCKET_NAME")
    r2_account = current_app.config.get("R2_ACCOUNT_ID")
    r2_key = current_app.config.get("R2_ACCESS_KEY_ID")
    r2_secret = current_app.config.get("R2_SECRET_ACCESS_KEY")
    r2_public = (current_app.config.get("R2_PUBLIC_URL") or "").strip().rstrip("/")

    if r2_bucket and r2_account and r2_key and r2_secret and r2_public:
        import boto3
        from botocore.config import Config as BotoConfig

        region = (os.environ.get("R2_REGION") or "auto").strip() or "auto"
        endpoint = f"https://{r2_account}.r2.cloudflarestorage.com"
        s3 = boto3.client(
            "s3",
            region_name=region,
            endpoint_url=endpoint,
            aws_access_key_id=r2_key,
            aws_secret_access_key=r2_secret,
            config=BotoConfig(signature_version="s3v4"),
        )
        obj_key = f"{subdir}/{secrets.token_hex(16)}{ext}"
        file_storage.seek(0)
        body = file_storage.read()
        s3.put_object(
            Bucket=r2_bucket,
            Key=obj_key,
            Body=body,
            ContentType=content_types.get(ext, "application/octet-stream"),
        )
        return f"{r2_public}/{obj_key}"

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
    raise ValueError("Unsupported attachment format")


def _default_media_group_content(count: int) -> str:
    return f"[{max(count, 1)} attachments]"


def _max_upload_mb() -> int:
    raw = int(current_app.config.get("MAX_CONTENT_LENGTH") or 0)
    if raw <= 0:
        return 0
    return max(1, raw // (1024 * 1024))


def _room_for_car_public_id(car_public_id: str) -> str:
    return f"chat:{car_public_id}"


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


def _emit_message_update(car: Car, event_name: str, payload: dict) -> None:
    try:
        socketio.emit(event_name, payload, room=_room_for_car_public_id(car.public_id))
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
            Message.query.filter(or_(Message.sender_id == me.id, Message.receiver_id == me.id))
            .order_by(Message.created_at.desc())
            .limit(500)
            .all()
        )
        seen = set()
        chats = []
        for m in q:
            other_id = m.receiver_id if m.sender_id == me.id else m.sender_id
            if other_id in blocked_ids:
                continue
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

            car_title = None
            if car:
                car_title = getattr(car, "title", None) or ""
                if not car_title.strip():
                    car_title = f"{car.brand} {car.model} {car.year}".strip()

            chats.append(
                {
                    "conversation_id": int(m.car_id or 0),
                    "car_id": car.public_id if car else None,
                    "car_title": car_title,
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
            base_q.order_by(Message.created_at.asc())
            .offset((page - 1) * per_page)
            .limit(per_page)
            .all()
        )

        # Mark messages to me as read (best-effort).
        try:
            Message.query.filter(
                Message.car_id == car.id,
                Message.receiver_id == me.id,
                Message.is_read == False,  # noqa: E712
            ).update({"is_read": True})
            db.session.commit()
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
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

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
                        Message.car_id == car.id,
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

        # Best-effort FCM push to receiver's device.
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

        return jsonify({"success": True, "message": msg.to_dict()}), 201
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
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

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
            return jsonify({"message": "receiver_id required"}), 400

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
        return jsonify({"success": True, "message": msg.to_dict()}), 201
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
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

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
            return jsonify({"message": "receiver_id required"}), 400

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
        return jsonify({"success": True, "message": msg.to_dict()}), 201
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to send video message"}), 500


@bp.route("/api/chat/<conversation_id>/send_media_group", methods=["POST"])
@jwt_required()
@rate_limit(max_requests=20, window_minutes=10, per_ip=False)
def send_media_group_message(conversation_id: str):
    """Send multiple images/videos as one grouped chat message."""
    try:
        me = get_current_user()
        if not me:
            return jsonify({"message": "Unauthorized"}), 401

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
            return jsonify({"message": "receiver_id required"}), 400

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

        content = (request.form.get("content") or "").strip() or _default_media_group_content(len(attachments))

        msg = Message(
            sender_id=me.id,
            receiver_id=receiver.id,
            car_id=car.id,
            reply_to_id=reply_to.id if reply_to else None,
            reply_to=reply_to,
            content=content,
            message_type="media_group",
            attachment_url=attachments[0]["url"] if attachments else None,
            attachments=attachments,
            listing_preview=listing_preview,
            is_read=False,
        )
        db.session.add(msg)
        db.session.commit()
        db.session.refresh(msg)

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

        return jsonify({"success": True, "message": msg.to_dict()}), 201
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
        if msg.attachments or msg.attachment_url or msg.listing_preview or msg.message_type != "text":
            return jsonify({"message": "Only text messages can be edited"}), 400

        data = validate_input_sanitization(request.get_json(silent=True) or {})
        content = str(data.get("content") or "").strip()
        if not content:
            return jsonify({"message": "content required"}), 400
        if len(content) > 4000:
            return jsonify({"message": "content too long"}), 400

        msg.content = content
        msg.edited_at = datetime.utcnow()
        db.session.commit()

        car = db.session.get(Car, msg.car_id) if msg.car_id else None
        payload = msg.to_dict()
        if car:
            _emit_message_update(car, "message_updated", payload)
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
        msg.edited_at = datetime.utcnow()
        db.session.commit()

        car = db.session.get(Car, msg.car_id) if msg.car_id else None
        payload = msg.to_dict()
        if car:
            _emit_message_update(car, "message_deleted", payload)
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
        token = str(data.get("token") or "").strip()
        if not token:
            return jsonify({"message": "token is required"}), 400

        me.firebase_token = token
        db.session.commit()
        return jsonify({"message": "Token registered"}), 200
    except Exception:
        db.session.rollback()
        return jsonify({"message": "Failed to register token"}), 500


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

