#!/usr/bin/env python3
"""DRY-RUN quote-repair analysis for the pilot evidence (Ford Everest, Toyota Land Cruiser, Toyota Camry).

  python tools/catalog_enrichment/quote_repair.py            # offline, deterministic: writes reports/pilot_quote_repair_proposals.json
  python tools/catalog_enrichment/quote_repair.py --collect  # NETWORK, separate step: store candidate snapshots (see below)

NOTHING here edits evidence/*.json, generated/*, authored quotes, values, ids or URLs. The report is a review artefact.

Every record whose supporting quote is not (yet) verified is classified exactly once:

  SAFE_QUOTE_REPAIR     the preserved snapshot explicitly supports the SAME authored values for the SAME configuration; the old
                        quote differs only in layout / punctuation / case / inserted headers / table formatting. The proposal is
                        text copied verbatim from the snapshot (only runs of whitespace are collapsed, exactly like the validator).
  FACTUAL_CHANGE        the snapshot states a DIFFERENT value in the very phrase the old quote used (old "225 net combined hp",
                        now "232 net combined hp"). Never repaired. Every other record of that source is also held back, because the
                        page has demonstrably been revised.
  NEEDS_MANUAL_REVIEW   anything else (value not explicitly stated, ambiguous location, multi-column table, year/trim context, no snapshot).

How a candidate is found (normalisation is used for DISCOVERY only, the proposed text is never normalised):
  1. old quote and snapshot are tokenised (Unicode NFKC, case-folded, punctuation/whitespace ignored, thousands separators removed);
  2. maximal runs of old-quote tokens that occur contiguously in the snapshot are located (runs that occur at several places must be
     resolved by proximity to an unambiguous run, otherwise the record is ambiguous);
  3. runs close to each other are merged into one exact snapshot slice; far-apart runs become separate " … " segments;
  4. the slices are pruned to the smallest contiguous block that still supports every authored value (value-aware, token-exact);
  5. safety gates: all authored values stated (numbers bound to their unit word), model mention kept, no second trim / column
     ambiguity, table-row binding, year context, no new contradiction wording, and the standard validator (trace_check) must pass.

Candidate snapshots: a source whose old quotes all failed has no preserved evidence snapshot (by design). --collect stores the
extracted text of its current page under reports/quote_repair_snapshots/<evidence stem>/<SOURCE_ID>.txt (sha256 must equal the
content_sha256 recorded by the earlier re-validation fetch). Applying a proposal for such a source later requires promoting that
snapshot with fetch_snapshot.py - this tool only simulates it to count the VERIFIED values that would be restored.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
import tempfile
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import enrichment_lib as L  # noqa: E402

SCHEMA = "carnet.quote_repair_proposals/1"
SAFE, FACT, MANUAL = "SAFE_QUOTE_REPAIR", "FACTUAL_CHANGE", "NEEDS_MANUAL_REVIEW"
CLASSES = (SAFE, FACT, MANUAL)
PILOT = [("ford_everest", "Ford Everest"), ("toyota_land_cruiser", "Toyota Land Cruiser"), ("toyota_camry", "Toyota Camry")]
SNAP_DIR = HERE / "reports" / "quote_repair_snapshots"
REPORT = HERE / "reports" / "pilot_quote_repair_proposals.json"

MIN_RUN_TOKENS = 3  # shortest old-quote run searched in the snapshot
MIN_RUN_CHARS = 8  # ... and the minimum total token length (rejects "2 5 L"-style accidents)
BRIDGE_TOKENS = 12  # snapshot tokens that may be skipped between two runs that are merged into one exact slice (e.g. a price line)
ANCHOR_TOKENS = 60  # a run found at several places must lie this close to an unambiguous run
MIN_COVERAGE = 0.5  # share of old-quote tokens that must be found (in runs) before a candidate is trusted
CONTRADICTION_PHRASES = ("no longer", "discontinued", "not available", "not offered", "except", "excluding", "replaced by", "replacing")
UNRESOLVABLE = "UNRESOLVABLE"


# ----------------------------------------------------------------------------------------------------------------
# tokenisation (discovery only)
# ----------------------------------------------------------------------------------------------------------------
_NM = r"(?<![^\W\d_])[Nn][.\u00b7\u22c5\u2022\u30fb\uff65]?m(?![^\W\d_])"  # the torque unit written Nm / N.m / N·m / N･m
_TOK = re.compile(r"\d[\d,]*(?:\.\d+)?|" + _NM + r"|[^\W\d_]+")


def _norm_tok(s: str) -> str:
    s = unicodedata.normalize("NFKC", s).casefold()
    if len(s) in (2, 3) and s[0] == "n" and s[-1] == "m" and not s[1:-1].isalnum():
        return "nm"
    return s.replace(",", "") if s[:1].isdigit() else s


def tokenize(text: str) -> list[tuple[str, int, int]]:
    """-> [(normalised token, start, end)] with offsets into `text` (numbers keep decimals, lose thousands commas)."""
    return [(_norm_tok(m.group()), m.start(), m.end()) for m in _TOK.finditer(text)]


def words(text) -> list[str]:
    return [t for t, _, _ in tokenize(str(text))]


def _is_num(t: str) -> bool:
    return t[:1].isdigit()


def _contains_seq(hay: list[str], needle: list[str]) -> bool:
    n = len(needle)
    if n == 0:
        return True
    return any(hay[i:i + n] == needle for i in range(len(hay) - n + 1))


def _short_word(raw: str, text: str) -> bool:
    """Short trims ('E', 'L', 'SE') must match as a whole, case-sensitive word (a token match would find 'e' anywhere)."""
    return re.search(rf"(?<![A-Za-z0-9]){re.escape(raw)}(?![A-Za-z0-9])", text) is not None


# ----------------------------------------------------------------------------------------------------------------
# authored values -> what the candidate must state
# ----------------------------------------------------------------------------------------------------------------
_UNIT_WORDS = {
    ("horsepower", "hp"): {"hp", "horsepower", "bhp"}, ("horsepower", "ps"): {"ps"}, ("horsepower", "kw"): {"kw"},
    ("torque", "nm"): {"nm"}, ("torque", "lb-ft"): {"lb", "ft"}, ("torque", "lb ft"): {"lb", "ft"},
    ("displacement", "cc"): {"cc", "displacement"}, ("displacement", "cm3"): {"cm", "displacement"},
    ("displacement", "l"): {"l", "liter", "litre", "liters", "litres"},
}


def _num_str(v) -> str:
    return f"{v:g}" if isinstance(v, float) else str(v)


def authored_fields(rec: dict) -> list[dict]:
    """Every authored value that the quote must state. kind: str (token-exact), num (plain number token), bound (number next to its unit word)."""
    f: list[dict] = []

    def s(label, raw):
        if raw not in (None, ""):
            f.append({"label": label, "kind": "str", "value": raw})

    for k in ("trim", "body_type", "drivetrain", "generation"):  # market / year are source-level scope, checked by source identity + the year-context gate
        s(k, rec.get(k))
    m = re.search(r"Listed markets?:\s*([^.]+)\.", str(rec.get("notes") or ""))  # a market stated only in the notes is still an authored fact
    if m:
        s("notes.listed_markets", m.group(1).strip())
    for k in ("seats", "doors"):
        v = rec.get(k)
        if isinstance(v, int):
            f.append({"label": k, "kind": "num", "value": v})
        else:
            s(k, v)
    eng = rec.get("engine") or {}
    d = eng.get("displacement_raw")
    if isinstance(d, dict) and d.get("value") is not None:
        f.append({"label": "engine.displacement_raw", "kind": "bound", "value": d["value"], "unit": d.get("unit"), "attr": "displacement"})
    else:
        s("engine.displacement_raw", d)
    c = eng.get("cylinders")
    if isinstance(c, int):
        f.append({"label": "engine.cylinders", "kind": "num", "value": c})
    else:
        s("engine.cylinders", c)
    s("engine.fuel_type", eng.get("fuel_type"))
    s("engine.aspiration", eng.get("aspiration"))
    s("engine.display_name", eng.get("display_name"))
    for k in ("horsepower", "torque"):
        v = eng.get(k)
        if isinstance(v, dict) and v.get("value") is not None:
            f.append({"label": f"engine.{k}", "kind": "bound", "value": v["value"], "unit": v.get("unit"), "attr": k})
    tr = rec.get("transmission") or {}
    s("transmission.type", tr.get("type"))
    if isinstance(tr.get("gears"), int):
        f.append({"label": "transmission.gears", "kind": "num", "value": tr["gears"]})
    return f


def _units_joined(toks: list[str]) -> list[str]:
    """'N' 'm' (from 'N.m' / 'N m') -> 'nm', so a torque unit written with a dot or a space is still the unit Nm."""
    out: list[str] = []
    for t in toks:
        if t == "m" and out and out[-1] == "n":
            out[-1] = "nm"
        else:
            out.append(t)
    return out


def bound_numbers(toks: list[str], kws: set[str], before: int = 3, after: int = 4) -> set[str]:
    """Numeric tokens that have one of `kws` within `before` tokens in front or `after` tokens behind."""
    toks = _units_joined(toks)
    out = set()
    n = len(toks)
    for i, t in enumerate(toks):
        if _is_num(t) and (any(toks[k] in kws for k in range(max(0, i - before), i)) or any(toks[k] in kws for k in range(i + 1, min(n, i + 1 + after)))):
            out.add(t)
    return out


def immediate_numbers(toks: list[str], kws: set[str]) -> set[str]:
    toks = _units_joined(toks)
    return {t for i, t in enumerate(toks[:-1]) if _is_num(t) and toks[i + 1] in kws}


def _field_supported(fd: dict, block_texts: list[str], block_toks: list[list[str]], seat_words: dict) -> bool:
    v = fd["value"]
    if fd["kind"] == "str":
        raw = str(v)
        if len(raw) <= 2 and raw.isascii():
            return any(_short_word(raw, t) for t in block_texts)
        need = words(raw)
        return bool(need) and any(_contains_seq(b, need) for b in block_toks)
    if fd["kind"] == "num":
        ns = _num_str(v)
        ok = any(ns in b for b in block_toks)
        if not ok and fd["label"] == "seats":
            ok = any(w in b for b in block_toks for w, n in seat_words.items() if n == v)
        return ok
    kws = _UNIT_WORDS.get((fd["attr"], (fd.get("unit") or "").casefold()), {(fd.get("unit") or "").casefold()} - {""})
    ns = _num_str(v)
    return any(ns in bound_numbers(b, kws | ({"displacement"} if fd["attr"] == "displacement" else set())) for b in block_toks)


def unsupported(rec: dict, blocks: list[str]) -> list[str]:
    toks = [[t for t, _, _ in tokenize(b)] for b in blocks]
    sw = L.NORM["seats"]["number_words"]
    return [fd["label"] for fd in authored_fields(rec) if not _field_supported(fd, blocks, toks, sw)]


# ----------------------------------------------------------------------------------------------------------------
# locating the old quote in the snapshot
# ----------------------------------------------------------------------------------------------------------------
class Snap:
    def __init__(self, text: str):
        self.text = text
        self.toks = tokenize(text)
        self.words = [t for t, _, _ in self.toks]
        idx: dict[tuple, list[int]] = {}
        for j in range(len(self.words) - 2):
            idx.setdefault(tuple(self.words[j:j + 3]), []).append(j)
        self.index = idx
        self.norm = L._ws(text)

    def span(self, j: int, n: int) -> tuple[int, int]:
        return self.toks[j][1], self.toks[j + n - 1][2]


def find_runs(seg_idx: int, a: list[str], snap: Snap) -> list[dict]:
    """Maximal runs of the old segment `a` that occur contiguously in the snapshot."""
    S, found = snap.words, []  # NB: runs are matched on the plain tokens (no unit joining)
    for i in range(len(a) - 2):
        for j in snap.index.get(tuple(a[i:i + 3]), ()):
            if i > 0 and j > 0 and a[i - 1] == S[j - 1]:
                continue
            n = 3
            while i + n < len(a) and j + n < len(S) and a[i + n] == S[j + n]:
                n += 1
            if sum(len(x) for x in a[i:i + n]) >= MIN_RUN_CHARS:
                found.append({"seg": seg_idx, "i": i, "n": n, "j": j})
    return found


def locate(old: str, snap: Snap) -> dict:
    """-> {coverage, runs:[{seg,i,n,j}] resolved, ambiguous:bool, old_tokens:int}"""
    segs = [[t for t, _, _ in tokenize(s)] for s in L.quote_segments(old)]
    total = sum(len(s) for s in segs) or 1
    runs = [r for k, a in enumerate(segs) for r in find_runs(k, a, snap)]
    groups: dict[tuple, list[dict]] = {}
    for r in runs:
        groups.setdefault((r["seg"], r["i"], r["n"]), []).append(r)
    chosen: list[list[dict]] = []
    used: set[tuple] = set()
    for key in sorted(groups, key=lambda k: (-k[2], k[0], k[1])):  # longest first, then old-quote order
        seg, i, n = key
        cells = {(seg, x) for x in range(i, i + n)}
        shared = cells & used
        if shared and not (len(shared) == 1 and shared <= {(seg, i), (seg, i + n - 1)}):
            continue  # runs may share one boundary token ("... Gas" + "Gas LE Price"), nothing more
        used |= cells
        chosen.append(groups[key])
    anchors = [g[0] for g in chosen if len(g) == 1]  # runs that occur exactly once
    resolved, ambiguous = [], False
    for g in chosen:
        if len(g) == 1:
            resolved.append(g[0])
            continue

        def dist(r):
            """Distance from candidate `r` to the unique runs next to it IN THE OLD QUOTE (the one before and the one after)."""
            before = [a for a in anchors if a["seg"] == r["seg"] and a["i"] < r["i"] and a["i"] + a["n"] - 1 <= r["i"]]
            after = [a for a in anchors if a["seg"] == r["seg"] and a["i"] > r["i"] and a["i"] >= r["i"] + r["n"] - 1]
            ds = []
            if before:
                a = max(before, key=lambda x: x["i"] + x["n"])
                ds.append(abs(r["j"] - (a["j"] + a["n"] - 1)))
            if after:
                a = min(after, key=lambda x: x["i"])
                ds.append(abs(a["j"] - (r["j"] + r["n"] - 1)))
            if not ds:  # nothing adjacent in the same piece of the old quote: any unique run anywhere
                ds = [abs(r["j"] - a["j"]) for a in anchors]
            return min(ds, default=10 ** 9)

        best = sorted((dist(r), r["j"], k) for k, r in enumerate(g))
        if not anchors or best[0][0] > ANCHOR_TOKENS or (len(best) > 1 and best[0][0] == best[1][0]):
            ambiguous = True  # identical text at several places and nothing close enough to choose between them
            continue
        resolved.append(g[best[0][2]])
    covered = len({(r["seg"], x) for r in resolved for x in range(r["i"], r["i"] + r["n"])})
    return {"coverage": covered / total, "runs": resolved, "ambiguous": ambiguous, "old_tokens": total, "segments": segs}


def merged_blocks(runs: list[dict], snap: Snap) -> list[tuple[int, int, int, int]]:
    """-> [(char_start, char_end, first_token, last_token)] after merging overlapping / near runs."""
    spans = sorted((r["j"], r["j"] + r["n"] - 1) for r in runs)
    out: list[list[int]] = []
    for a, b in spans:
        if out and a - out[-1][1] - 1 <= BRIDGE_TOKENS:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return [(snap.toks[a][1], snap.toks[b][2], a, b) for a, b in out]


def _units(snap: Snap, start: int, end: int) -> list[tuple[int, int]]:
    """Line / sentence units inside snap.text[start:end] (offsets into snap.text)."""
    out = []
    for m in re.finditer(r"[^\n]+", snap.text[start:end]):
        a, b = start + m.start(), start + m.end()
        if b - a > 200:
            pos = a
            for sm in re.finditer(r"(?<=[.!?])\s+", snap.text[a:b]):
                cut = a + sm.start()
                if cut > pos:
                    out.append((pos, cut))
                pos = a + sm.end()
            if pos < b:
                out.append((pos, b))
        else:
            out.append((a, b))
    return [(a, b) for a, b in out if snap.text[a:b].strip()]


# ----------------------------------------------------------------------------------------------------------------
# safety gates
# ----------------------------------------------------------------------------------------------------------------
def substitution_conflicts(rec: dict, old_toks: list[list[str]], snap: Snap) -> list[dict]:
    """Authored number N sits in the old quote as `N <words> <unit word>`. If the snapshot has the SAME phrase with another number
    and never states N in it, the fact has changed (old 225 net combined hp -> now 232 net combined hp)."""
    conflicts = []
    S = snap.words
    for fd in authored_fields(rec):
        if fd["kind"] != "bound":
            continue
        kws = _UNIT_WORDS.get((fd["attr"], (fd.get("unit") or "").casefold()), set())
        if not kws:
            continue
        ns = _num_str(fd["value"])
        for a in old_toks:
            for p, t in enumerate(a):
                if t != ns:
                    continue
                sig = None
                for k in range(p + 1, min(len(a), p + 5)):
                    if _is_num(a[k]):
                        break
                    if a[k] in kws:
                        sig = ("after", tuple(a[p + 1:k]), a[k])
                        break
                if sig is None or not sig[1]:  # need at least one context word besides the unit ("net combined")
                    continue
                phrase = list(sig[1]) + [sig[2]]
                seen = set()
                for q in range(len(S) - len(phrase)):
                    if _is_num(S[q]) and S[q + 1:q + 1 + len(phrase)] == phrase:
                        seen.add(S[q])
                if seen and ns not in seen:
                    conflicts.append({"label": fd["label"], "authored": ns, "unit": fd.get("unit"), "phrase": " ".join(phrase),
                                      "old_text": " ".join(a[max(0, p - 3):p + 1 + len(phrase)]), "snapshot_numbers": sorted(seen)})
    out, seen_keys = [], set()
    for c in conflicts:
        key = (c["label"], c["authored"], c["phrase"])
        if key not in seen_keys:
            seen_keys.add(key)
            out.append(c)
    return out


def _with_adjacent_punct(text: str, a: int, b: int) -> tuple[int, int]:
    """Widen a token-aligned span over punctuation glued to its edges ('(' in front, ')' '.' ',' behind) so a closing bracket / full stop is kept."""
    stop = "|" + L.QUOTE_SEGMENT_SEPARATOR  # never swallow a table cell border or the quote's own separator
    while a > 0 and not text[a - 1].isspace() and not text[a - 1].isalnum() and text[a - 1] not in stop:
        a -= 1
    while b < len(text) and not text[b].isspace() and not text[b].isalnum() and text[b] not in stop:
        b += 1
    return a, b


def table_binding_ok(rec: dict, blocks: list[str]) -> tuple[bool, str]:
    """A block with several data rows binds a value to a trim only through its row. Every authored value must come from the heading
    lines, the header row or the row that names the trim."""
    reduced, multi = [], False
    for b in blocks:
        lines = [ln for ln in b.split("\n") if ln.strip()]
        rows = [ln for ln in lines if ln.lstrip().startswith("|")]
        if len(rows) - 1 >= 2:
            multi = True
            trim = rec.get("trim")
            ident = [r for r in rows[1:] if trim and (_short_word(trim, r) if len(trim) <= 2 else _contains_seq(words(r), words(trim)))]
            if len(ident) != 1:
                return False, "multi-row table without exactly one row naming the trim"
            keep = [ln for ln in lines if not ln.lstrip().startswith("|")] + [rows[0], ident[0]]
            reduced.append("\n".join(keep))
        else:
            reduced.append(b)
    if multi and unsupported(rec, reduced):
        return False, "values are not all in the header / the trim's own row (cells shared across rows)"
    return True, ""


def other_trims_present(rec: dict, blocks: list[str], known_trims: list[str]) -> list[str]:
    own = rec.get("trim")
    ow = words(own or "")
    found = []
    for t in known_trims:
        tw = words(t)
        if t == own or (ow and tw and _contains_seq(ow, tw)):
            continue  # the trim itself, or a trim that is only a part of it ("E" within "E HEV"): not another trim
        if any((_short_word(t, b) if len(t) <= 2 and t.isascii() else _contains_seq(words(b), words(t))) for b in blocks):
            found.append(t)
    return found


# ----------------------------------------------------------------------------------------------------------------
# one record
# ----------------------------------------------------------------------------------------------------------------
def analyze_record(rec: dict, snap: Snap | None, known_trims: list[str], model_name: str) -> dict:
    """Pure: -> classification dict (no I/O). `snap` None = the source has no snapshot at all."""
    old = rec["evidence"]["supporting_text"]
    res = {"classification": MANUAL, "reason_code": None, "reason": None, "proposed_exact_quote": None, "proposed_segments": [],
           "authored_values_supported": {}, "authored_values_unsupported": [], "old_quote_token_coverage": None, "old_quote_tokens_not_located": [], "confidence": None, "factual_change": None}

    def done(cls, code, reason, **kw):
        res.update(classification=cls, reason_code=code, reason=reason, **kw)
        return res

    if snap is None:
        return done(MANUAL, "NO_SNAPSHOT", "The source could not be retrieved (HTTP error / search snippet only), so there is no preserved snapshot to repair against.")
    fields = authored_fields(rec)
    if not fields:
        return done(MANUAL, "NO_AUTHORED_VALUES", "The record has no authored value that a quote could be checked against.")
    loc = locate(old, snap)
    res["old_quote_token_coverage"] = round(loc["coverage"], 3)
    covered = {(r["seg"], x) for r in loc["runs"] for x in range(r["i"], r["i"] + r["n"])}
    res["old_quote_tokens_not_located"] = [t for k, s in enumerate(loc["segments"]) for i, t in enumerate(s) if (k, i) not in covered]
    conf = substitution_conflicts(rec, loc["segments"], snap)
    if conf:
        c = conf[0]
        return done(FACT, "NUMBER_CHANGED_IN_SAME_PHRASE",
                    f"The old quote states {c['label']} = {c['authored']} in the phrase '{c['phrase']}'; the current snapshot states {', '.join(c['snapshot_numbers'])} in that phrase and never {c['authored']}. This is a different fact, not a formatting change.",
                    factual_change=c)
    if loc["ambiguous"]:
        return done(MANUAL, "AMBIGUOUS_LOCATION", "Part of the old quote occurs at several places in the snapshot and cannot be placed unambiguously.")
    if not loc["runs"] or loc["coverage"] < MIN_COVERAGE:
        return done(MANUAL, "OLD_QUOTE_NOT_LOCATED", f"Only {loc['coverage']:.0%} of the old quote's tokens occur (in runs) in the snapshot; the passage cannot be identified safely.")
    blocks = merged_blocks(loc["runs"], snap)
    model_tokens = words(model_name.split(" ", 1)[1] if " " in model_name else model_name)
    # the model must stay named only if the part of the old quote that was actually located named it
    old_has_model = any(_contains_seq(loc["segments"][r["seg"]][r["i"]:r["i"] + r["n"]], model_tokens) for r in loc["runs"])

    def texts_of(parts):
        return [snap.text[a:b] for a, b in parts]

    def good(parts):
        t = texts_of(parts)
        if unsupported(rec, t):
            return False
        return (not old_has_model) or any(_contains_seq(words(x), model_tokens) for x in t)

    parts = [(b[0], b[1]) for b in blocks]
    located_parts = list(parts)  # before pruning: the year / trim context check also looks at the lines these came from
    miss = unsupported(rec, texts_of(parts))
    if miss:
        return done(MANUAL, "VALUE_NOT_STATED", "The passage the old quote came from does not state every authored value explicitly: " + ", ".join(miss) + ".", authored_values_unsupported=miss)
    if not good(parts):
        return done(MANUAL, "MODEL_MENTION_LOST", "The passage no longer names the model.")
    # prune: drop whole blocks, then leading / trailing line-or-sentence units, while every authored value stays stated
    for k in range(len(parts) - 1, -1, -1):
        if len(parts) > 1 and good(parts[:k] + parts[k + 1:]):
            parts = parts[:k] + parts[k + 1:]
    pruned = []
    for a, b in parts:
        u = _units(snap, a, b)
        lo, hi = 0, len(u) - 1
        while lo < hi and good(pruned + [(u[lo + 1][0], u[hi][1])] + parts[len(pruned) + 1:]):
            lo += 1
        while hi > lo and good(pruned + [(u[lo][0], u[hi - 1][1])] + parts[len(pruned) + 1:]):
            hi -= 1
        pruned.append((u[lo][0], u[hi][1]))
    parts = [_with_adjacent_punct(snap.text, a, b) for a, b in pruned]
    blocks_txt = texts_of(parts)
    # ---- gates
    for lab, hay in (("candidate", blocks_txt),):
        for fd in authored_fields(rec):
            if fd["kind"] == "bound":
                kws = _UNIT_WORDS.get((fd["attr"], (fd.get("unit") or "").casefold()), set())
                vals = set()
                for b in hay:
                    vals |= immediate_numbers(words(b), kws)
                if len(vals) >= 2:
                    return done(MANUAL, "COLUMN_OR_VARIANT_AMBIGUITY", f"The passage states several different {fd['attr']} values ({', '.join(sorted(vals))}) side by side; which one belongs to this record depends on column position.")
    if len(authored_fields(rec)) > 1 and rec.get("trim"):
        others = other_trims_present(rec, blocks_txt, known_trims)
        if others and any(fd["label"] != "trim" for fd in authored_fields(rec)):
            return done(MANUAL, "MULTI_TRIM_COLUMNS", "The passage lists several trims (" + ", ".join(others[:4]) + "...) so values are tied to trims only by column position.")
    ok, why = table_binding_ok(rec, blocks_txt)
    if not ok:
        return done(MANUAL, "TABLE_ROW_BINDING", why + ".")
    def lines_around(a, b):
        s = snap.text.rfind("\n", 0, a) + 1
        e = snap.text.find("\n", b)
        return snap.text[s:(len(snap.text) if e < 0 else e)]

    context = blocks_txt + [lines_around(a, b) for a, b in located_parts + parts]
    years = {int(t) for b in context for t in words(b) if re.fullmatch(r"(19|20)\d\d", t)}
    mine = {y for y in (rec.get("year_from"), rec.get("year_to")) if y}
    # a "year" that is part of the authored trim / variant / engine name (e.g. the Land Cruiser "1958" trim) is not a model year
    own_names = {t for k in ("trim", "variant") for t in words(str(rec.get(k) or ""))} | {t for t in words(str((rec.get("engine") or {}).get("display_name") or ""))}
    years = {y for y in years if str(y) not in own_names}
    if years and mine and not (years & mine):
        return done(MANUAL, "YEAR_CONTEXT", f"The passage names model year(s) {sorted(years)} but the record is for {sorted(mine)}.")
    old_l = old.casefold()
    new_phr = [p for p in CONTRADICTION_PHRASES if any(p in b.casefold() for b in blocks_txt) and p not in old_l]
    if new_phr:
        return done(MANUAL, "NEW_QUALIFIER", "The replacement passage adds qualifying wording that the old quote did not have: " + ", ".join(new_phr) + ".")
    segs = [L._ws(b) for b in blocks_txt]
    quote = f" {L.QUOTE_SEGMENT_SEPARATOR} ".join(segs)
    probe = copy.deepcopy(rec)
    probe["evidence"]["supporting_text"] = quote
    bad = L.trace_check(probe)
    if bad:
        return done(MANUAL, "VALIDATOR_WOULD_FAIL", "The standard traceability check would fail on the candidate: " + ", ".join(bad) + ".")
    if not all(s in snap.norm for s in segs):  # belt and braces: verbatim in the snapshot (as the validator reads it)
        return done(MANUAL, "NOT_VERBATIM", "Internal check failed: a candidate segment is not a verbatim slice of the snapshot.")
    supported = {fd["label"]: (f"{fd['value']} {fd.get('unit') or ''}".strip() if fd["kind"] == "bound" else fd["value"]) for fd in authored_fields(rec)}
    # HIGH: every token of the old quote was found in order (only layout / punctuation / case / inserted headings differ);
    # MEDIUM: a few old tokens are not in the snapshot (e.g. a repeated column label) - a reviewer should glance at old_quote_tokens_not_located
    res["confidence"] = "HIGH" if not res["old_quote_tokens_not_located"] else "MEDIUM"
    return done(SAFE, "VERBATIM_PASSAGE_STATES_SAME_VALUES",
                "The old quote's passage was located in the preserved snapshot (" + f"{loc['coverage']:.0%}" + " of its tokens, ignoring layout/punctuation/case); the replacement is the minimal verbatim slice that states every authored value for the same configuration.",
                proposed_exact_quote=quote, proposed_segments=segs, authored_values_supported=supported)


# ----------------------------------------------------------------------------------------------------------------
# files, sources, report
# ----------------------------------------------------------------------------------------------------------------
def _sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def snapshot_for(stem: str, sid: str, doc: dict, reval: dict, root: Path, snap_dir: Path):
    """-> (Snap|None, meta). Preserved evidence snapshot first; else the stored candidate snapshot; else None."""
    s = doc["sources"][sid]
    integ = s["integrity"]
    state = L.source_integrity_state(s)
    if state in L.VERIFIED_ELIGIBLE_STATES:
        f = L._snapshot_file(root, integ["snapshot_path"])
        b = f.read_bytes()
        return Snap(b.decode("utf-8")), {"kind": "preserved_evidence", "path": integ["snapshot_path"], "sha256": _sha(b), "requires_promotion": False}
    f = snap_dir / stem / f"{sid}.txt"
    if f.is_file():
        b = f.read_bytes()
        if _sha(b) == (reval.get(sid) or {}).get("content_sha256"):
            return Snap(b.decode("utf-8")), {"kind": "candidate_not_yet_preserved", "path": f.relative_to(root).as_posix(), "sha256": _sha(b), "requires_promotion": True}
    return None, {"kind": "none", "path": None, "sha256": None, "requires_promotion": False}


def analyze_doc(stem: str, model_name: str, doc: dict, root: Path = HERE, snap_dir: Path = SNAP_DIR) -> list[dict]:
    reval = {a["source_id"]: a for a in L.read_json(root / "reports" / f"{stem}_revalidation.json")["attempts"]}
    errs, _texts, assess = L.verify_snapshots(doc, root)
    if errs:
        raise SystemExit(f"{stem}: evidence snapshots do not validate: {errs[:3]}")
    known_trims = sorted({r["trim"] for r in doc["records"] if r.get("trim")})
    snaps: dict[str, tuple] = {}
    out = []
    for r in doc["records"]:
        a = assess[r["record_id"]]
        if a["eligible"]:
            continue
        sid = r["evidence"]["source_id"]
        if sid not in snaps:
            snaps[sid] = snapshot_for(stem, sid, doc, reval, root, snap_dir)
        snap, meta = snaps[sid]
        res = analyze_record(r, snap, known_trims, model_name)
        out.append({
            "evidence_id": r["record_id"], "model": model_name, "evidence_file": f"evidence/{stem}.json", "source_id": sid,
            "source_url": doc["sources"][sid]["url"], "source_integrity_state": a["state"], "classification": res["classification"],
            "reason_code": res["reason_code"], "reason": res["reason"], "old_quote": r["evidence"]["supporting_text"],
            "proposed_exact_quote": res["proposed_exact_quote"], "proposed_segments": res["proposed_segments"],
            "authored_values_supported": res["authored_values_supported"], "authored_values_unsupported": res["authored_values_unsupported"],
            "old_quote_token_coverage": res["old_quote_token_coverage"], "old_quote_tokens_not_located": res["old_quote_tokens_not_located"],
            "confidence": res["confidence"], "factual_change": res["factual_change"],
            "snapshot_kind": meta["kind"], "snapshot_path": meta["path"], "snapshot_sha256": meta["sha256"],
            "application_requires_snapshot_promotion": meta["requires_promotion"],
        })
    # a source whose page demonstrably changed is not repaired record-by-record
    changed = {p["source_id"] for p in out if p["classification"] == FACT}
    for p in out:
        if p["classification"] == SAFE and p["source_id"] in changed:
            p.update(classification=MANUAL, reason_code="SOURCE_HAS_FACTUAL_CHANGE", proposed_exact_quote=None, proposed_segments=[], confidence=None,
                     authored_values_supported={},
                     reason="Another record of this source is a FACTUAL_CHANGE, so the page has been revised since it was cited; nothing from it is repaired automatically.")
    return out


# ---- simulation: how many VERIFIED values would approval of every SAFE proposal restore?
def _verified(union: dict) -> dict:
    return {d: list(v) for d, v in union["verified"].items() if v}


def simulate(stem: str, doc: dict, proposals: list[dict], root: Path = HERE) -> dict:
    before_union = L.build_union(doc, L.detect_conflicts(doc["records"], stem.replace("_", "-")), root=root)
    safe = {p["evidence_id"]: p for p in proposals if p["classification"] == SAFE}
    new = copy.deepcopy(doc)
    with tempfile.TemporaryDirectory() as td:
        troot = Path(td)
        for rec in new["records"]:
            if rec["record_id"] in safe:
                rec["evidence"]["supporting_text"] = safe[rec["record_id"]]["proposed_exact_quote"]
        for sid, s in new["sources"].items():
            mine = [p for p in safe.values() if p["source_id"] == sid]
            if mine and mine[0]["application_requires_snapshot_promotion"]:  # simulate promoting the candidate snapshot
                data = (root / mine[0]["snapshot_path"]).read_bytes()
                path = f"evidence/_source_text/{sid}.txt"
                s["integrity"] = {"state": "PDF_VERIFIED" if L.is_pdf_source(s) else "FULL_TEXT_VERIFIED", "retrieved_at": s["integrity"].get("retrieved_at"),
                                  "content_sha256": _sha(data), "snapshot_path": path, "origin": "revalidation:refetch", "note": "simulation"}
                (troot / path).parent.mkdir(parents=True, exist_ok=True)
                (troot / path).write_bytes(data)
            elif L.source_integrity_state(s) in L.VERIFIED_ELIGIBLE_STATES:  # an already preserved snapshot: copy it to the scratch root
                path = s["integrity"]["snapshot_path"]
                (troot / path).parent.mkdir(parents=True, exist_ok=True)
                (troot / path).write_bytes((root / path).read_bytes())
        new = L.prepare_evidence(new)
        # unconfirmed = records of verified sources whose (possibly repaired) quote still fails
        for sid, s in new["sources"].items():
            if L.source_integrity_state(s) in L.VERIFIED_ELIGIBLE_STATES:
                text = L._ws((troot / s["integrity"]["snapshot_path"]).read_text(encoding="utf-8"))
                bad = sorted(r["record_id"] for r in new["records"] if r["evidence"]["source_id"] == sid and any(g not in text for g in L.quote_segments(r["evidence"]["supporting_text"])))
                if bad:
                    s["integrity"]["unconfirmed_record_ids"] = bad
                else:
                    s["integrity"].pop("unconfirmed_record_ids", None)
        validate_errs = L.validate_evidence(new)
        verify_errs, _texts, _assess = L.verify_snapshots(new, troot)
        after_union = L.build_union(new, L.detect_conflicts(new["records"], stem.replace("_", "-")), root=troot)
    b, a = _verified(before_union), _verified(after_union)
    newly = {d: sorted(set(map(str, a.get(d, []))) - set(map(str, b.get(d, [])))) for d in sorted(a)}
    lost = {d: sorted(set(map(str, b.get(d, []))) - set(map(str, a.get(d, [])))) for d in sorted(b)}
    return {"verified_values_before": sum(len(v) for v in b.values()), "verified_values_after": sum(len(v) for v in a.values()),
            "newly_verified": {d: v for d, v in newly.items() if v}, "no_longer_verified": {d: v for d, v in lost.items() if v},
            "records_passing_before": before_union["generated_from"]["records_passing_integrity_test"],
            "records_passing_after": after_union["generated_from"]["records_passing_integrity_test"],
            "simulation_validation_errors": validate_errs + verify_errs}


def build_report(root: Path = HERE, snap_dir: Path = SNAP_DIR) -> dict:
    proposals, per_model, sim, evid = [], {}, {}, {}
    for stem, name in PILOT:
        p = root / "evidence" / f"{stem}.json"
        doc = L.read_json(p)
        evid[f"evidence/{stem}.json"] = _sha(p.read_bytes())
        props = analyze_doc(stem, name, doc, root, snap_dir)
        proposals += props
        per_model[name] = {c: sum(1 for x in props if x["classification"] == c) for c in CLASSES}
        per_model[name]["analyzed"] = len(props)
        sim[name] = simulate(stem, doc, props, root)
    total = {c: sum(m[c] for m in per_model.values()) for c in CLASSES}
    total["analyzed"] = sum(m["analyzed"] for m in per_model.values())
    reasons: dict[str, int] = {}
    for p in proposals:
        reasons[f"{p['classification']}:{p['reason_code']}"] = reasons.get(f"{p['classification']}:{p['reason_code']}", 0) + 1
    return {
        "schema_version": SCHEMA, "dry_run": True, "applied": False,
        "policy": "Proposals only. No evidence file, authored quote, value, id or URL is modified by this report. A proposal is text copied verbatim from the snapshot named in the same entry.",
        "evidence_files_analyzed": evid,
        "summary": {"unresolved_records_analyzed": total["analyzed"], "by_classification": {c: total[c] for c in CLASSES},
                    "by_model": per_model, "by_reason": dict(sorted(reasons.items()))},
        "verified_values_if_all_safe_repairs_were_approved": {
            "total": {"before": sum(v["verified_values_before"] for v in sim.values()), "after": sum(v["verified_values_after"] for v in sim.values())},
            "by_model": sim},
        "proposals": proposals,
    }


def collect(root: Path = HERE, snap_dir: Path = SNAP_DIR) -> int:
    """NETWORK. Store the current extracted text of every source whose quotes all failed (needed to analyse them offline)."""
    import fetch_snapshot as F

    bad = 0
    for stem, _name in PILOT:
        doc = L.read_json(root / "evidence" / f"{stem}.json")
        reval = {a["source_id"]: a for a in L.read_json(root / "reports" / f"{stem}_revalidation.json")["attempts"]}
        for sid, s in sorted(doc["sources"].items()):
            if L.source_integrity_state(s) != "RETRIEVED_UNVERIFIABLE":
                continue
            res = F.fetch(s["url"])
            if not res["ok"]:
                print(f"{stem} {sid}: fetch failed {res['error']}")
                bad += 1
                continue
            text, _ext, _pdf = F.extract(res["raw"], res["content_type"], s["url"])
            b = F.snapshot_bytes(text)
            same = _sha(b) == reval[sid]["content_sha256"]
            (snap_dir / stem).mkdir(parents=True, exist_ok=True)
            (snap_dir / stem / f"{sid}.txt").write_bytes(b)
            print(f"{stem} {sid}: stored {len(b)} bytes; identical to the re-validation fetch: {same}")
            bad += 0 if same else 1
    return 1 if bad else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--collect", action="store_true", help="NETWORK: store candidate snapshots (does not analyse)")
    ap.add_argument("--out", help="report path (default reports/pilot_quote_repair_proposals.json)")
    a = ap.parse_args(argv)
    if a.collect:
        return collect()
    rep = build_report()
    out = Path(a.out) if a.out else REPORT
    L.write_json(out, rep)
    s = rep["summary"]
    print(f"analyzed={s['unresolved_records_analyzed']} " + " ".join(f"{c}={n}" for c, n in s["by_classification"].items()))
    for m, c in s["by_model"].items():
        print(f"  {m}: " + " ".join(f"{k}={v}" for k, v in c.items()))
    sim = rep["verified_values_if_all_safe_repairs_were_approved"]
    for m, v in sim["by_model"].items():
        print(f"  {m}: VERIFIED values {v['verified_values_before']} -> {v['verified_values_after']}  errors={v['simulation_validation_errors']}")
    print(f"  total VERIFIED values {sim['total']['before']} -> {sim['total']['after']}")
    print(f"wrote {out.relative_to(HERE) if out.is_relative_to(HERE) else out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
