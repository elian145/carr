import sys
import os
from sqlalchemy import text

sys.path.append(os.path.dirname(__file__) + '/..')
import app_new as app_module  # noqa: E402
from models import db  # noqa: E402


def main() -> None:
    app = app_module.app
    with app.app_context():
        engine = db.engine
        with engine.connect() as conn:
            cols = {row[1] for row in conn.execute(text('PRAGMA table_info(user)'))}
            changed = False
            if 'password' not in cols:
                conn.execute(text('ALTER TABLE user ADD COLUMN password VARCHAR(120)'))
                changed = True
            # Ensure password_hash exists (new schema)
            if 'password_hash' not in cols:
                conn.execute(text('ALTER TABLE user ADD COLUMN password_hash VARCHAR(128)'))
                changed = True
            conn.commit()
        print('ADD_USER_PASSWORD_COLUMN_OK' if changed else 'ADD_USER_PASSWORD_COLUMN_NOOP')


if __name__ == '__main__':
    main()


