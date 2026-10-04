#!/usr/bin/env python3
"""CarNet vehicle-data enrichment pilot: library (tooling only, never touches production assets).

Layers
  1. evidence records   evidence/<brand_model>.json   (hand/AI authored, every value quoted from a source)
  2. normalization      deterministic, rules in rules/normalization_rules.json (raw kept next to normalized)
  3. conflict detection same-configuration records that disagree are flagged, never resolved silently
  4. model union        generated/<brand_model>.union.json  (VERIFIED values + PROVISIONAL values + conflicts)
  5. comparison         reports/pilot_comparison.json  (CURRENT_CARNET vs NEW_VERIFIED ...), read-only on assets/

Nothing in here writes under assets/ or lib/. The only read of production data is
`load_current_carnet`, which goes through catalog_audit_readonly (read-only).
"""
from __future__ import annotations

import copy
import datetime as _dt
import json
import re
import sys
import unicodedata
from collections import Counter
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]

SCHEMA_EVIDENCE = "carnet.enrichment_evidence/1"
SCHEMA_UNION = "carnet.model_union/2"  # /2: transmission_variants dimension, production_policy, vocabulary_version
SCHEMA_COMPARISON = "carnet.pilot_comparison/2"  # /2: strict model boundaries, no only_from_prado

NORM = json.loads((HERE / "rules" / "normalization_rules.json").read_text(encoding="utf-8"))
SRC = json.loads((HERE / "rules" / "source_rules.json").read_text(encoding="utf-8"))

DIMENSIONS = [
    "trims",
    "engine_sizes",
    "cylinders",
    "fuel_types",
    "transmissions",  # family: Automatic | Manual
    "transmission_variants",  # CVT, e-CVT, DCT, AMT, Conventional automatic, named systems
    "transmission_gears",
    "drivetrains",
    "body_types",
    "seats",
    "doors",
]
# dimension -> normalized field on a record (None for trims/engine_sizes which are special)
DIM_FIELD = {
    "trims": "trim_key",
    "engine_sizes": "engine_size_label",
    "cylinders": "cylinders",
    "fuel_types": "fuel_type",
    "transmissions": "transmission_family",
    "transmission_variants": "transmission_variant",
    "transmission_gears": "transmission_gears",
    "drivetrains": "drivetrain",
    "body_types": "body_type",
    "seats": "seats",
    "doors": "doors",
}
# conflicts that belong to a comparison dimension
DIM_CONFLICT_FIELDS = {
    "trims": [],
    "engine_sizes": ["displacement_cc", "horsepower_hp", "torque_nm"],
    "cylinders": ["cylinders"],
    "fuel_types": ["fuel_type"],
    "transmissions": ["transmission_family"],
    "transmission_variants": ["transmission_variant"],
    "transmission_gears": ["transmission_gears"],
    "drivetrains": ["drivetrain"],
    "body_types": ["body_type"],
    "seats": ["seats"],
    "doors": ["doors"],
}
CARNET_STORES = {  # does the current CarNet dataset store this attribute at all?
    "trims": True,
    "engine_sizes": True,
    "cylinders": True,
    "fuel_types": True,
    "transmissions": True,
    "transmission_variants": False,
    "transmission_gears": False,
    "drivetrains": True,
    "body_types": True,
    "seats": True,
    "doors": False,
}
COMPARISON_DIMS_REQUESTED = ["trims", "engine_sizes", "cylinders", "fuel_types", "transmissions", "drivetrains", "seats", "body_types"]

# ----------------------------------------------------------------------------------------
# generic helpers
# ----------------------------------------------------------------------------------------


