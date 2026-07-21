"""Postgres full-text search helpers for public car listings (M-13).

Uses a GIN-indexed ``car.search_vector`` column (simple config — better for
brand/model tokens than english stemming). SQLite / missing column falls back
to ``ILIKE`` OR across title/brand/model/trim/location/description.
"""

from __future__ import annotations

import logging
import re

from sqlalchemy import func, or_, text

from .models import Car, db

logger = logging.getLogger(__name__)

_MAX_Q_LEN = 120
_SAFE_TOKEN = re.compile(r"[^\w\s\-./]+", re.UNICODE)


def normalize_search_query(raw: str | None) -> str:
    q = (raw or "").strip()
    if not q:
        return ""
    q = _SAFE_TOKEN.sub(" ", q)
    q = re.sub(r"\s+", " ", q).strip()
    return q[:_MAX_Q_LEN]


def _dialect_name() -> str:
    try:
        bind = db.session.get_bind()
        return (bind.dialect.name if bind is not None else "").lower()
    except Exception:
        return ""


def apply_listing_text_search(query, raw: str | None):
    """Filter ``query`` by free-text ``q`` / ``search``.

    Returns ``(query, rank_expr_or_None)``. When ``rank_expr`` is set, callers
    may ``order_by(rank_expr.desc())`` for relevance sorting.
    """
    term = normalize_search_query(raw)
    if not term:
        return query, None

    if _dialect_name() == "postgresql":
        try:
            # Bind once; column is maintained by migration trigger (not mapped).
            filtered = query.filter(
                text(
                    "car.search_vector @@ websearch_to_tsquery('simple', :fts_q)"
                ).bindparams(fts_q=term)
            )
            rank = text(
                "ts_rank_cd(car.search_vector, websearch_to_tsquery('simple', :fts_q))"
            ).bindparams(fts_q=term)
            return filtered, rank
        except Exception:
            logger.exception("Postgres FTS filter failed; falling back to ILIKE")

    like = f"%{term}%"
    return (
        query.filter(
            or_(
                Car.title.ilike(like),
                Car.brand.ilike(like),
                Car.model.ilike(like),
                Car.trim.ilike(like),
                Car.location.ilike(like),
                Car.description.ilike(like),
                Car.color.ilike(like),
            )
        ),
        None,
    )
