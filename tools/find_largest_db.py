import os
import sqlite3
import json
from dataclasses import dataclass
from typing import List


@dataclass
class DbStats:
	path: str
	car_count: int
	image_count: int
	size_bytes: int
	mtime: float


def table_exists(con: sqlite3.Connection, name: str) -> bool:
	try:
		cur = con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,))
		return cur.fetchone() is not None
	except Exception:
		return False


def collect_stats(path: str) -> DbStats:
	car_count = 0
	image_count = 0
	try:
		with sqlite3.connect(path) as con:
			if table_exists(con, 'car'):
				car_count = int(con.execute('SELECT COUNT(*) FROM car').fetchone()[0])
			if table_exists(con, 'car_image'):
				image_count = int(con.execute('SELECT COUNT(*) FROM car_image').fetchone()[0])
	except Exception:
		pass
	return DbStats(path=path, car_count=car_count, image_count=image_count, size_bytes=os.path.getsize(path), mtime=os.path.getmtime(path))


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
	parser.add_argument('--root', default=os.path.join('kk', 'instance'))
	args = parser.parse_args()

	all_paths = find_all_db_paths(args.root)
	stats = [collect_stats(p) for p in all_paths]
	stats.sort(key=lambda s: (s.car_count, s.image_count, s.size_bytes, s.mtime), reverse=True)
	result = {
		'all': [s.__dict__ for s in stats],
		'best': (stats[0].__dict__ if stats else None),
	}
	print(json.dumps(result))


if __name__ == '__main__':
	main()