def collapse_ws(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def _rx(p: str) -> re.Pattern:
    return re.compile(p, re.I)


def _first(rules, text):
    for r in rules:
        if re.search(r["pattern"], text, re.I):
            return r
    return None


def half_up(x, ndigits=1) -> Decimal:
    q = Decimal(1).scaleb(-ndigits)
    return Decimal(str(x)).quantize(q, rounding=ROUND_HALF_UP)


def fmt_label_from_liters(liters) -> str:
    return f"{half_up(liters, 1)}L"


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_")


# ----------------------------------------------------------------------------------------
# normalizers (each returns (value, flags))
# ----------------------------------------------------------------------------------------


def norm_fuel(raw):
    if raw is None or str(raw).strip() == "":
        return None, []
    r = _first(NORM["fuel_type"]["rules"], str(raw))
    if r:
        return r["value"], []
    return None, [f"unmapped:fuel_type:{raw}"]


def norm_transmission(raw, gears_given=None):
    """Two-level transmission (LOCKED vocabulary).
    -> ({'family','variant','named_systems','gears'}, flags)
    family  : Automatic | Manual | None
    variant : canonical variant (CVT, e-CVT, DCT, AMT, Conventional automatic) if the source says so, else the
              source's own named system (SelectShift, Direct Shift, ...), else None. Never discarded.
    gears   : kept wherever stated (also for CVTs, with a flag)."""
    out = {"family": None, "variant": None, "named_systems": [], "gears": None}
    flags = []
    tr = NORM["transmission"]
    if raw is not None and str(raw).strip() != "":
        t = str(raw)
        if any(re.search(p, t, re.I) for p in tr["automatic_patterns"]):
            out["family"] = "Automatic"
        elif any(re.search(p, t, re.I) for p in tr["manual_patterns"]):
            out["family"] = "Manual"
        else:
            flags.append(f"unmapped:transmission:{raw}")
        out["named_systems"] = [n["label"] for n in tr["named_systems"] if re.search(n["pattern"], t, re.I)]
        v = _first(tr["variant_rules"], t)
        if v:
            out["variant"] = v["value"]
        elif out["named_systems"]:
            out["variant"] = out["named_systems"][0]
        for p in tr["gear_count_patterns"]:
            m = re.search(p, t, re.I)
            if m:
                out["gears"] = int(m.group(1))
                break
    if gears_given is not None:
        out["gears"] = int(gears_given)
    if out["gears"] is not None and out["variant"] in tr["gears_flag_when_variant"]:
        flags.append("gears_stated_for_cvt")
    return out, flags


def norm_drivetrain(raw):
    if raw is None or str(raw).strip() == "":
        return None, []
    t = str(raw)
    r = _first(NORM["drivetrain"]["rules"], t)
    if r:
        return r["value"], []
    u = _first(NORM["drivetrain"]["unresolved_rules"], t)
    if u:
        return None, [u["flag"]]
    return None, [f"unmapped:drivetrain:{raw}"]


def norm_body(raw):
    if raw is None or str(raw).strip() == "":
        return None, []
    r = _first(NORM["body_type"]["rules"], str(raw))
    if r:
        return r["value"], []
    return None, [f"unmapped:body_type:{raw}"]


def _int_from_words(t: str):
    words = NORM["seats"]["number_words"]
    for w, n in words.items():
        if re.search(rf"\b{w}\b", t, re.I):
            return n
    return None


def norm_seats(raw):
    if raw is None or (isinstance(raw, str) and raw.strip() == ""):
        return None, []
    flags = []
    if isinstance(raw, bool):
        return None, [f"unmapped:seats:{raw}"]
    if isinstance(raw, int):
        n = raw
    else:
        t = str(raw)
        m = re.search(r"\d+", t)
        n = int(m.group(0)) if m else _int_from_words(t)
        if re.search(r"up\s*to|as many as|maximum|max\.?", t, re.I):
            flags.append("seats_is_maximum")
    lo, hi = NORM["seats"]["valid_range"]
    if n is None or not (lo <= n <= hi):
        return None, flags + [f"unmapped:seats:{raw}"]
    return n, flags


def norm_doors(raw):
    if raw is None or (isinstance(raw, str) and raw.strip() == ""):
        return None, []
    n = raw if isinstance(raw, int) else (int(re.search(r"\d+", str(raw)).group(0)) if re.search(r"\d+", str(raw)) else _int_from_words(str(raw)))
    lo, hi = NORM["doors"]["valid_range"]
    if n is None or not (lo <= n <= hi):
        return None, [f"unmapped:doors:{raw}"]
    return n, []


def norm_cylinders(raw):
    if raw is None or (isinstance(raw, str) and raw.strip() == ""):
        return None, []
    lo, hi = NORM["cylinders"]["valid_range"]
    if isinstance(raw, int):
        n = raw
    else:
        n = None
        for p in NORM["cylinders"].get("word_patterns", []):
            m = re.search(p, str(raw), re.I)
            if m:
                n = NORM["cylinders"]["number_words"][m.group(1).lower()]
                break
        for p in ([] if n is not None else NORM["cylinders"]["patterns"]):
            m = re.search(p, str(raw), re.I)
            if m:
                n = int(m.group(1))
                break
    if n is None or not (lo <= n <= hi):
        return None, [f"unmapped:cylinders:{raw}"]
    return n, []


_CC_RX = re.compile(r"(\d[\d,]*(?:\.\d+)?)\s*(?:cc|c\.c\.?|cm3|cm\u00b3|cu\.?\s*cm)\b", re.I)
_L_RX = re.compile(r"(\d+(?:\.\d+)?)\s*-?\s*(?:l|litre|liter|litres|liters)\b", re.I)


def norm_displacement(raw):
    """raw: str like '2.3L', '3,198 cc', or {'value': 2993, 'unit': 'cc'|'cm3'|'L'}.
    -> ({'cc','nominal_l','label'}, flags)"""
    out = {"cc": None, "nominal_l": None, "label": None}
    if raw is None or (isinstance(raw, str) and raw.strip() == ""):
        return out, []
    kind = value = None
    if isinstance(raw, dict):
        unit = str(raw.get("unit", "")).lower().replace("\u00b3", "3").replace(" ", "")
        value = raw.get("value")
        if value is None:
            return out, [f"unmapped:displacement:{raw}"]
        if unit in ("cc", "cm3", "c.c.", "c.c"):
            kind = "cc"
        elif unit in ("l", "litre", "liter", "litres", "liters"):
            kind = "l"
            ndec = len(str(value).split(".")[1]) if "." in str(value) else 0
            out["_ndec"] = ndec
        else:
            return out, [f"unmapped:displacement_unit:{raw}"]
    else:
        t = str(raw)
        m = _CC_RX.search(t)
        if m:
            kind, value = "cc", float(m.group(1).replace(",", ""))
        else:
            m = _L_RX.search(t)
            if m:
                kind, value = "l", m.group(1)
                out["_ndec"] = len(m.group(1).split(".")[1]) if "." in m.group(1) else 0
    if kind is None:
        return out, [f"unmapped:displacement:{raw}"]
    if kind == "cc":
        cc = int(round(float(value)))
        out["cc"] = cc
        out["nominal_l"] = float(Decimal(cc) / 1000)
        out["label"] = fmt_label_from_liters(Decimal(cc) / 1000)
    else:
        lv = Decimal(str(value))
        out["nominal_l"] = float(lv)
        if out.get("_ndec", 0) >= 3:
            cc = int((lv * 1000).to_integral_value(rounding=ROUND_HALF_UP))
            out["cc"] = cc
            out["label"] = fmt_label_from_liters(Decimal(cc) / 1000)
        else:
            out["label"] = fmt_label_from_liters(lv)
    out.pop("_ndec", None)
    return out, []


def norm_aspiration(*texts):
    t = " ".join(x for x in texts if x)
    r = _first(NORM["aspiration"]["rules"], t) if t else None
    return (r["value"] if r else None), []


def _unit_key(u):
    return str(u).strip().lower().replace(" ", "")


def norm_horsepower(raw):
    """raw {'value','unit','basis'} -> (hp float 1dp, flags)"""
    if raw is None:
        return None, []
    tbl = NORM["power"]["to_hp_mechanical"]
    k = _unit_key(raw.get("unit", ""))
    if k not in tbl or raw.get("value") is None:
        return None, [f"unmapped:power_unit:{raw.get('unit')}"]
    return round(float(raw["value"]) * tbl[k], NORM["power"]["decimals"]), []


def norm_torque(raw):
    if raw is None:
        return None, []
    tbl = NORM["torque"]["to_nm"]
    k = _unit_key(raw.get("unit", ""))
    if k not in tbl or raw.get("value") is None:
        return None, [f"unmapped:torque_unit:{raw.get('unit')}"]
    return round(float(raw["value"]) * tbl[k], NORM["torque"]["decimals"]), []


def trim_key(raw):
    if raw is None:
        return None
    s = collapse_ws(str(raw))
    if not s or s.casefold() in NORM["trim"]["placeholders_ignored"]:
        return None
    return collapse_ws(re.sub(r"[-_/]", " ", s.casefold()))


def trim_display(raw):
    if raw is None:
        return None
    s = collapse_ws(str(raw))
    if not s or s.casefold() in NORM["trim"]["placeholders_ignored"]:
        return None
    if s != s.upper() and s != s.lower():
        return s

    def sub(tok):
        letters = re.sub(r"[^A-Za-z]", "", tok)
        return tok.upper() if len(letters) <= 3 else tok.title()

    return " ".join("".join(sub(p) if not re.fullmatch(r"[-/]", p) else p for p in re.split(r"([-/])", w)) for w in s.split(" "))


_MARKET_REV = None


def _market_reverse():
    global _MARKET_REV
    if _MARKET_REV is None:
        rev = {}
        for code, names in NORM["market"]["aliases"].items():
            for n in names:
                rev[n.casefold()] = code
        _MARKET_REV = rev
    return _MARKET_REV


def norm_market(raw):
    if raw is None or str(raw).strip() == "":
        return None, []
    k = collapse_ws(str(raw)).casefold()
    code = _market_reverse().get(k)
    if code is None:
        return None, [f"unmapped:market:{raw}"]
    if code == "other:global":
        return None, []
    if code == "gcc_approximate":
        return "gcc", ["market_approximate"]
    return code, []


# ----------------------------------------------------------------------------------------
# traceability ("no AI memory"): each raw value must appear in the record's own quote
# ----------------------------------------------------------------------------------------


def _trace_norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", str(s))
    s = re.sub(r"[\u00ae\u2122\u00a9]", "", s)
    s = re.sub(r"[\-\u2010\u2011\u2012\u2013\u2014\u2212]", " ", s)
    s = s.casefold()
    return collapse_ws(s)


def _num_tokens(text: str) -> str:
    t = unicodedata.normalize("NFKC", text)
    return re.sub(r"(?<=\d),(?=\d{3}\b)", "", t)


def _num_in_text(value, text: str) -> bool:
    cands = {str(value)}
    if isinstance(value, float):
        cands.add(f"{value:g}")
        cands.add(f"{value:.1f}")
    cands = {c for c in cands if c}
    t = _num_tokens(text)
    for c in cands:
        if re.search(rf"(?<![\d.]){re.escape(c)}(?!\d|\.\d)", t):
            return True
    return False


def _str_in_text(raw, text: str) -> bool:
    return _trace_norm(raw) in _trace_norm(text)


def trace_check(rec: dict) -> list[str]:
    """Return list of untraceable fields (value not found in supporting_text)."""
    text = (rec.get("evidence") or {}).get("supporting_text") or ""
    bad = []

    def chk_str(label, raw):
        if raw not in (None, "") and not _str_in_text(raw, text):
            bad.append(f"{label}={raw!r}")

    def chk_num(label, v):
        if v is not None and not _num_in_text(v, text):
            bad.append(f"{label}={v!r}")

    for k in ("market", "trim", "body_type", "drivetrain", "generation"):
        if k == "market":
            continue  # markets are source-scope metadata, checked via notes/source registry
        chk_str(k, rec.get(k))
    s = rec.get("seats")
    if s is not None:
        if isinstance(s, int):
            if not (_num_in_text(s, text) or any(re.search(rf"\b{w}\b", _trace_norm(text)) for w, n in NORM["seats"]["number_words"].items() if n == s)):
                bad.append(f"seats={s!r}")
        else:
            chk_str("seats", s)
    d = rec.get("doors")
    if d is not None:
        if isinstance(d, int):
            chk_num("doors", d)
        else:
            chk_str("doors", d)
    eng = rec.get("engine") or {}
    disp = eng.get("displacement_raw")
    if isinstance(disp, dict):
        chk_num("engine.displacement_raw.value", disp.get("value"))
    else:
        chk_str("engine.displacement_raw", disp)
    cyl = eng.get("cylinders")
    if isinstance(cyl, int):
        chk_num("engine.cylinders", cyl)
    else:
        chk_str("engine.cylinders", cyl)
    chk_str("engine.fuel_type", eng.get("fuel_type"))
    chk_str("engine.aspiration", eng.get("aspiration"))
    chk_str("engine.display_name", eng.get("display_name"))
    for k in ("horsepower", "torque"):
        v = eng.get(k)
        if v is not None:
            chk_num(f"engine.{k}.value", v.get("value"))
    tr = rec.get("transmission") or {}
    chk_str("transmission.type", tr.get("type"))
    if tr.get("gears") is not None:
        chk_num("transmission.gears", tr["gears"])
    return bad


# ----------------------------------------------------------------------------------------
# evidence file: structure validation + preparation (expand + normalize + score)
# ----------------------------------------------------------------------------------------

RECORD_KEYS = [
    "record_id", "brand", "model", "generation", "year_from", "year_to", "market", "trim", "variant",
    "body_type", "doors", "seats", "engine", "transmission", "drivetrain", "evidence", "notes",
    "normalized", "normalization_flags",
]
ENGINE_KEYS = ["display_name", "displacement_raw", "displacement_cc", "cylinders", "fuel_type", "aspiration", "horsepower", "torque"]
TRANSMISSION_KEYS = ["type", "gears"]
EVIDENCE_KEYS = [
    "source_id", "source_url", "source_name", "source_type", "source_tier", "source_integrity", "accessed_at", "confidence",
    "confidence_basis", "supporting_text",
]
SOURCE_KEYS = ["url", "name", "publisher", "tier", "host_type", "retrieval", "accessed_at", "model_year_label", "market_scope", "integrity", "notes"]


# ----------------------------------------------------------------------------------------
# evidence integrity (source authority is NOT evidence integrity)
# ----------------------------------------------------------------------------------------
INTEGRITY_RULES = SRC["evidence_integrity"]
INTEGRITY_STATES = list(INTEGRITY_RULES["states"])
VERIFIED_ELIGIBLE_STATES = frozenset(INTEGRITY_RULES["verified_eligible_states"])
NOT_VERIFIED_STATES = frozenset(INTEGRITY_RULES["not_verified_states"])
INTEGRITY_KEYS = [
    "state", "retrieved_at", "content_sha256", "snapshot_path", "origin", "note",
    # optional fetch provenance (written by fetch_snapshot.py)
    "retrieved_by", "final_url", "http_status", "content_type", "raw_sha256", "extractor", "previous_state", "unconfirmed_record_ids",
]
INTEGRITY_ORIGINS = INTEGRITY_RULES["integrity_origin_values"]
QUOTE_SEGMENT_SEPARATOR = "\u2026"  # a supporting_text may join several verbatim passages of ONE source with " … "
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}Z)?$")  # ISO date, or UTC timestamp when the retrieval time was recorded
_UNSET = object()


