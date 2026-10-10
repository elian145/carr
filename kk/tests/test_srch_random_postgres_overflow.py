"""SRCH-3 hotfix: Postgres integer overflow in seeded random ORDER BY.

Production regression after Search Batch 2: GET /api/cars?sort_by=random
(and recommended without preferences) returned HTTP 500 on PostgreSQL
because ``seeded_random_order_expr`` multiplied ``car.id`` (INTEGER) by a
near-int32 CRC seed, overflowing Postgres int32 arithmetic.

SQLite silently promotes integers, so the existing suite could not catch this.

These tests require a disposable local PostgreSQL (never Neon production).
They auto-start a throwaway cluster from portable binaries under ``.tmp_pg``
when present, or honor ``CARNET_DISPOSABLE_PG_URL``.
"""

from __future__ import annotations

import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

import pytest
from sqlalchemy import Column, Integer, MetaData, Table
from sqlalchemy.dialects import postgresql

_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

_PG_BIN = _REPO_ROOT / ".tmp_pg" / "pgsql" / "bin"
_MODULUS = 2147483647


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def _pg_bin(name: str) -> Path | None:
    exe = _PG_BIN / (name + (".exe" if os.name == "nt" else ""))
    return exe if exe.is_file() else None


def _start_disposable_postgres():
    """Yield (url, cleanup) for a throwaway local Postgres, or None."""
    env_url = (os.getenv("CARNET_DISPOSABLE_PG_URL") or "").strip()
    if env_url:
        return env_url, (lambda: None)

    initdb = _pg_bin("initdb")
    postgres = _pg_bin("postgres")
    createdb = _pg_bin("createdb")
    if not initdb or not postgres:
        return None

    data_dir = tempfile.mkdtemp(prefix="carnet_pg_data_")
    port = _free_port()
    env = os.environ.copy()
    env["PGHOST"] = "127.0.0.1"
    env["PGPORT"] = str(port)
    env["PGUSER"] = "carnet"
    # Locale-independent init for Windows portable builds.
    subprocess.run(
        [
            str(initdb),
            "-D",
            data_dir,
            "-U",
            "carnet",
            "--auth=trust",
            "--no-instructions",
            "--locale=C",
            "--encoding=UTF8",
        ],
        check=True,
        capture_output=True,
        env=env,
    )
    log_path = os.path.join(data_dir, "pg.log")
    proc = subprocess.Popen(
        [
            str(postgres),
            "-D",
            data_dir,
            "-p",
            str(port),
            "-h",
            "127.0.0.1",
            "-c",
            "fsync=off",
            "-c",
            "synchronous_commit=off",
            "-c",
            "full_page_writes=off",
        ],
        stdout=open(log_path, "w", encoding="utf-8"),
        stderr=subprocess.STDOUT,
        env=env,
    )

    def cleanup():
        try:
            proc.terminate()
            proc.wait(timeout=15)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
        shutil.rmtree(data_dir, ignore_errors=True)

    deadline = time.time() + 30
    while time.time() < deadline:
        if proc.poll() is not None:
            cleanup()
            raise RuntimeError(f"postgres exited early; see {log_path}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                break
        except OSError:
            time.sleep(0.2)
    else:
        cleanup()
        raise RuntimeError(f"postgres did not accept connections; see {log_path}")

    db_name = f"carnet_srch_{uuid.uuid4().hex[:8]}"
    if createdb and createdb.is_file():
        subprocess.run(
            [str(createdb), "-h", "127.0.0.1", "-p", str(port), "-U", "carnet", db_name],
            check=True,
            capture_output=True,
            env=env,
        )
    else:
        # Fallback: connect to postgres DB and CREATE DATABASE.
        import psycopg

        with psycopg.connect(
            f"postgresql://carnet@127.0.0.1:{port}/postgres",
            autocommit=True,
        ) as conn:
            conn.execute(f'CREATE DATABASE "{db_name}"')

    url = f"postgresql+psycopg://carnet@127.0.0.1:{port}/{db_name}"
    return url, cleanup


@pytest.fixture(scope="module")
def pg_url():
    started = _start_disposable_postgres()
    if started is None:
        pytest.skip(
            "No disposable Postgres (set CARNET_DISPOSABLE_PG_URL or unpack "
            "binaries under .tmp_pg/pgsql/bin)"
        )
    url, cleanup = started
    yield url
    cleanup()


@pytest.fixture(scope="module")
def app_ctx(pg_url):
    tmp = tempfile.TemporaryDirectory(
        prefix="carlist_srch_pg_", ignore_cleanup_errors=True
    )
    # Isolate from any ambient DATABASE_URL / Neon credentials.
    prev = {
        k: os.environ.get(k)
        for k in ("DATABASE_URL", "DB_PATH", "APP_ENV", "SMS_PROVIDER", "LISTING_REQUIRE_APPROVAL")
    }
    os.environ["APP_ENV"] = "testing"
    os.environ["SMS_PROVIDER"] = "console"
    os.environ.pop("LISTING_REQUIRE_APPROVAL", None)
    os.environ.pop("DB_PATH", None)
    os.environ["DATABASE_URL"] = pg_url

    from kk.app_factory import create_app

    app, *_ = create_app()
    from kk.models import User, db

    with app.app_context():
        db.drop_all()
        db.create_all()
        assert db.engine.dialect.name == "postgresql", db.engine.dialect.name

    yield app, app.test_client(), db, User

    with app.app_context():
        db.session.remove()
        db.engine.dispose()
    for key, val in prev.items():
        if val is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = val
    tmp.cleanup()


@pytest.fixture
def client(app_ctx):
    return app_ctx[1]


def _phone() -> str:
    return f"077{uuid.uuid4().int % 10**8:08d}"


def _seller(app_ctx) -> int:
    app, _c, db, User = app_ctx
    with app.app_context():
        user = User(
            username=f"pg_{uuid.uuid4().hex[:10]}",
            phone_number=_phone(),
            first_name="P",
            last_name="G",
            is_active=True,
            is_verified=True,
            phone_verified=True,
            public_id=f"pub-{uuid.uuid4().hex[:12]}",
        )
        user.set_password("Aa123456!")
        db.session.add(user)
        db.session.commit()
        return user.id


def _car(
    app_ctx,
    seller_id: int,
    *,
    brand: str,
    model: str,
    year: int = 2020,
    price: int = 10000,
    status: str = "active",
    force_id: int | None = None,
):
    app, _c, db, _User = app_ctx
    from kk.models import Car

    with app.app_context():
        car = Car(
            seller_id=seller_id,
            public_id=f"car-{uuid.uuid4().hex[:12]}",
            brand=brand,
            model=model,
            year=year,
            mileage=10,
            engine_type="gas",
            transmission="auto",
            drive_type="fwd",
            condition="used",
            body_type="suv",
            price=price,
            location="Erbil",
            is_active=True,
            status=status,
            title=f"{brand} {model}",
            media_status="ready",
        )
        if force_id is not None:
            car.id = force_id
        db.session.add(car)
        db.session.commit()
        return {"id": car.id, "public_id": car.public_id, "brand": brand, "model": model}


def _ids(resp) -> list[str]:
    body = resp.get_json()
    return [c["id"] for c in body.get("cars") or []]


# ---------------------------------------------------------------------------
# Pure SQL evidence (bug vs fix) on disposable Postgres
# ---------------------------------------------------------------------------


def test_pg_raw_int_multiply_overflows(pg_url):
    """Pre-fix shape: INTEGER * INTEGER overflows on Postgres."""
    import psycopg

    dsn = pg_url.replace("postgresql+psycopg://", "postgresql://")
    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            with pytest.raises(psycopg.errors.NumericValueOutOfRange):
                # Literal ints only — reproduces production ORDER BY arithmetic.
                cur.execute(
                    f"SELECT MOD((2::integer * {_MODULUS}::integer)"
                    f" + ({_MODULUS}::integer * 17), {_MODULUS}::integer)"
                )


def test_pg_bigint_cast_does_not_overflow(pg_url):
    import psycopg

    dsn = pg_url.replace("postgresql+psycopg://", "postgresql://")
    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT MOD((2::bigint * {_MODULUS}::bigint)"
                f" + ({_MODULUS}::bigint * 17), {_MODULUS}::bigint)"
            )
            assert cur.fetchone()[0] is not None
            # Large listing ids + max seed stay safe.
            cur.execute(
                f"SELECT MOD((2000000000::bigint * {_MODULUS}::bigint)"
                f" + ({_MODULUS}::bigint * 17), {_MODULUS}::bigint)"
            )
            assert cur.fetchone()[0] is not None


def test_seeded_random_order_expr_compiles_with_bigint_casts():
    from kk.listing_search import seeded_random_order_expr

    md = MetaData()
    t = Table("car", md, Column("id", Integer))
    expr = seeded_random_order_expr("overflow-seed", id_column=t.c.id)
    sql = str(
        expr.compile(
            dialect=postgresql.dialect(),
            compile_kwargs={"literal_binds": True},
        )
    ).upper()
    assert "CAST" in sql and "BIGINT" in sql


# ---------------------------------------------------------------------------
# End-to-end API on disposable Postgres
# ---------------------------------------------------------------------------


def test_pg_random_with_seed_http_200(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"PgR-{uuid.uuid4().hex[:8]}"
    for i in range(5):
        _car(app_ctx, seller_id, brand=brand, model=f"M{i}", price=1000 + i)

    resp = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "sort_by": "random",
            "sort_seed": "stable-seed-pg",
            "per_page": 10,
        },
    )
    assert resp.status_code == 200, resp.data
    assert resp.get_json()["pagination"].get("sort_seed") == "stable-seed-pg"


