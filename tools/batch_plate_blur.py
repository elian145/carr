from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Tuple


def _iter_images(root: Path, recursive: bool) -> List[Path]:
	exts = {".jpg", ".jpeg", ".png", ".webp"}
	if recursive:
		return [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in exts]
	return [p for p in root.iterdir() if p.is_file() and p.suffix.lower() in exts]


def _safe_relpath(path: Path, base: Path) -> Path:
	try:
		return path.relative_to(base)
	except Exception:
		# Fallback: flatten if something odd happens
		return Path(path.name)


def main() -> int:
	parser = argparse.ArgumentParser(description="Batch blur license plates using Roboflow Hosted API + OpenCV.")
	parser.add_argument("--input", required=True, help="Input folder containing images")
	parser.add_argument("--output", required=True, help="Output folder to write processed images")
	parser.add_argument("--recursive", action="store_true", help="Recurse into subfolders")
	parser.add_argument("--expand", type=float, default=float(os.getenv("PLATE_BLUR_EXPAND", "0") or "0"))
	parser.add_argument("--report", default="", help="Optional JSON report path")
	args = parser.parse_args()

	in_dir = Path(args.input).expanduser().resolve()
	out_dir = Path(args.output).expanduser().resolve()
	out_dir.mkdir(parents=True, exist_ok=True)

	if not in_dir.is_dir():
		print(f"Input folder does not exist: {in_dir}")
		return 2

	# Ensure repo-root imports work when running from anywhere
	repo_root = Path(__file__).resolve().parents[1]
	if str(repo_root) not in sys.path:
		sys.path.insert(0, str(repo_root))

	try:
		from kk.license_plate_blur import blur_license_plates, get_plate_detector
	except Exception as e:
		print(f"Failed to import kk.license_plate_blur: {e}")
		return 3

	detector = get_plate_detector()
	if not detector.is_configured():
		print("Roboflow is not configured. Set ROBOFLOW_API_KEY (and optionally ROBOFLOW_PROJECT/ROBOFLOW_VERSION).")
		return 4

	images = _iter_images(in_dir, args.recursive)
	if not images:
		print(f"No images found in: {in_dir}")
		return 0

	report: Dict[str, Dict] = {}
	ok = 0
	blurred = 0
	no_plates = 0
	failed = 0

	for src in images:
		rel = _safe_relpath(src, in_dir)
		dst = (out_dir / rel).resolve()
		dst.parent.mkdir(parents=True, exist_ok=True)

		try:
			raw = src.read_bytes()
			out_bytes, meta = blur_license_plates(
				image_bytes=raw,
				output_ext=src.suffix.lower(),
				detector=detector,
				expand_ratio=float(args.expand),
			)
			dst.write_bytes(out_bytes)
			ok += 1
			status = meta.get("status")
			if status == "blurred":
				blurred += 1
			elif status == "no_plates":
				no_plates += 1
			report[str(rel).replace("\\", "/")] = {
				"input": str(src),
				"output": str(dst),
				**meta,
			}
		except Exception as e:
			failed += 1
			report[str(rel).replace("\\", "/")] = {"input": str(src), "output": str(dst), "status": "failed", "error": str(e)}

	print(f"Processed: {ok}/{len(images)} | blurred: {blurred} | no_plates: {no_plates} | failed: {failed}")

	if args.report:
		rep_path = Path(args.report).expanduser().resolve()
		rep_path.parent.mkdir(parents=True, exist_ok=True)
		rep_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
		print(f"Report written: {rep_path}")

	return 0 if failed == 0 else 5


if __name__ == "__main__":
	raise SystemExit(main())

