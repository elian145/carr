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

Restriction (CN-SEARCH-02): tier 5 above only *deprioritizes* a related-but-
different model like "Land Cruiser Prado" -- it still shows up (just lower)
for a "Land Cruiser" search. Follow-up feedback wants it excluded entirely
when the query is itself a known, exact model name: searching "Land Cruiser"
should be *restricted* to the Land Cruiser family (including numeric/
generation variants such as "Land Cruiser 300"/"70"/"76"), not merely
prioritized over "Land Cruiser Prado".

``_sibling_canonical_models()`` answers this generically using the same
canonical brand/model dataset the app already ships and seeds its catalog
tables from (``assets/car_catalog.json`` -- see ``kk/catalog_service.py``):
if the normalized query exactly matches a known canonical model name, any
*other* canonical model name that starts with the query followed by a WORD
(not a digit) is a distinct sibling model and is excluded from the result
set entirely (``_exclude_sibling_models``), before ``LIMIT``/``OFFSET`` is
ever applied. A continuation that starts with a digit (cataloged or not --
e.g. "Land Cruiser 300" even if that exact generation isn't itself a
catalog entry) is treated as the same model family and is never excluded.
If the query does not exactly match a known canonical model, no exclusion
is applied and normal broad keyword search behavior (tiers 1-8 above)
governs ranking as before.
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


def _normalize_plain(raw: str | None) -> str:
    """Python-side ``lower(trim(collapse-whitespace(raw)))`` -- the same
    normalization ``build_relevance_rank_expr`` applies in SQL, used here to
    compare a query against the canonical model catalog in Python.
    """
    return re.sub(r"\s+", " ", (raw or "").strip().lower())


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
    term_norm = _normalize_plain(term)
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


_canonical_model_names_cache: frozenset[str] | None = None


def _canonical_model_names() -> frozenset[str]:
    """Every model name across every brand in the app's canonical vehicle
    catalog (``assets/car_catalog.json``), normalized. This is the same
    static dataset ``kk/catalog_service.py::seed_catalog`` uses to populate
    ``CatalogVehicleModel`` and that the Flutter app bundles for its
    make/model pickers -- i.e. the single canonical "known model names"
    source for the whole app, not something reinvented here.

    Cached for the life of the process: this is a static bundled file, not
    request/user data, so re-parsing it on every search request would be
    wasted work. Returns an empty set (falls back to unrestricted broad
    search) if the catalog can't be loaded for any reason -- a missing/
    malformed catalog file must never break search.
    """
    global _canonical_model_names_cache
    if _canonical_model_names_cache is not None:
        return _canonical_model_names_cache

    names: set[str] = set()
    try:
        from .catalog_service import load_catalog_json

        data = load_catalog_json()
        models_map = data.get("models") or {}
        if isinstance(models_map, dict):
            for model_list in models_map.values():
                if not isinstance(model_list, list):
                    continue
                for raw_name in model_list:
                    norm = _normalize_plain(str(raw_name or ""))
                    if norm:
                        names.add(norm)
    except Exception:
        logger.exception(
            "Failed to load canonical model catalog for search restriction; "
            "falling back to unrestricted broad search"
        )

    _canonical_model_names_cache = frozenset(names)
    return _canonical_model_names_cache


def _sibling_canonical_models(term_norm: str) -> list[str]:
    """Other canonical model names that must be EXCLUDED when ``term_norm``
    itself exactly matches a known canonical model.

    A canonical name is a "sibling" (distinct model, exclude it) when it
    starts with ``term_norm`` followed by a separator (space/hyphen) and a
    WORD -- e.g. querying "land cruiser" makes "land cruiser prado" a
    sibling. It is instead treated as the SAME model family (never
    excluded, regardless of whether it is itself cataloged) when the
    character right after the separator is a DIGIT -- e.g. "land cruiser
    70"/"land cruiser 76" continue the same base model with a generation/
    trim number. Returns ``[]`` immediately if ``term_norm`` doesn't exactly
    match a known canonical model, i.e. normal broad search applies.
    """
    if not term_norm or term_norm not in _canonical_model_names():
        return []

    prefix_len = len(term_norm)
    siblings: list[str] = []
    for name in _canonical_model_names():
        if name == term_norm or not name.startswith(term_norm):
            continue
        remainder = name[prefix_len:]
        if not remainder or remainder[0] not in (" ", "-"):
            continue
        continuation = remainder[1:]
        if continuation and continuation[0].isdigit():
            continue  # same-family generation/variant -- never a sibling
        siblings.append(name)
    return siblings


def _exclude_sibling_models(query, sibling_models: list[str]):
    """Remove rows whose ``Car.model`` belongs to one of ``sibling_models``
    (or is itself an extension of one, e.g. a future trim-in-model string)
    from ``query``. No-op when ``sibling_models`` is empty.
    """
    if not sibling_models:
        return query
    model_n = _normalized_text(Car.model)
    is_sibling = or_(
        *[
            or_(
                model_n == sibling,
                model_n.like(f"{like_escape(sibling)} %", escape="\\"),
                model_n.like(f"{like_escape(sibling)}-%", escape="\\"),
            )
            for sibling in sibling_models
        ]
    )
    return query.filter(~is_sibling)


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

    CN-SEARCH-02: when ``raw`` normalizes to an exact known canonical model
    name (see ``_canonical_model_names``), distinct sibling models sharing
    the same leading words (e.g. "Land Cruiser Prado" for a "Land Cruiser"
    query) are excluded from the returned ``query`` entirely -- not merely
    ranked lower -- via ``_exclude_sibling_models``. This happens before
    ``LIMIT``/``OFFSET`` (pagination) is applied by the caller, so an
    excluded sibling model can never "reappear" on a later page. Non-exact
    queries are unaffected and keep the prior broad-match behavior.
    """
    term = normalize_search_query(raw)
    if not term:
        return query, None

    sibling_models = _sibling_canonical_models(_normalize_plain(term))

    if _dialect_name() == "postgresql":
        try:
            # Bind once; column is maintained by migration trigger (not mapped).
            filtered = query.filter(
                text(
                    "car.search_vector @@ websearch_to_tsquery('simple', :fts_q)"
                ).bindparams(fts_q=term)
            )
            filtered = _exclude_sibling_models(filtered, sibling_models)
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
    filtered = _exclude_sibling_models(filtered, sibling_models)
    return filtered, build_relevance_rank_expr(term)