def source_integrity_state(src: dict | None) -> str | None:
    integ = (src or {}).get("integrity")
    return integ.get("state") if isinstance(integ, dict) else None


def is_pdf_source(src: dict) -> bool:
    from urllib.parse import urlparse

    return src.get("retrieval") == "pdf_downloaded_and_parsed" or urlparse(src.get("url") or "").path.lower().endswith(".pdf")


def _sha256_file_bytes(raw: bytes) -> str:
    import hashlib

    return hashlib.sha256(raw).hexdigest()


def _ws(s) -> str:
    return " ".join(str(s).split())


def quote_segments(text: str) -> list[str]:
    return [_ws(seg) for seg in (text or "").split(QUOTE_SEGMENT_SEPARATOR) if seg.strip()]


def _snapshot_file(root: Path, snapshot_path: str) -> Path | None:
    """Resolve a snapshot path; it must stay inside <root>/evidence (no traversal, no absolute paths)."""
    p = (root / snapshot_path).resolve()
    base = (root / "evidence").resolve()
    return p if base in p.parents else None


def load_snapshots(doc: dict, root: Path = HERE) -> tuple[dict, list[str]]:
    """-> ({source_id: whitespace-normalised preserved text or None}, errors).

    Only sources that CLAIM a verifiable state are read. The preserved file must exist and match integrity.content_sha256.
    A live page is never consulted. A source with an unreadable / tampered snapshot gets None (and an error)."""
    texts: dict[str, str | None] = {}
    errs: list[str] = []
    for sid, s in doc.get("sources", {}).items():
        integ = s.get("integrity") if isinstance(s.get("integrity"), dict) else {}
        if integ.get("state") not in VERIFIED_ELIGIBLE_STATES:
            continue
        sp = integ.get("snapshot_path")
        f = _snapshot_file(root, sp) if isinstance(sp, str) and sp else None
        if f is None:
            errs.append(f"{sid}: snapshot_path {sp!r} is missing or outside evidence/")
            texts[sid] = None
        elif not f.exists():
            errs.append(f"{sid}: snapshot {sp} is missing")
            texts[sid] = None
        else:
            raw = f.read_bytes()
            if _sha256_file_bytes(raw) != integ.get("content_sha256"):
                errs.append(f"{sid}: snapshot {sp} hash does not match integrity.content_sha256 (preserved content was altered)")
                texts[sid] = None
            else:
                texts[sid] = _ws(raw.decode("utf-8", errors="replace"))
    return texts, errs


def assess_records(doc: dict, texts: dict | None) -> dict:
    """Per record: does it pass the integrity test that allows a tier 1-3 value to be VERIFIED?

    eligible = tier 1-3 AND source state in {FULL_TEXT_VERIFIED, PDF_VERIFIED} AND snapshot readable AND every quote
    segment found in the snapshot. `texts` = load_snapshots(...)[0] (or an in-memory dict in tests)."""
    texts = texts or {}
    out = {}
    for r in doc["records"]:
        ev = r.get("evidence") or {}
        sid = ev.get("source_id")
        src = doc["sources"].get(sid) or {}
        state = source_integrity_state(src)
        tier = src.get("tier")
        a = {"source_id": sid, "tier": tier, "state": state, "quote_validated": None, "eligible": False, "reason": None}
        if state not in VERIFIED_ELIGIBLE_STATES:
            a["reason"] = f"integrity:{state}"
        elif texts.get(sid) is None:
            a["quote_validated"], a["reason"] = False, "snapshot_unavailable"
        else:
            missing = [s for s in quote_segments(ev.get("supporting_text")) if s not in texts[sid]]
            a["quote_validated"] = not missing
            if missing:
                a["reason"] = "quote_not_in_snapshot"
            elif not isinstance(tier, int) or tier > 3:
                a["reason"] = "tier_above_3"
            else:
                a["eligible"] = True
        out[r["record_id"]] = a
    return out


def verify_snapshots(doc: dict, root: Path = HERE) -> tuple[list[str], dict, dict]:
    """-> (errors, texts, assessments). A doc that CLAIMS a verified state must be backed by its preserved snapshot."""
    texts, errs = load_snapshots(doc, root)
    assess = assess_records(doc, texts)
    # A record may be listed in integrity.unconfirmed_record_ids ONLY if its quote really is absent from the preserved
    # snapshot (changed page, review needed). It then never verifies; the listing must be exactly accurate.
    listed = {}
    for sid, s in doc.get("sources", {}).items():
        for rid in (s.get("integrity") or {}).get("unconfirmed_record_ids") or []:
            listed[rid] = sid
    known = {r["record_id"]: r for r in doc["records"]}
    for rid, sid in sorted(listed.items()):
        if rid not in known or known[rid]["evidence"]["source_id"] != sid:
            errs.append(f"{rid}: listed in unconfirmed_record_ids of {sid} but is not a record citing that source")
        elif assess[rid]["quote_validated"]:
            errs.append(f"{rid}: listed as unconfirmed but its quote IS found in the snapshot of {sid} (stale listing; re-run the revalidation)")
    for rid, a in assess.items():
        if a["reason"] == "quote_not_in_snapshot" and rid not in listed:
            for seg in quote_segments(known[rid]["evidence"]["supporting_text"]):
                if seg not in texts[a["source_id"]]:
                    errs.append(f"{rid}: quote segment not found in preserved snapshot of {a['source_id']}: {seg[:90]!r}")
    return errs, texts, assess


def integrity_counts(doc: dict) -> dict:
    """Records and sources per integrity state (every state listed, zeros included)."""
    rec = {s: 0 for s in INTEGRITY_STATES}
    srcs = {s: 0 for s in INTEGRITY_STATES}
    for s in doc["sources"].values():
        st = source_integrity_state(s)
        if st in srcs:
            srcs[st] += 1
    for r in doc["records"]:
        st = source_integrity_state(doc["sources"].get(r["evidence"]["source_id"]))
        if st in rec:
            rec[st] += 1
    return {"records": rec, "sources": srcs}


