web: gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"
worker: celery -A kk.tasks.celery_app.celery_app worker --loglevel=info --concurrency=2 --max-tasks-per-child=50 --max-memory-per-child=200000
beat: celery -A kk.tasks.celery_app.celery_app beat --loglevel=info