def test_pg_random_without_seed_http_200(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"PgN-{uuid.uuid4().hex[:8]}"
    _car(app_ctx, seller_id, brand=brand, model="X")

    resp = client.get(
        "/api/cars",
        query_string={"brand": brand, "sort_by": "random", "per_page": 5},
    )
    assert resp.status_code == 200, resp.data
    seed = resp.get_json()["pagination"].get("sort_seed")
    assert seed and isinstance(seed, str)


def test_pg_recommended_with_and_without_seed_http_200(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"PgRec-{uuid.uuid4().hex[:8]}"
    for i in range(3):
        _car(app_ctx, seller_id, brand=brand, model=f"R{i}", price=500 + i)

    bare = client.get(
        "/api/cars",
        query_string={"brand": brand, "sort_by": "recommended", "per_page": 10},
    )
    assert bare.status_code == 200, bare.data

    seeded = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "sort_by": "recommended",
            "sort_seed": "rec-seed-1",
            "per_page": 10,
        },
    )
    assert seeded.status_code == 200, seeded.data


def test_pg_random_pagination_45_distinct_across_3_pages(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"Pg45-{uuid.uuid4().hex[:8]}"
    created = [
        _car(app_ctx, seller_id, brand=brand, model=f"P{i}", price=1000 + i)[
            "public_id"
        ]
        for i in range(45)
    ]
    seed = "stable-seed-batch2-pg"
    collected: list[str] = []
    for page in (1, 2, 3):
        resp = client.get(
            "/api/cars",
            query_string={
                "brand": brand,
                "sort_by": "random",
                "sort_seed": seed,
                "page": page,
                "per_page": 20,
            },
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        assert body["pagination"].get("sort_seed") == seed
        collected.extend(_ids(resp))

    assert len(collected) == 45
    assert len(set(collected)) == 45
    assert set(collected) == set(created)

    again = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "sort_by": "random",
            "sort_seed": seed,
            "page": 1,
            "per_page": 20,
        },
    )
    assert _ids(again) == collected[:20]


