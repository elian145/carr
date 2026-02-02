import os
import sys
import glob
import shutil
from typing import List, Tuple

"""
Builds or fetches a YOLOv8l model specialized for Iraqi license plates.

Strategy:
- If kk/weights/yolov8l-iraqi-license-plate.pt exists, do nothing.
- Else, bootstrap labels using an existing license-plate detector,
  create a YOLO dataset, and fine-tune YOLOv8l.

Requirements:
- ultralytics installed
- OpenCV, numpy

Usage:
  python tools/build_iraqi_lp_model.py "C:\\Users\\VeeStore\\Desktop\\prado"
"""

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
WEIGHTS_DIR = os.path.join(ROOT, 'kk', 'weights')
OUT_WEIGHTS = os.path.join(WEIGHTS_DIR, 'yolov8l-iraqi-license-plate.pt')
DATASET_DIR = os.path.join(ROOT, 'kk', 'datasets', 'iraqi_lp')

def ensure_dirs():
	if not os.path.isdir(WEIGHTS_DIR):
		os.makedirs(WEIGHTS_DIR, exist_ok=True)
	os.makedirs(DATASET_DIR, exist_ok=True)
	os.makedirs(os.path.join(DATASET_DIR, 'images', 'train'), exist_ok=True)
	os.makedirs(os.path.join(DATASET_DIR, 'images', 'val'), exist_ok=True)
	os.makedirs(os.path.join(DATASET_DIR, 'labels', 'train'), exist_ok=True)
	os.makedirs(os.path.join(DATASET_DIR, 'labels', 'val'), exist_ok=True)

def list_images(folder: str) -> List[str]:
	patterns = ("*.jpg","*.jpeg","*.png","*.webp","*.bmp","*.tif","*.tiff","*.JPG","*.JPEG","*.PNG","*.BMP","*.TIF","*.TIFF")
	paths: List[str] = []
	for p in patterns:
		paths.extend(glob.glob(os.path.join(folder, '**', p), recursive=True))
	return sorted(list(dict.fromkeys(paths)))

