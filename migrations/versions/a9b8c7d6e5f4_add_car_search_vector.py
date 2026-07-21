"""Add Postgres tsvector + GIN index for listing full-text search.

Revision ID: a9b8c7d6e5f4
Revises: z4a5b6c7d8e9
Create Date: 2026-07-21

M-13: replace leading-wildcard ILIKE free-text with ``search_vector @@`` queries.
Uses the ``simple`` text search config so brand/model tokens are not stemmed away.
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "a9b8c7d6e5f4"
down_revision = "z4a5b6c7d8e9"
branch_labels = None
depends_on = None

_VECTOR_EXPR = """
(
  setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
  setweight(to_tsvector('simple', coalesce(brand, '')), 'A') ||
  setweight(to_tsvector('simple', coalesce(model, '')), 'A') ||
  setweight(to_tsvector('simple', coalesce(trim, '')), 'B') ||
  setweight(to_tsvector('simple', coalesce(location, '')), 'B') ||
  setweight(to_tsvector('simple', coalesce(color, '')), 'C') ||
  setweight(to_tsvector('simple', coalesce(description, '')), 'D')
)
"""

_TRIGGER_FN = """
CREATE OR REPLACE FUNCTION car_search_vector_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('simple', coalesce(NEW.title, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(NEW.brand, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(NEW.model, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(NEW.trim, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(NEW.location, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(NEW.color, '')), 'C') ||
    setweight(to_tsvector('simple', coalesce(NEW.description, '')), 'D');
  RETURN NEW;
END
$$ LANGUAGE plpgsql;
"""


def upgrade() -> None:
    conn = op.get_bind()
    if conn.dialect.name != "postgresql":
        return
    inspector = sa.inspect(conn)
    if not inspector.has_table("car"):
        return
    cols = {c["name"] for c in inspector.get_columns("car")}
    if "search_vector" not in cols:
        op.execute(sa.text("ALTER TABLE car ADD COLUMN search_vector tsvector"))
        op.execute(sa.text(f"UPDATE car SET search_vector = {_VECTOR_EXPR}"))
    indexes = {ix["name"] for ix in inspector.get_indexes("car")}
    if "ix_car_search_vector" not in indexes:
        op.execute(
            sa.text(
                "CREATE INDEX ix_car_search_vector ON car USING GIN (search_vector)"
            )
        )
    op.execute(sa.text(_TRIGGER_FN))
    op.execute(sa.text("DROP TRIGGER IF EXISTS trg_car_search_vector ON car"))
    op.execute(
        sa.text(
            """
            CREATE TRIGGER trg_car_search_vector
            BEFORE INSERT OR UPDATE OF title, brand, model, trim, location, color, description
            ON car
            FOR EACH ROW
            EXECUTE PROCEDURE car_search_vector_update()
            """
        )
    )


def downgrade() -> None:
    conn = op.get_bind()
    if conn.dialect.name != "postgresql":
        return
    op.execute(sa.text("DROP TRIGGER IF EXISTS trg_car_search_vector ON car"))
    op.execute(sa.text("DROP FUNCTION IF EXISTS car_search_vector_update()"))
    inspector = sa.inspect(conn)
    if not inspector.has_table("car"):
        return
    indexes = {ix["name"] for ix in inspector.get_indexes("car")}
    if "ix_car_search_vector" in indexes:
        op.execute(sa.text("DROP INDEX IF EXISTS ix_car_search_vector"))
    cols = {c["name"] for c in inspector.get_columns("car")}
    if "search_vector" in cols:
        op.execute(sa.text("ALTER TABLE car DROP COLUMN search_vector"))
