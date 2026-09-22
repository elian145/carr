"""Full-text search + relevance ranking helpers for public car listings.

Filtering (M-13): uses a GIN-indexed ``car.search_vector`` column (simple
config -- better for brand/model tokens than english stemming) on Postgres.
SQLite / missing column falls back to ``ILIKE`` OR across
title/brand/model/trim/location/description/color.

Ranking (CN-SEARCH-01): the free-text filters above are intentionally broad
-- ``websearch_to_tsquery`` ANDs query tokens across a shared tsvector, and
the ILIKE fallback ORs a plain substring across several columns. That is
correct for *matching* ("Land Cruiser Prado" legitimately contains both the
"land" and "cruiser" tokens for a "Land Cruiser" query, and must not be
excluded), but it does **not** distinguish an exact/near-exact model match
from a broader match that merely happens to contain the same tokens. Without
that distinction, ``ORDER BY`` fell back to recency/featured status, so a
query like "Land Cruiser" could be dominated by "Land Cruiser Prado" listings
whenever those simply outnumbered (or were newer/featured than) the real
"Land Cruiser" listings -- LIMIT/OFFSET pagination then hid the exact matches
on later pages entirely.

``build_relevance_rank_expr()`` below computes a generic, name-agnostic
"how good is this match" tier (as a plain SQL ``CASE`` expression, portable
across Postgres and SQLite -- no dialect-specific functions) that
``_order_cars_query`` (kk/routes/cars.py) sorts by *before* falling back to
featured/recency. It is not hardcoded to any specific brand/model: it only
looks at the shape of the stored ``model``/``brand``/``title`` text relative
to the normalized query --

    1. exact normalized model match                  ("Land Cruiser")
    2. exact normalized "brand model" match           ("Toyota Land Cruiser")
    3. model starts with query, remainder is numeric  ("Land Cruiser 70")
       (i.e. same base model, later generation/variant number)
    4. "brand model" ends with " " + query            ("... Toyota Land Cruiser")
    5. model starts with query, remainder is a word   ("Land Cruiser Prado")
       (i.e. a related but different, more specific model)
    6. model contains query elsewhere
    7. title / "brand model" contains query elsewhere
    8. matched via some other field only (description/color/location/trim)
"""

from __future__ import annotations

import logging
import re

from sqlalchemy import and_, case, func, literal, or_, text

from .models import Car, db

logger = logging.getLogger(__name__)

_MAX_Q_LEN = 120
_SAFE_TOKEN = re.compile(r"[^\w\s\-./]+", re.UNICODE)

# Relevance tiers used by build_relevance_rank_expr(); higher == better match.
# Gaps are intentional (room to insert future tiers without renumbering).
_RANK_EXACT_MODEL = 100
_RANK_EXACT_BRAND_MODEL = 95
_RANK_MODEL_VARIANT = 90
_RANK_BRAND_MODEL_SUFFIX = 80
_RANK_MODEL_RELATED = 60
_RANK_MODEL_CONTAINS = 45
_RANK_TITLE_CONTAINS = 30
_RANK_COMBINED_CONTAINS = 25
_RANK_OTHER_FIELD = 10

_DIGITS = tuple("0123456789")


def normalize_search_query(raw: str | None) -> str:
    """Trim, drop unsafe characters, and collapse internal whitespace.

    Keeps letters/digits/underscore/whitespace plus a small allowlist of
    punctuation useful in car names (``-``, ``.``, ``/``) so terms like
    "mercedes-benz c-class" survive intact. Does *not* lowercase -- callers
    that need case-insensitive comparison lowercase separately (SQL
    ``ILIKE``/``LIKE`` on a lowered column already handles that; see
    ``build_relevance_rank_expr``).
    """
    q = (raw or "").strip()
    if not q:
        return ""
    q = _SAFE_TOKEN.sub(" ", q)
    q = re.sub(r"\s+", " ", q).strip()
    return q[:_MAX_Q_LEN]


def like_escape(value: str) -> str:
    """Escape ``\\``, ``%`` and ``_`` so ``value`` matches literally when
    substituted into a ``LIKE``/``ILIKE`` pattern (BE-15).

    Callers must pass ``escape="\\\\"`` alongside the escaped value, e.g.
    ``Car.brand.ilike(f"%{like_escape(brand)}%", escape="\\\\")``. Backslash
    is escaped first so a literal backslash in ``value`` isn't mistaken for
    (part of) an escape sequence introduced by this function.
    """
    return (
        value.replace("\\", "\\\\")
        .replace("%", "\\%")
        .replace("_", "\\_")
    )


def _dialect_name() -> str:
    try:
        bind = db.session.get_bind()
        return (bind.dialect.name if bind is not None else "").lower()
    except Exception:
        return ""


