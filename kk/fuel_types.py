"""Canonical fuel / powertrain vocabulary for listings and search filters.

The Flutter app stores and sends exactly one of ``gasoline``, ``diesel``,
``electric``, ``hybrid`` and ``plug-in hybrid`` (see
``lib/services/car_spec_powertrain.dart``, which this mirrors). Older rows,
seed scripts and other API clients also spell the hybrid family as
``plug_in_hybrid``, ``Plugin Hybrid``, ``PHEV``, ``HEV`` ...

Only the hybrid family (``hybrid`` / ``plug-in hybrid``) is normalised here:

* storage: a recognised hybrid spelling is saved as the canonical value, so the
  Hybrid and Plug-in Hybrid search filters (exact matches) find the listing;
* search: a Hybrid / Plug-in Hybrid filter matches every stored spelling of that
  one canonical fuel, and **only** that fuel. ``hybrid`` never matches
  ``plug-in hybrid``, ``electric``, ``gasoline`` or ``mild-hybrid``.

Every other value (``gasoline``, ``diesel``, ``electric``, ``lpg`` ...) keeps its
existing behaviour byte for byte. The moderation engine needs no change: its
``classify_powertrain`` already treats any of these spellings as a hybrid, so a
hybrid with a combustion displacement / cylinder count is never flagged as an
"electric car with an engine".
"""
from __future__ import annotations

import re

GASOLINE = "gasoline"
DIESEL = "diesel"
ELECTRIC = "electric"
HYBRID = "hybrid"
PLUG_IN_HYBRID = "plug-in hybrid"

#: Canonical values this module normalises on write / expands on search.
HYBRID_FAMILY = frozenset({HYBRID, PLUG_IN_HYBRID})

_FOLD = re.compile(r"[\s_\-/+]+")

# Folded spelling (lower case, separators collapsed to one space) -> canonical.
_CANONICAL = {
    "gasoline": GASOLINE,
    "gas": GASOLINE,
    "petrol": GASOLINE,
    "benzin": GASOLINE,
    "diesel": DIESEL,
    "electric": ELECTRIC,
    "ev": ELECTRIC,
    "bev": ELECTRIC,
    "battery electric": ELECTRIC,
    "hybrid": HYBRID,
    "hev": HYBRID,
    "full hybrid": HYBRID,
    "self charging hybrid": HYBRID,
    "plug in hybrid": PLUG_IN_HYBRID,
    "plugin hybrid": PLUG_IN_HYBRID,
    "plug in": PLUG_IN_HYBRID,
    "plugin": PLUG_IN_HYBRID,
    "phev": PLUG_IN_HYBRID,
    "erev": PLUG_IN_HYBRID,
    "range extender": PLUG_IN_HYBRID,
}

# Every raw (lower-cased, trimmed) spelling stored for a hybrid-family value,
# used to expand a search filter into an exact IN (...) match.
_STORED_SPELLINGS = {
    HYBRID: (
        "hybrid",
        "hev",
        "full hybrid",
        "full-hybrid",
        "full_hybrid",
        "self-charging hybrid",
        "self charging hybrid",
    ),
    PLUG_IN_HYBRID: (
        "plug-in hybrid",
        "plug_in_hybrid",
        "plug in hybrid",
        "plugin hybrid",
        "plugin_hybrid",
        "plug-in",
        "plug in",
        "plugin",
        "phev",
        "erev",
        "range extender",
        "range-extender",
    ),
}


def _fold(raw) -> str:
    return _FOLD.sub(" ", str(raw or "").strip().lower()).strip()


def canonical_fuel_type(raw) -> str | None:
    """The canonical fuel of any known spelling, else ``None``.

    Exact on the folded text: ``mild hybrid``, ``lpg`` and unknown values are NOT
    mapped (a mild hybrid is not a ``hybrid`` for search purposes)."""
    return _CANONICAL.get(_fold(raw))


def storage_fuel_value(raw):
    """Value to persist for ``fuel_type`` / ``engine_type``.

    A recognised hybrid-family spelling becomes the canonical value; everything
    else is returned unchanged (existing stored values keep their exact text)."""
    canon = canonical_fuel_type(raw)
    return canon if canon in HYBRID_FAMILY else raw


def stored_spellings(canonical: str) -> tuple[str, ...]:
    """Lower-case stored spellings that mean ``canonical`` (hybrid family only)."""
    return _STORED_SPELLINGS.get(canonical, ())


def fuel_filter_matches(car_value, token: str) -> bool:
    """Python mirror of the SQL fuel filter for ONE filter ``token``.

    ``token`` is a single, already lower-cased filter entry. Hybrid-family
    tokens match every spelling of that one canonical fuel; any other token keeps
    the exact (case-insensitive) comparison used before."""
    token_canon = canonical_fuel_type(token)
    if token_canon in HYBRID_FAMILY:
        return canonical_fuel_type(car_value) == token_canon
    return str(car_value or "").strip().lower() == token
