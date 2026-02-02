import os
import sys
import shutil
import random
from typing import List, Tuple

import cv2
import numpy as np

# Ensure project root is importable
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
	sys.path.append(ROOT)

from kk.ai_service import car_analysis_service  # Reuse loaded YOLO model


def iou_xyxy(a: Tuple[int, int, int, int], b: Tuple[int, int, int, int]) -> float:
	ax1, ay1, ax2, ay2 = a
	bx1, by1, bx2, by2 = b
	ix1, iy1 = max(ax1, bx1), max(ay1, by1)
	ix2, iy2 = min(ax2, bx2), min(ay2, by2)
	iw, ih = max(0, ix2 - ix1), max(0, iy2 - iy1)
	inter = iw * ih
	if inter <= 0:
		return 0.0
	area_a = max(0, ax2 - ax1) * max(0, ay2 - ay1)
	area_b = max(0, bx2 - bx1) * max(0, by2 - by1)
	union = max(1e-6, area_a + area_b - inter)
	return float(inter) / float(union)


def nms_merge(boxes: List[Tuple[float, int, int, int, int]], iou_thr: float = 0.50) -> List[Tuple[float, int, int, int, int]]:
	# Sort by confidence descending
	boxes_sorted = sorted(boxes, key=lambda t: t[0], reverse=True)
	selected: List[Tuple[float, int, int, int, int]] = []
	for cand in boxes_sorted:
		keep = True
		for sel in selected:
			if iou_xyxy((cand[1], cand[2], cand[3], cand[4]), (sel[1], sel[2], sel[3], sel[4])) >= iou_thr:
				keep = False
				break
		if keep:
			selected.append(cand)
	return selected


def collect_detections(img_bgr: np.ndarray) -> List[Tuple[float, int, int, int, int]]:
	H, W = img_bgr.shape[:2]
	dets: List[Tuple[float, int, int, int, int]] = []
	model = car_analysis_service.license_plate_model
	if model is None:
		print("PseudoLabel: ERROR -> YOLO model not initialized.")
		return dets
	scales = [1.0, 1.25, 1.5]
	for s in scales:
		if s == 1.0:
			img_s = img_bgr
		else:
			img_s = cv2.resize(img_bgr, None, fx=s, fy=s, interpolation=cv2.INTER_LINEAR)
		res = model.predict(img_s, conf=0.25, iou=0.5, imgsz=1280, verbose=False)
		if not res:
			print(f"PseudoLabel: scale={s:.2f} -> 0 dets")
			continue
		boxes = getattr(res[0], 'boxes', None)
		if boxes is None or not hasattr(boxes, 'xyxy'):
			print(f"PseudoLabel: scale={s:.2f} -> no boxes field")
			continue
		try:
			xyxy = boxes.xyxy.cpu().numpy() if hasattr(boxes.xyxy, 'cpu') else boxes.xyxy
			confs = boxes.conf.cpu().numpy() if hasattr(boxes, 'conf') and hasattr(boxes, 'cpu') else None
		except Exception:
			xyxy, confs = None, None
		cnt = 0
		if xyxy is not None:
			for i, b in enumerate(xyxy):
				c = float(confs[i]) if confs is not None and i < len(confs) else 1.0
				x1s, y1s, x2s, y2s = [float(v) for v in b]
				# Map back to original coordinates
				x1 = int(x1s / s); x2 = int(x2s / s)
				y1 = int(y1s / s); y2 = int(y2s / s)
				# Clamp
				x1 = max(0, min(W - 1, x1)); x2 = max(0, min(W, x2))
				y1 = max(0, min(H - 1, y1)); y2 = max(0, min(H, y2))
				if x2 <= x1 or y2 <= y1:
					continue
				# Plate-like filters for Iraqi visuals
				bw = max(1, x2 - x1); bh = max(1, y2 - y1)
				ar = bw / float(bh)
				cy = (y1 + y2) * 0.5
				if cy < (0.50 * H):
					continue
				if not (1.5 <= ar <= 7.0):
					continue
				dets.append((c, x1, y1, x2, y2))
				cnt += 1
		print(f"PseudoLabel: scale={s:.2f} -> {cnt} dets")
	# Merge across scales
	merged = nms_merge(dets, iou_thr=0.5)
	return merged


