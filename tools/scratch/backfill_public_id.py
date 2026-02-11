import sys, uuid
sys.path.append('kk')
import app_new as app_module
from models import db
from sqlalchemy import text

app = app_module.app
with app.app_context():
    eng = db.engine
    with eng.connect() as conn:
        # backfill null public_id
        rows = conn.execute(text("SELECT id FROM car WHERE public_id IS NULL OR public_id=''"))
        ids = [r[0] for r in rows]
        for cid in ids:
            conn.execute(text("UPDATE car SET public_id=:pid WHERE id=:cid"), {'pid': str(uuid.uuid4()), 'cid': cid})
        if ids:
            conn.commit()
print('BACKFILL_DONE', len(ids) if 'ids' in locals() else 0)