def migrate_integrity(doc: dict, snapshot_dir: Path, root: Path = HERE) -> tuple[dict, list[str]]:
    """Deterministically add `integrity` to sources that have none, from EXISTING metadata only (never overwrites).

    snippet retrieval                          -> SNIPPET_ONLY
    legacy `sha256` + matching cached text     -> FULL_TEXT_VERIFIED / PDF_VERIFIED (claim; verify_snapshots re-checks it)
    any other full-text / PDF retrieval record -> RETRIEVED_UNVERIFIABLE (no preserved content exists to prove it)
    Returns (doc, log lines)."""
    doc = copy.deepcopy(doc)
    log = []
    for sid, s in sorted(doc["sources"].items()):
        legacy_sha = s.pop("sha256", None)
        if isinstance(s.get("integrity"), dict):
            continue
        if s["retrieval"] == "search_snippet_only":
            integ = {
                "state": "SNIPPET_ONLY", "retrieved_at": s["accessed_at"], "content_sha256": None, "snapshot_path": None,
                "origin": "migration:snippet_retrieval",
                "note": "Evidence came from a search-result snippet; the underlying page/document was not retrieved or validated.",
            }
        else:
            cache = snapshot_dir / f"{sid}.txt"
            if legacy_sha and cache.exists() and _sha256_file_bytes(cache.read_bytes()) == legacy_sha:
                integ = {
                    "state": "PDF_VERIFIED" if is_pdf_source(s) else "FULL_TEXT_VERIFIED", "retrieved_at": s["accessed_at"],
                    "content_sha256": legacy_sha, "snapshot_path": cache.resolve().relative_to(root.resolve()).as_posix(),
                    "origin": "migration:cached_snapshot", "note": None,
                }
            else:
                integ = {
                    "state": "RETRIEVED_UNVERIFIABLE", "retrieved_at": s["accessed_at"], "content_sha256": None, "snapshot_path": None,
                    "origin": "migration:legacy_no_snapshot",
                    "note": f"Retrieval was recorded as {s['retrieval']} but no snapshot/hash was preserved, so the quotes cannot be re-validated against retrieved content.",
                }
        s["integrity"] = integ
        log.append(f"{sid}: {integ['state']}")
    doc["sources"] = {k: _order_source(v) for k, v in doc["sources"].items()}
    return doc, log


def _order_source(s: dict) -> dict:
    out = {k: s[k] for k in SOURCE_KEYS if k in s}
    if isinstance(out.get("integrity"), dict):
        out["integrity"] = {k: out["integrity"].get(k) for k in INTEGRITY_KEYS if k in out["integrity"]}
    for k in s:
        if k not in out:
            out[k] = s[k]
    return out


def validate_source_integrity(sid: str, s: dict) -> list[str]:
    errs = []
    integ = s.get("integrity")
    if not isinstance(integ, dict):
        return [f"source {sid}: integrity block is required (run the integrity migration or author it)"]
    for k in integ:
        if k not in INTEGRITY_KEYS:
            errs.append(f"source {sid}: unknown integrity key {k}")
    st = integ.get("state")
    if st not in INTEGRITY_STATES:
        return errs + [f"source {sid}: integrity.state must be one of {INTEGRITY_STATES}"]
    if integ.get("origin") not in INTEGRITY_ORIGINS:
        errs.append(f"source {sid}: integrity.origin must be one of {INTEGRITY_ORIGINS}")
    if not (isinstance(integ.get("retrieved_at"), str) and _DATE_RE.match(integ["retrieved_at"])):
        errs.append(f"source {sid}: integrity.retrieved_at must be an ISO date or UTC timestamp")
    unconf = integ.get("unconfirmed_record_ids")
    if unconf is not None:
        if st not in VERIFIED_ELIGIBLE_STATES:
            errs.append(f"source {sid}: unconfirmed_record_ids only applies to a verified state")
        elif not (isinstance(unconf, list) and all(isinstance(x, str) for x in unconf) and unconf == sorted(set(unconf))):
            errs.append(f"source {sid}: unconfirmed_record_ids must be a sorted list of unique record ids")
    sha, sp = integ.get("content_sha256"), integ.get("snapshot_path")
    if st in VERIFIED_ELIGIBLE_STATES:
        if s.get("retrieval") == "search_snippet_only":
            errs.append(f"source {sid}: {st} is impossible for retrieval=search_snippet_only")
        if not (isinstance(sha, str) and _SHA256_RE.match(sha)):
            errs.append(f"source {sid}: {st} requires integrity.content_sha256 (64 hex chars)")
        if not (isinstance(sp, str) and sp.startswith("evidence/")):
            errs.append(f"source {sid}: {st} requires integrity.snapshot_path under evidence/")
        if st == "PDF_VERIFIED" and not is_pdf_source(s):
            errs.append(f"source {sid}: PDF_VERIFIED requires a PDF source (retrieval pdf_downloaded_and_parsed or a .pdf URL)")
    else:
        if sha is not None or sp is not None:
            errs.append(f"source {sid}: {st} must not carry content_sha256 / snapshot_path (no preserved content is claimed)")
        if s.get("retrieval") == "search_snippet_only" and st not in ("SNIPPET_ONLY", "UNAVAILABLE"):
            errs.append(f"source {sid}: retrieval=search_snippet_only can only be SNIPPET_ONLY or UNAVAILABLE")
    return errs


PROPOSAL_RULES = INTEGRITY_RULES["proposals"]
PROPOSAL_INTEGRITY_VERSION = PROPOSAL_RULES["current_integrity_version"]
PROPOSALS = HERE / "proposals"


class ProposalNotActionable(Exception):
    """Raised when something tries to treat a stale / legacy / unverified proposal as actionable."""


def proposal_problems(doc: dict) -> list[str]:
    """Why `doc` (a proposals/*.json patch set) is NOT actionable. Empty list = actionable.

    Actionable only if: proposal_status present, state=current, actionable=true, evidence_integrity_version is the
    current rules version, applied=false (a proposal file is never the applied record) and every cited source has an
    integrity state that is verified-eligible."""
    ps = doc.get("proposal_status")
    if not isinstance(ps, dict):
        return ["proposal has no proposal_status (legacy proposal: treated as stale / non-actionable)"]
    out = []
    if ps.get("state") != "current":
        out.append(f"proposal_status.state is {ps.get('state')!r}, not 'current'")
    if ps.get("actionable") is not True:
        out.append("proposal_status.actionable is not true")
    if ps.get("evidence_integrity_version") != PROPOSAL_INTEGRITY_VERSION:
        out.append(f"proposal_status.evidence_integrity_version is {ps.get('evidence_integrity_version')!r}, current rules version is {PROPOSAL_INTEGRITY_VERSION}")
    if doc.get("applied") is not False:
        out.append("applied must be false in a proposal file")
    for key, src in sorted((doc.get("sources") or {}).items()):
        st = (src.get("integrity") or {}).get("state") if isinstance(src, dict) else None
        if st not in VERIFIED_ELIGIBLE_STATES:
            out.append(f"source {key}: integrity state {st!r} is not FULL_TEXT_VERIFIED / PDF_VERIFIED")
    return out


def validate_proposal(doc: dict) -> list[str]:
    """Consistency errors of the proposal's own status declaration (a stale proposal that is correctly declared is valid)."""
    ps = doc.get("proposal_status")
    if not isinstance(ps, dict):
        return ["proposal_status is required: mark a legacy proposal state=stale / actionable=false, or regenerate it"]
    errs = []
    if ps.get("state") not in ("current", "stale"):
        errs.append("proposal_status.state must be 'current' or 'stale'")
    if not isinstance(ps.get("actionable"), bool):
        errs.append("proposal_status.actionable must be a boolean")
    if doc.get("applied") is not False:
        errs.append("applied must be false in a proposal file")
    if ps.get("state") == "stale":
        if ps.get("actionable") is not False:
            errs.append("a stale proposal must have actionable=false")
        if not (isinstance(ps.get("stale_reason"), str) and ps["stale_reason"].strip()):
            errs.append("a stale proposal must give proposal_status.stale_reason")
    if ps.get("actionable") is True:
        errs += [f"claims actionable=true but is not actionable: {p}" for p in proposal_problems(doc)]
    return errs


def assert_proposal_actionable(doc: dict) -> None:
    """Gate for any future apply step. Raises ProposalNotActionable with every reason; never returns for stale proposals."""
    problems = proposal_problems(doc)
    if problems:
        raise ProposalNotActionable("; ".join(problems))


def confidence_for(source: dict, rec: dict):
    adj = SRC["confidence_adjustments"]
    tier = str(source["tier"])
    base = SRC["tiers"][tier]["base_confidence"]
    basis = [f"tier{tier}_base:{base}"]
    score = base
    r = adj["retrieval"].get(source["retrieval"], 0.0)
    if r:
        basis.append(f"retrieval:{source['retrieval']}:{r:+}")
        score += r
    h = adj["host_type"].get(source["host_type"], 0.0)
    if h:
        basis.append(f"host_type:{source['host_type']}:{h:+}")
        score += h
    if rec.get("year_from") is None and rec.get("year_to") is None:
        a = adj["no_model_year_stated"]
        basis.append(f"no_model_year_stated:{a:+}")
        score += a
    score = max(adj["floor"], min(adj["ceiling"], score))
    return round(score, 2), basis


