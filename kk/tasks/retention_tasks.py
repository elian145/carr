"""Celery wrapper for the opt-in retention cleanup (F-16). See kk/retention.py."""

from __future__ import annotations

from ..retention import retention_mode, run_retention
from .celery_app import celery_app


@celery_app.task(name="kk.tasks.retention_tasks.run_retention_cleanup")
def run_retention_cleanup() -> dict:
    """No-op unless RETENTION_ENABLED=1; counts only unless RETENTION_DRY_RUN=0."""
    mode = retention_mode()
    return {"mode": mode, "counts": run_retention()}
