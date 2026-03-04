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
        cols = {row[1] for row in conn.execute(text('PRAGMA table_info(car)'))}
        print('CAR_COLS', sorted(cols))
        if 'public_id' not in cols:
            conn.execute(text('ALTER TABLE car ADD COLUMN public_id VARCHAR(50)'))
            conn.commit()
        # verify
        cols2 = {row[1] for row in conn.execute(text('PRAGMA table_info(car)'))}
        print('CAR_COLS_AFTER', sorted(cols2))
print('CHECK_DONE')