def normalize_record(rec: dict) -> tuple[dict, list[str]]:
    flags: list[str] = []
    eng = rec.get("engine") or {}
    tr = rec.get("transmission") or {}
    disp, f = norm_displacement(eng.get("displacement_raw"))
    flags += f
    cyl, f = norm_cylinders(eng.get("cylinders"))
    flags += f
    fuel, f = norm_fuel(eng.get("fuel_type"))
    flags += f
    asp, f = norm_aspiration(eng.get("aspiration"))
    flags += f
    hp, f = norm_horsepower(eng.get("horsepower"))
    flags += f
    nm, f = norm_torque(eng.get("torque"))
    flags += f
    t, f = norm_transmission(tr.get("type"), tr.get("gears"))
    flags += f
    dt, f = norm_drivetrain(rec.get("drivetrain"))
    flags += f
    body, f = norm_body(rec.get("body_type"))
    flags += f
    seats, f = norm_seats(rec.get("seats"))
    flags += f
    doors, f = norm_doors(rec.get("doors"))
    flags += f
    market, f = norm_market(rec.get("market"))
    flags += f
    engine_present = any(
        v is not None for v in (eng.get("display_name"), eng.get("displacement_raw"), eng.get("cylinders"), eng.get("fuel_type"), eng.get("horsepower"), eng.get("torque"))
    )
    if disp["label"]:
        group = disp["label"]
    elif engine_present:
        group = "unlabeled_engine"
    else:
        group = "model_level"
    norm = {
        "market": market,
        "trim": trim_display(rec.get("trim")),
        "trim_key": trim_key(rec.get("trim")),
        "body_type": body,
        "doors": doors,
        "seats": seats,
        "seats_is_maximum": "seats_is_maximum" in flags,
        "engine_group": group,
        "engine_size_label": disp["label"],
        "displacement_cc": disp["cc"],
        "displacement_nominal_l": disp["nominal_l"],
        "cylinders": cyl,
        "fuel_type": fuel,
        "aspiration": asp,
        "horsepower_hp": hp,
        "torque_nm": nm,
        "transmission_family": t["family"],
        "transmission_variant": t["variant"],
        "transmission_named_systems": t["named_systems"],
        "transmission_gears": t["gears"],
        "drivetrain": dt,
    }
    return norm, flags


def _order(d: dict, keys: list[str]) -> dict:
    out = {k: d[k] for k in keys if k in d}
    for k in d:
        if k not in out:
            out[k] = d[k]
    return out


def prepare_evidence(doc: dict) -> dict:
    """Idempotent: expands source info, scores confidence, normalizes. Authored fields are untouched."""
    doc = copy.deepcopy(doc)
    sources = doc.get("sources", {})
    out_records = []
    for rec in doc.get("records", []):
        r = copy.deepcopy(rec)
        r.setdefault("brand", doc.get("brand"))
        r.setdefault("model", doc.get("model"))
        for k in ("generation", "year_from", "year_to", "market", "trim", "variant", "body_type", "doors", "seats", "drivetrain", "notes"):
            r.setdefault(k, None)
        eng = r.get("engine") or {}
        r["engine"] = _order({k: eng.get(k) for k in ENGINE_KEYS if k != "displacement_cc"}, ENGINE_KEYS)
        tr = r.get("transmission") or {}
        r["transmission"] = {k: tr.get(k) for k in TRANSMISSION_KEYS}
        ev = r.get("evidence") or {}
        sid = ev.get("source_id")
        src = sources.get(sid)
        newev = {"source_id": sid}
        if src:
            newev.update(
                source_url=src.get("url"),
                source_name=src.get("name"),
                source_type=SRC["tiers"][str(src["tier"])]["source_type"],
                source_tier=src["tier"],
                source_integrity=source_integrity_state(src),
                accessed_at=src.get("accessed_at"),
            )
            score, basis = confidence_for(src, r)
            newev["confidence"] = score
            newev["confidence_basis"] = basis
        newev["supporting_text"] = ev.get("supporting_text")
        r["evidence"] = newev
        norm, flags = normalize_record(r)
        r["engine"]["displacement_cc"] = norm["displacement_cc"]
        r["engine"] = _order(r["engine"], ENGINE_KEYS)
        r["normalized"] = norm
        r["normalization_flags"] = flags
        out_records.append(_order(r, RECORD_KEYS))
    doc["schema_version"] = SCHEMA_EVIDENCE
    doc["records"] = out_records
    return doc


def validate_evidence(doc: dict, models=None) -> list[str]:
    errs: list[str] = []
    if doc.get("schema_version") != SCHEMA_EVIDENCE:
        errs.append(f"schema_version must be {SCHEMA_EVIDENCE}")
    for k in ("brand", "model", "researched_at", "sources", "records"):
        if k not in doc:
            errs.append(f"missing top-level key {k}")
    if errs:
        return errs
    sources = doc["sources"]
    for sid, s in sources.items():
        for k in ("url", "name", "tier", "host_type", "retrieval", "accessed_at"):
            if s.get(k) in (None, ""):
                errs.append(f"source {sid}: missing {k}")
        for k in s:
            if k not in SOURCE_KEYS:
                errs.append(f"source {sid}: unknown key {k}")
        if s.get("tier") not in (1, 2, 3, 4, 5):
            errs.append(f"source {sid}: tier must be 1..5")
        if s.get("host_type") not in SRC["host_types"]:
            errs.append(f"source {sid}: bad host_type {s.get('host_type')}")
        if s.get("retrieval") not in SRC["retrieval_methods"]:
            errs.append(f"source {sid}: bad retrieval {s.get('retrieval')}")
        errs += validate_source_integrity(sid, s)
    seen = set()
    for i, r in enumerate(doc["records"]):
        rid = r.get("record_id") or f"#{i}"
        if rid in seen:
            errs.append(f"{rid}: duplicate record_id")
        seen.add(rid)
        for k in r:
            if k not in RECORD_KEYS:
                errs.append(f"{rid}: unknown key {k}")
        for k in (r.get("engine") or {}):
            if k not in ENGINE_KEYS:
                errs.append(f"{rid}: unknown engine key {k}")
        for k in (r.get("transmission") or {}):
            if k not in TRANSMISSION_KEYS:
                errs.append(f"{rid}: unknown transmission key {k}")
        ev = r.get("evidence") or {}
        for k in ev:
            if k not in EVIDENCE_KEYS:
                errs.append(f"{rid}: unknown evidence key {k}")
        if ev.get("source_id") not in sources:
            errs.append(f"{rid}: unknown source_id {ev.get('source_id')}")
        if not (ev.get("supporting_text") or "").strip():
            errs.append(f"{rid}: supporting_text required")
        if (r.get("brand"), r.get("model")) != (doc["brand"], doc["model"]):
            errs.append(f"{rid}: brand/model differ from file header")
        yf, yt = r.get("year_from"), r.get("year_to")
        for nm, y in (("year_from", yf), ("year_to", yt)):
            if y is not None and not (isinstance(y, int) and 1900 <= y <= 2100):
                errs.append(f"{rid}: {nm} must be a 4-digit int or null")
        if yf is not None and yt is not None and yf > yt:
            errs.append(f"{rid}: year_from > year_to")
        for k in ("horsepower", "torque"):
            v = (r.get("engine") or {}).get(k)
            if v is not None and (not isinstance(v, dict) or "value" not in v or "unit" not in v):
                errs.append(f"{rid}: engine.{k} must be {{value, unit}}")
        for bad in trace_check(r):
            errs.append(f"{rid}: value not found in supporting_text -> {bad}")
        norm, flags = normalize_record(r)
        for fl in flags:
            if fl.startswith("unmapped:"):
                errs.append(f"{rid}: {fl}")
    if models is not None:
        canon = models.canonical_model(doc["brand"], doc["model"])
        if canon != doc["model"]:
            errs.append(f"model identity: {doc['brand']} / {doc['model']} is not a canonical catalog model (resolved to {canon!r})")
        for r in doc["records"]:
            rc = models.canonical_model(r.get("brand") or "", r.get("model") or "")
            if rc != canon:
                errs.append(f"{r.get('record_id')}: record model {r.get('model')!r} resolves to {rc!r}, not {canon!r}")
    return errs


