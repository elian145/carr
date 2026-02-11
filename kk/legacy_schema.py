from __future__ import annotations


def ensure_minimal_schema_compat(app, db) -> None:
    """
    Best-effort schema compatibility for legacy SQLite DBs.

    This is intentionally defensive: it should never block app startup.
    """
    try:
        with app.app_context():
            from sqlalchemy import text

            conn = db.engine.connect()

            def _cols(table: str):
                return {row[1] for row in conn.execute(text(f"PRAGMA table_info({table})"))}

            try:
                car_cols = _cols("car")

                def _add_car(col: str, typ: str):
                    if col not in car_cols:
                        conn.execute(text(f"ALTER TABLE car ADD COLUMN {col} {typ}"))
                        car_cols.add(col)

                _add_car("public_id", "VARCHAR(50)")
                _add_car("seller_id", "INTEGER")
                for col, typ in (
                    ("brand", "TEXT"),
                    ("model", "TEXT"),
                    ("year", "INTEGER DEFAULT 0"),
                    ("mileage", "INTEGER DEFAULT 0"),
                    ("engine_type", "TEXT"),
                    ("transmission", "TEXT"),
                    ("drive_type", "TEXT"),
                    ("condition", "TEXT"),
                    ("body_type", "TEXT"),
                    ("status", "TEXT DEFAULT 'active'"),
                ):
                    _add_car(col, typ)

                for col, typ in (
                    ("price", "FLOAT DEFAULT 0"),
                    ("currency", "TEXT DEFAULT 'USD'"),
                    ("location", "TEXT"),
                    ("seating", "INTEGER DEFAULT 5"),
                    ("latitude", "FLOAT"),
                    ("longitude", "FLOAT"),
                ):
                    _add_car(col, typ)

                for col, typ in (
                    ("trim", "TEXT"),
                    ("title_status", "TEXT"),
                    ("fuel_type", "TEXT"),
                    ("color", "TEXT"),
                    ("fuel_economy", "TEXT"),
                    ("vin", "TEXT"),
                    ("is_active", "BOOLEAN DEFAULT 1"),
                    ("is_featured", "BOOLEAN DEFAULT 0"),
                    ("views", "INTEGER DEFAULT 0"),
                    ("created_at", "DATETIME"),
                    ("updated_at", "DATETIME"),
                ):
                    _add_car(col, typ)

                conn.commit()

                # User table columns
                user_cols = _cols("user")

                def _add_user(col: str, typ: str):
                    if col not in user_cols:
                        conn.execute(text(f"ALTER TABLE user ADD COLUMN {col} {typ}"))
                        user_cols.add(col)

                for col, typ in (
                    ("public_id", "VARCHAR(50)"),
                    ("email", "TEXT"),
                    ("phone_number", "TEXT"),
                    ("first_name", "TEXT"),
                    ("last_name", "TEXT"),
                    ("is_admin", "BOOLEAN DEFAULT 0"),
                    ("is_active", "BOOLEAN DEFAULT 1"),
                    ("is_verified", "BOOLEAN DEFAULT 0"),
                    ("phone_verification_code_hash", "TEXT"),
                    ("phone_verification_expires_at", "DATETIME"),
                    ("phone_verification_attempts", "INTEGER DEFAULT 0"),
                    ("phone_verification_last_sent_at", "DATETIME"),
                    ("phone_verification_locked_until", "DATETIME"),
                    ("profile_picture", "TEXT"),
                    ("last_login", "DATETIME"),
                    ("created_at", "DATETIME"),
                    ("updated_at", "DATETIME"),
                ):
                    _add_user(col, typ)

                conn.commit()

                # Car image table columns
                ci_cols = _cols("car_image")

                def _add_ci(col: str, typ: str):
                    if col not in ci_cols:
                        conn.execute(text(f"ALTER TABLE car_image ADD COLUMN {col} {typ}"))
                        ci_cols.add(col)

                for col, typ in (
                    ("is_primary", "BOOLEAN DEFAULT 0"),
                    ('"order"', "INTEGER DEFAULT 0"),
                    ("created_at", "DATETIME"),
                ):
                    _add_ci(col, typ)

                conn.commit()

                # Car video table columns
                cv_cols = _cols("car_video")

                def _add_cv(col: str, typ: str):
                    if col not in cv_cols:
                        conn.execute(text(f"ALTER TABLE car_video ADD COLUMN {col} {typ}"))
                        cv_cols.add(col)

                for col, typ in (
                    ("thumbnail_url", "TEXT"),
                    ("duration", "INTEGER"),
                    ('"order"', "INTEGER DEFAULT 0"),
                    ("created_at", "DATETIME"),
                ):
                    _add_cv(col, typ)

                conn.commit()
            finally:
                conn.close()
    except Exception:
        # Best-effort; do not block app startup
        pass

