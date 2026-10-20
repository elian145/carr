"""Admin API for automated listing moderation.

All routes sit under ``/api/admin/auto-moderation`` and use the same
``admin_required`` gate and permission helpers as the rest of the admin API.
"""

from __future__ import annotations

import logging

from flask import Blueprint, jsonify, request

from ..admin_roles import assert_permission
from ..auth import admin_required, get_current_user, log_user_action
from ..auto_moderation import admin_actions, config, stats
from ..auto_moderation import reasons as reason_mod
from ..auto_moderation.triggers import request_moderation
from ..models import (
    Car,
    ListingModerationEvent,
    ListingModerationRun,
    User,
    db,
)

bp = Blueprint("admin_auto_moderation", __name__, url_prefix="/api/admin/auto-moderation")
logger = logging.getLogger(__name__)


def _deny(permission: str):
    _, err = assert_permission(permission)
    return err


def _admin_name(user) -> str:
    return (getattr(user, "username", None) or "admin")[:100]


def _event_dict(ev: ListingModerationEvent) -> dict:
    return {
        "id": ev.id,
        "type": ev.event_type,
        "actor": ev.actor,
        "data": ev.data,
        "created_at": ev.created_at.isoformat() if ev.created_at else None,
    }


def _run_dict(run: ListingModerationRun, *, detail: bool = False) -> dict:
    car = run.car
    seller = db.session.get(User, run.seller_id) if run.seller_id else None
    reasons = run.reasons or []
    out = {
        "id": run.public_id,
        "subject_type": run.subject_type,
        "mode": run.mode,
        "status": run.status,
        "decision": run.decision,
        "outcome": run.outcome,
        "applied": run.applied_at is not None,
        "applied_at": run.applied_at.isoformat() if run.applied_at else None,
        "attempts": run.attempts,
        "reason_codes": [r.get("code") for r in reasons if r.get("level") in ("review", "hold")],
        "reason_labels": [
            reason_mod.label_for(r.get("code")) for r in reasons if r.get("level") in ("review", "hold")
        ],
        "suspicious": any(r.get("suspicious") for r in reasons),
        "admin_outcome": run.admin_outcome,
        "admin_outcome_by": run.admin_outcome_by,
        "admin_outcome_at": run.admin_outcome_at.isoformat() if run.admin_outcome_at else None,
        "override_action": run.override_action,
        "override_by": run.override_by,
        "override_at": run.override_at.isoformat() if run.override_at else None,
        "override_note": run.override_note,
        "created_at": run.created_at.isoformat() if run.created_at else None,
        "decided_at": run.decided_at.isoformat() if run.decided_at else None,
        "listing": {
            "id": run.car_public_id,
            "title": car.title if car else None,
            "status": car.status if car else None,
            "is_active": bool(car.is_active) if car else None,
            "price": float(car.price) if car is not None and car.price is not None else None,
            "currency": car.currency if car else None,
        },
        "seller": {"id": seller.public_id, "username": seller.username} if seller else None,
        "revision_id": run.revision_public_id,
    }
    if detail:
        out.update(
            {
                "reasons": [reason_mod.enrich(r) for r in reasons if isinstance(r, dict)],
                "checks": run.checks,
                "ai": run.ai,
                "content_token": run.content_token,
                "engine_version": run.engine_version,
                "error": run.error,
                "events": [_event_dict(e) for e in run.events],
            }
        )
    return out


def _find_run(public_id: str) -> ListingModerationRun | None:
    return ListingModerationRun.query.filter_by(public_id=(public_id or "").strip()).first()


@bp.route("/settings", methods=["GET"])
@admin_required
def get_settings():
    denied = _deny("auto_moderation.read")
    if denied:
        return denied
    payload = config.public_settings()
    payload["shadow_report"] = stats.shadow_report(payload["settings"])
    return jsonify(payload), 200


