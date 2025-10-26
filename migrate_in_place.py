import sys, uuid
sys.path.append('kk')
import app_new as app_module
from models import db
from sqlalchemy import text

app = app_module.app
with app.app_context():
    eng = db.engine
    print('DB_FILE', eng.url.database)
    with eng.connect() as conn:
        def cols(table):
            return {row[1] for row in conn.execute(text(f'PRAGMA table_info({table})'))}
        # Car columns
        ccols = cols('car')
        need = []
        def add_car(col, typ):
            if col not in ccols:
                need.append((col, typ))
        add_car('public_id', 'VARCHAR(50)')
        add_car('ai_analyzed','BOOLEAN DEFAULT 0')
        add_car('ai_detected_brand','VARCHAR(50)')
        add_car('ai_detected_model','VARCHAR(50)')
        add_car('ai_detected_color','VARCHAR(20)')
        add_car('ai_detected_body_type','VARCHAR(20)')
        add_car('ai_detected_condition','VARCHAR(20)')
        add_car('ai_confidence_score','FLOAT')
        add_car('ai_analysis_timestamp','DATETIME')
        add_car('license_plates_blurred','BOOLEAN DEFAULT 0')
        for col, typ in need:
            conn.execute(text(f'ALTER TABLE car ADD COLUMN {col} {typ}'))
        # User columns
        ucols = cols('user')
        if 'public_id' not in ucols:
            conn.execute(text('ALTER TABLE user ADD COLUMN public_id VARCHAR(50)'))
        # Backfill public_id values
        for table in ('car','user'):
            rows = conn.execute(text(f"SELECT rowid FROM {table} WHERE public_id IS NULL OR public_id=''"))
            ids = [r[0] for r in rows]
            for rid in ids:
                pid = str(uuid.uuid4())
                conn.execute(text(f"UPDATE {table} SET public_id=:pid WHERE rowid=:rid"), {'pid': pid, 'rid': rid})
        conn.commit()
print('MIGRATE_OK')