def test_pg_old_client_omitting_sort_seed_stable(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"PgOld-{uuid.uuid4().hex[:8]}"
    created = [
        _car(app_ctx, seller_id, brand=brand, model=f"O{i}", price=3000 + i)[
            "public_id"
        ]
        for i in range(45)
    ]
    collected: list[str] = []
    echoed: list[str] = []
    for page in (1, 2, 3):
        resp = client.get(
            "/api/cars",
            query_string={
                "brand": brand,
                "sort_by": "random",
                "page": page,
                "per_page": 20,
            },
        )
        assert resp.status_code == 200, resp.data
        body = resp.get_json()
        seed = body["pagination"].get("sort_seed")
        assert seed and isinstance(seed, str)
        echoed.append(seed)
        collected.extend(_ids(resp))

    assert echoed[0] == echoed[1] == echoed[2]
    assert len(collected) == 45
    assert len(set(collected)) == 45
    assert set(collected) == set(created)


def test_pg_large_listing_ids_and_max_seed_safe(app_ctx, client):
    """Force large integer PKs + wide seed so pre-fix int32 multiply dies."""
    seller_id = _seller(app_ctx)
    brand = f"PgBig-{uuid.uuid4().hex[:8]}"
    # Skip serial into a high range, then insert explicit large ids.
    app, _c, db, _User = app_ctx
    with app.app_context():
        db.session.execute(
            db.text("SELECT setval(pg_get_serial_sequence('car', 'id'), 1900000000)")
        )
        db.session.commit()

    created = []
    for i, lid in enumerate((1_900_000_001, 1_900_000_050, 2_000_000_000)):
        created.append(
            _car(
                app_ctx,
                seller_id,
                brand=brand,
                model=f"L{i}",
                price=9000 + i,
                force_id=lid,
            )["public_id"]
        )

    # Max-width CRC-ish seed string; sanitize keeps it hashable.
    seed = "Z" * 64
    resp = client.get(
        "/api/cars",
        query_string={
            "brand": brand,
            "sort_by": "random",
            "sort_seed": seed,
            "per_page": 10,
        },
    )
    assert resp.status_code == 200, resp.data
    assert set(_ids(resp)) == set(created)

    # Advance the serial past explicit PKs so later tests do not collide.
    with app.app_context():
        db.session.execute(
            db.text(
                "SELECT setval(pg_get_serial_sequence('car', 'id'), "
                "(SELECT MAX(id) FROM car))"
            )
        )
        db.session.commit()


def test_pg_filtered_random_pagination_no_dupes(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"PgFlt-{uuid.uuid4().hex[:8]}"
    created = [
        _car(app_ctx, seller_id, brand=brand, model="Camry", price=1000 + i)[
            "public_id"
        ]
        for i in range(25)
    ]
    # Distractors that must not appear when brand-filtered.
    _car(app_ctx, seller_id, brand=f"Other-{uuid.uuid4().hex[:6]}", model="X", price=1)

    seed = "filter-seed-pg"
    collected: list[str] = []
    for page in (1, 2):
        resp = client.get(
            "/api/cars",
            query_string={
                "brand": brand,
                "model": "Camry",
                "model_match": "exact",
                "sort_by": "random",
                "sort_seed": seed,
                "page": page,
                "per_page": 20,
            },
        )
        assert resp.status_code == 200, resp.data
        collected.extend(_ids(resp))

    assert len(collected) == 25
    assert len(set(collected)) == 25
    assert set(collected) == set(created)


def test_pg_newest_oldest_price_unchanged(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"PgSort-{uuid.uuid4().hex[:8]}"
    cheap = _car(app_ctx, seller_id, brand=brand, model="A", price=100)
    mid = _car(app_ctx, seller_id, brand=brand, model="B", price=500)
    dear = _car(app_ctx, seller_id, brand=brand, model="C", price=900)

    newest = client.get(
        "/api/cars",
        query_string={"brand": brand, "sort_by": "newest", "per_page": 10},
    )
    assert newest.status_code == 200
    nids = _ids(newest)
    assert nids.index(dear["public_id"]) < nids.index(cheap["public_id"])

    oldest = client.get(
        "/api/cars",
        query_string={"brand": brand, "sort_by": "oldest", "per_page": 10},
    )
    assert oldest.status_code == 200
    oids = _ids(oldest)
    assert oids.index(cheap["public_id"]) < oids.index(dear["public_id"])

    price_asc = client.get(
        "/api/cars",
        query_string={"brand": brand, "sort_by": "price_asc", "per_page": 10},
    )
    assert price_asc.status_code == 200
    assert _ids(price_asc) == [
        cheap["public_id"],
        mid["public_id"],
        dear["public_id"],
    ]


def test_pg_invalid_oversized_seed_safe(app_ctx, client):
    seller_id = _seller(app_ctx)
    brand = f"PgBad-{uuid.uuid4().hex[:8]}"
    _car(app_ctx, seller_id, brand=brand, model="B")

    for bad in ("x" * 500, "'; DROP TABLE car; --", "@@@", -999):
        resp = client.get(
            "/api/cars",
            query_string={
                "brand": brand,
                "sort_by": "random",
                "sort_seed": bad,
                "per_page": 5,
            },
        )
        assert resp.status_code == 200, (bad, resp.data)
        assert isinstance(resp.get_json()["pagination"].get("sort_seed"), str)
