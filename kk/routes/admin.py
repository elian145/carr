from __future__ import annotations

import logging

from flask import Blueprint, jsonify, request
from sqlalchemy import asc, desc, func, or_
from sqlalchemy.orm import joinedload

from ..auth import admin_required, get_current_user, log_user_action
from ..models import (
    Car,
    ListingAnalytics,
    ListingReport,
    Message,
    Notification,
    SavedSearch,
    User,
    UserAction,
    UserReport,
    db,
)
from ..time_utils import utcnow

bp = Blueprint("admin", __name__, url_prefix="/api/admin")
logger = logging.getLogger(__name__)


def _pagination_dict(pagination, page: int, per_page: int) -> dict:
    return {
        "page": page,
        "per_page": per_page,
        "total": pagination.total,
        "pages": pagination.pages,
        "has_next": pagination.has_next,
        "has_prev": pagination.has_prev,
    }


def _bool_param(name: str) -> bool | None:
    raw = (request.args.get(name) or "").strip().lower()
    if raw in ("1", "true", "yes", "on"):
        return True
    if raw in ("0", "false", "no", "off"):
        return False
    return None


def _find_car(car_id: str) -> Car | None:
    cid = (car_id or "").strip()
    if not cid:
        return None
    car = Car.query.filter_by(public_id=cid).first()
    if car:
        return car
    if cid.isdigit():
        return Car.query.filter_by(id=int(cid)).first()
    return None


def _find_user(public_id: str) -> User | None:
    pid = (public_id or "").strip()
    if not pid:
        return None
    return User.query.filter_by(public_id=pid).first()