def boundary_warnings(doc: dict, models) -> list[str]:
    """A record bound to model M whose quoted text/notes mention a LONGER sibling model of the same brand
    (e.g. 'Land Cruiser Prado' inside a Land Cruiser record) may describe the wrong vehicle. Warning, not error:
    a comparison sentence legitimately may name a sibling. Review these."""
    import model_boundaries as mb

    out = []
    brand, model = doc["brand"], doc["model"]
    mk = mb.mkey(model)
    siblings = [c for (b, a, c) in models.prefix_pairs() if b == brand and mb.mkey(a) == mk]
    for r in doc["records"]:
        hay = mb.mkey(" ".join(str(x or "") for x in ((r.get("evidence") or {}).get("supporting_text"), r.get("notes"), (r.get("engine") or {}).get("display_name"), r.get("trim"), r.get("variant"))))
        for s in siblings:
            if re.search(rf"(?<![a-z0-9]){re.escape(mb.mkey(s))}(?![a-z0-9])", hay):
                out.append(f"{r['record_id']}: text mentions sibling model {s!r}")
    return out


# ----------------------------------------------------------------------------------------
# evidence manifest: proof that no evidence record is ever silently lost or edited
# ----------------------------------------------------------------------------------------
_DERIVED_EVIDENCE_KEYS = {"source_url", "source_name", "source_type", "source_tier", "source_integrity", "accessed_at", "confidence", "confidence_basis"}


