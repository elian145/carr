import sys
sys.path.append('kk')

import app_new as app_module
from models import db, User


def set_password_for(user_key: str, new_password: str) -> None:
	app = app_module.app
	with app.app_context():
		db.create_all()
		# Find by username first, then fallback to email
		user = User.query.filter((User.username == user_key) | (User.email == user_key)).first()
		if not user:
			print('NO_USER')
			return
		# Force email to key for legacy mobile login compatibility
		try:
			user.email = user_key
		except Exception:
			pass
		user.username = user.username or user_key
		user.set_password(new_password)
		user.is_active = True
		db.session.commit()
		print('SET_PASSWORD_BY_USERNAME_OK', user.username or user.email)


if __name__ == '__main__':
	import argparse
	p = argparse.ArgumentParser()
	p.add_argument('--user', required=True, help='username or email')
	p.add_argument('--password', required=True)
	a = p.parse_args()
	set_password_for(a.user, a.password)



