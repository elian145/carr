"""Celery Flask app context sharing (P-06)."""

from __future__ import annotations

import os

import pytest

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-celery")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-celery")


@pytest.fixture(autouse=True)
def _reset_celery_flask_app_singleton():
    """Test-isolation guard: `kk.tasks.celery_app._flask_app` is a
    process-global lazy singleton (see its own docstring: "Created once per
    process"). Both tests below explicitly call
    ``reset_celery_flask_app_for_tests()`` then ``get_celery_flask_app()``,
    which (re)creates that singleton bound to *this file's* own minimal,
    no-``DB_PATH`` Flask app/database.

    Without resetting it again afterward, that stale app stays cached for
    the rest of the pytest process. Any later test module that calls a
    ``@celery_app.task``-decorated function *directly* (not via
    ``.delay()``/``.apply()``) -- e.g.
    ``kk.tasks.alert_tasks.notify_saved_searches_for_car``/
    ``notify_price_drop_for_car`` in ``test_mi03_locale.py`` -- would then
    silently run inside *this* stale app context instead of its own
    (``FlaskContextTask.__call__`` always pushes whatever
    ``get_celery_flask_app()`` currently returns), so ``db.session.get(Car,
    car_id)`` looks up the id in the wrong database and finds nothing.
    """
    yield
    from kk.tasks.celery_app import reset_celery_flask_app_for_tests

    reset_celery_flask_app_for_tests()


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


def test_reset_helper_actually_clears_the_singleton():
    """Regression guard for the test-isolation fix in
    `_reset_celery_flask_app_singleton` above: pins the exact contract that
    fixture depends on -- `reset_celery_flask_app_for_tests()` must set the
    module-global `_flask_app` back to `None`, not merely leave it pointing
    at *a* Flask app. If this contract silently breaks, this file's own
    tests would go back to leaking their (no-``DB_PATH``) app into whatever
    test module runs next in the same pytest process -- e.g.
    `test_mi03_locale.py`'s direct calls into `@celery_app.task`-decorated
    background functions, which push whatever `get_celery_flask_app()`
    currently returns via `FlaskContextTask.__call__`."""
    import kk.tasks.celery_app as celery_app_module

    celery_app_module.get_celery_flask_app()
    assert celery_app_module._flask_app is not None

    celery_app_module.reset_celery_flask_app_for_tests()
    assert celery_app_module._flask_app is None
