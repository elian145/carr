from __future__ import annotations

import logging

from flask import Blueprint, jsonify, request

from ..auth import admin_required
from ..models import Car, Message, Notification, User, UserAction, db

bp = Blueprint("admin", __name__, url_prefix="/api/admin")
logger = logging.getLogger(__name__)


@bp.route("/dashboard", methods=["GET"])
@admin_required
def dashboard():
    """Admin dashboard stats (JSON)."""
    try:
        total_users = User.query.count()
        active_users = User.query.filter_by(is_active=True).count()
        total_cars = Car.query.count()
        active_cars = Car.query.filter_by(is_active=True).count()
        total_messages = Message.query.count()
        total_notifications = Notification.query.count()

        recent_users = User.query.order_by(User.created_at.desc()).limit(10).all()
        recent_cars = Car.query.order_by(Car.created_at.desc()).limit(10).all()
        recent_messages = Message.query.order_by(Message.created_at.desc()).limit(10).all()

        user_actions = (
            db.session.query(UserAction.action_type, db.func.count(UserAction.id).label("count"))
            .group_by(UserAction.action_type)
            .all()
        )

        return (
            jsonify(
                {
                    "stats": {
                        "total_users": total_users,
                        "active_users": active_users,
                        "total_cars": total_cars,
                        "active_cars": active_cars,
                        "total_messages": total_messages,
                        "total_notifications": total_notifications,
                    },
                    "recent_activity": {
                        "users": [u.to_dict(include_private=True) for u in recent_users],
                        "cars": [c.to_dict() for c in recent_cars],
                        "messages": [m.to_dict() for m in recent_messages],
                    },
                    "user_actions": [{"action_type": a.action_type, "count": int(a.count)} for a in user_actions],
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin dashboard error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get dashboard statistics"}), 500


@bp.route("/users", methods=["GET"])
@admin_required
def users():
    """List users with pagination and optional search."""
    try:
        page = request.args.get("page", 1, type=int)
        per_page = request.args.get("per_page", 20, type=int)
        search = (request.args.get("search") or "").strip()

        q = User.query
        if search:
            like = f"%{search}%"
            q = q.filter(
                (User.username.ilike(like))
                | (User.email.ilike(like))
                | (User.first_name.ilike(like))
                | (User.last_name.ilike(like))
            )

        pagination = q.order_by(User.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
        items = [u.to_dict(include_private=True) for u in pagination.items]
        return (
            jsonify(
                {
                    "users": items,
                    "pagination": {
                        "page": page,
                        "per_page": per_page,
                        "total": pagination.total,
                        "pages": pagination.pages,
                        "has_next": pagination.has_next,
                        "has_prev": pagination.has_prev,
                    },
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin get users error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get users"}), 500


@bp.route("/users/<user_id>", methods=["GET"])
@admin_required
def user_detail(user_id: str):
    """Get one user detail + their cars + recent actions."""
    try:
        user = User.query.filter_by(public_id=user_id).first()
        if not user:
            return jsonify({"message": "User not found"}), 404

        cars = Car.query.filter_by(seller_id=user.id).all()
        recent_actions = (
            UserAction.query.filter_by(user_id=user.id).order_by(UserAction.created_at.desc()).limit(20).all()
        )
        return (
            jsonify(
                {
                    "user": user.to_dict(include_private=True),
                    "cars": [c.to_dict() for c in cars],
                    "recent_actions": [a.to_dict() for a in recent_actions],
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin get user error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get user"}), 500


@bp.route("/cars", methods=["GET"])
@admin_required
def cars():
    """List cars with pagination and optional filters."""
    try:
        page = request.args.get("page", 1, type=int)
        per_page = request.args.get("per_page", 20, type=int)
        active_only = request.args.get("active_only", "false").strip().lower() in ("1", "true", "yes", "on")

        q = Car.query
        if active_only:
            q = q.filter_by(is_active=True)

        pagination = q.order_by(Car.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
        items = [c.to_dict() for c in pagination.items]
        return (
            jsonify(
                {
                    "cars": items,
                    "pagination": {
                        "page": page,
                        "per_page": per_page,
                        "total": pagination.total,
                        "pages": pagination.pages,
                        "has_next": pagination.has_next,
                        "has_prev": pagination.has_prev,
                    },
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin get cars error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get cars"}), 500


@bp.route("/messages", methods=["GET"])
@admin_required
def messages():
    """List recent messages."""
    try:
        page = request.args.get("page", 1, type=int)
        per_page = request.args.get("per_page", 50, type=int)
        pagination = Message.query.order_by(Message.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
        return (
            jsonify(
                {
                    "messages": [m.to_dict() for m in pagination.items],
                    "pagination": {
                        "page": page,
                        "per_page": per_page,
                        "total": pagination.total,
                        "pages": pagination.pages,
                        "has_next": pagination.has_next,
                        "has_prev": pagination.has_prev,
                    },
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin get messages error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get messages"}), 500


@bp.route("/notifications", methods=["GET"])
@admin_required
def notifications():
    """List recent notifications."""
    try:
        page = request.args.get("page", 1, type=int)
        per_page = request.args.get("per_page", 50, type=int)
        pagination = Notification.query.order_by(Notification.created_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )
        return (
            jsonify(
                {
                    "notifications": [n.to_dict() for n in pagination.items],
                    "pagination": {
                        "page": page,
                        "per_page": per_page,
                        "total": pagination.total,
                        "pages": pagination.pages,
                        "has_next": pagination.has_next,
                        "has_prev": pagination.has_prev,
                    },
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin get notifications error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get notifications"}), 500


@bp.route("/user-actions", methods=["GET"])
@admin_required
def user_actions():
    """List user action audit records."""
    try:
        page = request.args.get("page", 1, type=int)
        per_page = request.args.get("per_page", 50, type=int)
        pagination = UserAction.query.order_by(UserAction.created_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )
        return (
            jsonify(
                {
                    "actions": [a.to_dict() for a in pagination.items],
                    "pagination": {
                        "page": page,
                        "per_page": per_page,
                        "total": pagination.total,
                        "pages": pagination.pages,
                        "has_next": pagination.has_next,
                        "has_prev": pagination.has_prev,
                    },
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin get user-actions error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get user actions"}), 500

