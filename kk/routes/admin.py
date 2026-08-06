from __future__ import annotations

import logging
import os

from flask import Blueprint, current_app, jsonify, request, send_from_directory
from sqlalchemy import asc, desc, func, or_
from sqlalchemy.orm import joinedload, selectinload

from ..auth import admin_required, get_current_user, log_user_action
from ..extensions import socketio
from ..push import send_push
from ..admin_roles import (
    VALID_ROLES,
    assert_permission,
    normalize_admin_role,
    user_has_permission,
)
from ..models import (
    Car,
    DealerApplication,
    DealerDecision,
    DealerProfile,
    ListingAnalytics,
    ListingReport,
    Message,
    Notification,
    ScheduledNotification,
    SavedSearch,
    User,
    UserAction,
    UserReport,
    db,
)
from ..response_cache import invalidate_filter_facets_cache
from ..listing_search import apply_listing_text_search
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


def _deny(permission: str):
    _, err = assert_permission(permission)
    return err


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
        denied = _deny("dashboard")
        if denied:
            return denied
        admin_user = get_current_user()
        can_read_users = user_has_permission(admin_user, "users.read")
        can_read_messages = user_has_permission(admin_user, "messages")

        total_users = User.query.count()
        active_users = User.query.filter_by(is_active=True).count()
        total_cars = Car.query.count()
        active_cars = Car.query.filter_by(is_active=True).count()
        total_messages = Message.query.count()
        total_notifications = Notification.query.count()

        pending_user_reports = UserReport.query.filter_by(status="pending").count()
        pending_listing_reports = ListingReport.query.filter_by(status="pending").count()
        pending_dealers = User.query.filter(User.dealer_status == "pending").count()
        pending_listings = Car.query.filter(
            Car.is_active.is_(True),
            Car.status == "pending",
        ).count()
        dealer_accounts = User.query.filter(User.account_type == "dealer").count()
        featured_cars = Car.query.filter_by(is_featured=True, is_active=True).count()
        total_saved_searches = SavedSearch.query.count()
        total_user_actions = UserAction.query.count()
        engagement = db.session.query(
            func.coalesce(func.sum(ListingAnalytics.views), 0),
            func.coalesce(func.sum(ListingAnalytics.messages), 0),
            func.coalesce(func.sum(ListingAnalytics.calls), 0),
            func.coalesce(func.sum(ListingAnalytics.favorites), 0),
        ).one()

        recent_users = (
            User.query.order_by(User.created_at.desc()).limit(10).all()
            if can_read_users
            else []
        )
        recent_cars = (
            Car.query.options(
                selectinload(Car.images),
                selectinload(Car.videos),
                joinedload(Car.seller),
            )
            .order_by(Car.created_at.desc())
            .limit(10)
            .all()
        )
        recent_messages = (
            Message.query.order_by(Message.created_at.desc()).limit(10).all()
            if can_read_messages
            else []
        )

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
                        "pending_listings": pending_listings,
                        "dealer_accounts": dealer_accounts,
                        "featured_cars": featured_cars,
                        "total_saved_searches": total_saved_searches,
                        "total_user_actions": total_user_actions,
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


