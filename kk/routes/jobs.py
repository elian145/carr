from __future__ import annotations

import logging

from flask import Blueprint, jsonify
from flask_jwt_extended import jwt_required

from celery.result import AsyncResult

from ..auth import get_current_user
from ..job_ownership import is_valid_task_id, resolve_job_owner
from ..tasks.celery_app import celery_app

logger = logging.getLogger(__name__)

bp = Blueprint("jobs", __name__)


def _public_job_result(result) -> dict | list | str | int | float | bool | None:
    """Strip internal ownership fields before returning results to clients."""
    if not isinstance(result, dict):
        return result
    cleaned = dict(result)
    cleaned.pop("owner_public_id", None)
    cleaned.pop("ownerPublicId", None)
    return cleaned


@bp.route("/api/jobs/<task_id>", methods=["GET"])
@jwt_required()
def job_status(task_id: str):
    """
    Poll a Celery task result.

    Only the user who enqueued the job may read its state/result.
    """
    me = get_current_user()
    if not me:
        return jsonify({"message": "Unauthorized"}), 401

    tid = (task_id or "").strip()
    if not is_valid_task_id(tid):
        return jsonify({"message": "Job not found"}), 404

    try:
        r = AsyncResult(tid, app=celery_app)
        state = r.state

        result_payload = None
        meta_payload = None
        try:
            if state == "SUCCESS":
                result_payload = r.result
            info = r.info
            if isinstance(info, dict):
                meta_payload = info
        except Exception:
            result_payload = None
            meta_payload = None

        owner = resolve_job_owner(
            tid,
            result_payload=result_payload,
            meta_payload=meta_payload,
        )
        if not owner or owner != me.public_id:
            # Do not leak existence of other users' jobs.
            logger.info(
                "job_status denied for user %s on task %s (owner=%s)",
                me.public_id,
                tid,
                owner or "unknown",
            )
            return jsonify({"message": "Job not found"}), 404

        payload: dict = {"task_id": tid, "state": state}
        if state == "SUCCESS":
            payload["result"] = _public_job_result(result_payload)
        elif state == "FAILURE":
            payload["error"] = "job_failed"
        return jsonify(payload), 200
    except Exception:
        # Broker/backend unavailable (e.g., Redis not running). Keep response stable.
        # Only the registered owner should learn that the backend is down for this id.
        owner = resolve_job_owner(tid)
        if not owner or owner != me.public_id:
            return jsonify({"message": "Job not found"}), 404
        return jsonify(
            {
                "task_id": tid,
                "state": "UNAVAILABLE",
                "error": "jobs_backend_unavailable",
            }
        ), 503
