web: gunicorn "kk.wsgi:app" -c "gunicorn.conf.py"
worker: celery -A kk.tasks.celery_app.celery_app worker --loglevel=info