def authored_fingerprint(rec: dict) -> str:
    import hashlib

    r = copy.deepcopy(rec)
    r.pop("normalized", None)
    r.pop("normalization_flags", None)
    (r.get("engine") or {}).pop("displacement_cc", None)
    for k in _DERIVED_EVIDENCE_KEYS:
        (r.get("evidence") or {}).pop(k, None)
    return hashlib.sha256(json.dumps(r, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()[:16]


def evidence_manifest(doc: dict) -> dict:
    return {"record_count": len(doc["records"]), "records": {r["record_id"]: authored_fingerprint(r) for r in doc["records"]}}


def check_manifest(doc: dict, manifest: dict | None) -> tuple[list[str], list[str]]:
    """-> (errors, notices). Errors: a previously recorded record_id vanished. Notices: authored content changed or new ids."""
    if not manifest:
        return [], ["no manifest recorded yet"]
    cur = evidence_manifest(doc)["records"]
    errs = [f"record {rid} is in the manifest but missing from the evidence file" for rid in manifest["records"] if rid not in cur]
    notes = [f"record {rid} authored content changed since the manifest (accept with: run_pilot.py manifest)" for rid, h in manifest["records"].items() if rid in cur and cur[rid] != h]
    notes += [f"record {rid} is new since the manifest" for rid in cur if rid not in manifest["records"]]
    return errs, notes


# ----------------------------------------------------------------------------------------
# conflict detection
# ----------------------------------------------------------------------------------------

CONFLICT_FIELDS = [
    "displacement_cc", "cylinders", "fuel_type", "horsepower_hp", "torque_nm",
    "transmission_family", "transmission_variant", "transmission_gears", "drivetrain", "body_type", "seats", "doors",
]
TOL = {"horsepower_hp": NORM["power"]["conflict_tolerance_hp"], "torque_nm": NORM["torque"]["conflict_tolerance_nm"]}


HYBRID_FUELS = {"Hybrid", "Plug-in Hybrid"}


def _year_range(r):
    yf, yt = r.get("year_from"), r.get("year_to")
    if yf is None and yt is None:
        return None
    return (yf if yf is not None else yt, yt if yt is not None else yf)


def _market_compat(a, b):
    if a is None or b is None or a == b:
        return True
    return False


def _opt_equal(a, b):
    return a is None or b is None or a == b


def compatible(a: dict, b: dict) -> tuple[bool, str]:
    """-> (same configuration?, severity)"""
    na, nb = a["normalized"], b["normalized"]
    if na["engine_group"] != nb["engine_group"] or na["engine_group"] == "unlabeled_engine":
        return False, ""
    if not _market_compat(na["market"], nb["market"]):
        return False, ""
    fa, fb = na["fuel_type"], nb["fuel_type"]
    if fa and fb and ((fa in HYBRID_FUELS) != (fb in HYBRID_FUELS)):
        return False, ""  # hybrid and non-hybrid powertrains of one engine size are different configurations
    if not _opt_equal(na["trim_key"], nb["trim_key"]):
        return False, ""
    if not _opt_equal(a.get("variant"), b.get("variant")):
        return False, ""
    ya, yb = _year_range(a), _year_range(b)
    if ya and yb:
        if ya[1] < yb[0] or yb[1] < ya[0]:
            return False, ""
        return True, "definite"
    return True, "possible_year_unspecified"


def _differs(field, x, y):
    if x is None or y is None:
        return False
    if field in TOL:
        return abs(x - y) > TOL[field]
    if field == "transmission_variant":
        # a source's own marketing name (SelectShift, Direct Shift, ...) can sit on top of any canonical variant,
        # so only two CANONICAL variants can contradict each other
        canon = NORM["transmission"]["canonical_variant"]
        return x in canon and y in canon and x != y
    return x != y


def detect_conflicts(records: list[dict], model_slug: str) -> list[dict]:
    n = len(records)
    pairs = {}  # field -> list of (i, j, severity)
    for i in range(n):
        for j in range(i + 1, n):
            ok, sev = compatible(records[i], records[j])
            if not ok:
                continue
            for f in CONFLICT_FIELDS:
                if f == "seats" and (records[i]["normalized"]["seats_is_maximum"] or records[j]["normalized"]["seats_is_maximum"]):
                    continue
                if _differs(f, records[i]["normalized"][f], records[j]["normalized"][f]):
                    pairs.setdefault((f, records[i]["normalized"]["engine_group"]), []).append((i, j, sev))
    conflicts = []
    for (field, group), plist in pairs.items():
        parent = {}

        def find(x):
            parent.setdefault(x, x)
            while parent[x] != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        for i, j, _ in plist:
            parent[find(i)] = find(j)
        clusters = {}
        for i, j, sev in plist:
            c = find(i)
            clusters.setdefault(c, {"members": set(), "sev": set()})
            clusters[c]["members"].update([i, j])
            clusters[c]["sev"].add(sev)
        for c in clusters.values():
            members = sorted(c["members"], key=lambda k: records[k]["record_id"])
            vals = []
            for k in members:
                r = records[k]
                vals.append(
                    {
                        "record_id": r["record_id"],
                        "value": r["normalized"][field],
                        "source_id": r["evidence"]["source_id"],
                        "source_tier": r["evidence"]["source_tier"],
                        "market": r["normalized"]["market"],
                        "trim": r["normalized"]["trim"],
                        "year_from": r.get("year_from"),
                        "year_to": r.get("year_to"),
                    }
                )
            conflicts.append(
                {
                    "field": field,
                    "engine_group": group,
                    "severity": "definite" if c["sev"] == {"definite"} else "possible_year_unspecified",
                    "values": vals,
                    "resolution": "UNRESOLVED (both records preserved; reviewer decides)",
                }
            )
    conflicts.sort(key=lambda c: (c["field"], c["engine_group"], c["values"][0]["record_id"]))
    for n_, c in enumerate(conflicts, 1):
        c["conflict_id"] = f"CF-{model_slug}-{n_:03d}"
    return [_order(c, ["conflict_id", "field", "engine_group", "severity", "values", "resolution"]) for c in conflicts]


# ----------------------------------------------------------------------------------------
# union
# ----------------------------------------------------------------------------------------


def _sort_key(v):
    if isinstance(v, (int, float)):
        return (0, v, "")
    m = re.match(r"^(\d+(?:\.\d+)?)L$", str(v))
    if m:
        return (0, float(m.group(1)), "")
    return (1, 0, str(v).casefold())


def build_union(doc: dict, conflicts: list[dict], evidence_file: str | None = None, texts=_UNSET, root: Path = HERE) -> dict:
    """texts: {source_id: preserved snapshot text} used to validate quotes. Default: read the preserved snapshots named by
    each source's integrity block (under `root`). Passing {} (or no readable snapshot) means nothing can be VERIFIED."""
    recs = doc["records"]
    if texts is _UNSET:
        texts = load_snapshots(doc, root)[0]
    assess = assess_records(doc, texts)
    contested = set()  # (record_id, field): any conflict at all
    conflicted = set()  # (record_id, field): demotes the record (see verification_policy)
    for c in conflicts:
        for v in c["values"]:
            contested.add((v["record_id"], c["field"]))
            if v["source_tier"] <= 3:
                # demoted only if a DIFFERENT value is also asserted by another tier 1-3 record
                if any(o["source_tier"] <= 3 and o is not v and _differs(c["field"], v["value"], o["value"]) for o in c["values"]):
                    conflicted.add((v["record_id"], c["field"]))
            else:
                conflicted.add((v["record_id"], c["field"]))
    # fields whose conflicts can demote a union value. An engine size EXISTS even when its power figures
    # are disputed, so engine_sizes (and trims) are never demoted by spec conflicts.
    dim_conf_fields = {d: DIM_CONFLICT_FIELDS[d] for d in DIMENSIONS}
    dim_conf_fields["engine_sizes"] = []

    details = {}
    union_verified, union_prov, union_nsr = {}, {}, {}
    for dim in DIMENSIONS:
        field = DIM_FIELD[dim]
        bucket = {}
        for r in recs:
            val = r["normalized"].get(field)
            if val is None:
                continue
            b = bucket.setdefault(val, {"records": [], "display": r["normalized"]["trim"] if dim == "trims" else val})
            b["records"].append(r)
        rows = []
        for val, b in bucket.items():
            rs = b["records"]
            fields = dim_conf_fields[dim]
            not_conflicted = [r for r in rs if not any((r["record_id"], f) in conflicted for f in fields)]
            # VERIFIED needs authority (tier 1-3) AND integrity (preserved snapshot of the source, quote found in it)
            strong = [r for r in not_conflicted if assess[r["record_id"]]["eligible"]]
            # tier 1-3 support that fails the integrity test: useful, but the source content was never validated
            authoritative = [r for r in not_conflicted if r["evidence"]["source_tier"] <= 3]
            status = "VERIFIED" if strong else ("NEEDS_SOURCE_RETRIEVAL" if authoritative else "PROVISIONAL")
            years = [y for r in rs for y in (r.get("year_from"), r.get("year_to")) if y is not None]
            rows.append(
                {
                    "value": b["display"],
                    "status": status,
                    "integrity_states": sorted({assess[r["record_id"]]["state"] or "MISSING" for r in rs}),
                    "validated_record_ids": sorted(r["record_id"] for r in rs if assess[r["record_id"]]["quote_validated"]),
                    "best_tier": min(r["evidence"]["source_tier"] for r in rs),
                    "max_confidence": max(r["evidence"]["confidence"] for r in rs),
                    "support_count": len(rs),
                    "record_ids": sorted(r["record_id"] for r in rs),
                    "source_ids": sorted({r["evidence"]["source_id"] for r in rs}),
                    "markets": sorted({r["normalized"]["market"] for r in rs if r["normalized"]["market"]}),
                    "years": [min(years), max(years)] if years else None,
                    "in_conflict": any((r["record_id"], f) in contested for r in rs for f in DIM_CONFLICT_FIELDS[dim]),
                    "_sort": _sort_key(val if dim != "trims" else b["display"]),
                    "_key": val,
                }
            )
        rows.sort(key=lambda x: x["_sort"])
        details[dim] = [{k: v for k, v in x.items() if not k.startswith("_")} for x in rows]
        union_verified[dim] = [x["value"] for x in rows if x["status"] == "VERIFIED"]
        union_prov[dim] = [x["value"] for x in rows if x["status"] == "PROVISIONAL"]
        union_nsr[dim] = [x["value"] for x in rows if x["status"] == "NEEDS_SOURCE_RETRIEVAL"]

    # per-engine detail
    engines = {}
    for r in recs:
        n = r["normalized"]
        if n["engine_group"] in ("model_level", "unlabeled_engine"):
            continue
        e = engines.setdefault(
            n["engine_group"],
            {"engine_size_label": n["engine_group"], "displacement_cc": set(), "cylinders": set(), "fuel_types": set(), "aspirations": set(),
             "power_hp": [], "torque_nm": [], "record_ids": [], "best_tier": 9},
        )
        if n["displacement_cc"]:
            e["displacement_cc"].add(n["displacement_cc"])
        if n["cylinders"]:
            e["cylinders"].add(n["cylinders"])
        if n["fuel_type"]:
            e["fuel_types"].add(n["fuel_type"])
        if n["aspiration"]:
            e["aspirations"].add(n["aspiration"])
        if n["horsepower_hp"] is not None:
            e["power_hp"].append({"value": n["horsepower_hp"], "record_id": r["record_id"], "trim": n["trim"]})
        if n["torque_nm"] is not None:
            e["torque_nm"].append({"value": n["torque_nm"], "record_id": r["record_id"], "trim": n["trim"]})
        e["record_ids"].append(r["record_id"])
        e["best_tier"] = min(e["best_tier"], r["evidence"]["source_tier"])
    engine_list = []
    for lab in sorted(engines, key=_sort_key):
        e = engines[lab]
        engine_list.append(
            {
                "engine_size_label": lab,
                "displacement_cc": sorted(e["displacement_cc"]),
                "cylinders": sorted(e["cylinders"]),
                "fuel_types": sorted(e["fuel_types"]),
                "aspirations": sorted(e["aspirations"]),
                "power_hp": sorted(e["power_hp"], key=lambda x: (x["value"], x["record_id"])),
                "torque_nm": sorted(e["torque_nm"], key=lambda x: (x["value"], x["record_id"])),
                "best_tier": e["best_tier"],
                "record_ids": sorted(e["record_ids"]),
            }
        )
    tiers = {}
    for r in recs:
        tiers[str(r["evidence"]["source_tier"])] = tiers.get(str(r["evidence"]["source_tier"]), 0) + 1
    used_sources = sorted({r["evidence"]["source_id"] for r in recs})
    return {
        "schema_version": SCHEMA_UNION,
        "brand": doc["brand"],
        "model": doc["model"],
        "generated_from": {
            "evidence_file": evidence_file or f"evidence/{slug(doc['brand'])}_{slug(doc['model'])}.json",
            "researched_at": doc["researched_at"],
            "record_count": len(recs),
            "source_count": len(used_sources),
            "records_by_source_tier": dict(sorted(tiers.items())),
            "records_by_integrity_state": integrity_counts(doc)["records"],
            "sources_by_integrity_state": integrity_counts(doc)["sources"],
            "records_passing_integrity_test": sum(1 for a in assess.values() if a["eligible"]),
        },
        "research_coverage": doc.get("coverage", []),
        "vocabulary_version": NORM["locked_vocabulary"]["version"],
        "production_policy": {
            "production_bound_section": "verified",
            "verified_requires": "tier 1-3 AND source integrity FULL_TEXT_VERIFIED or PDF_VERIFIED AND quote found in the preserved snapshot AND no unresolved tier 1-3 conflict",
            "includes_provisional": False,
            "includes_needs_source_retrieval": False,
            "provisional_values_live_in": "provisional_only (research output only; never auto-promoted)",
            "needs_source_retrieval_values_live_in": "needs_source_retrieval (tier 1-3 evidence whose source content was never validated; never auto-promoted)",
            "unresolved_conflicts": len(conflicts),
            "conflicts_block_promotion_until_reviewed": bool(conflicts),
            "review_status": "UNREVIEWED",
        },
        "verified": union_verified,
        "union": copy.deepcopy(union_verified),  # legacy alias of 'verified' (identical content), kept for existing consumers
        "provisional_only": union_prov,
        "needs_source_retrieval": union_nsr,
        "empty_dimensions": [d for d in DIMENSIONS if not union_verified[d] and not union_prov[d] and not union_nsr[d]],
        "engines": engine_list,
        "details": details,
        "conflicts": conflicts,
    }


# ----------------------------------------------------------------------------------------
# current CarNet (READ-ONLY) + comparison
# ----------------------------------------------------------------------------------------


def load_current_carnet():
    sys.path.insert(0, str(HERE))
    import catalog_audit_readonly as audit  # read-only helper, only reads assets/

    import model_boundaries as mb

    cat, ds = audit.load()
    return {"audit": audit, "cat": cat, "idx": audit.build_index(ds), "models": mb.ModelIndex(cat)}


def current_carnet(ctx, brand: str, model: str) -> dict:
    """CarNet's current values for ONE canonical model. Dataset rows are assigned by the deterministic resolver in
    model_boundaries.py (longest canonical model wins; ambiguous qualifiers are quarantined), NOT by the app's
    prefix heuristic, so 'Land Cruiser Prado ...' rows can never count as 'Land Cruiser'."""
    audit = ctx["audit"]
    cat = ctx["cat"]
    mi = ctx["models"]
    canon = mi.canonical_model(brand, model)
    if canon is None:
        raise ValueError(f"{brand} / {model} is not a canonical catalog model; add it to the catalog or an alias first")
    bid, legacy_rows = audit.family_rows(ctx["idx"], brand, model)
    rows, excluded = mi.split_dataset_rows(brand, canon, legacy_rows)
    boundary = {
        "algorithm": "model_boundaries.py (rules/model_boundaries.json)",
        "legacy_family_rows": len(legacy_rows),
        "strict_rows": len(rows),
        "excluded_rows": sum(len(v) for v in excluded.values()),
        "excluded_by_reason": {k: len(v) for k, v in sorted(excluded.items())},
        "excluded_examples": {k: sorted({x["name"] for x in v})[:4] for k, v in sorted(excluded.items())},
        "accepted_by_status": dict(sorted(Counter(r["_boundary"]["status"] for r in rows).items())),
        "accepted_with_flags": sorted({f"{r['name']} :: {f}" for r in rows for f in r["_boundary"]["flags"]})[:10],
    }

    dims = {d: {} for d in DIMENSIONS}

    def add(dim, key, display, row):
        e = dims[dim].setdefault(key, {"value": display, "dataset_rows": 0, "raw_values": set()})
        e["dataset_rows"] += 1

    for t in (cat["trimsByBrandModel"].get(brand) or {}).get(model) or []:
        k = trim_key(t)
        if k:
            add("trims", k, trim_display(t) or t, None)
    for r in rows:
        if r["liters_resolved"] is not None:
            lab = fmt_label_from_liters(r["liters_resolved"])
            add("engine_sizes", lab, lab, r)
        if r["cylinders"] is not None:
            add("cylinders", r["cylinders"], r["cylinders"], r)
        v, _ = norm_fuel(r["fuel_type"])
        if r["fuel_type"]:
            add("fuel_types", v or f"?{r['fuel_type']}", v or f"?{r['fuel_type']}", r)
            if v:
                dims["fuel_types"][v]["raw_values"].add(r["fuel_type"])
        t, _ = norm_transmission(r["transmission"])
        if r["transmission"]:
            add("transmissions", t["family"] or f"?{r['transmission']}", t["family"] or f"?{r['transmission']}", r)
        d, _ = norm_drivetrain(r["drivetrain"])
        if r["drivetrain"]:
            add("drivetrains", d or f"?{r['drivetrain']}", d or f"?{r['drivetrain']}", r)
            if d:
                dims["drivetrains"][d]["raw_values"].add(r["drivetrain"])
        b, _ = norm_body(r["body_type"])
        if r["body_type"]:
            add("body_types", b or f"?{r['body_type']}", b or f"?{r['body_type']}", r)
        s, _ = norm_seats(r["seats"])
        if s is not None:
            add("seats", s, s, r)
    out_dims = {}
    for d, m in dims.items():
        items = []
        for k, e in m.items():
            items.append(
                {
                    "key": k,
                    "value": e["value"],
                    "dataset_rows": e["dataset_rows"],
                    "raw_values": sorted(e["raw_values"]),
                }
            )
        items.sort(key=lambda x: _sort_key(x["value"]))
        out_dims[d] = items
    return {
        "brand": brand,
        "model": model,
        "in_car_catalog_models": model in (cat["models"].get(brand) or []),
        "dataset_family_rows": len(rows),
        "boundary": boundary,
        "petrol_rows_whose_dataset_name_says_hybrid": sum(
            1 for r in rows if norm_fuel(r["fuel_type"])[0] == "Petrol" and re.search(r"hybrid|\bhev\b", r["name"], re.I)
        ),
        "dataset_model_names": sorted({r["name"] for r in rows}),
        "dataset_year_span": [min(r["year_from"] for r in rows), max((r["year_end_raw"] or r["year_from"]) for r in rows)] if rows else None,
        "dimensions": out_dims,
    }


LEGACY_VIEWS = {
    "drivetrains": {"map": NORM["drivetrain"]["legacy_collapse"], "reason": "legacy dataset and Sell/Search pickers have no 4WD value; every 4x4 is stored as AWD"},
    "fuel_types": {"map": {"Hybrid": "Petrol", "Plug-in Hybrid": "Petrol"}, "reason": "legacy dataset stores every hybrid as 'Petrol (Gasoline)'"},
}


def _vkey(dim, v):
    return trim_key(v) if dim == "trims" else v


def compare_model(union: dict, current: dict) -> dict:
    out = {"brand": union["brand"], "model": union["model"], "current_carnet_meta": {k: current[k] for k in ("in_car_catalog_models", "dataset_family_rows", "boundary", "petrol_rows_whose_dataset_name_says_hybrid", "dataset_model_names", "dataset_year_span")}, "dimensions": {}}
    conflicts = union["conflicts"]
    for dim in DIMENSIONS:
        cur_items = current["dimensions"][dim]
        cur = {x["key"]: x for x in cur_items}
        ver_det = [x for x in union["details"][dim] if x["status"] == "VERIFIED"]
        prov_det = [x for x in union["details"][dim] if x["status"] == "PROVISIONAL"]
        nsr_det = [x for x in union["details"][dim] if x["status"] == "NEEDS_SOURCE_RETRIEVAL"]

        def keyof(x):
            return _vkey(dim, x["value"])

        ver = {keyof(x): x for x in ver_det}
        prov = {keyof(x): x for x in prov_det}
        nsr = {keyof(x): x for x in nsr_det}
        cur_keys = set(cur)
        entry = {
            "carnet_stores_field": CARNET_STORES[dim],
            "CURRENT_CARNET": [x["value"] for x in cur_items],
            "NEW_VERIFIED": [x["value"] for x in ver_det],
            "NEW_PROVISIONAL_ONLY": [x["value"] for x in prov_det],
            "NEW_NEEDS_SOURCE_RETRIEVAL": [x["value"] for x in nsr_det],
            "MATCHED": [ver[k]["value"] for k in ver if k in cur_keys],
            "MISSING_FROM_CARNET": [ver[k]["value"] for k in ver if k not in cur_keys],
            "PROVISIONAL_NOT_IN_CARNET": [prov[k]["value"] for k in prov if k not in cur_keys],
            "NEEDS_SOURCE_RETRIEVAL_NOT_IN_CARNET": [nsr[k]["value"] for k in nsr if k not in cur_keys],
            "CARNET_VALUE_ONLY_PROVISIONAL": [cur[k]["value"] for k in cur if k in prov and k not in ver],
            "CARNET_VALUE_ONLY_NEEDS_SOURCE_RETRIEVAL": [cur[k]["value"] for k in cur if k in nsr and k not in ver],
            "ONLY_IN_CARNET": [],
            "CONFLICTS": [],
        }
        for k, x in cur.items():
            if k in ver or k in prov or k in nsr:
                continue
            entry["ONLY_IN_CARNET"].append({"value": x["value"], "dataset_rows": x["dataset_rows"]})
        if dim in LEGACY_VIEWS:
            mp = LEGACY_VIEWS[dim]["map"]
            ver_leg = {mp.get(v["value"], v["value"]) for v in ver_det}
            entry["legacy_view"] = {
                "reason": LEGACY_VIEWS[dim]["reason"],
                "mapping": mp,
                "MISSING_FROM_CARNET": sorted(v for v in ver_leg if v not in cur_keys),
            }
        for c in conflicts:
            if c["field"] in DIM_CONFLICT_FIELDS[dim]:
                entry["CONFLICTS"].append(
                    {
                        "conflict_id": c["conflict_id"],
                        "field": c["field"],
                        "engine_group": c["engine_group"],
                        "severity": c["severity"],
                        "values": [(v["record_id"], v["value"]) for v in c["values"]],
                    }
                )
        if not CARNET_STORES[dim]:
            entry["note"] = "CarNet's dataset does not store this attribute; every verified value is new information."
        out["dimensions"][dim] = entry
    out["conflict_count"] = len(conflicts)
    out["conflicts_not_attached_to_a_dimension"] = [c["conflict_id"] for c in conflicts if not any(c["field"] in fs for fs in DIM_CONFLICT_FIELDS.values())]
    return out


# ----------------------------------------------------------------------------------------
# io
# ----------------------------------------------------------------------------------------


def assert_not_production(path: Path):
    p = path.resolve()
    for forbidden in (REPO / "assets", REPO / "lib"):
        if p == forbidden.resolve() or forbidden.resolve() in p.parents:
            raise SystemExit(f"refusing to write under {forbidden} (pilot is tooling only)")


def write_json(path: Path, data):
    assert_not_production(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def today() -> str:
    return _dt.date.today().isoformat()