def split_train_val(items: List[str], val_ratio: float = 0.1) -> Tuple[List[str], List[str]]:
	if not items:
		return [], []
	n = len(items)
	v = max(1, int(n * val_ratio)) if n > 9 else max(1, n // 5)
	return items[:-v] or items, items[-v:]

def bootstrap_labels(img_paths: List[str]) -> Tuple[int, int]:
	"""
	Run an existing YOLO license-plate detector to generate YOLO-format labels.
	Filters by aspect ratio [1.5, 7.0].
	Returns: (num_labeled, num_images)
	"""
	import cv2
	import numpy as np
	from ultralytics import YOLO

	# Prefer local plate detectors if available
	candidates = [
		os.path.join(ROOT, 'kk', 'weights', 'yolov8l-license-plate.pt'),
		os.path.join(ROOT, 'kk', 'weights', 'yolov8m-license-plate.pt'),
		os.path.join(ROOT, 'kk', 'weights', 'yolov8n-license-plate.pt'),
		'keremberke/yolov8l-license-plate',
		'keremberke/yolov8m-license-plate',
		'keremberke/yolov8n-license-plate',
	]
	model = None
	for c in candidates:
		try:
			model = YOLO(c)
			print(f"[bootstrap] Using detector: {c}")
			break
		except Exception:
			continue
	if model is None:
		raise RuntimeError("No bootstrap detector available for license plates.")

	num_labeled = 0
	for idx, ip in enumerate(img_paths, 1):
		img = cv2.imread(ip)
		if img is None:
			continue
		h, w = img.shape[:2]
		res = model.predict(img, conf=0.30, iou=0.5, imgsz=1280, verbose=False)
		boxes = []
		if res:
			r0 = res[0]
			bx = getattr(r0, 'boxes', None)
			if bx is not None and hasattr(bx, 'xyxy'):
				try:
					xyxy = bx.xyxy.cpu().numpy() if hasattr(bx.xyxy, 'cpu') else bx.xyxy
					confs = bx.conf.cpu().numpy() if hasattr(bx, 'conf') and hasattr(bx, 'cpu') else None
				except Exception:
					xyxy, confs = None, None
				if xyxy is not None:
					for i, b in enumerate(xyxy):
						x1, y1, x2, y2 = [int(v) for v in b]
						x1 = max(0, min(w - 1, x1)); x2 = max(0, min(w, x2))
						y1 = max(0, min(h - 1, y1)); y2 = max(0, min(h, y2))
						if x2 <= x1 or y2 <= y1:
							continue
						bw = max(1, x2 - x1); bh = max(1, y2 - y1)
						ar = bw / float(bh)
						if 1.5 <= ar <= 7.0:
							# Convert to YOLO normalized cx,cy,w,h
							cx = (x1 + x2) / 2.0 / w
							cy = (y1 + y2) / 2.0 / h
							nw = bw / w
							nh = bh / h
							boxes.append((0, cx, cy, nw, nh))  # class 0 = license_plate
		if boxes:
			# Decide split dir by presence in train/val move later
			num_labeled += 1
		print(f"[bootstrap] {idx}/{len(img_paths)} -> {len(boxes)} boxes")
		yield ip, boxes

def write_dataset(imgs_train: List[str], imgs_val: List[str], labels_map: dict):
	def write_split(split_name: str, imgs: List[str]):
		copied = 0
		for ip in imgs:
			try:
				base = os.path.basename(ip)
				dst_img = os.path.join(DATASET_DIR, 'images', split_name, base)
				shutil.copy2(ip, dst_img)
				lab = labels_map.get(ip, [])
				lbl_name = os.path.splitext(base)[0] + '.txt'
				dst_lbl = os.path.join(DATASET_DIR, 'labels', split_name, lbl_name)
				with open(dst_lbl, 'w', encoding='utf-8') as f:
					for cls_id, cx, cy, w, h in lab:
						f.write(f"{cls_id} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}\n")
				copied += 1
			except Exception as e:
				print(f"[dataset] WARN copy/label failed for {ip}: {e}")
		print(f"[dataset] {split_name} images copied: {copied}")
	# Execute writes
	write_split('train', imgs_train)
	write_split('val', imgs_val)
	yaml_path = os.path.join(DATASET_DIR, 'data.yaml')
	with open(yaml_path, 'w', encoding='utf-8') as f:
		f.write("path: {}\n".format(DATASET_DIR.replace('\\','/')))
		f.write("train: images/train\n")
		f.write("val: images/val\n")
		f.write("names:\n")
		f.write("  0: license_plate\n")
	return yaml_path

def train_model(yaml_path: str, epochs: int = 30, imgsz: int = 1280, batch: int = 8):
	from ultralytics import YOLO
	# Start from a strong base. If plate-specialized large exists, prefer it
	start_candidates = [
		os.path.join(ROOT, 'kk', 'weights', 'yolov8l-license-plate.pt'),
		'keremberke/yolov8l-license-plate',
		'yolov8l.pt'
	]
	model = None
	for c in start_candidates:
		try:
			model = YOLO(c)
			print(f"[train] Starting from: {c}")
			break
		except Exception:
			continue
	if model is None:
		model = YOLO('yolov8l.pt')
		print("[train] Fallback to yolov8l.pt")

	results = model.train(data=yaml_path, epochs=epochs, imgsz=imgsz, batch=batch, device=0 if os.environ.get('CUDA_VISIBLE_DEVICES') else 'cpu')
	# Save best weights to expected path
	best = getattr(results, 'best', None) or os.path.join(model.trainer.save_dir, 'weights', 'best.pt')
	os.makedirs(WEIGHTS_DIR, exist_ok=True)
	shutil.copy2(best, OUT_WEIGHTS)
	print(f"[train] Saved best weights to: {OUT_WEIGHTS}")

def main():
	if len(sys.argv) < 2:
		print("Usage: python tools/build_iraqi_lp_model.py \"C:\\path\\to\\iraqi_images\"")
		sys.exit(1)
	src_folder = sys.argv[1]
	if not os.path.isdir(src_folder):
		print(f"Invalid folder: {src_folder}")
		sys.exit(1)
	ensure_dirs()
	if os.path.exists(OUT_WEIGHTS):
		print(f"Already present: {OUT_WEIGHTS}")
		return
	imgs = list_images(src_folder)
	if not imgs:
		print("No images found to bootstrap.")
		return
	labels_map = {}
	labeled = 0
	for ip, boxes in bootstrap_labels(imgs):
		labels_map[ip] = boxes
		if boxes:
			labeled += 1
	print(f"[bootstrap] Labeled {labeled}/{len(imgs)} images")

	train, val = split_train_val(imgs)
	print(f"[dataset] preparing split: train={len(train)} val={len(val)}")
	yaml_path = write_dataset(train, val, labels_map)
	print(f"[dataset] Wrote dataset to: {DATASET_DIR}")
	train_model(yaml_path)

if __name__ == "__main__":
	main()