def save_yolo_label(label_path: str, boxes_xyxy: List[Tuple[int, int, int, int]], W: int, H: int) -> None:
	os.makedirs(os.path.dirname(label_path), exist_ok=True)
	with open(label_path, 'w', encoding='utf-8') as f:
		for (x1, y1, x2, y2) in boxes_xyxy:
			w = (x2 - x1) / float(W)
			h = (y2 - y1) / float(H)
			cx = (x1 + x2) * 0.5 / float(W)
			cy = (y1 + y2) * 0.5 / float(H)
			# class 0 is 'plate'
			f.write(f"0 {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}\n")


def main():
	if len(sys.argv) < 2:
		print("Usage: python tools/pseudo_label_iraqi_lp.py \"C:\\path\\to\\images\" [out_dir]")
		sys.exit(1)
	src_dir = sys.argv[1]
	out_root = sys.argv[2] if len(sys.argv) >= 3 else os.path.join(ROOT, "dataset_iraqi_lp")
	img_globs = (".jpg",".jpeg",".png",".bmp",".tif",".tiff",".webp",".JPG",".JPEG",".PNG",".BMP",".TIF",".TIFF",".WEBP")

	# Build file list
	all_imgs: List[str] = []
	for root, _, files in os.walk(src_dir):
		for name in files:
			if any(name.endswith(ext) for ext in img_globs):
				all_imgs.append(os.path.join(root, name))
	if not all_imgs:
		print("PseudoLabel: No images found.")
		return

	random.shuffle(all_imgs)
	split_idx = max(1, int(len(all_imgs) * 0.9))
	train_imgs = all_imgs[:split_idx]
	val_imgs   = all_imgs[split_idx:]

	def copy_and_label(img_paths: List[str], split: str) -> Tuple[int, int]:
		out_img_dir = os.path.join(out_root, split, "images")
		out_lbl_dir = os.path.join(out_root, split, "labels")
		os.makedirs(out_img_dir, exist_ok=True)
		os.makedirs(out_lbl_dir, exist_ok=True)
		num_imgs, num_boxes = 0, 0
		for ip in img_paths:
			img = cv2.imread(ip)
			if img is None: 
				continue
			H, W = img.shape[:2]
			dets = collect_detections(img)
			bxs = [(x1, y1, x2, y2) for (_, x1, y1, x2, y2) in dets]
			# Save image copy and labels
			base = os.path.splitext(os.path.basename(ip))[0]
			target_img = os.path.join(out_img_dir, f"{base}.jpg")
			cv2.imwrite(target_img, img, [int(cv2.IMWRITE_JPEG_QUALITY), 95])
			label_path = os.path.join(out_lbl_dir, f"{base}.txt")
			save_yolo_label(label_path, bxs, W, H)
			num_imgs += 1
			num_boxes += len(bxs)
		return num_imgs, num_boxes

	tr_i, tr_b = copy_and_label(train_imgs, "train")
	va_i, va_b = copy_and_label(val_imgs, "val")

	# Write data.yaml
	data_yaml = os.path.join(out_root, "data.yaml")
	with open(data_yaml, "w", encoding="utf-8") as f:
		f.write("path: " + out_root.replace("\\","/") + "\n")
		f.write("train: train/images\n")
		f.write("val: val/images\n")
		f.write("nc: 1\n")
		f.write("names: ['plate']\n")

	print(f"PseudoLabel: DONE -> dataset at {out_root}")
	print(f"  train: images={tr_i}, boxes={tr_b}")
	print(f"  val:   images={va_i}, boxes={va_b}")
	print(f"  data.yaml: {data_yaml}")


if __name__ == "__main__":
	main()


