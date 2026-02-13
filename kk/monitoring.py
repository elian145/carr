from __future__ import annotations

import os

from flask import Flask, g


def init_monitoring(app: Flask) -> None:
    """
    Optional monitoring hooks (Sentry).
    Enabled only when SENTRY_DSN is set.
    """
    dsn = (os.environ.get("SENTRY_DSN") or "").strip()
    if not dsn:
        return
    try:
        import sentry_sdk  # type: ignore
        from sentry_sdk.integrations.flask import FlaskIntegration  # type: ignore

        traces = float(os.environ.get("SENTRY_TRACES_SAMPLE_RATE", "0.0") or "0.0")
        profiles = float(os.environ.get("SENTRY_PROFILES_SAMPLE_RATE", "0.0") or "0.0")

        def before_send(event, hint):
            # Attach request_id when available (helps correlate with logs).
            try:
                rid = getattr(g, "request_id", None)
                if rid:
                    event.setdefault("tags", {})["request_id"] = rid
            except Exception:
                pass
            return event

        sentry_sdk.init(
            dsn=dsn,
            integrations=[FlaskIntegration()],
            traces_sample_rate=max(0.0, min(1.0, traces)),
            profiles_sample_rate=max(0.0, min(1.0, profiles)),
            environment=(os.environ.get("APP_ENV") or os.environ.get("FLASK_ENV") or "production").strip().lower(),
            send_default_pii=False,
            before_send=before_send,
        )
        app.logger.info("Sentry monitoring enabled")
    except Exception:
        app.logger.warning("Sentry monitoring requested but failed to initialize", exc_info=True)

