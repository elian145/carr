import sys
import argparse

sys.path.append('kk')

import app_new as app_module
from models import db, User


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument('--email_or_phone', required=True)
    p.add_argument('--password', required=True)
    a = p.parse_args()

    app = app_module.app
    with app.app_context():
        db.create_all()
        q = User.query.filter((User.email == a.email_or_phone) | (User.phone_number == a.email_or_phone))
        user = q.first()
        if not user:
            print('NO_USER')
            return
        print('FOUND_USER', user.email or user.phone_number, user.username)
        ok = user.check_password(a.password)
        print('PASSWORD_OK' if ok else 'PASSWORD_BAD')


if __name__ == '__main__':
    main()


