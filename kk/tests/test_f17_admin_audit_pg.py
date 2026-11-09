"""F-17 on a DISPOSABLE PostgreSQL: migration b8e4f2a6c1d3 up/down, no FK to
user, append-only trigger, and user deletion cascading user_action but not the
audit trail. Opt-in like the other *_pg tests (CARNET_PG_TEST_URL +
CARNET_PG_TEST_CONFIRM_DISPOSABLE=1, local host only).
"""

from __future__ import annotations

import os

import pytest

from kk.tests.test_b8_account_deletion_pg import (
    PG_URL,
    _drop,
    _flask_db,
    _insert_user,
    _q,
    _recreate,
    _require_disposable,
)

pytestmark = pytest.mark.skipif(
    not PG_URL, reason="CARNET_PG_TEST_URL not set (PostgreSQL rehearsal only)"
)

PREV = "a7d3e1c9b5f2"
TIP = "b8e4f2a6c1d3"


@pytest.fixture(scope="module")
def dsn():
    from sqlalchemy.engine import make_url

    url = make_url(PG_URL).set(drivername="postgresql")
    _require_disposable(url)
    name = f"{url.database}_f17"
    _recreate(url, name)
    d = url.set(database=name).render_as_string(hide_password=False)
    _flask_db(d, "upgrade")
    yield d
    _drop(url, name)


def test_schema_has_no_fk_and_trigger(dsn):
    assert _q(dsn, "select version_num from alembic_version") == [(TIP,)]
    assert _q(
        dsn, "select count(*) from pg_constraint where conrelid = 'admin_audit_log'::regclass and contype = 'f'"
    ) == [(0,)]
    assert _q(
        dsn, "select count(*) from pg_trigger where tgrelid = 'admin_audit_log'::regclass and not tgisinternal"
    ) == [(1,)]


def test_append_only_trigger_and_no_cascade_from_user_delete(dsn):
    import psycopg

    uid = _insert_user(dsn)
    _q(dsn, "insert into admin_audit_log (admin_user_id, admin_username, action_type, created_at) "
            "values (%s, 'adm', 'admin_purge_user', now())", uid)
    _q(dsn, "insert into user_action (user_id, action_type, created_at) values (%s, 'admin_purge_user', now())", uid)

    with pytest.raises(psycopg.errors.RaiseException):
        _q(dsn, "update admin_audit_log set action_type = 'x' where admin_user_id = %s", uid)
    with pytest.raises(psycopg.errors.RaiseException):
        _q(dsn, "delete from admin_audit_log where admin_user_id = %s", uid)

    _q(dsn, 'delete from "user" where id = %s', uid)
    assert _q(dsn, "select count(*) from user_action where user_id = %s", uid) == [(0,)]  # the F-17 cascade
    assert _q(dsn, "select count(*) from admin_audit_log where admin_user_id = %s", uid) == [(1,)]


def test_downgrade_then_upgrade_is_clean(dsn):
    _flask_db(dsn, "downgrade", PREV)
    assert _q(dsn, "select version_num from alembic_version") == [(PREV,)]
    assert _q(dsn, "select to_regclass('public.admin_audit_log') is not null") == [(False,)]
    assert _q(dsn, "select count(*) from pg_proc where proname = 'admin_audit_log_append_only'") == [(0,)]
    assert _q(dsn, "select to_regclass('public.account_deletion_request') is not null") == [(True,)]
    _flask_db(dsn, "upgrade")
    assert _q(dsn, "select version_num from alembic_version") == [(TIP,)]
    assert _q(dsn, "select to_regclass('public.admin_audit_log') is not null") == [(True,)]