@bp.route("/meta/badges", methods=["GET"])
@admin_required
def meta_badges():
    """Lightweight counts for sidebar badges (avoids full dashboard payload)."""
    try:
        denied = _deny("dashboard")
        if denied:
            return denied
        pending_user_reports = UserReport.query.filter_by(status="pending").count()
        pending_listing_reports = ListingReport.query.filter_by(status="pending").count()
        return (
            jsonify(
                {
                    "pending_reports": pending_user_reports + pending_listing_reports,
                    "pending_dealers": User.query.filter(User.dealer_status == "pending").count(),
                    "pending_listings": Car.query.filter(
                        Car.is_active.is_(True),
                        Car.status == "pending",
                    ).count(),
                    "users": User.query.count(),
                    "listings": Car.query.count(),
                    "dealers": User.query.filter(User.account_type == "dealer").count(),
                    "messages": Message.query.count(),
                    "notifications": Notification.query.count(),
                    "saved_searches": SavedSearch.query.count(),
                    "audit_log": UserAction.query.count(),
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin meta_badges error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load badge counts"}), 500


@bp.route("/users", methods=["GET"])
@admin_required
def users():
    """List users with pagination and optional search."""
    try:
        denied = _deny("users.read")
        if denied:
            return denied
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
        denied = _deny("users.read")
        if denied:
            return denied
        user = User.query.filter_by(public_id=user_id).first()
        if not user:
            return jsonify({"message": "User not found"}), 404

        cars = (
            Car.query.options(
                selectinload(Car.images),
                selectinload(Car.videos),
                joinedload(Car.seller),
            )
            .filter_by(seller_id=user.id)
            .all()
        )
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
        denied = _deny("listings.read")
        if denied:
            return denied
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

        pagination = (
            q.options(
                selectinload(Car.images),
                selectinload(Car.videos),
                joinedload(Car.seller),
            )
            .order_by(order_by)
            .paginate(page=page, per_page=per_page, error_out=False)
        )
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
        denied = _deny("messages")
        if denied:
            return denied
        page = request.args.get("page", 1, type=int)
        per_page = min(max(request.args.get("per_page", 50, type=int), 1), 100)
        search = (request.args.get("search") or "").strip()
        is_read = _bool_param("is_read")
        car_id = (request.args.get("car_id") or "").strip()

        q = Message.query.options(
            joinedload(Message.sender),
            joinedload(Message.receiver),
            joinedload(Message.car),
        ).filter(Message.is_deleted.is_(False))
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


@bp.route("/messages/thread", methods=["GET"])
@admin_required
def message_thread():
    """Full conversation for a listing (car_id = public id)."""
    try:
        denied = _deny("messages")
        if denied:
            return denied
        car_id = (request.args.get("car_id") or "").strip()
        if not car_id:
            return jsonify({"message": "car_id is required"}), 400
        car = _find_car(car_id)
        if not car:
            return jsonify({"message": "Listing not found"}), 404
        rows = (
            Message.query.options(
                joinedload(Message.sender),
                joinedload(Message.receiver),
                joinedload(Message.car),
            )
            .filter(Message.car_id == car.id, Message.is_deleted.is_(False))
            .order_by(Message.created_at.asc())
            .limit(500)
            .all()
        )
        return (
            jsonify(
                {
                    "car": car.to_dict(),
                    "messages": [m.to_dict() for m in rows],
                    "count": len(rows),
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin message_thread error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load message thread"}), 500


@bp.route("/notifications", methods=["GET"])
@admin_required
def notifications():
    """List recent notifications."""
    try:
        denied = _deny("notifications.read")
        if denied:
            return denied
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
        denied = _deny("audit")
        if denied:
            return denied
        page = request.args.get("page", 1, type=int)
        per_page = min(max(request.args.get("per_page", 50, type=int), 1), 100)
        action_type = (request.args.get("action_type") or "").strip()
        user_id = (request.args.get("user_id") or "").strip()
        target_type = (request.args.get("target_type") or "").strip()
        scope = (request.args.get("scope") or "all").strip().lower()

        q = UserAction.query
        if scope == "admin":
            q = q.filter(
                or_(
                    UserAction.action_type.like("admin_%"),
                    UserAction.action_type.like("dealer_%"),
                )
            )
        elif scope == "user":
            q = q.filter(
                ~UserAction.action_type.like("admin_%"),
                ~UserAction.action_type.like("dealer_%"),
            )
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


def _dealer_admin_dict(user: User) -> dict:
    data = user.to_dict(include_private=True)
    application = user.dealer_application
    if application:
        data["dealer_status"] = application.status
        data["dealer_application"] = application.to_dict(include_decisions=True)
        if application.verification_photo_filename:
            data["dealer_application"]["verification_photo_url"] = (
                f"/api/admin/dealers/{user.public_id}/verification-photo"
            )
    return data


def _review_dealer_application(
    target: User, admin_user: User, action: str, reason: str | None = None
) -> tuple[DealerApplication, Notification]:
    application = target.dealer_application
    if not application:
        raise ValueError("Dealer application not found")

    action = (action or "").strip().lower()
    allowed = {
        "submitted": {"under_review", "needs_changes", "approved", "rejected"},
        "under_review": {"needs_changes", "approved", "rejected"},
    }
    if action not in allowed.get(application.status, set()):
        raise ValueError(
            f"Cannot move dealer application from {application.status} to {action}"
        )
    if action in {"needs_changes", "rejected"} and not reason:
        raise ValueError("A reason is required for this decision")

    now = utcnow()
    application.status = action
    application.review_reason = reason if action in {"needs_changes", "rejected"} else None
    application.reviewed_at = now if action in {"needs_changes", "approved", "rejected"} else None
    application.updated_at = now
    target.updated_at = now

    if action == "approved":
        target.account_type = "dealer"
        target.dealer_status = "approved"
        target.dealership_name = application.dealership_name
        target.dealership_phone = application.dealership_phone
        target.dealership_phones = application.dealership_phones
        target.dealership_location = application.dealership_location
        target.dealership_description = application.dealership_description
        profile = target.dealer_profile
        if profile is None:
            profile = DealerProfile(user=target)
            db.session.add(profile)
        profile.dealership_name = application.dealership_name
        profile.dealership_phone = application.dealership_phone
        profile.dealership_phones = application.dealership_phones
        profile.dealership_location = application.dealership_location
        profile.dealership_description = application.dealership_description
        profile.dealership_cover_picture = target.dealership_cover_picture
        profile.dealership_latitude = target.dealership_latitude
        profile.dealership_longitude = target.dealership_longitude
        profile.dealership_opening_hours = target.dealership_opening_hours
        profile.is_featured = bool(target.is_featured_dealer)
    else:
        target.account_type = "user"
        target.dealer_status = (
            "pending" if action in {"under_review", "needs_changes"} else action
        )

    db.session.add(
        DealerDecision(
            application=application,
            reviewer=admin_user,
            decision=action,
            reason=reason,
            application_snapshot=application.snapshot(),
        )
    )
    messages = {
        "under_review": (
            "Dealer application under review",
            "An administrator has started reviewing your dealer application.",
        ),
        "needs_changes": (
            "Dealer application needs changes",
            reason or "Please update your dealer application.",
        ),
        "approved": (
            "Dealer application approved",
            "Your dealership is verified and active. Complete your public profile with a logo, cover image, opening hours, and contact details.",
        ),
        "rejected": (
            "Dealer application declined",
            reason or "Your dealer application was not approved.",
        ),
    }
    title, message = messages[action]
    notification = Notification(
        user_id=target.id,
        title=title,
        message=message,
        notification_type="dealer_application",
        data={"application_id": application.public_id, "status": action},
    )
    db.session.add(notification)
    return application, notification


@bp.route("/dealers/pending", methods=["GET"])
@admin_required
def dealers_pending():
    """List users waiting for dealer verification (`dealer_status == pending`)."""
    try:
        denied = _deny("dealers")
        if denied:
            return denied
        rows = (
            User.query.join(DealerApplication)
            .filter(DealerApplication.status.in_(("submitted", "under_review")))
            .order_by(DealerApplication.submitted_at.asc())
            .all()
        )
        return jsonify({"dealers": [_dealer_admin_dict(u) for u in rows]}), 200
    except Exception as e:
        logger.error("admin dealers_pending error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list pending dealers"}), 500


@bp.route("/dealers/<user_public_id>/verification-photo", methods=["GET"])
@admin_required
def dealer_verification_photo(user_public_id: str):
    """Return a private dealership photo to authorized dealer reviewers."""
    denied = _deny("dealers")
    if denied:
        return denied
    target = User.query.filter_by(public_id=(user_public_id or "").strip()).first()
    application = target.dealer_application if target else None
    filename = application.verification_photo_filename if application else None
    if not filename:
        return jsonify({"message": "Verification photo not found"}), 404
    folder = os.path.join(
        current_app.config["PRIVATE_UPLOAD_FOLDER"],
        "dealer_verification",
    )
    response = send_from_directory(
        folder,
        os.path.basename(filename),
        as_attachment=False,
        max_age=0,
    )
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Pragma"] = "no-cache"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@bp.route("/dealers/<user_public_id>/approve", methods=["POST"])
@admin_required
def dealers_approve(user_public_id: str):
    """Approve a pending dealer application."""
    try:
        denied = _deny("dealers")
        if denied:
            return denied
        admin_user = get_current_user()
        if not admin_user:
            return jsonify({"message": "Unauthorized"}), 401
        pid = (user_public_id or "").strip()
        if not pid:
            return jsonify({"message": "User id is required"}), 400
        target = User.query.filter_by(public_id=pid).first()
        if not target:
            return jsonify({"message": "User not found"}), 404
        application, notification = _review_dealer_application(
            target,
            admin_user,
            "approved",
        )
        db.session.commit()

        push_data = {
            "type": "dealer_application",
            "status": "approved",
            "notification_id": notification.public_id,
            "application_id": application.public_id,
        }
        if target.firebase_token:
            try:
                send_push(
                    target.firebase_token,
                    title=notification.title,
                    body=notification.message,
                    data=push_data,
                )
            except Exception:
                logger.exception(
                    "Dealer approval push failed for user %s",
                    target.public_id,
                )
        try:
            socketio.emit(
                "new_notification",
                notification.to_dict(),
                room=f"user:{target.public_id}",
            )
        except Exception:
            logger.exception(
                "Dealer approval realtime notification failed for user %s",
                target.public_id,
            )

        log_user_action(
            admin_user,
            "dealer_approve",
            target_type="user",
            target_id=pid,
            metadata={
                "approved_user_internal_id": target.id,
                "application_id": application.public_id,
            },
        )
        return jsonify({"message": "Dealer approved", "user": _dealer_admin_dict(target)}), 200
    except ValueError as e:
        db.session.rollback()
        return jsonify({"message": str(e)}), 400
    except Exception as e:
        db.session.rollback()
        logger.error("admin dealers_approve error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to approve dealer"}), 500


@bp.route("/dealers/<user_public_id>/reject", methods=["POST"])
@admin_required
def dealers_reject(user_public_id: str):
    """Reject a pending dealer application (user stays a normal account)."""
    try:
        denied = _deny("dealers")
        if denied:
            return denied
        admin_user = get_current_user()
        if not admin_user:
            return jsonify({"message": "Unauthorized"}), 401
        pid = (user_public_id or "").strip()
        if not pid:
            return jsonify({"message": "User id is required"}), 400
        target = User.query.filter_by(public_id=pid).first()
        if not target:
            return jsonify({"message": "User not found"}), 404
        data = request.get_json(silent=True) or {}
        reason = (data.get("reason") or "").strip() or None
        application, _notification = _review_dealer_application(
            target,
            admin_user,
            "rejected",
            reason,
        )
        db.session.commit()

        log_user_action(
            admin_user,
            "dealer_reject",
            target_type="user",
            target_id=pid,
            metadata={"reason": reason, "application_id": application.public_id},
        )
        return jsonify({"message": "Dealer application rejected", "user": _dealer_admin_dict(target)}), 200
    except ValueError as e:
        db.session.rollback()
        return jsonify({"message": str(e)}), 400
    except Exception as e:
        db.session.rollback()
        logger.error("admin dealers_reject error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to reject dealer application"}), 500


@bp.route("/dealers/<user_public_id>/review", methods=["POST"])
@admin_required
def dealers_review(user_public_id: str):
    """Start review or request changes using an explicit lifecycle transition."""
    try:
        denied = _deny("dealers")
        if denied:
            return denied
        admin_user = get_current_user()
        if not admin_user:
            return jsonify({"message": "Unauthorized"}), 401
        target = _find_user(user_public_id)
        if not target:
            return jsonify({"message": "User not found"}), 404
        data = request.get_json(silent=True) or {}
        action = (data.get("action") or "").strip().lower()
        reason = (data.get("reason") or "").strip() or None
        if action not in {"under_review", "needs_changes"}:
            return jsonify({"message": "action must be under_review or needs_changes"}), 400
        application, _notification = _review_dealer_application(
            target,
            admin_user,
            action,
            reason,
        )
        db.session.commit()
        log_user_action(
            admin_user,
            f"dealer_{action}",
            target_type="dealer_application",
            target_id=application.public_id,
            metadata={"reason": reason} if reason else None,
        )
        return jsonify(
            {
                "message": "Dealer application updated",
                "user": _dealer_admin_dict(target),
            }
        ), 200
    except ValueError as e:
        db.session.rollback()
        return jsonify({"message": str(e)}), 400
    except Exception as e:
        db.session.rollback()
        logger.error("admin dealers_review error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to review dealer application"}), 500


@bp.route("/dealers/<user_public_id>/featured", methods=["PATCH"])
@admin_required
def dealers_set_featured(user_public_id: str):
    """Toggle is_featured_dealer for an approved dealer."""
    try:
        denied = _deny("dealers")
        if denied:
            return denied
        admin_user = get_current_user()
        pid = (user_public_id or "").strip()
        target = User.query.filter_by(public_id=pid).first()
        if not target:
            return jsonify({"message": "User not found"}), 404
        data = request.get_json(silent=True) or {}
        if "is_featured_dealer" not in data:
            return jsonify({"message": "is_featured_dealer is required"}), 400
        featured = bool(data["is_featured_dealer"])
        if featured and (target.dealer_status or "") != "approved":
            return jsonify({"message": "Only approved dealers can be featured"}), 400
        target.is_featured_dealer = featured
        if target.dealer_profile:
            target.dealer_profile.is_featured = featured
            target.dealer_profile.updated_at = utcnow()
        target.updated_at = utcnow()
        db.session.commit()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_dealer_featured",
                target_type="user",
                target_id=pid,
                metadata={"is_featured_dealer": featured},
            )
        return jsonify({"user": target.to_dict(include_private=True)}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin dealers_set_featured error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update featured dealer"}), 500


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
        denied = _deny("reports")
        if denied:
            return denied
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
                    joinedload(ListingReport.car).joinedload(Car.seller),
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
        denied = _deny("reports")
        if denied:
            return denied
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
        denied = _deny("reports")
        if denied:
            return denied
        report = (
            ListingReport.query.options(
                joinedload(ListingReport.reporter),
                joinedload(ListingReport.car).joinedload(Car.seller),
            )
            .filter_by(id=report_id)
            .first()
        )
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
        denied = _deny("search")
        if denied:
            return denied
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
        cars_q, _rank = apply_listing_text_search(
            Car.query.options(
                selectinload(Car.images),
                selectinload(Car.videos),
                joinedload(Car.seller),
            ),
            q,
        )
        cars = cars_q.order_by(Car.created_at.desc()).limit(limit).all()
        # Merge public_id hits that FTS may miss (UUID fragments).
        by_id = {c.id: c for c in cars}
        for c in (
            Car.query.options(
                selectinload(Car.images),
                selectinload(Car.videos),
                joinedload(Car.seller),
            )
            .filter(Car.public_id.ilike(like))
            .order_by(Car.created_at.desc())
            .limit(limit)
            .all()
        ):
            by_id.setdefault(c.id, c)
        cars = sorted(
            by_id.values(),
            key=lambda c: c.created_at or utcnow(),
            reverse=True,
        )[:limit]
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
        denied = _deny("listings.read")
        if denied:
            return denied
        car = _find_car(car_id)
        if not car:
            return jsonify({"message": "Listing not found"}), 404
        analytics = ListingAnalytics.query.filter_by(car_id=car.id).first()
        reports = (
            ListingReport.query.filter_by(car_id=car.id)
            .options(
                joinedload(ListingReport.reporter),
                joinedload(ListingReport.car).joinedload(Car.seller),
            )
            .order_by(ListingReport.created_at.desc())
            .limit(20)
            .all()
        )
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
        denied = _deny("listings.write")
        if denied:
            return denied
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
        invalidate_filter_facets_cache()
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


@bp.route("/cars/bulk-status", methods=["POST"])
@admin_required
def bulk_update_car_status():
    """Apply the same status patch to multiple listings (max 50)."""
    try:
        denied = _deny("listings.write")
        if denied:
            return denied
        admin_user = get_current_user()
        data = request.get_json(silent=True) or {}
        ids = data.get("ids") or []
        if not isinstance(ids, list) or not ids:
            return jsonify({"message": "ids array is required"}), 400
        if len(ids) > 50:
            return jsonify({"message": "Maximum 50 listings per bulk update"}), 400

        patch = {}
        if "is_active" in data:
            patch["is_active"] = bool(data["is_active"])
        if "is_featured" in data:
            patch["is_featured"] = bool(data["is_featured"])
        if "status" in data and str(data["status"]).strip():
            patch["status"] = str(data["status"]).strip()
        if not patch:
            return jsonify({"message": "Provide is_active, is_featured, and/or status"}), 400

        updated = []
        missing = []
        for raw_id in ids:
            car = _find_car(str(raw_id))
            if not car:
                missing.append(str(raw_id))
                continue
            if "is_active" in patch:
                car.is_active = patch["is_active"]
            if "is_featured" in patch:
                car.is_featured = patch["is_featured"]
            if "status" in patch:
                car.status = patch["status"]
            car.updated_at = utcnow()
            updated.append(car.public_id or str(car.id))

        if not updated:
            return jsonify({"message": "No matching listings found", "missing": missing}), 404

        db.session.commit()
        invalidate_filter_facets_cache()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_bulk_update_listings",
                target_type="car",
                target_id=",".join(updated[:10]),
                metadata={"patch": patch, "updated_count": len(updated), "missing": missing},
            )
        return (
            jsonify(
                {
                    "message": f"Updated {len(updated)} listing(s)",
                    "updated": updated,
                    "missing": missing,
                }
            ),
            200,
        )
    except Exception as e:
        db.session.rollback()
        logger.error("admin bulk_update_car_status error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to bulk update listings"}), 500


