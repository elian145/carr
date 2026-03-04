import os
import sqlite3
import json
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class DbCandidate:
	path: str
	car_count: int
	image_count: int


def table_exists(con: sqlite3.Connection, name: str) -> bool:
	try:
		cur = con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,))
		return cur.fetchone() is not None
	except Exception:
		return False


def user_email_exists(path: str, email: str) -> bool:
	try:
		with sqlite3.connect(path) as con:
			if not table_exists(con, 'user'):
				return False
			cur = con.execute("SELECT 1 FROM user WHERE email = ? LIMIT 1", (email,))
			return cur.fetchone() is not None
	except Exception:
		return False


def collect_stats(path: str) -> DbCandidate:
	car_count = 0
	image_count = 0
	with sqlite3.connect(path) as con:
		if table_exists(con, 'car'):
			car_count = con.execute('SELECT COUNT(*) FROM car').fetchone()[0]
		if table_exists(con, 'car_image'):
			image_count = con.execute('SELECT COUNT(*) FROM car_image').fetchone()[0]
	return DbCandidate(path=path, car_count=int(car_count), image_count=int(image_count))


def find_all_db_paths(root: str) -> List[str]:
	paths: List[str] = []
	for dirpath, _dirnames, filenames in os.walk(root):
		for name in filenames:
			if name.lower().endswith('.db'):
				paths.append(os.path.join(dirpath, name))
	return paths


def main():
	import argparse
	parser = argparse.ArgumentParser()
	parser.add_argument('--root', default=os.path.join('kk','instance'))
	parser.add_argument('--email', required=True)
	args = parser.parse_args()

	all_paths = find_all_db_paths(args.root)
	matching: List[DbCandidate] = []
	for p in all_paths:
		if user_email_exists(p, args.email):
			matching.append(collect_stats(p))

	matching.sort(key=lambda c: (c.car_count, c.image_count, os.path.getmtime(c.path)), reverse=True)
	result = {
		'matches': [c.__dict__ for c in matching],
		'best': (matching[0].__dict__ if matching else None),
	}
	print(json.dumps(result))


if __name__ == '__main__':
	main()


