"""Export the compact RUNTIME overlay the Flutter app loads (assets/car_iqcars_overlay.json).

Source: generated/carnet_iqcars_overlay_candidate.json (the reviewed safe candidate), cross-checked against
generated/carnet_iqcars_overlay_exclusions.json. Offline, deterministic, read-only on everything except the one output file.

  python tools/catalog_enrichment/iqcars/export_runtime_overlay.py            # (re)write assets/car_iqcars_overlay.json
  python tools/catalog_enrichment/iqcars/export_runtime_overlay.py --check    # exit 1 if the committed asset is stale

Runtime format 3 (brand -> model -> independent additive lists; empty lists are omitted):

  {"_meta": {...tiny...}, "Toyota": {"Land Cruiser Prado": {"trims_add": [...], "engine_variants_add": ["2.4T", "2.7", "2.8TD"],
                                                           "cylinders": [4, 6]}}}

engine_variants_add holds EVERY approved IQ engine variant of the model as "<litres><qualifier>" (compact; e.g. "2.4T", "4.5TD",
"2.4"). The qualifier is kept verbatim (T / TD / D / TC / none): the app compares engines by displacement + qualifier, so a
"2.4T" is not hidden by an existing "2.4 D". Variants on sizes CarNet already has are included on purpose -- whether a variant is
new is decided in the app against the real CarNet labels (the tooling comparison is displacement-only). Nothing is inferred
from a qualifier (no fuel type, no cylinders).

ONLY these lists reach the app. Never exported: raw responses, source ids/urls, held duplicate trims, excluded values,
ambiguous/unmatched models, contaminated default-list models' engines, research metadata. No trim->engine->cylinder
relationship exists in the format.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
CANDIDATE = HERE / "generated" / "carnet_iqcars_overlay_candidate.json"
EXCLUSIONS = HERE / "generated" / "carnet_iqcars_overlay_exclusions.json"
OUT = REPO / "assets" / "car_iqcars_overlay.json"

ENGINE_RE = re.compile(r"^\d{1,2}\.\dL$")  # candidate displacement, e.g. "2.7L" (never a qualifier such as "TD")
VARIANT_RE = re.compile(r"^(\d{1,2}\.\d)(TD|TC|T|D)?$")  # runtime token, e.g. "2.4T", "4.5TD", "2.4"
FORMAT_VERSION = 3
# The unrestricted defaults IQ returns for unrelated models are 139 engines / 10 cylinder counts. Model-specific lists are tiny.
MAX_ENGINE_VARIANTS_PER_MODEL = 30
MAX_CYLINDERS_PER_MODEL = 6


def _sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def _variant_key(token: str):
    m = VARIANT_RE.match(token)
    return float(m.group(1)), m.group(2) or ""


def _tokens(m: dict) -> list[str]:
    """Every IQ engine variant of the model (added + informational ones on sizes CarNet already has) as runtime tokens."""
    seen: dict[tuple[str, str], None] = {}
    rows = list(m.get("engine_variants") or []) + list(m.get("informational_engine_variants_on_sizes_carnet_already_has") or [])
    for v in rows:
        size, q = v["size"], (v.get("qualifier") or "")
        if not ENGINE_RE.match(size):
            raise SystemExit(f"non-displacement engine size in variant of {m['brand']} {m['model']}: {size!r}")
        seen[(size, q)] = None
    # a candidate size without any variant row is exported plain (no qualifier invented)
    have = {s for s, _ in seen}
    for s in m.get("engine_sizes_add") or []:
        if s not in have:
            seen[(s, "")] = None
    out = []
    for size, q in seen:
        token = f"{size[:-1]}{q}"
        if not VARIANT_RE.match(token):
            raise SystemExit(f"unsupported engine variant in {m['brand']} {m['model']}: {token!r}")
        out.append(token)
    return sorted(set(out), key=_variant_key)


def build(candidate: dict, exclusions: dict) -> dict:
    ambiguous = {(e["iq_brand"], e["iq_model"]) for e in exclusions["ambiguous_iq_models"]}
    unmatched = {(e["iq_brand"], e["iq_model"]) for e in exclusions["unmatched_iq_models"]}
    explicit = {(e["iq_brand"], e["iq_model"]) for e in exclusions["explicitly_excluded_models"]}
    default_engine = {(e["brand"], e["model"]) for e in exclusions["unrestricted_default_engine_lists"]}
    default_cyl = {(e["brand"], e["model"]) for e in exclusions["unrestricted_default_cylinder_lists"]}
    held = {(e["brand"], e["model"], e["iq_trim"]) for e in exclusions["trims_held_for_review"]}
    quarantined = {(e["brand"], e["model"], int(e["value"])) for e in exclusions.get("quarantined_cylinder_values", [])}
    blocked = ambiguous | unmatched | explicit

    out: dict[str, dict[str, dict]] = {}
    for m in candidate["models"]:
        key = (m["brand"], m["model"])
        if key in blocked:
            raise SystemExit(f"candidate contains an excluded model: {key}")
        trims = list(m["trims_add"])
        raw_sizes = set(m["engine_sizes_add"])
        if any(not ENGINE_RE.match(s) for s in raw_sizes):
            raise SystemExit(f"non-displacement engine value in {key}: {sorted(raw_sizes)}")
        cyls = sorted({int(c) for c in m["cylinders"]})
        if not set(int(c) for c in m["cylinders_add"]) <= set(cyls):
            raise SystemExit(f"candidate cylinders_add is not a subset of the full approved set in {key}")
        for qb, qm, qv in quarantined:
            if (qb, qm) == key and qv in cyls:
                raise SystemExit(f"quarantined cylinder {qv} leaked into {key}")
        if key in default_engine:
            if raw_sizes or m.get("engine_variants"):
                raise SystemExit(f"default engine list leaked into {key}")
            variants: list[str] = []  # contaminated default list: engines are never exported for this model
        elif m.get("cylinders_only"):
            variants = []  # entry exists only to carry the full cylinder set; engine scope is unchanged from format 2
        else:
            variants = _tokens(m)
        if key in default_cyl and cyls:
            raise SystemExit(f"default cylinder list leaked into {key}")
        for t in trims:
            if (m["brand"], m["model"], t) in held:
                raise SystemExit(f"held duplicate trim exported: {key} {t!r}")
        if len(variants) > MAX_ENGINE_VARIANTS_PER_MODEL or len(cyls) > MAX_CYLINDERS_PER_MODEL:
            raise SystemExit(f"suspiciously long list (default-list contamination?) in {key}")
        entry: dict[str, list] = {}
        if trims:
            entry["trims_add"] = trims
        if variants:
            entry["engine_variants_add"] = variants
        if cyls:
            entry["cylinders"] = cyls
        if not entry:
            continue
        out.setdefault(m["brand"], {})[m["model"]] = entry

    models = sum(len(v) for v in out.values())
    doc: dict = {
        "_meta": {
            "format": FORMAT_VERSION,
            "semantics": "additive, model-level, independent lists; never removes CarNet values; no trim/engine/cylinder links; "
                         "engine variants compare by displacement + qualifier; cylinders is the FULL approved IQ set "
                         "(the app unions it with its own CarNet baseline)",
            "models": models,
            "source": "iqcars/generated/carnet_iqcars_overlay_candidate.json",
            "source_sha256": _sha256(CANDIDATE),
        }
    }
    for b in sorted(out):
        doc[b] = {mo: out[b][mo] for mo in sorted(out[b])}
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


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    cand = json.loads(CANDIDATE.read_text(encoding="utf-8"))
    exc = json.loads(EXCLUSIONS.read_text(encoding="utf-8"))
    data = render(build(cand, exc))
    if args.check:
        # Newline-tolerant: a Windows checkout with core.autocrlf may rewrite LF as CRLF; the content is what matters
        # (the Dart runtime parses JSON and is newline-agnostic).
        ok = OUT.exists() and OUT.read_bytes().replace(b"\r\n", b"\n") == data
        print("runtime overlay is", "up to date" if ok else "STALE")
        return 0 if ok else 1
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(data)
    doc = json.loads(data.decode("utf-8"))
    print(f"wrote {OUT} ({len(data)} bytes, {doc['_meta']['models']} models)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
