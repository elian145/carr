from __future__ import annotations

import json
import logging
import os
import time
import uuid
from typing import Any

from flask import Flask, Response, g, jsonify, request
from werkzeug.exceptions import HTTPException


def _client_ip() -> str:
    xff = (request.headers.get("X-Forwarded-For") or "").split(",")[0].strip()
    return xff or (request.remote_addr or "unknown")


def _safe_request_id(raw: str) -> str | None:
    rid = (raw or "").strip()
    if not rid:
        return None
    if len(rid) > 128:
        return None
    # Allow common header-safe characters only
    for ch in rid:
        if not (ch.isalnum() or ch in "-_:."):
            return None
    return rid


class JsonLogFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(record.created)),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        # If extra fields were passed, include them.
        for k, v in record.__dict__.items():
            if k.startswith("_"):
                continue
            if k in (
                "name",
                "msg",
                "args",
                "levelname",
                "levelno",
                "pathname",
                "filename",
                "module",
                "exc_info",
                "exc_text",
                "stack_info",
                "lineno",
                "funcName",
                "created",
                "msecs",
                "relativeCreated",
                "thread",
                "threadName",
                "processName",
                "process",
            ):
                continue
            if k in payload:
                continue
            try:
                json.dumps(v)
                payload[k] = v
            except Exception:
                payload[k] = str(v)
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(app: Flask) -> None:
    level = (os.environ.get("LOG_LEVEL") or "INFO").strip().upper()
    json_logs = (os.environ.get("LOG_JSON") or "").strip().lower() in ("1", "true", "yes", "on")

    handler = logging.StreamHandler()
    if json_logs:
        handler.setFormatter(JsonLogFormatter())
    else:
        handler.setFormatter(logging.Formatter("[%(asctime)s] %(levelname)s %(name)s: %(message)s"))

    root = logging.getLogger()
    root.setLevel(level)
    # Avoid adding duplicate handlers in tests/hot reload.
    if not any(isinstance(h, logging.StreamHandler) for h in root.handlers):
        root.addHandler(handler)

    app.logger.setLevel(level)


def install_request_id_and_access_log(app: Flask) -> None:
    request_id_header = (os.environ.get("REQUEST_ID_HEADER") or "X-Request-ID").strip()

    @app.before_request
    def _request_start():
        rid = _safe_request_id(request.headers.get(request_id_header) or "")
        if not rid:
            rid = uuid.uuid4().hex
        g.request_id = rid
        g._t0 = time.perf_counter()

    @app.after_request
    def _request_end(response: Response):
        try:
            response.headers[request_id_header] = getattr(g, "request_id", "")
        except Exception:
            pass

        try:
            dt_ms = int((time.perf_counter() - float(getattr(g, "_t0", time.perf_counter()))) * 1000)
        except Exception:
            dt_ms = -1

        # Do not log request bodies or auth headers.
        app.logger.info(
            "request",
            extra={
                "event": "request",
                "request_id": getattr(g, "request_id", None),
                "method": request.method,
                "path": request.path,
                "status": getattr(response, "status_code", None),
                "duration_ms": dt_ms,
                "ip": _client_ip(),
                "ua": (request.headers.get("User-Agent") or "")[:200],
            },
        )
        return response


def install_api_error_handlers(app: Flask) -> None:
    """
    Ensure all /api/* errors return a stable JSON shape including request_id.
    Avoid leaking exception internals in production.
    """

    def _is_api_request() -> bool:
        try:
            return (request.path or "").startswith("/api/")
        except Exception:
            return False

    def _request_id() -> str | None:
        try:
            return getattr(g, "request_id", None)
        except Exception:
            return None

    @app.errorhandler(HTTPException)
    def _http_error(e: HTTPException):
        if not _is_api_request():
            return e
        code = int(getattr(e, "code", 500) or 500)
        msg = getattr(e, "description", None) or "Request failed"
        return jsonify({"message": msg, "status": code, "request_id": _request_id()}), code

    @app.errorhandler(Exception)
    def _unhandled_error(e: Exception):
        if not _is_api_request():
            # Keep Flask default behavior for non-API routes.
            raise e

        env = (os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "production").strip().lower()
        rid = _request_id()

        # Log full exception server-side.
        app.logger.exception(
            "unhandled_exception",
            extra={"event": "unhandled_exception", "request_id": rid, "path": request.path},
        )

        if env in ("development", "testing"):
            return jsonify({"message": "Internal server error", "status": 500, "request_id": rid, "error": str(e)}), 500
        return jsonify({"message": "Internal server error", "status": 500, "request_id": rid}), 500