@bp.route("/settings", methods=["PUT", "PATCH"])
@admin_required
def update_settings():
    denied = _deny("auto_moderation.write")
    if denied:
        return denied
    try:
        admin_user = get_current_user()
        body = request.get_json(silent=True)
        if not isinstance(body, dict):
            return jsonify({"message": "JSON object required"}), 400
        body = dict(body)
        confirm_live = body.pop("confirm_live", False) is True
        try:
            patch = config.validate_patch(body)
        except ValueError as e:
            return jsonify({"message": str(e), "code": "invalid_setting"}), 400

        current = config.load_settings()
        merged = config._deep_merge(current, patch)
        if patch.get("mode") == "live" and current.get("mode") != "live":
            if not config.env_allow_live():
                return (
                    jsonify(
                        {
                            "code": "live_not_allowed_by_environment",
                            "message": "Live auto-approval is not allowed by this environment "
                            "(AUTO_MODERATION_ALLOW_LIVE is not set).",
                        }
                    ),
                    409,
                )
            if config.kill_switch_active(current):
                return (
                    jsonify({"code": "kill_switch_active", "message": "Release the kill switch first."}),
                    409,
                )
            if merged.get("require_ai_for_auto_approve", True) and not config.ai_provider_configured():
                return (
                    jsonify(
                        {
                            "code": "ai_not_configured",
                            "message": "No AI provider is configured, and auto-approval is set to "
                            "require one.",
                        }
                    ),
                    409,
                )
            # Judged against the gate settings ALREADY in force: loosening the
            # thresholds and flipping to live in one request is not allowed.
            report = stats.shadow_report(current)
            if not report["gate"]["passed"]:
                return (
                    jsonify(
                        {
                            "code": "shadow_gate_not_passed",
                            "message": "Shadow-mode results do not yet meet the configured "
                            "thresholds for live mode.",
                            "shadow_report": report,
                        }
                    ),
                    409,
                )
            if not confirm_live:
                return (
                    jsonify(
                        {
                            "code": "confirmation_required",
                            "message": "Send confirm_live: true to enable automatic approval.",
                            "shadow_report": report,
                        }
                    ),
                    400,
                )
        new = config.save_settings(patch)
        if admin_user:
            log_user_action(
                admin_user,
                "admin_update_auto_moderation_settings",
                target_type="settings",
                target_id="auto_moderation",
                metadata={"keys": sorted(patch.keys()), "mode": patch.get("mode")},
            )
        return jsonify(config.public_settings(new)), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin auto-moderation update_settings error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update auto-moderation settings"}), 500


@bp.route("/kill-switch", methods=["POST"])
@admin_required
def kill_switch():
    """Engage (moderator or super_admin) / release (super_admin) the global
    kill switch. Takes effect immediately: the apply step re-reads it under
    the subject's lock, so even a decision already in flight is blocked."""
    body = request.get_json(silent=True) or {}
    if not isinstance(body.get("enabled"), bool):
        return jsonify({"message": "enabled (boolean) is required"}), 400
    enabled = body["enabled"]
    denied = _deny("auto_moderation.killswitch" if enabled else "auto_moderation.write")
    if denied:
        return denied
    try:
        admin_user = get_current_user()
        reason = str(body.get("reason") or "")
        new = config.set_kill_switch(enabled, actor=_admin_name(admin_user), reason=reason)
        if admin_user:
            log_user_action(
                admin_user,
                "admin_auto_moderation_kill_switch",
                target_type="settings",
                target_id="auto_moderation",
                metadata={"enabled": enabled, "reason": reason[:300]},
            )
        out = config.public_settings(new)
        if not enabled and config.env_kill_switch():
            out["warning"] = "AUTO_MODERATION_KILL_SWITCH is set in the environment and still forces the switch on."
        return jsonify(out), 200
    except Exception as e:
        db.session.rollback()
        logger.error("admin auto-moderation kill_switch error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to update kill switch"}), 500


@bp.route("/stats", methods=["GET"])
@admin_required
def get_stats():
    denied = _deny("auto_moderation.read")
    if denied:
        return denied
    days = min(max(request.args.get("days", 30, type=int), 1), 365)
    return jsonify(stats.summary(days)), 200


@bp.route("/shadow-report", methods=["GET"])
@admin_required
def get_shadow_report():
    denied = _deny("auto_moderation.read")
    if denied:
        return denied
    days = request.args.get("days", type=int)
    return jsonify(stats.shadow_report(config.load_settings(), days)), 200


_VIEWS = {
    "all": lambda q: q,
    "auto_approved": lambda q: q.filter(ListingModerationRun.outcome == "published"),
    "would_approve": lambda q: q.filter(
        ListingModerationRun.mode == "shadow", ListingModerationRun.decision == "AUTO_APPROVE"
    ),
    "flagged": lambda q: q.filter(ListingModerationRun.decision == "NEEDS_REVIEW"),
    "held": lambda q: q.filter(ListingModerationRun.decision == "HOLD"),
    "errors": lambda q: q.filter(ListingModerationRun.status == "error"),
}