def _normalized_text(col):
    """``lower(trim(col))`` with a best-effort collapse of doubled internal
    spaces. Pure ``lower``/``trim``/``replace`` -- supported identically by
    Postgres and SQLite, so this is safe to use regardless of dialect.
    """
    c = func.lower(func.trim(col))
    # Two passes collapse up to 4 consecutive spaces down to 1; real listing
    # data is not expected to have more than that, and this is a ranking
    # signal (not a correctness-critical filter), so it need not be exact.
    c = func.replace(c, "  ", " ")
    c = func.replace(c, "  ", " ")
    return c


def build_relevance_rank_expr(term: str):
    """Build a dialect-agnostic ``CASE`` expression scoring how well each
    row's model/brand/title matches normalized free-text ``term``.

    Returns ``None`` if ``term`` normalizes to empty. Otherwise, an integer
    SQL expression suitable for ``order_by(desc(expr))`` -- higher scores
    are better matches. See module docstring for the tier list; this is
    generic across any brand/model pair, not specific to "Land Cruiser".
    """
    term_norm = re.sub(r"\s+", " ", (term or "").strip().lower())
    if not term_norm:
        return None

    like_term = like_escape(term_norm)

    model_n = _normalized_text(Car.model)
    title_n = _normalized_text(Car.title)
    combined_n = _normalized_text(Car.brand.concat(" ").concat(Car.model))

    starts_with_model = model_n.like(f"{like_term}%", escape="\\")
    contains_model = model_n.like(f"%{like_term}%", escape="\\")
    contains_title = title_n.like(f"%{like_term}%", escape="\\")
    contains_combined = combined_n.like(f"%{like_term}%", escape="\\")

    # "brand model" ends with " " + query, e.g. combined "toyota land
    # cruiser" for query "land cruiser". Deliberately anchored to the END
    # of the combined string (not "contains anywhere") -- otherwise a
    # different, longer model sharing the same leading words (e.g. "toyota
    # land cruiser prado") would incorrectly qualify too.
    brand_model_suffix = combined_n.like(f"% {like_term}", escape="\\")

    # After the query prefix inside `model`, is the very next meaningful
    # character (skipping one space/hyphen separator, if present) a digit?
    # If so this is treated as a later generation/variant of the SAME model
    # (e.g. "Land Cruiser" -> "Land Cruiser 70"/"Land Cruiser 76"). If the
    # continuation is a word instead (e.g. "Land Cruiser" -> "Land Cruiser
    # Prado", "Corolla" -> "Corolla Cross"), it is a related but distinct
    # model and must rank lower. This is a generic, name-agnostic heuristic
    # -- no specific brand/model is hardcoded.
    prefix_len = func.length(literal(term_norm))
    next_char = func.substr(model_n, prefix_len + 1, 1)
    after_sep_char = func.substr(model_n, prefix_len + 2, 1)
    continuation_char = case(
        (next_char.in_((" ", "-")), after_sep_char),
        else_=next_char,
    )
    is_numeric_continuation = continuation_char.in_(_DIGITS)

    return case(
        (model_n == term_norm, _RANK_EXACT_MODEL),
        (combined_n == term_norm, _RANK_EXACT_BRAND_MODEL),
        (and_(starts_with_model, is_numeric_continuation), _RANK_MODEL_VARIANT),
        (brand_model_suffix, _RANK_BRAND_MODEL_SUFFIX),
        (starts_with_model, _RANK_MODEL_RELATED),
        (contains_model, _RANK_MODEL_CONTAINS),
        (contains_title, _RANK_TITLE_CONTAINS),
        (contains_combined, _RANK_COMBINED_CONTAINS),
        else_=_RANK_OTHER_FIELD,
    )


def apply_listing_text_search(query, raw: str | None):
    """Filter ``query`` by free-text ``q`` / ``search`` and attach a
    relevance rank expression.

    Returns ``(query, rank_expr_or_None)``. When ``rank_expr`` is set,
    callers should ``order_by(desc(rank_expr), ...)`` for relevance sorting
    (see ``kk/routes/cars.py::_order_cars_query``). ``rank_expr`` is the
    generic exactness-aware tier from ``build_relevance_rank_expr`` -- used
    for *both* dialects, so SQLite (dev/tests) and Postgres (prod) rank
    matches consistently. The underlying row-matching filter stays
    dialect-specific (Postgres FTS vs. ILIKE fallback) since that's a
    performance/matching concern independent of ranking.
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
            return filtered, build_relevance_rank_expr(term)
        except Exception:
            logger.exception("Postgres FTS filter failed; falling back to ILIKE")

    like = f"%{term}%"
    filtered = query.filter(
        or_(
            Car.title.ilike(like),
            Car.brand.ilike(like),
            Car.model.ilike(like),
            Car.trim.ilike(like),
            Car.location.ilike(like),
            Car.description.ilike(like),
            Car.color.ilike(like),
        )
    )
    return filtered, build_relevance_rank_expr(term)