@bp.route("/notifications/broadcast", methods=["POST"])
@admin_required
def broadcast_notification():
    """Create in-app notifications now, or schedule for later via scheduled_at."""
    try:
        denied = _deny("notifications.broadcast")
        if denied:
            return denied
        from ..notification_broadcast import (
            create_scheduled_notification,
            execute_broadcast,
            parse_scheduled_at,
        )

        admin_user = get_current_user()
        data = request.get_json(silent=True) or {}
        title = (data.get("title") or "").strip()
        message = (data.get("message") or "").strip()
        notification_type = (data.get("notification_type") or "admin").strip() or "admin"
        audience = (data.get("audience") or "all").strip().lower()
        target_user_id = (data.get("target_user_id") or "").strip() or None
        send_push_flag = bool(data.get("send_push", True))
        scheduled_raw = data.get("scheduled_at")

        if scheduled_raw:
            scheduled_at = parse_scheduled_at(scheduled_raw)
            row = create_scheduled_notification(
                title=title,
                message=message,
                scheduled_at=scheduled_at,
                audience=audience,
                target_user_id=target_user_id,
                notification_type=notification_type,
                send_push_flag=send_push_flag,
                created_by_user_id=admin_user.id if admin_user else None,
            )
            if admin_user:
                log_user_action(
                    admin_user,
                    "admin_schedule_notification",
                    target_type="scheduled_notification",
                    target_id=str(row.id),
                    metadata={
                        "title": title,
                        "audience": audience,
                        "scheduled_at": scheduled_at.isoformat(),
                    },
                )
            return (
                jsonify(
                    {
                        "message": "Notification scheduled",
                        "scheduled": True,
                        "scheduled_notification": row.to_admin_dict(),
                    }
                ),
                201,
            )

        result = execute_broadcast(
            title=title,
            message=message,
            audience=audience,
            target_user_id=target_user_id,
            notification_type=notification_type,
            send_push_flag=send_push_flag,
        )
        if admin_user:
            log_user_action(
                admin_user,
                "admin_broadcast_notification",
                target_type="notification",
                metadata={
                    "title": title,
                    "audience": audience,
                    "created": result.get("created"),
                    "pushed": result.get("pushed"),
                    "send_push": send_push_flag,
                },
            )
        return jsonify({**result, "scheduled": False}), 200
    except ValueError as e:
        return jsonify({"message": str(e)}), 400
    except Exception as e:
        db.session.rollback()
        logger.error("admin broadcast_notification error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to broadcast notification"}), 500