@bp.route("/runs", methods=["GET"])
@admin_required
def list_runs():
    denied = _deny("auto_moderation.read")
    if denied:
        return denied
    view = (request.args.get("view") or "all").strip().lower()
    if view not in _VIEWS:
        return jsonify({"message": "Invalid view"}), 400
    page = request.args.get("page", 1, type=int)
    per_page = min(max(request.args.get("per_page", 20, type=int), 1), 100)
    q = ListingModerationRun.query.filter(ListingModerationRun.status != "stale")
    q = _VIEWS[view](q)
    stype = (request.args.get("subject_type") or "").strip()
    if stype in ("listing", "revision"):
        q = q.filter(ListingModerationRun.subject_type == stype)
    mode = (request.args.get("mode") or "").strip()
    if mode in ("shadow", "live"):
        q = q.filter(ListingModerationRun.mode == mode)
    if request.args.get("awaiting_human") in ("1", "true"):
        q = q.filter(ListingModerationRun.admin_outcome.is_(None))
    pagination = q.order_by(ListingModerationRun.id.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )
    return (
        jsonify(
            {
                "runs": [_run_dict(r) for r in pagination.items],
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


@bp.route("/runs/<run_id>", methods=["GET"])
@admin_required
def run_detail(run_id: str):
    denied = _deny("auto_moderation.read")
    if denied:
        return denied
    run = _find_run(run_id)
    if run is None:
        return jsonify({"message": "Run not found"}), 404
    return jsonify({"run": _run_dict(run, detail=True)}), 200


@bp.route("/listings/<car_id>/history", methods=["GET"])
@admin_required
def listing_history(car_id: str):
    """Every evaluation and log event for one listing (including its edits)."""
    denied = _deny("auto_moderation.read")
    if denied:
        return denied
    cid = (car_id or "").strip()
    car = Car.query.filter_by(public_id=cid).first()
    if car is None and cid.isdigit():
        car = db.session.get(Car, int(cid))
    public_id = car.public_id if car else cid
    runs = (
        ListingModerationRun.query.filter_by(car_public_id=public_id)
        .order_by(ListingModerationRun.id.desc())
        .limit(100)
        .all()
    )
    return jsonify({"runs": [_run_dict(r, detail=True) for r in runs]}), 200


@bp.route("/runs/<run_id>/override", methods=["POST"])
@admin_required
def override_run(run_id: str):
    denied = _deny("listings.write") or _deny("auto_moderation.read")
    if denied:
        return denied
    run = _find_run(run_id)
    if run is None:
        return jsonify({"message": "Run not found"}), 404
    body = request.get_json(silent=True) or {}
    action = str(body.get("action") or "").strip().lower()
    note = str(body.get("note") or "")
    admin_user = get_current_user()
    admin = _admin_name(admin_user)
    try:
        if action == "approve":
            result = admin_actions.approve(run.id, admin=admin, note=note)
        elif action == "revoke":
            result = admin_actions.revoke(run.id, admin=admin, note=note)
        elif action == "require_review":
            result = admin_actions.require_review(run.id, admin=admin, note=note)
        elif action == "clear_review_pin":
            result = admin_actions.require_review(run.id, admin=admin, note=note, clear=True)
        else:
            return jsonify({"message": "Unknown action", "code": "invalid_action"}), 400
        if admin_user:
            log_user_action(
                admin_user,
                f"admin_auto_moderation_{action}",
                target_type="car",
                target_id=run.car_public_id,
                metadata={"run": run.public_id},
            )
        return jsonify(result), 200
    except admin_actions.ActionError as e:
        db.session.rollback()
        return jsonify(e.to_dict()), e.status
    except Exception as e:
        db.session.rollback()
        logger.error("admin auto-moderation override error: %s", e, exc_info=True)
        return jsonify({"message": "Failed to apply override"}), 500


@bp.route("/runs/<run_id>/reevaluate", methods=["POST"])
@admin_required
def reevaluate_run(run_id: str):
    denied = _deny("listings.write") or _deny("auto_moderation.read")
    if denied:
        return denied
    run = _find_run(run_id)
    if run is None:
        return jsonify({"message": "Run not found"}), 404
    sid = run.revision_id if run.subject_type == "revision" else run.car_id
    if sid is None:
        return jsonify({"message": "Nothing left to evaluate", "code": "subject_gone"}), 409
    queued = request_moderation(run.subject_type, sid, trigger="manual")
    return jsonify({"queued": bool(queued)}), (202 if queued else 503)
