import os
import sys

def main():
	try:
		from ultralytics import YOLO
	except Exception as e:
		print("Train: ERROR -> ultralytics not installed. Install with: pip install ultralytics")
		sys.exit(1)

	root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
	data_yaml = os.path.join(root, "dataset_iraqi_lp", "data.yaml")
	if len(sys.argv) >= 2:
		data_yaml = sys.argv[1]
	if not os.path.exists(data_yaml):
		print(f"Train: data.yaml not found at {data_yaml}")
		sys.exit(1)

	epochs = int(os.environ.get("IRAQI_LP_EPOCHS", "50"))
	imgsz = int(os.environ.get("IRAQI_LP_IMGSZ", "1280"))
	batch = int(os.environ.get("IRAQI_LP_BATCH", "8"))

	print(f"Train: starting -> data={data_yaml}, epochs={epochs}, imgsz={imgsz}, batch={batch}")
	model = YOLO('yolov8l.pt')
	r = model.train(data=data_yaml, epochs=epochs, imgsz=imgsz, batch=batch, workers=0)
	print("Train: completed.")
	# Try to copy best weights to kk/weights/yolov8l-iraqi-license-plate.pt
	try:
		best = os.path.join(r.save_dir, "weights", "best.pt")
		target = os.path.join(root, "kk", "weights", "yolov8l-iraqi-license-plate.pt")
		os.makedirs(os.path.dirname(target), exist_ok=True)
		import shutil
		shutil.copy2(best, target)
		print(f"Train: best weights copied to {target}")
	except Exception as e:
		print(f"Train: could not copy best weights automatically: {e}")

if __name__ == "__main__":
	main()


