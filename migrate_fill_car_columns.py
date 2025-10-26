import sys
import uuid
from datetime import datetime

sys.path.append('kk')

import app_new as app_module
from models import db
from sqlalchemy import text


def add_column(conn, table: str, col: str, typ: str):
    cols = {row[1] for row in conn.execute(text(f"PRAGMA table_info({table})"))}
    if col not in cols:
        conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {col} {typ}"))
        return True
    return False


def run():
    app = app_module.app
    with app.app_context():
        eng = db.engine
        with eng.connect() as conn:
            # Ensure table exists
            db.create_all()

            changed = False
            # Core columns expected by kk/models.py
            core = [
                ("public_id", "VARCHAR(50)"),
                ("seller_id", "INTEGER"),
                ("brand", "VARCHAR(50)"),
                ("model", "VARCHAR(50)"),
                ("year", "INTEGER"),
                ("mileage", "INTEGER DEFAULT 0"),
                ("engine_type", "VARCHAR(50)"),
                ("transmission", "VARCHAR(20)"),
                ("drive_type", "VARCHAR(20)"),
                ("condition", "VARCHAR(20)"),
                ("body_type", "VARCHAR(30)"),
                ("price", "FLOAT"),
                ("currency", "VARCHAR(3) DEFAULT 'USD'"),
                ("location", "VARCHAR(100)"),
                ("latitude", "FLOAT"),
                ("longitude", "FLOAT"),
                ("description", "TEXT"),
                ("color", "VARCHAR(30)"),
                ("fuel_economy", "VARCHAR(20)"),
                ("vin", "VARCHAR(17)"),
                ("is_active", "BOOLEAN DEFAULT 1"),
                ("is_featured", "BOOLEAN DEFAULT 0"),
                ("views_count", "INTEGER DEFAULT 0"),
                ("created_at", "DATETIME"),
                ("updated_at", "DATETIME"),
                # AI columns (might already be present via previous migration)
                ("ai_analyzed", "BOOLEAN DEFAULT 0"),
                ("ai_detected_brand", "VARCHAR(50)"),
                ("ai_detected_model", "VARCHAR(50)"),
                ("ai_detected_color", "VARCHAR(20)"),
                ("ai_detected_body_type", "VARCHAR(20)"),
                ("ai_detected_condition", "VARCHAR(20)"),
                ("ai_confidence_score", "FLOAT"),
                ("ai_analysis_timestamp", "DATETIME"),
                ("license_plates_blurred", "BOOLEAN DEFAULT 0"),
            ]

            for col, typ in core:
                changed |= add_column(conn, "car", col, typ)

            # Backfill values from legacy columns where possible
            car_cols = {row[1] for row in conn.execute(text('PRAGMA table_info(car)'))}

            # seller_id backfill from any known legacy column
            if 'seller_id' in car_cols:
                for legacy in ('user_id', 'seller', 'owner_id'):
                    if legacy in car_cols:
                        conn.execute(text(f"UPDATE car SET seller_id = {legacy} WHERE seller_id IS NULL"))
                        break

            # engine_type from fuel_type, with default
            if 'engine_type' in car_cols:
                if 'fuel_type' in car_cols:
                    conn.execute(text("UPDATE car SET engine_type = fuel_type WHERE (engine_type IS NULL OR engine_type = '') AND (fuel_type IS NOT NULL AND fuel_type <> '')"))
                conn.execute(text("UPDATE car SET engine_type = COALESCE(NULLIF(engine_type,''),'gasoline') WHERE engine_type IS NULL OR engine_type = ''"))

            # transmission default
            if 'transmission' in car_cols:
                conn.execute(text("UPDATE car SET transmission = COALESCE(NULLIF(transmission,''),'automatic') WHERE transmission IS NULL OR transmission = ''"))

            # drive_type default
            if 'drive_type' in car_cols:
                conn.execute(text("UPDATE car SET drive_type = COALESCE(NULLIF(drive_type,''),'fwd') WHERE drive_type IS NULL OR drive_type = ''"))

            # condition default
            if 'condition' in car_cols:
                conn.execute(text("UPDATE car SET condition = COALESCE(NULLIF(condition,''),'used') WHERE condition IS NULL OR condition = ''"))

            # body_type default
            if 'body_type' in car_cols:
                conn.execute(text("UPDATE car SET body_type = COALESCE(NULLIF(body_type,''),'sedan') WHERE body_type IS NULL OR body_type = ''"))

            # mileage default 0
            if 'mileage' in car_cols:
                conn.execute(text("UPDATE car SET mileage = COALESCE(mileage, 0)"))

            # location backfill from city
            if 'location' in car_cols and 'city' in car_cols:
                conn.execute(text("UPDATE car SET location = city WHERE (location IS NULL OR location = '') AND (city IS NOT NULL AND city <> '')"))

            # is_active from status
            if 'is_active' in car_cols and 'status' in car_cols:
                conn.execute(text("UPDATE car SET is_active = CASE WHEN LOWER(status) = 'active' THEN 1 ELSE 1 END WHERE is_active IS NULL"))

            # created_at default now if null
            if 'created_at' in car_cols:
                conn.execute(text("UPDATE car SET created_at = COALESCE(created_at, CURRENT_TIMESTAMP)"))

            # Ensure public_id values for car and user
            for tbl in ('car','user'):
                tcols = {row[1] for row in conn.execute(text(f'PRAGMA table_info({tbl})'))}
                if 'public_id' not in tcols:
                    conn.execute(text(f'ALTER TABLE {tbl} ADD COLUMN public_id VARCHAR(50)'))
                ids = [r[0] for r in conn.execute(text(f"SELECT id FROM {tbl} WHERE public_id IS NULL OR public_id = ''"))]
                for rid in ids:
                    conn.execute(text(f"UPDATE {tbl} SET public_id = :pid WHERE id = :rid"), {"pid": str(uuid.uuid4()), "rid": rid})

            conn.commit()
            print('MIGRATE_CAR_COLUMNS_OK')


if __name__ == '__main__':
    run()