def _action_to_admin_dict(action: UserAction) -> dict:
    data = action.to_dict()
    user = User.query.get(action.user_id) if action.user_id else None
    data["user_public_id"] = user.public_id if user else None
    data["user_username"] = user.username if user else None
    return data


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

        pending_user_reports = UserReport.query.filter_by(status="pending").count()
        pending_listing_reports = ListingReport.query.filter_by(status="pending").count()
        pending_dealers = User.query.filter(User.dealer_status == "pending").count()
        dealer_accounts = User.query.filter(User.account_type == "dealer").count()
        featured_cars = Car.query.filter_by(is_featured=True, is_active=True).count()
        engagement = db.session.query(
            func.coalesce(func.sum(ListingAnalytics.views), 0),
            func.coalesce(func.sum(ListingAnalytics.messages), 0),
            func.coalesce(func.sum(ListingAnalytics.calls), 0),
            func.coalesce(func.sum(ListingAnalytics.favorites), 0),
        ).one()

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
                        "inactive_users": total_users - active_users,
                        "total_cars": total_cars,
                        "active_cars": active_cars,
                        "inactive_cars": total_cars - active_cars,
                        "total_messages": total_messages,
                        "total_notifications": total_notifications,
                        "pending_reports": pending_user_reports + pending_listing_reports,
                        "pending_user_reports": pending_user_reports,
                        "pending_listing_reports": pending_listing_reports,
                        "pending_dealers": pending_dealers,
                        "dealer_accounts": dealer_accounts,
                        "featured_cars": featured_cars,
                        "total_listing_views": int(engagement[0] or 0),
                        "total_listing_messages": int(engagement[1] or 0),
                        "total_listing_calls": int(engagement[2] or 0),
                        "total_listing_favorites": int(engagement[3] or 0),
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
        per_page = min(max(request.args.get("per_page", 20, type=int), 1), 100)
        search = (request.args.get("search") or "").strip()
        account_type = (request.args.get("account_type") or "").strip().lower()
        dealer_status = (request.args.get("dealer_status") or "").strip().lower()
        is_active = _bool_param("is_active")
        is_admin = _bool_param("is_admin")

        q = User.query
        if search:
            like = f"%{search}%"
            q = q.filter(
                (User.username.ilike(like))
                | (User.email.ilike(like))
                | (User.first_name.ilike(like))
                | (User.last_name.ilike(like))
                | (User.phone_number.ilike(like))
            )
        if account_type and account_type != "all":
            q = q.filter(User.account_type == account_type)
        if dealer_status and dealer_status != "all":
            q = q.filter(User.dealer_status == dealer_status)
        if is_active is not None:
            q = q.filter(User.is_active == is_active)
        if is_admin is not None:
            q = q.filter(User.is_admin == is_admin)

        pagination = q.order_by(User.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
        items = [u.to_dict(include_private=True) for u in pagination.items]
        return (
            jsonify(
                {
                    "users": items,
                    "pagination": _pagination_dict(pagination, page, per_page),
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
        per_page = min(max(request.args.get("per_page", 20, type=int), 1), 100)
        search = (request.args.get("search") or "").strip()
        brand = (request.args.get("brand") or "").strip()
        status = (request.args.get("status") or "").strip().lower()
        active_only = request.args.get("active_only", "false").strip().lower() in ("1", "true", "yes", "on")
        is_featured = _bool_param("is_featured")
        min_price = request.args.get("min_price", type=float)
        max_price = request.args.get("max_price", type=float)
        sort = (request.args.get("sort") or "created_desc").strip().lower()

        q = Car.query
        if search:
            like = f"%{search}%"
            q = q.filter(
                (Car.title.ilike(like))
                | (Car.brand.ilike(like))
                | (Car.model.ilike(like))
                | (Car.location.ilike(like))
                | (Car.public_id.ilike(like))
            )
        if brand and brand != "all":
            q = q.filter(Car.brand.ilike(brand))
        if status and status != "all":
            q = q.filter(Car.status == status)
        if active_only:
            q = q.filter_by(is_active=True)
        if is_featured is not None:
            q = q.filter(Car.is_featured == is_featured)
        if min_price is not None:
            q = q.filter(Car.price >= min_price)
        if max_price is not None:
            q = q.filter(Car.price <= max_price)

        order_map = {
            "created_desc": desc(Car.created_at),
            "created_asc": asc(Car.created_at),
            "price_desc": desc(Car.price),
            "price_asc": asc(Car.price),
            "views_desc": desc(Car.views_count),
        }
        order_by = order_map.get(sort, desc(Car.created_at))

        pagination = q.order_by(order_by).paginate(page=page, per_page=per_page, error_out=False)
        items = [c.to_dict() for c in pagination.items]
        return (
            jsonify(
                {
                    "cars": items,
                    "pagination": _pagination_dict(pagination, page, per_page),
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
        per_page = min(max(request.args.get("per_page", 50, type=int), 1), 100)
        search = (request.args.get("search") or "").strip()
        is_read = _bool_param("is_read")
        car_id = (request.args.get("car_id") or "").strip()

        q = Message.query.filter(Message.is_deleted.is_(False))
        if search:
            q = q.filter(Message.content.ilike(f"%{search}%"))
        if is_read is not None:
            q = q.filter(Message.is_read == is_read)
        if car_id:
            car = _find_car(car_id)
            if car:
                q = q.filter(Message.car_id == car.id)

        pagination = q.order_by(Message.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
        return (
            jsonify(
                {
                    "messages": [m.to_dict() for m in pagination.items],
                    "pagination": _pagination_dict(pagination, page, per_page),
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
        per_page = min(max(request.args.get("per_page", 50, type=int), 1), 100)
        notification_type = (request.args.get("type") or "").strip()
        is_read = _bool_param("is_read")

        q = Notification.query
        if notification_type and notification_type != "all":
            q = q.filter(Notification.notification_type == notification_type)
        if is_read is not None:
            q = q.filter(Notification.is_read == is_read)

        pagination = q.order_by(Notification.created_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )
        rows = []
        for n in pagination.items:
            row = n.to_dict()
            u = User.query.get(n.user_id)
            row["user_public_id"] = u.public_id if u else None
            row["user_username"] = u.username if u else None
            rows.append(row)
        return (
            jsonify(
                {
                    "notifications": rows,
                    "pagination": _pagination_dict(pagination, page, per_page),
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
        per_page = min(max(request.args.get("per_page", 50, type=int), 1), 100)
        action_type = (request.args.get("action_type") or "").strip()
        user_id = (request.args.get("user_id") or "").strip()
        target_type = (request.args.get("target_type") or "").strip()

        q = UserAction.query
        if action_type:
            q = q.filter(UserAction.action_type == action_type)
        if target_type:
            q = q.filter(UserAction.target_type == target_type)
        if user_id:
            user = _find_user(user_id)
            if user:
                q = q.filter(UserAction.user_id == user.id)

        pagination = q.order_by(UserAction.created_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )
        return (
            jsonify(
                {
                    "actions": [_action_to_admin_dict(a) for a in pagination.items],
                    "pagination": _pagination_dict(pagination, page, per_page),
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


_VALID_REPORT_STATUSES = frozenset({"pending", "reviewed", "resolved", "dismissed"})


def _apply_report_status(report, status: str, admin_notes: str | None):
    report.status = status
    report.admin_notes = admin_notes
    if status in ("resolved", "dismissed"):
        report.resolved_at = utcnow()
    else:
        report.resolved_at = None


@bp.route("/reports", methods=["GET"])
@admin_required
def list_reports():
    """List user and listing reports for moderation."""
    try:
        page = request.args.get("page", 1, type=int)
        per_page = min(max(request.args.get("per_page", 20, type=int), 1), 100)
        status = (request.args.get("status") or "pending").strip().lower()
        report_type = (request.args.get("type") or "all").strip().lower()

        user_q = UserReport.query
        listing_q = ListingReport.query
        if status and status != "all":
            user_q = user_q.filter_by(status=status)
            listing_q = listing_q.filter_by(status=status)

        user_reports = []
        listing_reports = []
        if report_type in ("all", "user"):
            user_reports = (
                user_q.options(
                    joinedload(UserReport.reporter),
                    joinedload(UserReport.reported),
                )
                .order_by(UserReport.created_at.desc())
                .limit(200)
                .all()
            )
        if report_type in ("all", "listing"):
            listing_reports = (
                listing_q.options(
                    joinedload(ListingReport.reporter),
                    joinedload(ListingReport.car),
                )
                .order_by(ListingReport.created_at.desc())
                .limit(200)
                .all()
            )

        combined = [r.to_admin_dict() for r in user_reports] + [
            r.to_admin_dict() for r in listing_reports
        ]
        combined.sort(key=lambda x: x.get("created_at") or "", reverse=True)

        total = len(combined)
        start = (page - 1) * per_page
        end = start + per_page
        items = combined[start:end]
        pages = max(1, (total + per_page - 1) // per_page)

        return (
            jsonify(
                {
                    "reports": items,
                    "pagination": {
                        "page": page,
                        "per_page": per_page,
                        "total": total,
                        "pages": pages,
                        "has_next": end < total,
                        "has_prev": page > 1,
                    },
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin list_reports error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list reports"}), 500


@bp.route("/reports/user/<int:report_id>", methods=["PATCH"])
@admin_required
def update_user_report(report_id: int):
    """Resolve or dismiss a user report."""
    try:
        report = UserReport.query.get(report_id)
        if not report:
            return jsonify({"message": "Report not found"}), 404
        data = request.get_json(silent=True) or {}
        status = (data.get("status") or "").strip().lower()
        if status not in _VALID_REPORT_STATUSES:
            return jsonify({"message": "Invalid status"}), 400
        admin_notes = (data.get("admin_notes") or "").strip()[:2000] or None
        _apply_report_status(report, status, admin_notes)
        db.session.commit()
        return jsonify({"report": report.to_admin_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update_user_report error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update report"}), 500


@bp.route("/reports/listing/<int:report_id>", methods=["PATCH"])
@admin_required
def update_listing_report(report_id: int):
    """Resolve or dismiss a listing report."""
    try:
        report = ListingReport.query.get(report_id)
        if not report:
            return jsonify({"message": "Report not found"}), 404
        data = request.get_json(silent=True) or {}
        status = (data.get("status") or "").strip().lower()
        if status not in _VALID_REPORT_STATUSES:
            return jsonify({"message": "Invalid status"}), 400
        admin_notes = (data.get("admin_notes") or "").strip()[:2000] or None
        _apply_report_status(report, status, admin_notes)
        db.session.commit()
        return jsonify({"report": report.to_admin_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update_listing_report error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update report"}), 500


@bp.route("/search", methods=["GET"])
@admin_required
def global_search():
    """Search users and listings from a single query."""
    try:
        q = (request.args.get("q") or "").strip()
        limit = min(max(request.args.get("limit", 10, type=int), 1), 50)
        if not q:
            return jsonify({"users": [], "cars": []}), 200
        like = f"%{q}%"
        users = (
            User.query.filter(
                (User.username.ilike(like))
                | (User.email.ilike(like))
                | (User.phone_number.ilike(like))
                | (User.first_name.ilike(like))
                | (User.last_name.ilike(like))
            )
            .order_by(User.created_at.desc())
            .limit(limit)
            .all()
        )
        cars = (
            Car.query.filter(
                (Car.title.ilike(like))
                | (Car.brand.ilike(like))
                | (Car.model.ilike(like))
                | (Car.location.ilike(like))
                | (Car.public_id.ilike(like))
            )
            .order_by(Car.created_at.desc())
            .limit(limit)
            .all()
        )
        return (
            jsonify(
                {
                    "users": [u.to_dict(include_private=True) for u in users],
                    "cars": [c.to_dict() for c in cars],
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin global_search error: %s", e, exc_info=True)
        return jsonify({"message": "Search failed"}), 500


@bp.route("/cars/<car_id>", methods=["GET"])
@admin_required
def car_detail(car_id: str):
    """Listing detail with seller and engagement analytics."""
    try:
        car = _find_car(car_id)
        if not car:
            return jsonify({"message": "Listing not found"}), 404
        analytics = ListingAnalytics.query.filter_by(car_id=car.id).first()
        reports = ListingReport.query.filter_by(car_id=car.id).order_by(ListingReport.created_at.desc()).limit(20).all()
        return (
            jsonify(
                {
                    "car": car.to_dict(include_private=True),
                    "analytics": analytics.to_dict() if analytics else None,
                    "reports": [r.to_admin_dict() for r in reports],
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin car_detail error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get listing"}), 500


@bp.route("/cars/<car_id>/status", methods=["PATCH"])
@admin_required
def update_car_status(car_id: str):
    """Activate/deactivate or change listing status."""
    try:
        admin_user = get_current_user()
        car = _find_car(car_id)
        if not car:
            return jsonify({"message": "Listing not found"}), 404
        data = request.get_json(silent=True) or {}
        if "is_active" in data:
            car.is_active = bool(data["is_active"])
        if "status" in data and str(data["status"]).strip():
            car.status = str(data["status"]).strip()
        if "is_featured" in data:
            car.is_featured = bool(data["is_featured"])
        car.updated_at = utcnow()
        db.session.commit()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_update_listing",
                target_type="car",
                target_id=car.public_id or str(car.id),
                metadata=data,
            )
        return jsonify({"car": car.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update_car_status error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update listing"}), 500


@bp.route("/users/<user_id>/status", methods=["PATCH"])
@admin_required
def update_user_status(user_id: str):
    """Activate/deactivate a user account."""
    try:
        admin_user = get_current_user()
        user = _find_user(user_id)
        if not user:
            return jsonify({"message": "User not found"}), 404
        data = request.get_json(silent=True) or {}
        if "is_active" in data:
            user.is_active = bool(data["is_active"])
        user.updated_at = utcnow()
        db.session.commit()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_update_user",
                target_type="user",
                target_id=user.public_id,
                metadata=data,
            )
        return jsonify({"user": user.to_dict(include_private=True)}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update_user_status error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update user"}), 500


@bp.route("/dealers", methods=["GET"])
@admin_required
def dealers_list():
    """List dealer accounts with optional status filter."""
    try:
        status = (request.args.get("status") or "all").strip().lower()
        q = User.query.filter(
            or_(User.account_type == "dealer", User.dealer_status != "none")
        )
        if status != "all":
            q = q.filter(User.dealer_status == status)
        rows = q.order_by(User.created_at.desc()).limit(500).all()
        return jsonify({"dealers": [u.to_dict(include_private=True) for u in rows]}), 200
    except Exception as e:
        logger.error("admin dealers_list error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list dealers"}), 500


@bp.route("/analytics/overview", methods=["GET"])
@admin_required
def analytics_overview():
    """Platform-wide listing engagement and top performers."""
    try:
        totals = db.session.query(
            func.coalesce(func.sum(ListingAnalytics.views), 0),
            func.coalesce(func.sum(ListingAnalytics.messages), 0),
            func.coalesce(func.sum(ListingAnalytics.calls), 0),
            func.coalesce(func.sum(ListingAnalytics.shares), 0),
            func.coalesce(func.sum(ListingAnalytics.favorites), 0),
            func.count(ListingAnalytics.id),
        ).one()
        top = (
            ListingAnalytics.query.options(joinedload(ListingAnalytics.car))
            .order_by(ListingAnalytics.views.desc())
            .limit(20)
            .all()
        )
        return (
            jsonify(
                {
                    "totals": {
                        "views": int(totals[0] or 0),
                        "messages": int(totals[1] or 0),
                        "calls": int(totals[2] or 0),
                        "shares": int(totals[3] or 0),
                        "favorites": int(totals[4] or 0),
                        "tracked_listings": int(totals[5] or 0),
                    },
                    "top_listings": [a.to_dict() for a in top],
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin analytics_overview error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get analytics"}), 500


@bp.route("/insights", methods=["GET"])
@admin_required
def insights():
    """Trends: signups, listings, messages by day; popular brands."""
    try:
        days = min(max(request.args.get("days", 14, type=int), 1), 90)

        signup_rows = (
            db.session.query(func.date(User.created_at).label("day"), func.count(User.id))
            .filter(User.created_at.isnot(None))
            .group_by(func.date(User.created_at))
            .order_by(func.date(User.created_at).desc())
            .limit(days)
            .all()
        )
        listing_rows = (
            db.session.query(func.date(Car.created_at).label("day"), func.count(Car.id))
            .filter(Car.created_at.isnot(None))
            .group_by(func.date(Car.created_at))
            .order_by(func.date(Car.created_at).desc())
            .limit(days)
            .all()
        )
        message_rows = (
            db.session.query(func.date(Message.created_at).label("day"), func.count(Message.id))
            .filter(Message.created_at.isnot(None))
            .group_by(func.date(Message.created_at))
            .order_by(func.date(Message.created_at).desc())
            .limit(days)
            .all()
        )
        brand_rows = (
            db.session.query(Car.brand, func.count(Car.id).label("count"))
            .group_by(Car.brand)
            .order_by(func.count(Car.id).desc())
            .limit(15)
            .all()
        )
        location_rows = (
            db.session.query(Car.location, func.count(Car.id).label("count"))
            .group_by(Car.location)
            .order_by(func.count(Car.id).desc())
            .limit(15)
            .all()
        )

        def _series(rows):
            return [{"day": str(d), "count": int(c)} for d, c in reversed(rows)]

        return (
            jsonify(
                {
                    "signups_by_day": _series(signup_rows),
                    "listings_by_day": _series(listing_rows),
                    "messages_by_day": _series(message_rows),
                    "top_brands": [{"brand": b, "count": int(c)} for b, c in brand_rows],
                    "top_locations": [{"location": loc, "count": int(c)} for loc, c in location_rows],
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin insights error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to get insights"}), 500


@bp.route("/saved-searches", methods=["GET"])
@admin_required
def saved_searches():
    """List saved searches across users."""
    try:
        page = request.args.get("page", 1, type=int)
        per_page = min(max(request.args.get("per_page", 30, type=int), 1), 100)
        search = (request.args.get("search") or "").strip()
        q = SavedSearch.query
        if search:
            like = f"%{search}%"
            q = q.filter(SavedSearch.name.ilike(like))
        pagination = q.order_by(SavedSearch.created_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )
        items = []
        for s in pagination.items:
            row = s.to_dict()
            u = User.query.get(s.user_id)
            row["user_public_id"] = u.public_id if u else None
            row["user_username"] = u.username if u else None
            items.append(row)
        return (
            jsonify(
                {
                    "saved_searches": items,
                    "pagination": _pagination_dict(pagination, page, per_page),
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin saved_searches error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list saved searches"}), 500


@bp.route("/meta/filters", methods=["GET"])
@admin_required
def meta_filters():
    """Distinct values for admin filter dropdowns."""
    try:
        brands = [r[0] for r in db.session.query(Car.brand).distinct().order_by(Car.brand).limit(200).all() if r[0]]
        statuses = [r[0] for r in db.session.query(Car.status).distinct().order_by(Car.status).all() if r[0]]
        action_types = [
            r[0]
            for r in db.session.query(UserAction.action_type)
            .distinct()
            .order_by(UserAction.action_type)
            .all()
            if r[0]
        ]
        notification_types = [
            r[0]
            for r in db.session.query(Notification.notification_type)
            .distinct()
            .order_by(Notification.notification_type)
            .all()
            if r[0]
        ]
        return (
            jsonify(
                {
                    "brands": brands,
                    "listing_statuses": statuses,
                    "action_types": action_types,
                    "notification_types": notification_types,
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin meta_filters error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load filter metadata"}), 500

