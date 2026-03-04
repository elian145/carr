from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Iterable, Tuple

from kk.license_plate_blur import blur_license_plates, get_plate_detector


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}


def iter_images(input_dir: Path, recursive: bool) -> Iterable[Path]:
	pattern = "**/*" if recursive else "*"
	for p in input_dir.glob(pattern):
		if not p.is_file():
			continue
		if p.suffix.lower() in IMAGE_EXTS:
			yield p


def safe_relpath(p: Path, base: Path) -> Path:
	try:
		return p.relative_to(base)
	except Exception:
		return Path(p.name)


def process_one(*, src: Path, dst: Path, expand_ratio: float) -> Tuple[str, dict]:
	src_bytes = src.read_bytes()
	out_bytes, meta = blur_license_plates(
		image_bytes=src_bytes,
		output_ext=src.suffix.lower(),
		detector=get_plate_detector(),
		expand_ratio=expand_ratio,
	)
	dst.parent.mkdir(parents=True, exist_ok=True)
	dst.write_bytes(out_bytes)
	return (meta.get("status") or "unknown"), meta


def main() -> int:
	parser = argparse.ArgumentParser(description="Batch blur license plates using Roboflow + OpenCV.")
	parser.add_argument("input_dir", help="Input folder containing images")
	parser.add_argument("output_dir", help="Output folder for processed images")
	parser.add_argument("--recursive", action="store_true", help="Recurse into subfolders")
	parser.add_argument(
		"--skip-existing",
		action="store_true",
		help="Skip files that already exist in output_dir (recommended for big folders)",
	)
	parser.add_argument(
		"--log-every",
		type=int,
		default=25,
		help="Print progress every N images (0 prints every file). Default: 25.",
	)
	parser.add_argument(
		"--expand",
		type=float,
		default=float(os.getenv("PLATE_BLUR_EXPAND", "0") or "0"),
		help="Expand detected box by ratio (e.g. 0.1). Defaults to PLATE_BLUR_EXPAND or 0.",
	)
	parser.add_argument(
		"--write-meta",
		action="store_true",
		help="Write <filename>.json next to each output image with detector metadata",
	)
	args = parser.parse_args()

	input_dir = Path(args.input_dir).expanduser().resolve()
	output_dir = Path(args.output_dir).expanduser().resolve()

	if not input_dir.exists() or not input_dir.is_dir():
		print(f"Input dir not found: {input_dir}")
		return 2

	detector = get_plate_detector()
	if not detector.is_configured():
		print("Roboflow detector is not configured. Set ROBOFLOW_API_KEY (and optionally ROBOFLOW_PROJECT/ROBOFLOW_VERSION or ROBOFLOW_MODEL).")
		return 3

	output_dir.mkdir(parents=True, exist_ok=True)

	processed = 0
	blurred = 0
	no_plates = 0
	failed = 0
	skipped = 0

	for src in iter_images(input_dir, recursive=bool(args.recursive)):
		rel = safe_relpath(src, input_dir)
		dst = output_dir / rel
		if args.skip_existing and dst.exists():
			skipped += 1
			continue
		try:
			status, meta = process_one(src=src, dst=dst, expand_ratio=float(args.expand))
			processed += 1
			if status == "blurred":
				blurred += 1
			elif status == "no_plates":
				no_plates += 1
			else:
				failed += 1
			if int(args.log_every) == 0:
				print(f"[{status}] {src.name} -> {dst}", flush=True)
			elif processed % int(args.log_every) == 0:
				print(
					f"progress processed={processed} skipped={skipped} blurred={blurred} no_plates={no_plates} other/failed={failed} last={src.name} status={status}",
					flush=True,
				)

			if args.write_meta:
				meta_path = dst.with_suffix(dst.suffix + ".json")
				meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
		except Exception as e:
			failed += 1
			print(f"[error] {src} -> {dst}: {e}", flush=True)

	print(
		f"Done. processed={processed} skipped={skipped} blurred={blurred} no_plates={no_plates} other/failed={failed} output_dir={output_dir}",
		flush=True,
	)
	return 0 if processed > 0 else 4


if __name__ == "__main__":
	raise SystemExit(main())

