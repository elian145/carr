# One-off migrations (legacy)

These scripts patch **old SQLite dev databases** with ad-hoc `ALTER TABLE` / backfill steps.

**For production and new schema changes, use Alembic instead:**

```bash
flask db upgrade
```

Scripts live here (not repo root) so the project root stays clean.

## Run (from repo root)

```bash
python scripts/one_off_migrations/migrate_add_seller_id.py
python scripts/one_off_migrations/migrate_car_image_kind.py
# ... etc.
```

Only run against a database you own; back up `instance/*.db` first.
