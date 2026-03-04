import sys
import argparse
import uuid

# Ensure project root is on path so we can import kk as a package
import os
ROOT = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(ROOT)
sys.path.append(PROJECT_ROOT)

from kk import app_new as app_module
from kk.models import db, User


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument('--email', required=True)
	parser.add_argument('--password', required=True)
	args = parser.parse_args()

	app = app_module.app
	with app.app_context():
		db.create_all()

		user = User.query.filter_by(email=args.email).first()
		if not user:
			# Create minimal valid user if missing (phone required/unique)
			phone = f"070{uuid.uuid4().int % (10**8):08d}"
			user = User(
				username=args.email,  # set username to email for legacy login compatibility
				email=args.email,
				phone_number=phone,
				first_name='Elian',
				last_name='User',
				is_active=True,
			)
			db.session.add(user)
			# Ensure password_hash is set before any flush to satisfy NOT NULL constraint
			user.set_password(args.password)
			db.session.flush()

		# Ensure username equals email so legacy login matches on username
		user.username = args.email
		user.set_password(args.password)
		user.is_active = True
		db.session.commit()
		print(f"SET_PASSWORD_OK email={args.email}")


if __name__ == '__main__':
	main()


