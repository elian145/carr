"""Export the compact RUNTIME provenance index the Flutter app loads (assets/car_iqcars_provenance.json).

The runtime overlay (assets/car_iqcars_overlay.json) is ADDITIVE: it carries what IQ Cars has and CarNet lacks (trims_add), plus
every approved IQ engine variant / cylinder count. It cannot tell the app which of CarNet's OWN brands, models and trims IQ Cars
also has. This index closes that gap so the app can show IQ Cars entries first without ever removing or renaming a CarNet value.

  python tools/catalog_enrichment/iqcars/export_runtime_provenance.py            # (re)write assets/car_iqcars_provenance.json
  python tools/catalog_enrichment/iqcars/export_runtime_provenance.py --check    # exit 1 if the committed asset is stale

Format 1 (brand -> model -> {"trims": [...]}); a model key present means "this CarNet model has an exact IQ Cars identity":

  {"_meta": {"kind": "iqcars_provenance", "format": 1, ...},
   "Toyota": {"Corolla": {"trims": ["L", "XSE", ...]}, "Prius": {}, ...}}

Rules (all mirrored from build_overlay.py so the two assets can never disagree):
  * MODEL IDENTITY: only the exact canonical identity matches of iqcars_model_matching_report.json ("matched"). Ambiguous, unmatched
    and explicitly excluded IQ models never appear (Land Cruiser FJ is NOT a Land Cruiser). Names are CarNet's own spelling.
  * BRAND IDENTITY: a brand is an IQ brand iff at least one of its models has an IQ identity (derived, never stored separately).
  * SHARED TRIMS: an IQ trim of a matched model that is EXACTLY (after NFKC + whitespace normalisation, case-sensitive) a CarNet
    trim of the same model. Lookalikes (`iM` vs `IM`, `EX.R` vs `EXR`, `Twin-Turbo` vs `Twin Turbo`) are NOT shared: they stay
    separate, exactly as build_overlay.py holds them for review. The placeholder trims `Other` / empty are never shared.
  * Trims that IQ has and CarNet lacks are NOT repeated here (they are the overlay's `trims_add`).
Nothing else is exported: no ids, urls, raw responses, engines or cylinders (those already live in the overlay).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from normalize import norm_ws  # noqa: E402

REPO = HERE.parents[2]
GEN = HERE / "generated"
MATCHING = GEN / "iqcars_model_matching_report.json"
OPTIONS = GEN / "iqcars_model_options.json"
EXCLUSIONS = GEN / "carnet_iqcars_overlay_exclusions.json"
CATALOG = REPO / "assets" / "car_catalog.json"
OVERLAY = REPO / "assets" / "car_iqcars_overlay.json"
OUT = REPO / "assets" / "car_iqcars_provenance.json"

FORMAT_VERSION = 1
KIND = "iqcars_provenance"
PLACEHOLDER_TRIMS = {"other", ""}


def _sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def _carnet_trims(catalog: dict, brand: str, model: str) -> set[str]:
    raw = ((catalog.get("trimsByBrandModel") or {}).get(brand) or {}).get(model) or []
    out = set()
    for t in raw:
        n = norm_ws(t)
        if n and n.casefold() not in PLACEHOLDER_TRIMS:
            out.add(n)
    return out


def build(matching: dict, options: dict, exclusions: dict, catalog: dict, overlay: dict | None = None) -> dict:
    blocked = set()
    for sec in ("ambiguous_iq_models", "unmatched_iq_models", "explicitly_excluded_models"):
        blocked |= {(e["iq_brand"], e["iq_model"]) for e in exclusions[sec]}
    iq_by_id = {m["model_id"]: m for m in options["models"]}
    cat_models = {(b, m) for b, ms in catalog["models"].items() for m in ms}

    out: dict[str, dict[str, dict]] = {}
    for x in matching["matched"]:
        if (x["iq_brand"], x["iq_model"]) in blocked or (x["carnet_brand"], x["carnet_model"]) in blocked:
            continue
        key = (x["carnet_brand"], x["carnet_model"])
        if key not in cat_models:
            # The identity is expressed in CarNet's own spelling; a model the bundled catalog does not list is not exportable.
            continue
        iq = iq_by_id[x["iq_model_id"]]
        carnet = _carnet_trims(catalog, *key)
        shared, seen = [], set()
        for t in iq["trims"]:  # IQ's own order, deterministic
            if t in seen:
                continue
            seen.add(t)
            if t.casefold() in PLACEHOLDER_TRIMS:
                continue
            if t in carnet:
                shared.append(t)
        out.setdefault(key[0], {})[key[1]] = {"trims": shared} if shared else {}

    if overlay is not None:  # every overlay entry is by construction an exactly matched model
        missing = [(b, m) for b, ms in overlay.items() if not b.startswith("_") for m in ms if m not in out.get(b, {})]
        if missing:
            raise SystemExit(f"overlay models without an IQ identity: {missing[:5]}")

    doc: dict = {
        "_meta": {
            "kind": KIND,
            "format": FORMAT_VERSION,
            "semantics": "exact IQ Cars identities of CarNet brands/models plus the IQ trims CarNet already has; "
                         "lookalike trims are never merged; ambiguous/unmatched/excluded models are absent; "
                         "nothing is removed or renamed",
            "brands": len(out),
            "models": sum(len(v) for v in out.values()),
            "shared_trims": sum(len(m.get("trims", [])) for v in out.values() for m in v.values()),
            "source_sha256": {
                "matching": _sha256(MATCHING),
                "options": _sha256(OPTIONS),
                "catalog": _sha256(CATALOG),
            },
        }
    }
    for b in sorted(out):
        doc[b] = {m: out[b][m] for m in sorted(out[b])}
    return doc


def render(doc: dict) -> bytes:
    """Compact, deterministic, LF-terminated UTF-8 (one line per brand keeps diffs reviewable)."""
    lines = ["{"]
    keys = list(doc)
    for i, k in enumerate(keys):
        body = json.dumps(doc[k], ensure_ascii=False, separators=(",", ":"), sort_keys=False)
        lines.append(f"{json.dumps(k, ensure_ascii=False)}:{body}{',' if i < len(keys) - 1 else ''}")
    lines.append("}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def _load() -> tuple[dict, dict, dict, dict, dict]:
    rd = lambda p: json.loads(p.read_text(encoding="utf-8"))  # noqa: E731
    return rd(MATCHING), rd(OPTIONS), rd(EXCLUSIONS), rd(CATALOG), rd(OVERLAY)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    data = render(build(*_load()))
    if args.check:
        # Newline-tolerant (Windows autocrlf): the Dart runtime parses JSON and is newline-agnostic.
        ok = OUT.exists() and OUT.read_bytes().replace(b"\r\n", b"\n") == data
        print("runtime provenance is", "up to date" if ok else "STALE")
        return 0 if ok else 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(data)
    doc = json.loads(data.decode("utf-8"))
    m = doc["_meta"]
    print(f"wrote {OUT} ({len(data)} bytes, {m['brands']} brands, {m['models']} models, {m['shared_trims']} shared trims)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
