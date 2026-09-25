"""Regression guard for a Celery Beat task-name mismatch.

Bug: the ``cleanup-stale-image-staging-objects`` Beat schedule entry in
``kk/tasks/celery_app.py`` sent the dotted-module-path-style name
``"kk.tasks.image_tasks.cleanup_stale_image_staging_objects"``, but the task
itself is registered under the explicit SHORT name
``"kk.cleanup_stale_image_staging_objects"`` (see the
``@celery_app.task(name=...)`` decorator on
``kk.tasks.image_tasks.cleanup_stale_image_staging_objects``). Celery Beat
sends tasks by name string, not by import path, so a worker receiving that
schedule logged "Received unregistered task of type
'kk.tasks.image_tasks.cleanup_stale_image_staging_objects'" and the hourly
staging-cleanup sweep never ran.

This test compares the Beat schedule's ``"task"`` string against the task's
own ``.name`` attribute (not a second hardcoded literal) so it cannot drift
out of sync with whatever name the task is actually registered under, and
additionally checks that name is present in the live Celery task registry --
the exact condition the worker checks before running a task.
"""

from __future__ import annotations

import os

os.environ.setdefault("APP_ENV", "testing")
os.environ.setdefault("SECRET_KEY", "test-secret-key-for-celery-beat")
os.environ.setdefault("JWT_SECRET_KEY", "test-jwt-secret-key-for-celery-beat")


def test_cleanup_stale_staging_beat_entry_matches_registered_task_name():
    from kk.tasks import image_tasks
    from kk.tasks.celery_app import celery_app

    beat_entry = celery_app.conf.beat_schedule["cleanup-stale-image-staging-objects"]
    scheduled_name = beat_entry["task"]

    registered_name = image_tasks.cleanup_stale_image_staging_objects.name

    assert scheduled_name == registered_name, (
        "Beat schedule sends a task name that does not match the name "
        f"cleanup_stale_image_staging_objects is actually registered under: "
        f"scheduled={scheduled_name!r} registered={registered_name!r}. "
        "The worker would log 'Received unregistered task' and this backstop "
        "sweep would never run."
    )


def test_cleanup_stale_staging_beat_entry_name_is_a_real_registered_task():
    """The name Beat sends must actually exist in the Celery task registry --
    this is precisely what the worker checks before executing a task, and is
    what would raise "Received unregistered task of type ..." if it failed.
    """
    from kk.tasks.celery_app import celery_app

    scheduled_name = celery_app.conf.beat_schedule[
        "cleanup-stale-image-staging-objects"
    ]["task"]

    assert scheduled_name in celery_app.tasks, (
        f"Beat schedule references task name {scheduled_name!r}, which is "
        "not present in celery_app.tasks (the live task registry a worker "
        "consults before running a task)."
    )


def test_every_beat_schedule_entry_names_a_real_registered_task():
    """Generic guard covering every current AND future Beat entry (not just
    the one that was actually broken) -- so a future task added with the
    same short-name-vs-module-path-name mistake (e.g. the video-staging
    cleanup sweep added right after this fix) is caught the same way,
    without needing a new hardcoded test per task.

    ``celery_app.tasks`` is only fully populated once every module listed
    in ``include=[...]`` has actually been imported -- a real worker does
    this at startup (``celery.loader.import_default_modules()``), but a
    plain ``import celery_app`` alone does not, so this explicitly forces
    the same import step a worker would do, rather than relying on
    whichever task modules other test files happened to import first in
    this pytest process.
    """
    from kk.tasks.celery_app import celery_app

    celery_app.loader.import_default_modules()

    schedule = celery_app.conf.beat_schedule
    assert schedule, "expected at least one Beat schedule entry"

    for entry_name, entry in schedule.items():
        scheduled_name = entry["task"]
        assert scheduled_name in celery_app.tasks, (
            f"Beat entry {entry_name!r} references task name "
            f"{scheduled_name!r}, which is not in celery_app.tasks -- the "
            "worker would log 'Received unregistered task' for this entry."
        )
