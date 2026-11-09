# Listings backend (Flask + Socket.IO). Build from repo root:
#   docker build -t car-listings-backend .
#   docker run --env-file kk/.env.example -p 5000:5000 car-listings-backend
#
# Required production env: APP_ENV, SECRET_KEY, JWT_SECRET_KEY, DATABASE_URL
# (see DEPLOYMENT.md). PORT defaults to 5000 inside the container.

FROM python:3.11.9-slim-bookworm

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libglib2.0-0 \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY kk/requirements.txt /app/kk/requirements.txt
RUN pip install --no-cache-dir -r /app/kk/requirements.txt

# Run as an unprivileged user (a container escape / RCE in the app no longer
# starts as root). The app dir is owned by that user so runtime writes under
# /app (e.g. kk/static/uploads, instance/) keep working.
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app \
    && chown app:app /app

COPY --chown=app:app gunicorn.conf.py /app/gunicorn.conf.py
COPY --chown=app:app migrations /app/migrations
COPY --chown=app:app kk /app/kk
# F-31 / C-08: kk/r2_ops.py resolves ../tools/r2_s3_op.py relative to kk/.
COPY --chown=app:app tools/r2_s3_op.py /app/tools/r2_s3_op.py

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_ENV=production \
    PORT=5000

EXPOSE 5000

USER app

# /health is a cheap liveness route (no DB/Redis calls). Honour $PORT like gunicorn.conf.py.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["python", "-c", "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT', '5000'), timeout=4)"]

CMD ["gunicorn", "kk.wsgi:app", "-c", "gunicorn.conf.py"]
