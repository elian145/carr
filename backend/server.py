import io
import os
import sys
import logging
from pathlib import Path
from flask import Flask, request, jsonify, send_file
from werkzeug.utils import secure_filename
from dotenv import load_dotenv
import requests
import tempfile

# Ensure repo-root imports work when running from ./backend
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# Load environment variables; prefer .env, fallback to env.local
load_dotenv()
env_local_path = os.path.join(os.path.dirname(__file__), "env.local")
if os.path.exists(env_local_path):
	# Use override=True so env.local can repair empty/incorrect inherited env vars.
	# This makes behavior reproducible when the OS has stale/blank ROBOFLOW_*/LOGO_* vars.
	load_dotenv(env_local_path, override=True)

app = Flask(__name__)

# Logging configuration
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")
logger = logging.getLogger("watermarkly-backend")

LISTINGS_API_BASE = (os.getenv("LISTINGS_API_BASE") or "").strip().rstrip("/")

def _safe_resolve_under(root_dir: str, subpath: str) -> str | None:
	"""
	Return an absolute path to subpath under root_dir, or None if unsafe.

	Blocks:
	- path traversal (..)
	- absolute paths
	- symlinks that would escape root_dir (via resolve())
	"""
	try:
		root = Path(root_dir).resolve()
		# Treat incoming URL path as POSIX-ish and strip leading slashes.
		norm = (subpath or "").replace("\\", "/").lstrip("/")
		if not norm:
			return None
		candidate = (root / Path(norm)).resolve()
		root_s = str(root)
		cand_s = str(candidate)
		# Must be strictly inside root (not equal, not outside)
		if cand_s == root_s:
			return None
		if not cand_s.startswith(root_s + os.sep):
			return None
		return cand_s
	except Exception:
		return None

@app.route("/health", methods=["GET"])
def health():
	return jsonify({"status": "ok"}), 200