@bp.route("/notifications/scheduled", methods=["GET"])
@admin_required
def list_scheduled_notifications():
    """List scheduled broadcasts. Also processes any due items (beat fallback)."""
    try:
        denied = _deny("notifications.read")
        if denied:
            return denied
        from ..notification_broadcast import process_due_scheduled_notifications

        # Lazy delivery if Celery beat is not running
        try:
            process_due_scheduled_notifications(limit=10)
        except Exception as e:
            logger.warning("lazy process due scheduled notifications failed: %s", e)

        status = (request.args.get("status") or "all").strip().lower()
        page = request.args.get("page", 1, type=int)
        per_page = min(max(request.args.get("per_page", 20, type=int), 1), 100)
        q = ScheduledNotification.query
        if status != "all":
            q = q.filter(ScheduledNotification.status == status)
        pagination = q.order_by(ScheduledNotification.scheduled_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )
        return (
            jsonify(
                {
                    "scheduled": [r.to_admin_dict() for r in pagination.items],
                    "pagination": _pagination_dict(pagination, page, per_page),
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin list_scheduled_notifications error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list scheduled notifications"}), 500


@bp.route("/notifications/scheduled/<int:item_id>/cancel", methods=["POST"])
@admin_required
def cancel_scheduled_notification(item_id: int):
    try:
        denied = _deny("notifications.broadcast")
        if denied:
            return denied
        admin_user = get_current_user()
        row = ScheduledNotification.query.get(item_id)
        if not row:
            return jsonify({"message": "Scheduled notification not found"}), 404
        if row.status not in ("pending",):
            return jsonify({"message": f"Cannot cancel status={row.status}"}), 400
        row.status = "cancelled"
        row.updated_at = utcnow()
        db.session.commit()
        if admin_user:
            log_user_action(
                admin_user,
                "admin_cancel_scheduled_notification",
                target_type="scheduled_notification",
                target_id=str(row.id),
            )
        return jsonify({"scheduled_notification": row.to_admin_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin cancel_scheduled_notification error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to cancel scheduled notification"}), 500


@bp.route("/notifications/scheduled/process", methods=["POST"])
@admin_required
def process_scheduled_notifications():
    """Manually process due scheduled notifications (ops / no-beat fallback)."""
    try:
        denied = _deny("notifications.broadcast")
        if denied:
            return denied
        from ..notification_broadcast import process_due_scheduled_notifications

        result = process_due_scheduled_notifications(limit=50)
        return jsonify(result), 200
    except Exception as e:
        logger.error("admin process_scheduled_notifications error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to process scheduled notifications"}), 500


@bp.route("/users/<user_id>/status", methods=["PATCH"])
@admin_required
def update_user_status(user_id: str):
    """Activate/deactivate a user account."""
    try:
        denied = _deny("users.write")
        if denied:
            return denied
        admin_user = get_current_user()
        user = _find_user(user_id)
        if not user:
            return jsonify({"message": "User not found"}), 404
        data = request.get_json(silent=True) or {}
        if "is_active" in data:
            if user.is_admin and admin_user and user.id != admin_user.id:
                return (
                    jsonify({"message": "Cannot change status of another admin account"}),
                    403,
                )
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


@bp.route("/users/<user_id>/role", methods=["PATCH"])
@admin_required
def update_user_admin_role(user_id: str):
    """Grant/revoke admin access and set admin_role (super_admin only)."""
    try:
        denied = _deny("users.role")
        if denied:
            return denied
        admin_user = get_current_user()
        if not admin_user:
            return jsonify({"message": "Unauthorized"}), 401
        user = _find_user(user_id)
        if not user:
            return jsonify({"message": "User not found"}), 404
        if user.id == admin_user.id:
            return jsonify({"message": "Cannot change your own admin role"}), 400

        data = request.get_json(silent=True) or {}
        if "is_admin" in data:
            user.is_admin = bool(data["is_admin"])
        if not user.is_admin:
            user.admin_role = None
            from ..models import AdminAccount

            detached = AdminAccount.query.filter_by(
                origin_user_public_id=user.public_id,
            ).first()
            if detached:
                detached.is_active = False
                detached.principal.is_active = False
        else:
            role = (data.get("admin_role") or user.admin_role or "moderator").strip().lower()
            if role not in VALID_ROLES:
                return jsonify({"message": f"Invalid admin_role. Use: {', '.join(VALID_ROLES)}"}), 400
            user.admin_role = role
            from ..admin_identity import ensure_detached_admin_account

            detached = ensure_detached_admin_account(user)
            detached.admin_role = role
            detached.principal.admin_role = role

        user.updated_at = utcnow()
        db.session.commit()
        log_user_action(
            admin_user,
            "admin_update_user_role",
            target_type="user",
            target_id=user.public_id,
            metadata={
                "is_admin": user.is_admin,
                "admin_role": normalize_admin_role(user) if user.is_admin else None,
            },
        )
        return jsonify({"user": user.to_dict(include_private=True)}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update_user_admin_role error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update admin role"}), 500


@bp.route("/dealers", methods=["GET"])
@admin_required
def dealers_list():
    """List dealer accounts with optional status filter and pagination."""
    try:
        denied = _deny("dealers")
        if denied:
            return denied
        page = request.args.get("page", 1, type=int)
        per_page = min(max(request.args.get("per_page", 20, type=int), 1), 100)
        status = (request.args.get("status") or "all").strip().lower()
        base = User.query.join(DealerApplication)
        counts = {
            "all": base.count(),
            "draft": base.filter(DealerApplication.status == "draft").count(),
            "submitted": base.filter(DealerApplication.status == "submitted").count(),
            "under_review": base.filter(
                DealerApplication.status == "under_review"
            ).count(),
            "needs_changes": base.filter(
                DealerApplication.status == "needs_changes"
            ).count(),
            "approved": base.filter(DealerApplication.status == "approved").count(),
            "rejected": base.filter(DealerApplication.status == "rejected").count(),
        }
        counts["pending"] = counts["submitted"] + counts["under_review"]
        q = base
        if status == "pending":
            q = q.filter(
                DealerApplication.status.in_(("submitted", "under_review"))
            )
        elif status != "all":
            q = q.filter(DealerApplication.status == status)
        # Pending queue: oldest first so applications are reviewed in order
        order = (
            DealerApplication.submitted_at.asc()
            if status in {"pending", "submitted", "under_review"}
            else DealerApplication.updated_at.desc()
        )
        pagination = q.order_by(order).paginate(page=page, per_page=per_page, error_out=False)
        return (
            jsonify(
                {
                    "dealers": [_dealer_admin_dict(u) for u in pagination.items],
                    "pagination": _pagination_dict(pagination, page, per_page),
                    "counts": counts,
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin dealers_list error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to list dealers"}), 500


@bp.route("/analytics/overview", methods=["GET"])
@admin_required
def analytics_overview():
    """Platform-wide listing engagement and top performers."""
    try:
        denied = _deny("analytics")
        if denied:
            return denied
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
        denied = _deny("insights")
        if denied:
            return denied
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
        denied = _deny("saved_searches")
        if denied:
            return denied
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


@bp.route("/cars/<car_id>", methods=["DELETE"])
@admin_required
def delete_car(car_id: str):
    """Soft-delete a listing (hide from browse; keep row for audit)."""
    try:
        denied = _deny("listings.delete")
        if denied:
            return denied
        from ..favorites_cleanup import remove_listing_from_all_favorites
        from ..view_history import remove_listing_from_all_view_history

        admin_user = get_current_user()
        car = _find_car(car_id)
        if not car:
            return jsonify({"message": "Listing not found"}), 404

        remove_listing_from_all_favorites(car.id)
        remove_listing_from_all_view_history(car.id)
        car.is_active = False
        if not (car.status or "").strip() or car.status == "active":
            car.status = "hidden"
        car.updated_at = utcnow()
        db.session.commit()
        invalidate_filter_facets_cache()

        if admin_user:
            log_user_action(
                admin_user,
                "admin_delete_listing",
                target_type="car",
                target_id=car.public_id or str(car.id),
            )
        return jsonify({"message": "Listing soft-deleted", "car": car.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin delete_car error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to delete listing"}), 500


@bp.route("/users/<user_id>", methods=["DELETE"])
@admin_required
def delete_user(user_id: str):
    """Soft-delete a user: deactivate account and hide their listings."""
    try:
        denied = _deny("users.write")
        if denied:
            return denied
        admin_user = get_current_user()
        if not admin_user:
            return jsonify({"message": "Unauthorized"}), 401
        user = _find_user(user_id)
        if not user:
            return jsonify({"message": "User not found"}), 404
        if user.id == admin_user.id:
            return jsonify({"message": "Cannot delete your own account"}), 400
        if user.is_admin:
            return jsonify({"message": "Cannot delete another admin account"}), 400

        user.is_active = False
        user.updated_at = utcnow()
        cars_updated = (
            Car.query.filter_by(seller_id=user.id)
            .filter(Car.is_active.is_(True))
            .update({"is_active": False, "updated_at": utcnow()}, synchronize_session=False)
        )
        db.session.commit()

        log_user_action(
            admin_user,
            "admin_delete_user",
            target_type="user",
            target_id=user.public_id,
            metadata={"listings_deactivated": int(cars_updated or 0)},
        )
        return (
            jsonify(
                {
                    "message": "User deactivated",
                    "listings_deactivated": int(cars_updated or 0),
                    "user": user.to_dict(include_private=True),
                }
            ),
            200,
        )
    except Exception as e:
        db.session.rollback()
        logger.error("admin delete_user error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to delete user"}), 500


@bp.route("/cars/<car_id>/purge", methods=["DELETE"])
@admin_required
def purge_car(car_id: str):
    """Permanently delete a listing and related rows (super_admin only)."""
    try:
        denied = _deny("purge")
        if denied:
            return denied
        from ..favorites_cleanup import remove_listing_from_all_favorites
        from ..view_history import remove_listing_from_all_view_history
        from ..models import ListingAnalytics, ListingReport, SavedSearchAlert

        admin_user = get_current_user()
        car = _find_car(car_id)
        if not car:
            return jsonify({"message": "Listing not found"}), 404
        public_id = car.public_id or str(car.id)
        car_pk = car.id

        remove_listing_from_all_favorites(car_pk)
        remove_listing_from_all_view_history(car_pk)
        ListingReport.query.filter_by(car_id=car_pk).delete(synchronize_session=False)
        ListingAnalytics.query.filter_by(car_id=car_pk).delete(synchronize_session=False)
        SavedSearchAlert.query.filter_by(car_id=car_pk).delete(synchronize_session=False)
        Message.query.filter_by(car_id=car_pk).delete(synchronize_session=False)
        db.session.delete(car)
        db.session.commit()
        invalidate_filter_facets_cache()

        if admin_user:
            log_user_action(
                admin_user,
                "admin_purge_listing",
                target_type="car",
                target_id=public_id,
            )
        return jsonify({"message": "Listing permanently deleted", "id": public_id}), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin purge_car error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to purge listing"}), 500


@bp.route("/users/<user_id>/purge", methods=["DELETE"])
@admin_required
def purge_user(user_id: str):
    """Anonymize + deactivate a user permanently (super_admin). Keeps FK integrity."""
    try:
        denied = _deny("purge")
        if denied:
            return denied
        admin_user = get_current_user()
        if not admin_user:
            return jsonify({"message": "Unauthorized"}), 401
        user = _find_user(user_id)
        if not user:
            return jsonify({"message": "User not found"}), 404
        if user.id == admin_user.id:
            return jsonify({"message": "Cannot purge your own account"}), 400
        if user.is_admin:
            return jsonify({"message": "Cannot purge another admin account"}), 400

        pid = user.public_id
        suffix = pid.replace("-", "")[:8]
        user.is_active = False
        user.is_admin = False
        user.admin_role = None
        user.is_featured_dealer = False
        user.username = f"deleted_{suffix}"
        user.email = f"deleted_{suffix}@purged.local"
        user.phone_number = f"deleted_{suffix}"
        user.first_name = "Deleted"
        user.last_name = "User"
        user.profile_picture = None
        user.firebase_token = None
        user.dealership_name = None
        user.dealership_phone = None
        user.dealership_phones = None
        user.dealership_description = None
        user.dealership_cover_picture = None
        user.dealer_status = "none"
        user.account_type = "user"
        user.updated_at = utcnow()

        cars_updated = (
            Car.query.filter_by(seller_id=user.id)
            .filter(Car.is_active.is_(True))
            .update(
                {"is_active": False, "status": "hidden", "updated_at": utcnow()},
                synchronize_session=False,
            )
        )
        db.session.commit()
        log_user_action(
            admin_user,
            "admin_purge_user",
            target_type="user",
            target_id=pid,
            metadata={"listings_deactivated": int(cars_updated or 0)},
        )
        return (
            jsonify(
                {
                    "message": "User purged (anonymized)",
                    "listings_deactivated": int(cars_updated or 0),
                    "user": user.to_dict(include_private=True),
                }
            ),
            200,
        )
    except Exception as e:
        db.session.rollback()
        logger.error("admin purge_user error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to purge user"}), 500


@bp.route("/system/health", methods=["GET"])
@admin_required
def system_health():
    """Admin ops snapshot: API/DB/push/storage readiness + key counts."""
    try:
        denied = _deny("system")
        if denied:
            return denied
        import os
        from sqlalchemy import text

        from ..push import fcm_public_status

        db_ok = False
        db_error = None
        try:
            db.session.execute(text("SELECT 1"))
            db_ok = True
        except Exception as exc:
            db_error = str(exc)[:200]

        redis_url = (os.environ.get("REDIS_URL") or "").strip()
        redis_ok = None
        if redis_url:
            try:
                import redis  # type: ignore

                client = redis.from_url(redis_url, socket_connect_timeout=2)
                redis_ok = bool(client.ping())
            except Exception:
                redis_ok = False

        r2_ok = all(
            (os.environ.get(k) or "").strip()
            for k in (
                "R2_ACCOUNT_ID",
                "R2_BUCKET_NAME",
                "R2_ACCESS_KEY_ID",
                "R2_SECRET_ACCESS_KEY",
                "R2_PUBLIC_URL",
            )
        )
        from ..config import upload_persistence_mode

        storage = upload_persistence_mode()

        push = fcm_public_status()
        env = (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "production").strip()

        return (
            jsonify(
                {
                    "status": "ok" if db_ok else "degraded",
                    "environment": env,
                    "checks": {
                        "api": {"ok": True},
                        "database": {"ok": db_ok, "error": db_error},
                        "redis": {
                            "configured": bool(redis_url),
                            "ok": redis_ok,
                        },
                        "storage": {
                            "mode": storage,
                            "r2_configured": r2_ok,
                        },
                        "push": push,
                    },
                    "counts": {
                        "users": User.query.count(),
                        "active_users": User.query.filter_by(is_active=True).count(),
                        "listings": Car.query.count(),
                        "active_listings": Car.query.filter_by(is_active=True).count(),
                        "pending_reports": (
                            UserReport.query.filter_by(status="pending").count()
                            + ListingReport.query.filter_by(status="pending").count()
                        ),
                        "pending_dealers": User.query.filter(User.dealer_status == "pending").count(),
                        "messages": Message.query.count(),
                        "notifications": Notification.query.count(),
                    },
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin system_health error: %s", e, exc_info=True)
        return jsonify({"status": "error", "message": "Failed to load system health"}), 500


@bp.route("/settings", methods=["GET"])
@admin_required
def get_settings():
    """Admin platform settings (contact, legal URLs, pricing)."""
    try:
        denied = _deny("settings")
        if denied:
            return denied
        from ..app_settings import get_admin_settings_payload

        return jsonify(get_admin_settings_payload()), 200
    except Exception as e:
        logger.error("admin get_settings error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load settings"}), 500


@bp.route("/settings", methods=["PUT", "PATCH"])
@admin_required
def update_settings():
    """Update platform settings overrides (empty string clears back to env default)."""
    try:
        denied = _deny("settings")
        if denied:
            return denied
        from ..app_settings import update_platform_settings

        admin_user = get_current_user()
        data = request.get_json(silent=True) or {}
        if not isinstance(data, dict):
            return jsonify({"message": "JSON object required"}), 400
        payload = update_platform_settings(data)
        if admin_user:
            log_user_action(
                admin_user,
                "admin_update_settings",
                target_type="settings",
                target_id="platform",
                metadata={"keys": sorted(list(data.keys()))},
            )
        return jsonify(payload), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin update_settings error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update settings"}), 500


@bp.route("/meta/filters", methods=["GET"])
@admin_required
def meta_filters():
    """Distinct values for admin filter dropdowns."""
    try:
        denied = _deny("dashboard")
        if denied:
            return denied
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
                    "admin_roles": list(VALID_ROLES),
                }
            ),
            200,
        )
    except Exception as e:
        logger.error("admin meta_filters error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to load filter metadata"}), 500

