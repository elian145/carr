from __future__ import annotations

from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required

from celery.result import AsyncResult

from ..tasks.celery_app import celery_app

bp = Blueprint("jobs", __name__)


@bp.route("/api/jobs/<task_id>", methods=["GET"])
@jwt_required()
def job_status(task_id: str):
    """
    Poll a Celery task result.
    """
    try:
        r = AsyncResult(task_id, app=celery_app)
        payload = {"task_id": task_id, "state": r.state}
        if r.successful():
            payload["result"] = r.result
        elif r.failed():
            payload["error"] = "job_failed"
        return jsonify(payload), 200
    except Exception:
        # Broker/backend unavailable (e.g., Redis not running). Keep response stable.
        return jsonify({"task_id": task_id, "state": "UNAVAILABLE", "error": "jobs_backend_unavailable"}), 503

