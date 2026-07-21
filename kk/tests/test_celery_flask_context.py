"""Celery Flask app context sharing (P-06)."""

from __future__ import annotations

import os

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-celery")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-celery")


def test_get_celery_flask_app_is_process_singleton():
    from kk.tasks.celery_app import (
        FlaskContextTask,
        celery_app,
        get_celery_flask_app,
        reset_celery_flask_app_for_tests,
    )

    reset_celery_flask_app_for_tests()
    a = get_celery_flask_app()
    b = get_celery_flask_app()
    assert a is b
    assert celery_app.Task is FlaskContextTask or issubclass(celery_app.Task, FlaskContextTask)


def test_flask_context_task_pushes_app_context():
    from flask import current_app, has_app_context

    from kk.tasks.celery_app import celery_app, get_celery_flask_app, reset_celery_flask_app_for_tests

    reset_celery_flask_app_for_tests()
    app = get_celery_flask_app()

    @celery_app.task(name="kk.tests.probe_context_task")
    def probe():
        assert has_app_context()
        assert current_app.name == app.name
        return "ok"

    assert probe.apply().get() == "ok"
