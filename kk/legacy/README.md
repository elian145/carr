# Legacy backend (removed)

The pre-factory Flask monolith (`app.py` / `app_legacy.py` / `api.py`, ~6.5k lines)
was deleted in **H-11**. It had insecure development defaults (hardcoded secrets,
demo seed routes, payment stubs) and was never the production entrypoint.

**Canonical backend**

| Use | Entry |
|-----|--------|
| Production (Gunicorn) | `kk.wsgi:app` |
| App factory | `kk.app_factory.create_app()` |
| Local API | `python -m kk.app_new` |

Car brand/model/trim data formerly scraped from the monolith lives in
`tools/data/legacy_catalog_seed.json` (see `tools/extract_car_catalog.py`).

Git history still contains the old files if you need to inspect them.
