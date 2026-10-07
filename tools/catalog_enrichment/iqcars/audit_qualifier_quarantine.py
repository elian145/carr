#!/usr/bin/env python3
"""READ-ONLY audit of the ONE remaining Flutter-vs-tooling matching mismatch: the QUALIFIER QUARANTINE.

The Flutter matcher (strict sibling boundary) accepts every dataset row whose name starts with the catalog model (longest
canonical model wins).  The catalog-enrichment tooling (`model_boundaries.ModelIndex.resolve`) ALSO requires the text between the
model and the engine/spec portion to be a known trim, an engine descriptor, or a data-defined suffix grammar; otherwise the row is
`ambiguous_qualifier` (quarantined).  This script measures what that difference means at RUNTIME.  Nothing is changed.

Phases (run from the repo root):

  1. python tools/catalog_enrichment/iqcars/audit_qualifier_quarantine.py --prepare TMPDIR
        -> TMPDIR/strict_dataset.json   copy of assets/car_spec_dataset.json WITHOUT the quarantined rows (assets/ untouched)
        -> TMPDIR/quarantined_ids.json
  2. flutter test tools/catalog_enrichment/iqcars/audit/qualifier_quarantine_dump_test.dart   (twice, via QQ_DATASET / QQ_OUT)
        with the real dataset                 -> TMPDIR/current_dump.json     (CURRENT FLUTTER)
        with TMPDIR/strict_dataset.json       -> TMPDIR/strict_dump.json      (TOOLING-STRICT)
     The dump calls the SAME Search/Sell resolvers the app uses, so "what changes" is measured on real runtime output.
  3. python tools/catalog_enrichment/iqcars/audit_qualifier_quarantine.py --current TMPDIR/current_dump.json --strict TMPDIR/strict_dump.json

Writes generated/iqcars_qualifier_quarantine_audit.json and .md (canonical CRLF).

Row classes (deterministic, ordered rules; every rule id is recorded on the row; nothing is guessed into SAFE):
  A SAFE_TRIM_OR_VARIANT     qualifier is made ONLY of engine notation and/or well-known grade/trim/powertrain tokens (lexicon below),
                             or is a documented series name of the model (F-250 "Super Duty")
  B OTHER_MODEL_OR_SIBLING   qualifier names a different vehicle line (curated, each with a reason) or another model of the brand
                             appears in the catalog / the IQ Cars model list ("<model> <qualifier>")
  C AMBIGUOUS                anything else
  D MALFORMED_OR_NOISY       a model-number/displacement split ('Tiggo 2' + '0') or a qualifier with no information
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
from canonical_io import write_text_canonical  # noqa: E402
from model_boundaries import ModelIndex, mkey  # noqa: E402
import audit_family_matching as AF  # noqa: E402

REPO = HERE.parents[2]
GEN = HERE / "generated"

SAFE, OTHER, AMBIG, NOISE = "SAFE_TRIM_OR_VARIANT", "OTHER_MODEL_OR_SIBLING", "AMBIGUOUS", "MALFORMED_OR_NOISY"

# ------------------------------------------------------------------------------------------------ lexicons (reviewable)
# B: the qualifier names a different vehicle line.  (regex on the normalized qualifier, reason)
OTHER_FAMILY_RULES = [
    (r"\bverso\b", "Verso is a separate MPV line (Corolla Verso / Avensis Verso), not a trim of the saloon/hatch"),
    (r"^connect\b", "Transit Connect is a separate compact van, not a Transit trim"),
    (r"^majesta\b", "Crown Majesta is a separate luxury saloon line"),
    (r"^(spacio|rumion)\b", "Corolla Spacio / Rumion are separate Japanese-market models"),
    (r"^brezza\b", "Vitara Brezza is a separate vehicle"),
    (r"^hyryder\b", "Urban Cruiser Hyryder is a separate vehicle"),
    (r"^vivo\b", "Polo Vivo is a separately marketed model"),
    (r"^s cross\b", "SX4 S-Cross is a separate crossover, not the SX4 saloon/hatch"),
    (r"^grandcoupe\b", "Megane GrandCoupe is a separately named saloon body line"),
    (r"^(2500|3500)hd\b", "Sierra 2500HD/3500HD are the heavy-duty truck lines, not the light-duty Sierra"),
    (r"^suv\b", "'SUV' variant of a saloon/coupe nameplate (e.g. EQS SUV) is a different body line"),
    (r"^e vitara\b", "e Vitara is a separate EV, not the Vitara"),
]
# B: numbered model extension, e.g. Ioniq + '9 long range' (a model number then words); only when the model itself does not end in a digit
NUMBERED_MODEL_EXTENSION = re.compile(r"^[1-9] [a-z]{3,}")

# A: documented series names (brand, model) -> qualifier
SERIES_NAMES = {("Ford", "F-250"): {"super duty"}, ("Ford", "F-350"): {"super duty"}}

# A: grade / trim / powertrain vocabulary.  A qualifier is SAFE only if EVERY token is in GRADE or is engine notation.
GRADE = set("""
gt gti gtd gte gts gtx gta gl sl ss sc ts st rs sport performance competition type plus pro standard range long extended premium
longrange performante veloce ralliart wilderness denali premier trophy trofeo speed supersport superleggera black series blackwing
amg callaway bullitt mach sixpack hellcat redeye srt srt4 srt10 scat pack nismo line special one final diamond deluxe chief targa
carrera 4s gr grmn gsx mps vrs xtr z28 svr hi rider 4x crosstar blue recharge electrified ev euv hybrid activehybrid iv dm dmo idd hi4
hi4z tgi pse cup tech power edition 3wt 4wt evolution
""".split())
WEAK = set("s r v k e x f c m n".split())  # single letters: SAFE only when the row's body type is among the model's reference bodies
# a few multi-token phrases whose tokens are only valid TOGETHER (checked before token grading)
PHRASES_OK = ["g tron", "e power", "e tech", "z.e.", "dm i", "dm p", "type s", "pro 4x", "black series", "standard range", "long range",
              "extended range", "premium long range", "performance plus", "special edition", "final edition"]
ENG_TOK = re.compile(
    r"^(\d{1,4}[a-z]{0,8}|v\d{1,2}|w\d{1,2}|\d{2}v|l|h|hp|ps|kw|cat|sec|sd|sdl|turbo|turbodiesel|diesel|thp|puretech|tsi|tgdi|tfs|vvt|"
    r"kompressor|ecotec|cdi|blueefficiency|natural|gas|drive|lang|thrift|fire|i|d|t|tdi|gdi|xdrive|awd|4wd|2wd|quattro|4matic|long)$"
)
ENG_WHOLE = re.compile(r"^\d[ ,.]\d{1,3}[a-z]{0,8}( [a-z0-9]+)*$")  # '2 0td', '1 750 tb', '2 0ie e boxer', '2,0 16v'
_ENG_DIGIT_OR_V = re.compile(r"\d|v\d")


def tokens(q: str) -> list[str]:
    return [t for t in q.split(" ") if t]


def classify(brand, model, qual, ref_bodies, row_bodies, other_owner):
    """-> (class, rule_id, note)"""
    qk = qual
    toks = tokens(qk)
    if not toks or not re.search(r"[a-z0-9]", qk):
        return NOISE, "noise_empty", "qualifier carries no information"
    mtoks = mkey(model).split()
    # D: model-number / displacement split: model ends in a digit and the whole qualifier is one 1-2 digit token ('Tiggo 2' + '0')
    if len(toks) == 1 and re.fullmatch(r"\d{1,2}", toks[0]) and mtoks and re.search(r"\d$", mtoks[-1]) and len(toks[0]) == 1:
        return NOISE, "noise_split_model_number", f"'{model} {qual}' is a displacement/model-number split, not a variant"
    if len(toks) == 1 and re.fullmatch(r"\d", toks[0]):
        return NOISE, "noise_orphan_digit", "single orphan digit after the model"
    # B: curated other-family
    for rx, why in OTHER_FAMILY_RULES:
        if re.search(rx, qk):
            return OTHER, "other_family:" + rx, why
    if NUMBERED_MODEL_EXTENSION.match(qk) and not (mtoks and re.search(r"\d$", mtoks[-1])):
        return OTHER, "other_numbered_model", "a model number follows the nameplate (e.g. Ioniq 9)"
    # A: documented series name
    if qk in SERIES_NAMES.get((brand, model), ()):
        return SAFE, "safe_series_name", f"'{qk}' is the series name of {model}"
    # A: tokens fully explained by engine notation / grade vocabulary
    work = qk
    for ph in sorted(PHRASES_OK, key=len, reverse=True):
        work = re.sub(rf"(?:(?<=\s)|^){re.escape(ph)}(?=\s|$)", " ", work)
    wt = tokens(work)
    # a repeated model name ('CLA CLA 350', '360 360 Spider', 'EQV EQV 250') is the model written twice, not a qualifier
    repeated = False
    if wt and mtoks and wt[0] == mtoks[-1]:
        wt, repeated = wt[1:], True
    if not wt and repeated:
        return SAFE, "safe_repeated_model_name", "the model name is written twice"
    if not wt:
        return SAFE, "safe_phrase", "qualifier consists only of lexicon phrases"
    if ENG_WHOLE.match(qk):
        return SAFE, "safe_engine_notation", "engine notation the tooling's engine-start pattern does not recognise"
    if wt and all((t in GRADE) or ENG_TOK.match(t) for t in wt):
        has_eng = any(_ENG_DIGIT_OR_V.search(t) for t in wt)
        only_weak = all((t in WEAK) or re.fullmatch(r"\d+", t) for t in wt)
        if only_weak and ref_bodies and not (row_bodies & ref_bodies):
            return AMBIG, "ambiguous_weak_token_body_differs", "single-letter grade and the row's body type is not seen on the model's reference rows"
        if only_weak and not ref_bodies:
            return AMBIG, "ambiguous_weak_token_no_reference", "single-letter grade and the model has no tooling-accepted reference rows"
        return SAFE, "safe_engine_notation" if (has_eng and not any(t in GRADE for t in wt)) else "safe_grade_vocabulary", \
            "all qualifier tokens are engine notation / known grade or powertrain markers"
    # B: evidence that another model owns the row
    if other_owner:  # a model NAME appearing in the qualifier is only a hint (e.g. 'Gladiator Willys', 'RAM Magnum' engine): never forced into B
        return AMBIG, "ambiguous_other_model_name_in_qualifier", "another model name appears in the qualifier: " + ", ".join(other_owner)
    return AMBIG, "ambiguous_unclassified", "not explained by the lexicon and no other-model evidence"


# ------------------------------------------------------------------------------------------------ data
def load(p):
    return json.loads(Path(p).read_text(encoding="utf-8"))


class Ctx:
    def __init__(self):
        self.cat = load(REPO / "assets" / "car_catalog.json")
        self.ds = load(REPO / "assets" / "car_spec_dataset.json")
        self.brands = {b["id"]: b["name"] for b in self.ds["brands"]}
        self.idx = ModelIndex(self.cat, use_suffix_rules=True, strict_suffix_rules=True)
        self.rows_by_brand = defaultdict(list)
        for m in self.ds["models"]:
            self.rows_by_brand[AF.skey(self.brands[m["brand_id"]])].append(m)
        self.trims_by_model = defaultdict(list)
        for t in self.ds["trims"]:
            self.trims_by_model[t["model_id"]].append(t)
        self.spec_by_trim = {s["trim_id"]: s for s in self.ds["specs"]}
        # IQ model-level corroboration: IQ model names (all, incl. unmatched) and approved sets per CarNet model
        mm = load(GEN / "iqcars_model_matching_report.json")
        opts = {(o["brand"], o["model"]): o for o in load(GEN / "iqcars_model_options.json")["models"]}
        self.iq_names = defaultdict(set)
        for o in opts.values():
            self.iq_names[mkey(o["brand"])].add(mkey(o["model"]))
        for u in mm["unmatched_iq_models"] + mm["ambiguous_iq_models"]:
            self.iq_names[mkey(u["iq_brand"])].add(mkey(u["iq_model"]))
        self.iq = {}
        for m in mm["matched"]:
            o = opts.get((m["iq_brand"], m["iq_model"]))
            if o:
                self.iq[(m["carnet_brand"], m["carnet_model"])] = {
                    "disp": sorted({round(v["displacement_l"], 1) for v in o["engine_variants"] if v.get("displacement_l") is not None}),
                    "cyl": sorted(o["cylinders"]),
                    "trims": sorted({mkey(t) for t in o["trims"]}),
                }
        ov = load(REPO / "assets" / "car_iqcars_overlay.json")  # approved FULL cylinder sets (runtime)
        for b, ms in ov.items():
            if b == "_meta":
                continue
            for mo, v in ms.items():
                self.iq.setdefault((b, mo), {"disp": [], "cyl": [], "trims": []})["approved_cyl"] = v.get("cylinders", [])

    def row_info(self, row):
        trims = self.trims_by_model.get(row["id"], [])
        specs = [self.spec_by_trim[t["id"]] for t in trims if t["id"] in self.spec_by_trim]
        years = [t["year"] for t in trims if t.get("year")] + [t["year_end"] for t in trims if t.get("year_end")]
        cyl, eng = set(), set()
        for s in specs:
            m = re.search(r"(\d+)", str((s.get("raw_spec_pairs") or {}).get("Cylinders alignment:") or ""))
            if m:
                cyl.add(int(m.group(1)))
            if s.get("displacement_cc"):
                eng.add(round(s["displacement_cc"] / 1000.0, 1))
        return {
            "trims": len(trims),
            "year_from": min(years) if years else None, "year_to": max(years) if years else None,
            "engine_l": sorted(eng), "cylinders": sorted(cyl),
            "fuel": sorted({s["fuel_type"] for s in specs if s.get("fuel_type")}),
            "drivetrain": sorted({s["drivetrain"] for s in specs if s.get("drivetrain")}),
            "body": sorted({s["body_type"] for s in specs if s.get("body_type")}),
            "seats": sorted({s["seats"] for s in specs if s.get("seats")}),
            "transmission": sorted({s["transmission"] for s in specs if s.get("transmission")}),
        }


def collect(ctx: Ctx):
    """Every row the Flutter strict matcher keeps for model M but the tooling does not accept for M."""
    cat = ctx.cat
    quarantined = []  # (brand, model, row, resolution)
    accepted_rows = defaultdict(list)  # (brand, model) -> rows the tooling accepts (reference)
    seen_ids = defaultdict(list)
    for brand, models in cat["models"].items():
        rows = ctx.rows_by_brand.get(AF.skey(brand), [])
        for mo in models:
            longer = [x for x in models if AF.skey(x).startswith(AF.skey(mo) + " ")]
            for r in rows:
                if AF.matches(brand, mo, r["name"]) and not any(AF.matches(brand, x, r["name"]) for x in longer):
                    res = ctx.idx.resolve(brand, r["name"])
                    if res.accepted and res.model == mo:
                        accepted_rows[(brand, mo)].append(r)
                    else:
                        quarantined.append((brand, mo, r, res))
                        seen_ids[r["id"]].append((brand, mo))
    return quarantined, accepted_rows, seen_ids


def other_owner_evidence(ctx: Ctx, brand, model, qual):
    toks = tokens(qual)
    mk = mkey(model)
    out = []
    models = {mkey(x): x for x in ctx.cat["models"].get(brand, [])}
    for k in range(1, len(toks) + 1):
        ph = " ".join(toks[:k])
        if len(ph) >= 3 and ph in models and models[ph] != model:
            out.append(f"catalog:{models[ph]}")
        if f"{mk} {ph}" in ctx.iq_names.get(mkey(brand), ()):
            out.append(f"iq_model:{brand} {model} {ph}".strip())
        if f"{mk} {ph}" in models and models[f"{mk} {ph}"] != model:
            out.append(f"catalog:{models[f'{mk} {ph}']}")
    return sorted(set(out))


# ------------------------------------------------------------------------------------------------ prepare
def prepare(tmp: Path):
    ctx = Ctx()
    quarantined, _acc, seen = collect(ctx)
    ids = sorted({r["id"] for _b, _m, r, _x in quarantined})
    cross = {i: v for i, v in seen.items() if i in set(ids) and len(v) > 1}
    drop = set(ids)
    ds = ctx.ds
    keep_models = [m for m in ds["models"] if m["id"] not in drop]
    keep_ids = {m["id"] for m in keep_models}
    keep_trims = [t for t in ds["trims"] if t["model_id"] in keep_ids]
    keep_tids = {t["id"] for t in keep_trims}
    strict = {"brands": ds["brands"], "models": keep_models, "trims": keep_trims, "specs": [s for s in ds["specs"] if s["trim_id"] in keep_tids]}
    tmp.mkdir(parents=True, exist_ok=True)
    (tmp / "strict_dataset.json").write_text(json.dumps(strict, ensure_ascii=False), encoding="utf-8")
    (tmp / "quarantined_ids.json").write_text(json.dumps(ids), encoding="utf-8")
    print(f"quarantined row ids: {len(ids)}  (model,row pairs: {len(quarantined)}; rows shared by >1 catalog model: {len(cross)})")
    print(f"dataset rows {len(ds['models'])} -> {len(keep_models)}   wrote {tmp / 'strict_dataset.json'}")
    return 0


def prepare_selective(tmp: Path):
    """Dataset copy without ONLY the rows classified OTHER_MODEL_OR_SIBLING / MALFORMED_OR_NOISY (the proposed selective rule)."""
    ctx = Ctx()
    quarantined, accepted, _seen = collect(ctx)
    rows_out, _bm = build_rows(ctx, quarantined, accepted)
    drop = {x["dataset_model_id"] for x in rows_out if x["class"] in (OTHER, NOISE)}
    ds = ctx.ds
    keep_models = [m for m in ds["models"] if m["id"] not in drop]
    keep_ids = {m["id"] for m in keep_models}
    keep_trims = [t for t in ds["trims"] if t["model_id"] in keep_ids]
    keep_tids = {t["id"] for t in keep_trims}
    sel = {"brands": ds["brands"], "models": keep_models, "trims": keep_trims, "specs": [s for s in ds["specs"] if s["trim_id"] in keep_tids]}
    tmp.mkdir(parents=True, exist_ok=True)
    (tmp / "selective_dataset.json").write_text(json.dumps(sel, ensure_ascii=False), encoding="utf-8")
    print(f"selective rule removes {len(drop)} rows (OTHER_MODEL + MALFORMED); wrote {tmp / 'selective_dataset.json'}")
    return 0


# ------------------------------------------------------------------------------------------------ report
IMPORTANT = {
    "Toyota": ["Land Cruiser", "Land Cruiser Prado", "Corolla", "Corolla Cross", "Camry", "Hilux", "RAV4"],
    "BMW": ["3-Series", "4-Series", "5-Series", "X1", "X3", "X5"],
    "Lexus": ["LX", "GX", "RX"],
    "Ford": ["Everest", "Bronco", "Mustang"],
    "Volkswagen": ["Golf", "Golf R", "Tiguan"],
    "Nissan": ["Patrol"],
}
FIELDS = [("engines", "baseline_engines"), ("cylinders", "baseline_cylinders")]
OTHER_FIELDS = ["body", "fuel", "drive", "transmission", "seating"]
ROW_KEY = {"body": "body", "fuel": "fuel", "drive": "drivetrain", "transmission": "transmission", "seating": "seats"}


def lead_float(label: str):
    m = re.match(r"\s*(\d+(?:\.\d+)?)", str(label))
    return round(float(m.group(1)), 1) if m else None


def exclusion_key(qual: str, rule: str) -> str:
    """The reviewed qualifier prefix an exclusion entry would carry (spaced key, following the model name)."""
    if rule.startswith("other_family:"):
        m = re.search(rule.split(":", 1)[1], qual)
        return m.group(0).strip() if m else qual
    if rule == "other_numbered_model":
        return qual.split(" ")[0]
    return qual


def build_rows(ctx, quarantined, accepted_rows):
    # ---- reference sets from tooling-accepted rows per model (used for body corroboration only)
    ref_bodies = {}
    for k, rs in accepted_rows.items():
        b = set()
        for r in rs:
            b |= set(ctx.row_info(r)["body"])
        ref_bodies[k] = b

    # ---- per row records
    rows_out = []
    by_model = defaultdict(list)
    for brand, mo, r, res in quarantined:
        info = ctx.row_info(r)
        owner = other_owner_evidence(ctx, brand, mo, res.qualifier)
        klass, rule, note = classify(brand, mo, res.qualifier, ref_bodies.get((brand, mo), set()), set(info["body"]), owner)
        body_div = bool(ref_bodies.get((brand, mo))) and not (set(info["body"]) & ref_bodies[(brand, mo)])
        rec = {
            "dataset_brand": brand, "raw_name": r["name"], "dataset_model_id": r["id"],
            "flutter_brand": brand, "flutter_model": mo,
            "matched_model_prefix": mkey(mo), "qualifier": res.qualifier, "remainder": res.remainder,
            "tooling_status": res.status, "tooling_reason": "qualifier is not a known trim, engine descriptor or brand suffix grammar",
            "plausible_other_owner": owner,
            "engine_l": info["engine_l"], "cylinders": info["cylinders"], "fuel": info["fuel"], "drivetrain": info["drivetrain"],
            "body": info["body"], "seats": info["seats"], "transmission": info["transmission"],
            "year_from": info["year_from"], "year_to": info["year_to"],
            "body_not_in_model_reference_rows": body_div,
            "class": klass, "rule": rule, "note": note,
            "exclusion_key": exclusion_key(res.qualifier, rule) if klass in (OTHER, NOISE) else None,
        }
        rows_out.append(rec)
        by_model[(brand, mo)].append(rec)
    return rows_out, by_model


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prepare")
    ap.add_argument("--prepare-selective", dest="prepare_selective")
    ap.add_argument("--selective")
    ap.add_argument("--current")
    ap.add_argument("--strict")
    a = ap.parse_args()
    if a.prepare:
        return prepare(Path(a.prepare))
    if a.prepare_selective:
        return prepare_selective(Path(a.prepare_selective))
    if not (a.current and a.strict):
        ap.error("--prepare TMPDIR, or --current X --strict Y")

    ctx = Ctx()
    quarantined, accepted_rows, seen = collect(ctx)
    cur = {(m["brand"], m["model"]): m for m in load(a.current)["models"]}
    stc = {(m["brand"], m["model"]): m for m in load(a.strict)["models"]}

    rows_out, by_model = build_rows(ctx, quarantined, accepted_rows)

    cls = Counter(x["class"] for x in rows_out)

    # ---- groups by qualifier phrase / head token
    def group(keyfn):
        g = defaultdict(list)
        for x in rows_out:
            g[keyfn(x)].append(x)
        out = []
        for k, v in g.items():
            ex = []
            for x in v:
                if len(ex) < 3 and x["raw_name"] not in ex:
                    ex.append(x["raw_name"])
            out.append({"qualifier": k, "rows": len(v), "models": len({(x["flutter_brand"], x["flutter_model"]) for x in v}),
                        "class_distribution": dict(Counter(x["class"] for x in v)), "examples": ex,
                        "top_models": [f"{b} {m}" for (b, m), _ in Counter((x["flutter_brand"], x["flutter_model"]) for x in v).most_common(3)]})
        return sorted(out, key=lambda d: (-d["rows"], d["qualifier"]))

    by_phrase = group(lambda x: x["qualifier"])
    by_head = group(lambda x: (x["qualifier"].split(" ")[0] if x["qualifier"] else ""))

    # ---- app impact (Dart dumps)
    def sets(d, f):
        return set(d[f])

    affected = sorted(by_model)
    impact = {}
    changed_counts = Counter()
    lost_all_cov = []
    for k in affected:
        c, s = cur[k], stc[k]
        i = {
            "brand": k[0], "model": k[1], "quarantined_rows": len(by_model[k]),
            "current_rows": len(c["family_rows"]), "strict_rows": len(s["family_rows"]),
            "current": {"engines": c["baseline_engines"], "cylinders": c["baseline_cylinders"], **{f: c["baseline_other"][f] for f in OTHER_FIELDS}, "has_coverage": c["has_coverage"]},
            "strict": {"engines": s["baseline_engines"], "cylinders": s["baseline_cylinders"], **{f: s["baseline_other"][f] for f in OTHER_FIELDS}, "has_coverage": s["has_coverage"]},
        }
        ch = {}
        ch["engines"] = i["current"]["engines"] != i["strict"]["engines"]
        ch["cylinders"] = i["current"]["cylinders"] != i["strict"]["cylinders"]
        for f in OTHER_FIELDS:
            ch[f] = i["current"][f] != i["strict"][f]
        ch["has_coverage"] = i["current"]["has_coverage"] != i["strict"]["has_coverage"]
        ch["other_fields_any"] = any(ch[f] for f in OTHER_FIELDS)
        ch["effective_search_engines"] = c["search_engines"] != s["search_engines"]
        ch["effective_search_cylinders"] = c["search_cylinders"] != s["search_cylinders"]
        ch["effective_sell_cylinders"] = c["sell_cylinders"] != s["sell_cylinders"]
        i["changed"] = ch
        i["lost"] = {
            "engines": sorted(set(c["baseline_engines"]) - set(s["baseline_engines"])),
            "cylinders": sorted(set(c["baseline_cylinders"]) - set(s["baseline_cylinders"]), key=int),
            **{f: sorted(set(c["baseline_other"][f]) - set(s["baseline_other"][f]), key=str) for f in OTHER_FIELDS},
        }
        i["gained"] = {"engines": sorted(set(s["baseline_engines"]) - set(c["baseline_engines"])),
                       "cylinders": sorted(set(s["baseline_cylinders"]) - set(c["baseline_cylinders"]), key=int)}
        i["effective_current"] = {"search_engines": c["search_engines"], "search_cylinders": c["search_cylinders"], "sell_cylinders": c["sell_cylinders"]}
        i["effective_strict"] = {"search_engines": s["search_engines"], "search_cylinders": s["search_cylinders"], "sell_cylinders": s["sell_cylinders"]}
        for f, v in ch.items():
            if v:
                changed_counts[f] += 1
        if c["has_coverage"] and not s["has_coverage"]:
            lost_all_cov.append(f"{k[0]} {k[1]}")
        impact[k] = i

    # models outside the 316 must not change at all (parity of the experiment)
    outside_changed = [f"{b} {m}" for (b, m) in cur if (b, m) not in impact and (
        cur[(b, m)]["baseline_engines"] != stc[(b, m)]["baseline_engines"] or cur[(b, m)]["baseline_cylinders"] != stc[(b, m)]["baseline_cylinders"]
        or cur[(b, m)]["baseline_other"] != stc[(b, m)]["baseline_other"] or cur[(b, m)]["has_coverage"] != stc[(b, m)]["has_coverage"])]
    qnames = {(b, m): {x["raw_name"] for x in v} for (b, m), v in by_model.items()}
    dump_parity_bad = [f"{b} {m}" for (b, m) in affected
                       if set(cur[(b, m)]["family_rows"]) - qnames[(b, m)] != set(stc[(b, m)]["family_rows"])]

    # ---- IQ corroboration + per-option contributors
    def contributors(rows, field_key, value):
        out = []
        for x in rows:
            if field_key == "engines":
                hit = value in set(x["engine_l"])
            elif field_key == "cylinders":
                hit = int(value) in set(x["cylinders"])
            else:
                hit = value in (set(x[ROW_KEY[field_key]]) if field_key != "seating" else set(x["seats"]))
            if hit:
                out.append(x)
        return out

    other_flagged = lambda x: x["class"] == OTHER or bool(x["plausible_other_owner"])  # noqa: E731
    for k, i in impact.items():
        iq = ctx.iq.get(k, {})
        iq_disp, iq_cyl = set(iq.get("disp", [])), set(iq.get("cyl", [])) | set(iq.get("approved_cyl", []))
        rows = by_model[k]
        opt = []
        for lab in i["lost"]["engines"]:
            lf = lead_float(lab)
            cr = contributors(rows, "engines", lf) if lf is not None else []
            in_iq = lf is not None and any(abs(lf - d) < 0.05 for d in iq_disp)
            opt.append({"field": "engine", "value": lab, "in_iq": in_iq, "contributing_quarantined_rows": len(cr),
                        "contributing_classes": dict(Counter(x["class"] for x in cr)),
                        "all_contributors_look_like_other_model": bool(cr) and all(other_flagged(x) for x in cr),
                        "any_contributor_looks_like_other_model": any(other_flagged(x) for x in cr)})
        for v in i["lost"]["cylinders"]:
            cr = contributors(rows, "cylinders", v)
            opt.append({"field": "cylinders", "value": v, "in_iq": int(v) in iq_cyl, "contributing_quarantined_rows": len(cr),
                        "contributing_classes": dict(Counter(x["class"] for x in cr)),
                        "all_contributors_look_like_other_model": bool(cr) and all(other_flagged(x) for x in cr),
                        "any_contributor_looks_like_other_model": any(other_flagged(x) for x in cr)})
        for f in OTHER_FIELDS:
            for v in i["lost"][f]:
                cr = contributors(rows, f, v)
                opt.append({"field": f, "value": v, "in_iq": None, "contributing_quarantined_rows": len(cr),
                            "contributing_classes": dict(Counter(x["class"] for x in cr)),
                            "all_contributors_look_like_other_model": bool(cr) and all(other_flagged(x) for x in cr),
                            "any_contributor_looks_like_other_model": any(other_flagged(x) for x in cr)})
        i["lost_options_detail"] = opt
        i["iq_model_sets"] = {"displacements_l": sorted(iq_disp), "cylinders": sorted(iq_cyl)}
        i["class_distribution"] = dict(Counter(x["class"] for x in rows))
        i["top_qualifiers"] = [q for q, _ in Counter(x["qualifier"] for x in rows).most_common(5)]

    # ---- high-confidence contamination candidates
    high_conf, medium = [], []
    for k, i in impact.items():
        for o in i["lost_options_detail"]:
            if o["field"] in ("engine", "cylinders") and o["in_iq"] is False and o["contributing_quarantined_rows"]:
                rec = {"brand": k[0], "model": k[1], **{x: o[x] for x in ("field", "value", "contributing_quarantined_rows", "contributing_classes")}}
                rec["qualifiers"] = sorted({x["qualifier"] for x in by_model[k] if x["class"] == OTHER or x["plausible_other_owner"]})[:6]
                if o["all_contributors_look_like_other_model"]:
                    high_conf.append(rec)
                elif o["any_contributor_looks_like_other_model"]:
                    medium.append(rec)

    # ---- risk ranking
    def factor(o):
        """How suspicious a lost option is, from the classes of the quarantined rows that carry it (SAFE-only options barely count)."""
        cl = set(o["contributing_classes"])
        if not cl:
            return 0.3
        f = 1.0 if cl <= {OTHER, NOISE} else 0.7 if cl & {OTHER, NOISE} else 0.4 if AMBIG in cl else 0.1
        if o["in_iq"] is False:
            f *= 1.5
        return f

    def score(i):
        k = (i["brand"], i["model"])
        det = i["lost_options_detail"]
        s = 0.0
        reasons = []
        for fld, w, label in (("engine", 2, "engine option(s) disappear"), ("cylinders", 6, "cylinder count(s) disappear"), ("body", 4, "body type(s) disappear")):
            lo = [o for o in det if o["field"] == fld]
            if lo:
                s += sum(w * factor(o) for o in lo)
                extra = ""
                if fld != "engine":
                    extra = ": " + ", ".join(str(o["value"]) for o in lo)
                ni = [o for o in lo if o["in_iq"] is False]
                reasons.append(f"{len(lo)} {label}{extra}" + (f" ({len(ni)} not supported by IQ)" if ni else ""))
        n_oth = [o for o in det if o["field"] in ("fuel", "drive", "transmission", "seating")]
        if n_oth:
            s += sum(1.0 * factor(o) for o in n_oth)
            reasons.append(f"{len(n_oth)} fuel/drive/transmission/seat option(s) disappear")
        rows = by_model[k]
        nb = sum(1 for x in rows if x["class"] in (OTHER, NOISE))
        if nb:
            s += 3 * min(nb, 10)
            reasons.append(f"{nb} row(s) classified OTHER_MODEL / MALFORMED")
        ne = sum(1 for x in rows if x["plausible_other_owner"])
        if ne:
            s += 2 * min(ne, 10)
            reasons.append(f"{ne} row(s) where another known model name appears in the qualifier")
        nbd = sum(1 for x in rows if x["body_not_in_model_reference_rows"])
        if nbd:
            s += 1.5 * min(nbd, 10)
            reasons.append(f"{nbd} row(s) with a body type not on the model's reference rows")
        na = sum(1 for x in rows if x["class"] == AMBIG)
        if na:
            s += 0.3 * min(na, 10)
        if i["current"]["has_coverage"] and not i["strict"]["has_coverage"]:
            s += 8
            reasons.append("model would lose ALL baseline coverage")
        return s, reasons
    ranked = []
    for k, i in impact.items():
        s, rs = score(i)
        ranked.append({"brand": k[0], "model": k[1], "risk_score": round(s, 1), "reasons": rs, "quarantined_rows": i["quarantined_rows"],
                       "class_distribution": i["class_distribution"], "top_qualifiers": i["top_qualifiers"],
                       "lost": {f: v for f, v in i["lost"].items() if v},
                       "lost_not_in_iq": [f"{o['field']} {o['value']}" for o in i["lost_options_detail"] if o["in_iq"] is False]})
    ranked.sort(key=lambda d: (-d["risk_score"], -d["quarantined_rows"], d["brand"], d["model"]))
    top30 = ranked[:30]

    # ---- important models
    important = []
    for brand, ms in IMPORTANT.items():
        for mo in ms:
            k = (brand, mo)
            if k not in cur:
                important.append({"brand": brand, "model": mo, "in_catalog": False})
                continue
            if k not in impact:
                important.append({"brand": brand, "model": mo, "in_catalog": True, "affected": False, "quarantined_rows": 0,
                                  "result": "NOT AFFECTED: every strict row is accepted by the tooling"})
                continue
            i = impact[k]
            important.append({
                "brand": brand, "model": mo, "in_catalog": True, "affected": True, "quarantined_rows": i["quarantined_rows"],
                "rows_current_strict": [i["current_rows"], i["strict_rows"]],
                "class_distribution": i["class_distribution"], "top_qualifiers": i["top_qualifiers"],
                "changed": {f: v for f, v in i["changed"].items() if v},
                "lost": {f: v for f, v in i["lost"].items() if v},
                "lost_options_detail": [{x: o[x] for x in ("field", "value", "in_iq", "contributing_classes")} for o in i["lost_options_detail"]],
                "effective_search_engines": [i["effective_current"]["search_engines"], i["effective_strict"]["search_engines"]],
                "effective_search_cylinders": [i["effective_current"]["search_cylinders"], i["effective_strict"]["search_cylinders"]],
                "examples": [x["raw_name"] for x in by_model[k][:4]],
            })

    # ---- summary (the 14 report items)
    total = len(rows_out)
    summary = {
        "1_total_quarantined_rows": total,
        "2_affected_models": len(affected),
        "3_SAFE_TRIM_OR_VARIANT": cls[SAFE], "4_OTHER_MODEL_OR_SIBLING": cls[OTHER], "5_AMBIGUOUS": cls[AMBIG], "6_MALFORMED_OR_NOISY": cls[NOISE],
        "7_models_whose_engines_change": changed_counts["engines"],
        "8_models_whose_cylinders_change": changed_counts["cylinders"],
        "9_models_whose_other_fields_change": changed_counts["other_fields_any"],
        "9_detail": {f: changed_counts[f] for f in OTHER_FIELDS},
        "10_models_that_would_lose_all_baseline_coverage": len(lost_all_cov), "10_list": lost_all_cov,
        "has_coverage_changed": changed_counts["has_coverage"],
        "effective_search_engines_changed": changed_counts["effective_search_engines"],
        "effective_search_cylinders_changed": changed_counts["effective_search_cylinders"],
        "effective_sell_cylinders_changed": changed_counts["effective_sell_cylinders"],
        "models_with_no_runtime_change_at_all": sum(1 for i in impact.values() if not any(v for k2, v in i["changed"].items() if k2 != "other_fields_any")),
        "models_changed_outside_the_316 (must be 0)": outside_changed,
        "dart_dump_parity_failures (must be 0)": dump_parity_bad,
        "rows_shared_by_more_than_one_catalog_model": sum(1 for v in seen.values() if len(v) > 1),
        "rule_counts": dict(Counter(x["rule"].split(":")[0] for x in rows_out).most_common()),
        "rows_with_body_not_in_model_reference": sum(1 for x in rows_out if x["body_not_in_model_reference_rows"]),
        "rows_with_other_model_evidence": sum(1 for x in rows_out if x["plausible_other_owner"]),
        "lost_options_not_in_iq": sum(1 for i in impact.values() for o in i["lost_options_detail"] if o["in_iq"] is False),
        "high_confidence_contamination_candidates": len(high_conf),
        "medium_confidence_candidates": len(medium),
    }

    # per-class impact: what if ONLY class B + D rows were quarantined? (needs a dump; reported as row counts only)
    lex = {"other_family_rules": [{"regex": r, "reason": w} for r, w in OTHER_FAMILY_RULES],
           "numbered_model_extension": NUMBERED_MODEL_EXTENSION.pattern, "series_names": {f"{b}|{m}": sorted(v) for (b, m), v in SERIES_NAMES.items()},
           "grade_vocabulary": sorted(GRADE), "weak_single_letter_tokens": sorted(WEAK), "phrases_ok": PHRASES_OK, "engine_token_regex": ENG_TOK.pattern}

    class_by_model = defaultdict(Counter)
    for x in rows_out:
        class_by_model[(x["flutter_brand"], x["flutter_model"])][x["class"]] += 1
    models_only_safe = sum(1 for c in class_by_model.values() if set(c) == {SAFE})
    summary["models_whose_quarantined_rows_are_ALL_SAFE"] = models_only_safe
    summary["models_with_at_least_one_OTHER_row"] = sum(1 for c in class_by_model.values() if c[OTHER])
    summary["models_with_at_least_one_AMBIGUOUS_or_NOISE_row"] = sum(1 for c in class_by_model.values() if c[AMBIG] or c[NOISE])

    out = {
        "_meta": {"name": "iqcars_qualifier_quarantine_audit", "read_only": True,
                  "definition": "rows the Flutter strict matcher keeps for catalog model M but ModelIndex.resolve quarantines "
                                "(ambiguous_qualifier / distinct_vehicle_qualifier): the text between the model and the engine is not a known trim, "
                                "engine descriptor or brand suffix grammar",
                  "runtime_impact_method": "Dart dump (the app's own Search/Sell resolvers) over the real dataset vs a copy of the dataset with exactly "
                                           "those rows removed; assets/ and lib/ untouched",
                  "row_level_engine_cylinder_note": "row 'engine_l' comes from displacement_cc (1 dp) and 'cylinders' from 'Cylinders alignment:'; "
                                                    "the model-level engine/cylinder numbers come from the Dart dump",
                  "classification_lexicon": lex},
        "summary": summary,
        "groups_by_qualifier_phrase": by_phrase,
        "groups_by_head_token": by_head,
        "models": [impact[k] for k in affected],
        "top_30_high_risk_models": top30,
        "risk_ranking_top_100": ranked[:100],
        "iq_high_confidence_contamination_candidates": high_conf,
        "iq_medium_confidence_candidates": medium,
        "important_models": important,
        "rows": rows_out,
    }
    out["proposed_selective_exclusion"] = selective_impact(cur, load(a.selective), rows_out, ctx) if a.selective else None
    out["recommendation"] = recommend(summary, out)
    write_text_canonical(GEN / "iqcars_qualifier_quarantine_audit.json", json.dumps(out, ensure_ascii=False, indent=1) + "\n")
    write_text_canonical(GEN / "iqcars_qualifier_quarantine_audit.md", markdown(out))
    print(json.dumps({k: v for k, v in summary.items() if k != "10_list"}, ensure_ascii=False, indent=1))
    return 0


def selective_impact(cur, sel_dump, rows_out, ctx) -> dict:
    """Runtime impact of excluding ONLY the rows classed OTHER_MODEL_OR_SIBLING / MALFORMED_OR_NOISY (dump made from selective_dataset.json)."""
    sel = {(m["brand"], m["model"]): m for m in sel_dump["models"]}
    drop = [x for x in rows_out if x["class"] in (OTHER, NOISE)]
    per_model = defaultdict(list)
    for x in drop:
        per_model[(x["flutter_brand"], x["flutter_model"])].append(x)
    diffs, counts, lost_cov = [], Counter(), []
    for k, c in cur.items():
        s = sel[k]
        ch = {"engines": c["baseline_engines"] != s["baseline_engines"], "cylinders": c["baseline_cylinders"] != s["baseline_cylinders"],
              "coverage": c["has_coverage"] != s["has_coverage"], "search_engines": c["search_engines"] != s["search_engines"],
              "search_cylinders": c["search_cylinders"] != s["search_cylinders"], "sell_cylinders": c["sell_cylinders"] != s["sell_cylinders"]}
        for f in OTHER_FIELDS:
            ch[f] = c["baseline_other"][f] != s["baseline_other"][f]
        ch["other_fields_any"] = any(ch[f] for f in OTHER_FIELDS)
        for f, v in ch.items():
            counts[f] += int(v)
        if c["has_coverage"] and not s["has_coverage"]:
            lost_cov.append(f"{k[0]} {k[1]}")
        if any(ch.values()):
            diffs.append({"brand": k[0], "model": k[1], "rows_removed": len(per_model.get(k, [])), "changed": [f for f, v in ch.items() if v and f != "other_fields_any"],
                          "lost": {"engines": sorted(set(c["baseline_engines"]) - set(s["baseline_engines"])),
                                   "cylinders": sorted(set(c["baseline_cylinders"]) - set(s["baseline_cylinders"]), key=int),
                                   **{f: sorted(set(c["baseline_other"][f]) - set(s["baseline_other"][f]), key=str) for f in OTHER_FIELDS}},
                          "qualifiers": sorted({x["qualifier"] for x in per_model.get(k, [])})[:8]})
    phrases = Counter((x["flutter_brand"], x["flutter_model"], x["qualifier"]) for x in drop)
    return {
        "rule": "exclude a row from model M when its qualifier is on the explicit OTHER_MODEL list (curated lexicon, each phrase with a reason) "
                "or is a model-number/displacement split; keep everything else exactly as the Flutter matcher does today",
        "rows_removed": len(drop), "models_with_rows_removed": len(per_model),
        "runtime_impact": {f: counts[f] for f in counts},
        "models_that_would_lose_all_baseline_coverage": lost_cov,
        "changed_models": diffs,
        "deny_list": [{"brand": b, "model": m, "qualifier": q, "rows": n} for (b, m, q), n in sorted(phrases.items(), key=lambda kv: (-kv[1], kv[0]))],
        "deny_list_distinct_qualifiers": len({q for (_b, _m, q) in phrases}),
    }


def recommend(summary, out) -> dict:
    sel = out.get("proposed_selective_exclusion") or {}
    ri = sel.get("runtime_impact", {})
    entries = Counter((x["flutter_brand"], x["flutter_model"], x["exclusion_key"]) for x in out["rows"] if x["exclusion_key"])
    s = summary
    entry_models = {(b, m) for (b, m, _k) in entries}
    hc_covered = sum(1 for c in out["iq_high_confidence_contamination_candidates"] if (c["brand"], c["model"]) in entry_models)
    return {
        "decision": "PORT ONLY SELECTED QUALIFIER EXCLUSIONS (a reviewed, explicit exclusion list); do NOT port the tooling quarantine unchanged; "
                    "keep the current Flutter behaviour for every other row",
        "rationale": [
            f"Porting the tooling quarantine unchanged would remove {s['1_total_quarantined_rows']} rows from {s['2_affected_models']} models, change engines for "
            f"{s['7_models_whose_engines_change']}, cylinders for {s['8_models_whose_cylinders_change']} and other fields for {s['9_models_whose_other_fields_change']} models, "
            f"and leave {s['10_models_that_would_lose_all_baseline_coverage']} models with NO baseline coverage at all.",
            f"Only {s['4_OTHER_MODEL_OR_SIBLING']} of the {s['1_total_quarantined_rows']} rows ({s['4_OTHER_MODEL_OR_SIBLING'] * 100 // s['1_total_quarantined_rows']}%) show a different vehicle line; "
            f"{s['3_SAFE_TRIM_OR_VARIANT']} are clearly trims / engine designations / series names of the matched model (e.g. F-250 'Super Duty', Infiniti FX '35 V6', "
            "BYD 'DM-i', Porsche 'Carrera GTS'), so a blanket quarantine would delete correct data (it would remove every F-250/F-350 row).",
            f"{s['5_AMBIGUOUS']} rows cannot be classified automatically (mostly single-letter grades 'S', 'R', 'V', 'E', 'K', 'M', 'N', 'drw', Mercedes 'E 200 T'); "
            "they are not shown to contaminate anything provable, so they keep today's behaviour until reviewed.",
            f"The OTHER_MODEL rows are concentrated in a tiny, reviewable vocabulary: {sel.get('deny_list_distinct_qualifiers')} distinct qualifier phrases in "
            f"{sel.get('models_with_rows_removed')} models ({sel.get('rows_removed')} rows). Measured on the app's own resolvers, excluding only them changes engines for "
            f"{ri.get('engines')} models, cylinders for {ri.get('cylinders')}, other fields for {ri.get('other_fields_any')}, and removes ALL baseline rows of "
            f"{ri.get('coverage')} models ({', '.join(sel.get('models_that_would_lose_all_baseline_coverage', []))}), whose only dataset rows belong to another vehicle "
            "(Transit Connect, SX4 S-Cross); those models then fall back to the already-approved behaviour (IQ overlay data, otherwise Search 'Any only' / Sell manual).",
            f"{hc_covered} of the {s['high_confidence_contamination_candidates']} high-confidence contamination candidates (a CarNet option that exists only through a quarantined row, "
            "is absent from IQ Cars, and whose qualifier names another vehicle line) belong to a model that has an exclusion entry.",
        ],
        "rule": [
            "Add a small, explicit, reviewed map of dataset-name prefixes that must NOT be attributed to a shorter catalog model, next to the existing "
            "_reviewedDatasetFamilyPrefixes alias (same style, same tests): key = '<brand>|<model>' -> list of '<model> <qualifier>' spaced keys.",
            "A dataset row is dropped from model M when its spaced name equals or starts with '<M> <key> ' for any key listed for M (whole-word prefix, same folding as today).",
            "The list is generated from this audit (exclusion_entries below): OTHER_MODEL rows plus the two model-number/displacement splits (Tiggo 2 + '0'/'4').",
            "Do not port the tooling's suffix grammars, engine-start regex or trim vocabulary; do not touch the sibling matcher, slash families, Ram 2500 alias, BMW folding, IQ cylinder sets, "
            "engine-qualifier identity, Search 'Any only' or the Sell fallback.",
            "Add tests: each entry removes its rows and nothing else; the models left without baseline rows (Transit, SX4) behave as the resolver already does for a model with no baseline data.",
        ],
        "exclusion_entries": [{"brand": b, "model": m, "exclude_prefix": f"{mkey(m)} {k}".strip(), "rows": n}
                              for (b, m, k), n in sorted(entries.items(), key=lambda kv: (-kv[1], kv[0]))],
        "not_recommended": {
            "port_tooling_quarantine_unchanged": "too broad: removes correct data and all coverage of 27 models",
            "keep_flutter_behavior_unchanged": "leaves provable cross-vehicle contamination (Transit Connect in Transit, SX4 S-Cross in SX4, Corolla Verso/Spacio/Rumion in Corolla, "
                                               "Crown Majesta V8 in Crown, Sierra 2500HD/3500HD in Sierra)",
        },
    }


def markdown(out) -> str:
    s = out["summary"]
    L = ["# Qualifier-quarantine audit (Flutter strict matcher vs ModelIndex tooling)", "", "READ-ONLY. Nothing in lib/ or assets/ was changed.", "",
         "```json", json.dumps({k: v for k, v in s.items()}, ensure_ascii=False, indent=1), "```", "", "## Recommendation", ""]
    r = out["recommendation"]
    L.append(f"**{r.get('decision', '')}**")
    L.append("")
    for p in r.get("rationale", []):
        L.append(f"- {p}")
    if r.get("rule"):
        L += ["", "Precise rule:", ""] + [f"- {p}" for p in r["rule"]]
    sel = out.get("proposed_selective_exclusion")
    if sel:
        L += ["", "## Proposed selective exclusion - measured runtime impact", "", "```json",
              json.dumps({k: v for k, v in sel.items() if k not in ("changed_models", "deny_list")}, ensure_ascii=False, indent=1), "```", "",
              "| model | rows removed | changed | lost |", "|---|---|---|---|"]
        for m in sel["changed_models"]:
            L.append(f"| {m['brand']} {m['model']} | {m['rows_removed']} | {', '.join(m['changed'])} | {({k: v for k, v in m['lost'].items() if v})} |")
        L += ["", "### Exclusion entries (exclude_prefix, rows)", ""]
        for e in r.get("exclusion_entries", []):
            L.append(f"- {e['brand']} / {e['model']}: `{e['exclude_prefix']}` ({e['rows']} rows)")
    L += ["", "## Top qualifier groups (by phrase)", "", "| qualifier | rows | models | classes | examples |", "|---|---|---|---|---|"]
    for g in out["groups_by_qualifier_phrase"][:40]:
        L.append(f"| `{g['qualifier']}` | {g['rows']} | {g['models']} | {g['class_distribution']} | {'; '.join(g['examples'][:2])} |")
    L += ["", "## Top head tokens", "", "| head token | rows | models | classes |", "|---|---|---|---|"]
    for g in out["groups_by_head_token"][:25]:
        L.append(f"| `{g['qualifier']}` | {g['rows']} | {g['models']} | {g['class_distribution']} |")
    L += ["", "## Top 30 high-risk models", "", "| # | model | score | rows | lost options | not in IQ | reasons |", "|---|---|---|---|---|---|---|"]
    for n, m in enumerate(out["top_30_high_risk_models"], 1):
        L.append(f"| {n} | {m['brand']} {m['model']} | {m['risk_score']} | {m['quarantined_rows']} | {m['lost']} | {m['lost_not_in_iq']} | {'; '.join(m['reasons'])} |")
    L += ["", "## Important models", ""]
    for m in out["important_models"]:
        if not m.get("in_catalog", True):
            L.append(f"- {m['brand']} {m['model']}: not in catalog")
        elif not m["affected"]:
            L.append(f"- {m['brand']} {m['model']}: **not affected**")
        else:
            L.append(f"- {m['brand']} {m['model']}: **affected** {m['quarantined_rows']} row(s) {m['class_distribution']} changed={m['changed']} lost={m['lost']} examples={m['examples']}")
    L += ["", "## IQ-corroborated contamination candidates", "",
          f"high confidence ({len(out['iq_high_confidence_contamination_candidates'])}): lost option not in IQ AND every contributing quarantined row looks like another model", ""]
    for c in out["iq_high_confidence_contamination_candidates"]:
        L.append(f"- {c['brand']} {c['model']}: {c['field']} {c['value']} ({c['contributing_quarantined_rows']} rows, {c['contributing_classes']}) qualifiers={c['qualifiers']}")
    L += ["", f"medium confidence ({len(out['iq_medium_confidence_candidates'])}): lost option not in IQ AND at least one contributing row looks like another model", ""]
    for c in out["iq_medium_confidence_candidates"][:40]:
        L.append(f"- {c['brand']} {c['model']}: {c['field']} {c['value']} ({c['contributing_quarantined_rows']} rows, {c['contributing_classes']}) qualifiers={c['qualifiers']}")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    sys.exit(main())