# Transparent proxy for all other API requests so the app can use one API_BASE
@app.route("/api/<path:subpath>", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
def proxy_api(subpath: str):
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/api/{subpath}"
		params = request.args.to_dict(flat=False)
		# Build headers but avoid hop-by-hop/host and DO NOT forward content-type for multipart; requests will set it with boundary
		hdrs = {
			k: v
			for k, v in request.headers.items()
			if k.lower() not in ("host", "content-length", "transfer-encoding", "content-type")
		}
		method = request.method.upper()
		# Handle multipart forms
		files = None
		data = None
		json_body = None
		if request.files:
			logger.info(f"[proxy] incoming multipart fields: {list(request.files.keys())} to {target}")
			# Compatibility: some clients send images[]/files[]; also backend expects 'image' or 'images'
			files = []
			for key in request.files.keys():
				for storage in request.files.getlist(key):
					try:
						# Read file content to ensure forwarding is not empty
						content = storage.read()
						import io as _io
						buf = _io.BytesIO(content if isinstance(content, (bytes, bytearray)) else storage.stream.read())
					except Exception:
						try:
							import io as _io
							buf = _io.BytesIO(storage.stream.read())
						except Exception:
							buf = None
					fn = storage.filename or "upload.jpg"
					mt = storage.mimetype or "application/octet-stream"
					if buf is not None:
						# Attach with canonical 'images' key only.
						# NOTE: Do NOT also forward under original key, otherwise the upstream
						# backend may interpret it as two uploads of the same file and store duplicates.
						files.append(("images", (fn, buf, mt)))
			data = request.form.to_dict(flat=False)
		else:
			ctype = request.headers.get("Content-Type", "")
			if "application/json" in ctype:
				json_body = request.get_json(silent=True)
			else:
				data = request.get_data()
		logger.info(f"[proxy] forwarding file parts: {0 if files is None else len(files)} to {target}")
		# Longer timeout for multipart uploads; standard for others
		_has_multipart = (files is not None) or ("multipart/form-data" in (request.headers.get("Content-Type") or ""))
		_timeout_s = 600 if (method == "POST" and _has_multipart) else 60
		resp = _rq.request(method, target, params=params, headers=hdrs, data=data, json=json_body, files=files, timeout=_timeout_s, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

@app.route("/static/uploads/<path:subpath>", methods=["GET", "HEAD"])
def static_uploads_local(subpath: str):
	"""
	Serve images directly from local filesystem if present to avoid 404s due to
	mismatched static roots. Falls back to proxying to the listings server.
	Checks both repo_root/static/uploads and kk/static/uploads.
	"""
	try:
		repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
		roots = [
			os.path.join(repo_root, "static", "uploads"),
			os.path.join(repo_root, "kk", "static", "uploads"),
		]
		for root in roots:
			p = _safe_resolve_under(root, subpath)
			if p and os.path.isfile(p):
				return send_file(p, as_attachment=False, download_name=os.path.basename(p))
	except Exception:
		pass
	# Fallback to proxy to listings server static
	return proxy_uploads(subpath)

@app.route("/static/images/<path:subpath>", methods=["GET", "HEAD"])
def static_images_local(subpath: str):
	"""
	Serve brand and other images from local repo paths before proxying.
	Looks under static/images and kk/static/images.
	"""
	try:
		repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
		roots = [
			os.path.join(repo_root, "static", "images"),
			os.path.join(repo_root, "kk", "static", "images"),
		]
		for root in roots:
			p = _safe_resolve_under(root, subpath)
			if p and os.path.isfile(p):
				return send_file(p, as_attachment=False, download_name=os.path.basename(p))
	except Exception:
		pass
	# Fallback to proxy to listings server static/images
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/static/images/{subpath}"
		params = request.args.to_dict(flat=False)
		resp = _rq.request(request.method, target, params=params, headers={k: v for k, v in request.headers.items() if k.lower() != "host"}, timeout=60, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Static images proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

@app.route("/static/<path:subpath>", methods=["GET", "HEAD"])
def proxy_static(subpath: str):
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/static/{subpath}"
		params = request.args.to_dict(flat=False)
		resp = _rq.request(request.method, target, params=params, headers={k: v for k, v in request.headers.items() if k.lower() != "host"}, timeout=60, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Static proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

@app.route("/uploads/<path:subpath>", methods=["GET", "HEAD"])
def proxy_uploads(subpath: str):
	# Convenience: map /uploads/* -> listings /static/uploads/*
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/static/uploads/{subpath}"
		params = request.args.to_dict(flat=False)
		resp = _rq.request(request.method, target, params=params, headers={k: v for k, v in request.headers.items() if k.lower() != "host"}, timeout=60, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Uploads proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

@app.route("/car_photos/<path:subpath>", methods=["GET", "HEAD"])
def proxy_car_photos(subpath: str):
	# Convenience: map /car_photos/* -> listings /static/uploads/car_photos/*
	if not LISTINGS_API_BASE:
		return jsonify({"error": "ProxyNotConfigured", "message": "Set LISTINGS_API_BASE to your listings API base (no /api)."}), 500
	try:
		import requests as _rq
		target = f"{LISTINGS_API_BASE}/static/uploads/car_photos/{subpath}"
		params = request.args.to_dict(flat=False)
		resp = _rq.request(request.method, target, params=params, headers={k: v for k, v in request.headers.items() if k.lower() != "host"}, timeout=60, stream=False)
		from flask import Response as _FlaskResp
		exclude = {"Content-Encoding", "Transfer-Encoding", "Connection"}
		resp_headers = [(k, v) for k, v in resp.headers.items() if k not in exclude]
		return _FlaskResp(resp.content, status=resp.status_code, headers=resp_headers)
	except Exception as e:
		logger.exception("Car photos proxy error")
		return jsonify({"error": "ProxyError", "message": str(e)}), 502

# No-op analytics endpoint to avoid 500s blocking UI if upstream lacks it
@app.route("/api/analytics/track/view", methods=["POST"])
def analytics_track_view_noop():
	try:
		payload = request.get_json(silent=True) or {}
		logger.info(f"[analytics] view: {payload}")
	except Exception:
		pass
	return jsonify({"ok": True}), 200

def create_app():
	return app

if __name__ == "__main__":
	port = int(os.getenv("PORT", "5000"))
	app.run(host="0.0.0.0", port=port, debug=False)