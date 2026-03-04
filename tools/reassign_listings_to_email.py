import sys
sys.path.append('kk')

import app_new as app_module
from models import db
from sqlalchemy import text


def main(email: str) -> None:
    app = app_module.app
    with app.app_context():
        eng = db.engine
        with eng.connect() as conn:
            target = conn.execute(text("SELECT id FROM user WHERE email = :e"), {"e": email}).fetchone()
            if not target:
                print("NO_TARGET_USER")
                return
            target_id = int(target[0])

            # Collect legacy user ids to merge: same email or username 'elian'
            legacy_ids = [int(r[0]) for r in conn.execute(
                text("SELECT id FROM user WHERE email = :e OR LOWER(username) = 'elian'"), {"e": email}
            )]
            legacy_ids = [i for i in legacy_ids if i != target_id]

            moved = 0
            if legacy_ids:
                in_clause = ",".join(str(i) for i in legacy_ids)
                moved += conn.execute(
                    text(f"UPDATE car SET seller_id = :tid WHERE seller_id IN ({in_clause})"),
                    {"tid": target_id},
                ).rowcount or 0

            # Also handle legacy user_id column if present
            car_cols = {row[1] for row in conn.execute(text('PRAGMA table_info(car)'))}
            if 'user_id' in car_cols:
                moved += conn.execute(
                    text(
                        "UPDATE car SET seller_id = :tid "
                        "WHERE seller_id IS NULL AND user_id IN (SELECT id FROM user WHERE email = :e OR LOWER(username) = 'elian')"
                    ),
                    {"tid": target_id, "e": email},
                ).rowcount or 0

            conn.commit()
            total = conn.execute(text("SELECT COUNT(*) FROM car WHERE seller_id = :tid"), {"tid": target_id}).scalar() or 0
            print("REASSIGN_DONE", int(moved), "MY_TOTAL", int(total))


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--email", required=True)
    a = p.parse_args()
    main(a.email)


