import argparse
import sys

sys.path.append('kk')

from app import app, db, User  # type: ignore
from werkzeug.security import generate_password_hash  # type: ignore


def main() -> None:
	parser = argparse.ArgumentParser(description="Create or update a user in kk/app.py database")
	parser.add_argument('--email', required=True)
	parser.add_argument('--username', required=True)
	parser.add_argument('--password', required=True)
	args = parser.parse_args()

	with app.app_context():
		db.create_all()
		user = User.query.filter_by(email=args.email).first()
		if user is None:
			user = User(email=args.email, username=args.username, password=generate_password_hash(args.password))
			db.session.add(user)
			db.session.commit()
			print(f"USER_CREATED email={args.email} username={args.username}")
		else:
			user.username = args.username
			user.password = generate_password_hash(args.password)
			db.session.commit()
			print(f"USER_UPDATED email={args.email} username={args.username}")


if __name__ == '__main__':
	main()


