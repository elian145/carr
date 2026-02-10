from __future__ import annotations

import os
import logging

from flask import Blueprint, abort, jsonify, send_from_directory, current_app

bp = Blueprint("misc", __name__)
logger = logging.getLogger(__name__)


@bp.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200


@bp.route("/static/<path:filename>")
def static_files(filename: str):
    """Serve static files from kk/static, then repo root static/ as fallback."""
    if filename.startswith("uploads/uploads/"):
        filename = filename[len("uploads/") :]

    static_dir = os.path.join(current_app.root_path, "static")
    try:
        path_in_kk = os.path.join(static_dir, filename)
        if os.path.isfile(path_in_kk):
            return send_from_directory(static_dir, filename)
    except Exception as e:
        logger.warning("static_files kk/static failed for %s: %s", filename, e, exc_info=True)

    repo_static = os.path.abspath(os.path.join(current_app.root_path, "..", "static"))
    try:
        path_in_repo = os.path.join(repo_static, filename)
        if os.path.isfile(path_in_repo):
            return send_from_directory(repo_static, filename)
    except Exception as e:
        logger.warning("static_files repo static failed for %s: %s", filename, e, exc_info=True)

    abort(404)

