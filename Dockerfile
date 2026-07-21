# Listings backend (Flask + Socket.IO). Build from repo root:
#   docker build -t car-listings-backend .
#   docker run --env-file kk/.env.example -p 5000:5000 car-listings-backend
#
# Required production env: APP_ENV, SECRET_KEY, JWT_SECRET_KEY, DATABASE_URL
# (see DEPLOYMENT.md). PORT defaults to 5000 inside the container.

FROM python:3.12-slim-bookworm

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libglib2.0-0 \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY kk/requirements.txt /app/kk/requirements.txt
RUN pip install --no-cache-dir -r /app/kk/requirements.txt

COPY gunicorn.conf.py /app/gunicorn.conf.py
COPY migrations /app/migrations
COPY kk /app/kk

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_ENV=production \
    PORT=5000

EXPOSE 5000

CMD ["gunicorn", "kk.wsgi:app", "-c", "gunicorn.conf.py"]
