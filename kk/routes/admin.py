from __future__ import annotations

import logging

from flask import Blueprint, jsonify, request

from ..auth import admin_required, get_current_user, log_user_action
from ..models import Car, Message, Notification, User, UserAction, db
from ..time_utils import utcnow

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


@bp.route("/dealers/pending", methods=["GET"])
@admin_required
def dealers_pending():
    """List users waiting for dealer verification (`dealer_status == pending`)."""
    try:
        rows = (
            User.query.filter(User.dealer_status == "pending")
            .order_by(User.created_at.asc())
            .all()
        )
        return jsonify({"dealers": [u.to_dict(include_private=True) for u in rows]}), 200
    except Exception as e:
        logger.error("admin dealers_pending error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list pending dealers"}), 500


@bp.route("/dealers/<user_public_id>/approve", methods=["POST"])
@admin_required
def dealers_approve(user_public_id: str):
    """Approve a pending dealer application."""
    try:
        admin_user = get_current_user()
        if not admin_user:
            return jsonify({"message": "Unauthorized"}), 401
        pid = (user_public_id or "").strip()
        if not pid:
            return jsonify({"message": "User id is required"}), 400
        target = User.query.filter_by(public_id=pid).first()
        if not target:
            return jsonify({"message": "User not found"}), 404
        if getattr(target, "dealer_status", None) != "pending":
            return jsonify({"message": "This user is not pending dealer approval"}), 400

        target.account_type = "dealer"
        target.dealer_status = "approved"
        target.updated_at = utcnow()
        db.session.commit()

        log_user_action(
            admin_user,
            "dealer_approve",
            target_type="user",
            target_id=pid,
            metadata={"approved_user_internal_id": target.id},
        )
        return jsonify({"message": "Dealer approved", "user": target.to_dict(include_private=True)}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin dealers_approve error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to approve dealer"}), 500


@bp.route("/dealers/<user_public_id>/reject", methods=["POST"])
@admin_required
def dealers_reject(user_public_id: str):
    """Reject a pending dealer application (user stays a normal account)."""
    try:
        admin_user = get_current_user()
        if not admin_user:
            return jsonify({"message": "Unauthorized"}), 401
        pid = (user_public_id or "").strip()
        if not pid:
            return jsonify({"message": "User id is required"}), 400
        target = User.query.filter_by(public_id=pid).first()
        if not target:
            return jsonify({"message": "User not found"}), 404
        if getattr(target, "dealer_status", None) != "pending":
            return jsonify({"message": "This user is not pending dealer approval"}), 400

        data = request.get_json(silent=True) or {}
        reason = (data.get("reason") or "").strip() or None

        target.account_type = "user"
        target.dealer_status = "rejected"
        target.updated_at = utcnow()
        db.session.commit()

        log_user_action(
            admin_user,
            "dealer_reject",
            target_type="user",
            target_id=pid,
            metadata={"reason": reason} if reason else None,
        )
        return jsonify({"message": "Dealer application rejected", "user": target.to_dict(include_private=True)}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin dealers_reject error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to reject dealer application"}), 500

