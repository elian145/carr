#!/usr/bin/env python3
"""Deterministic canonical Brand+Model matching (tooling only, read-only on assets/).

Replaces the app-mirroring `name_matches_family` heuristic, which treats
'Land Cruiser Prado 2 7' as a 'Land Cruiser' row (first-word / prefix match).
Rules: see rules/model_boundaries.json -> "algorithm". No fuzzy matching, no guessing.

Brand suffix grammars (rules/brand_model_suffix_rules.json) add ONE more accepted status, `suffix_rule`: a
qualifier after the longest canonical model is accepted only if the whole qualifier fullmatches a data-defined,
brand+model-scoped powertrain/engine-code grammar (e.g. BMW '3 Series 320d', Mercedes 'E-Class E 220 d').
Every row ends as MATCHED / QUARANTINED / UNRESOLVED (`Resolution.outcome`). `ModelIndex(..., use_suffix_rules=False)`
reproduces the strict pre-grammar baseline. Audit/metrics: matching_audit.py.

CLI (repo root):
  python tools/catalog_enrichment/model_boundaries.py report            # writes reports/model_collisions.json
  python tools/catalog_enrichment/model_boundaries.py resolve "Toyota" "Land Cruiser Prado 2 7 (163 Hp)"
"""
from __future__ import annotations

import json
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from dataclasses import dataclass, field, replace
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
RULES_PATH = HERE / "rules" / "model_boundaries.json"

SUFFIX_RULES_PATH = HERE / "rules" / "brand_model_suffix_rules.json"

ACCEPTED = {"exact", "engine_descriptor", "trim_qualifier", "suffix_rule"}
REJECTED = {"distinct_vehicle_qualifier", "ambiguous_qualifier", "unresolved"}

# Three-state outcome used by the matching audit. Every dataset row gets exactly one; nothing is dropped.
MATCHED, QUARANTINED, UNRESOLVED = "MATCHED", "QUARANTINED", "UNRESOLVED"
_PLACEHOLDER = re.compile(r"\{([a-z_][a-z0-9_]*)\}")  # '{2,3}' quantifiers do not match (must start with a letter)

# What a dataset name looks like right after the model: the dataset writes displacement as '2 5', '1 33',
# '2 7l', '2 4i', or cc ('1100'), or kWh for EVs, or a bracketed group.
_ENGINE_START = re.compile(r"^(?:\d\s\d{1,2}[a-z]?(?=\s|$|\()|\d\.\d|\d{4}(?=\s|$|\()|\d{1,3}(?:\s\d{1,2})?\s?kwh\b|\()")


def mkey(s: str | None) -> str:
    """Normalized model key. Deliberately minimal and deterministic."""
    if s is None:
        return ""
    s = unicodedata.normalize("NFKC", str(s)).casefold()
    s = re.sub(r"[-_/]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


@dataclass
class Resolution:
    brand: str
    name: str
    status: str  # one of ACCEPTED | REJECTED
    model: str | None  # canonical model the name resolved to (the longest canonical prefix), None if unresolved
    remainder: str = ""
    qualifier: str = ""
    flags: list[str] = field(default_factory=list)
    rule: str | None = None  # id of the brand suffix grammar that accepted the qualifier (status == suffix_rule)

    @property
    def accepted(self) -> bool:
        return self.status in ACCEPTED

    @property
    def outcome(self) -> str:
        if self.status in ACCEPTED:
            return MATCHED
        if self.status == "unresolved":
            return UNRESOLVED
        return QUARANTINED  # a canonical model was found but the remainder is not provably a descriptor of it


class _Grammar:
    """One data-defined suffix grammar: which models it applies to, and the anchored qualifier regex."""

    def __init__(self, brand: str, spec: dict, classes: dict[str, str]):
        self.brand = brand
        self.id: str = spec["id"]
        self.kind: str = spec["kind"]
        self.flags: list[str] = list(spec.get("flags", []))
        self.template: str = spec["qualifier_regex"]
        self.models: dict[str, dict[str, str]] = {m: dict(v) for m, v in spec["models"].items()}
        self.classes = classes
        self.wildcard = False  # True when the spec used models {"*": {}} (model-independent engine-code notation)
        self._compiled: dict[str, re.Pattern] = {}

    def _expand(self, template: str, mvars: dict[str, str], depth: int = 0) -> str:
        if depth > 5:
            raise ValueError(f"token class nesting too deep in grammar {self.id}")

        def sub(m: re.Match) -> str:
            name = m.group(1)
            if name in mvars:
                return re.escape(mvars[name])
            if name in self.classes:
                return "(?:" + self._expand(self.classes[name], mvars, depth + 1) + ")"
            raise ValueError(f"grammar {self.id}: unknown placeholder {{{name}}}")

        return _PLACEHOLDER.sub(sub, template)

    def compile_for(self, model: str) -> re.Pattern:
        if model not in self._compiled:
            self._compiled[model] = re.compile(self._expand(self.template, self.models[model]))
        return self._compiled[model]

    def accepts(self, model: str, qualifier: str) -> bool:
        return model in self.models and self.compile_for(model).fullmatch(qualifier) is not None


class ModelIndex:
    def __init__(self, catalog: dict, rules: dict | None = None, suffix_rules: dict | None = None, use_suffix_rules: bool = True,
                 strict_suffix_rules: bool | None = None):
        """strict_suffix_rules: brands/models named in the suffix rules MUST exist in `catalog` (else ValueError).
        Defaults to True when suffix_rules are passed explicitly, False for the shipped rule file (so small test
        catalogs that lack e.g. BMW simply get no BMW grammar). load_index() and the tests on the real catalog are strict."""
        self.rules = rules if rules is not None else json.loads(RULES_PATH.read_text(encoding="utf-8"))
        self.use_suffix_rules = use_suffix_rules
        strict = (suffix_rules is not None) if strict_suffix_rules is None else strict_suffix_rules
        self.suffix_rules = suffix_rules if suffix_rules is not None else json.loads(SUFFIX_RULES_PATH.read_text(encoding="utf-8"))
        self.models: dict[str, list[str]] = {b: list(ms) for b, ms in catalog["models"].items()}
        self.trims: dict[str, dict[str, list[str]]] = catalog.get("trimsByBrandModel", {})
        self._brand_by_key = {mkey(b): b for b in self.models}
        # per brand: key -> canonical name (aliases included, mapped to their canonical model)
        self._keys: dict[str, dict[str, str]] = {}
        for b, ms in self.models.items():
            d: dict[str, str] = {}
            for m in ms:
                k = mkey(m)
                if k in d and d[k] != m:
                    raise ValueError(f"model key collision in catalog for {b}: {d[k]!r} vs {m!r}")
                d[k] = m
            for alias, canon in (self.rules.get("aliases", {}).get(b) or {}).items():
                if canon not in ms:
                    raise ValueError(f"alias {alias!r} of {b} points at non-catalog model {canon!r}")
                ka = mkey(alias)
                if ka in d and d[ka] != canon:
                    raise ValueError(f"alias {alias!r} of {b} collides with model {d[ka]!r}")
                d[ka] = canon
            self._keys[b] = d
        # compiled brand grammars (validated against the catalog; always built so a broken rule file fails loudly)
        self._grammars: dict[str, list[_Grammar]] = {}
        shared = dict(self.suffix_rules.get("token_classes", {}))
        seen_ids: set[str] = set()
        for brand, bspec in (self.suffix_rules.get("brands") or {}).items():
            if brand not in self.models:
                if strict:
                    raise ValueError(f"suffix rules: brand {brand!r} not in catalog")
                continue
            classes = {**shared, **(bspec.get("token_classes") or {})}
            gl = []
            for spec in bspec.get("grammars", []):
                g = _Grammar(brand, spec, classes)
                if g.id in seen_ids:
                    raise ValueError(f"duplicate suffix grammar id {g.id}")
                seen_ids.add(g.id)
                if "*" in g.models:  # model-independent engine-code notation: applies to every model of the brand (sibling self-check still enforced)
                    if len(g.models) != 1 or g.models["*"]:
                        raise ValueError(f"suffix grammar {g.id}: '*' must be the only model key and carry no variables")
                    g.models = {m: {} for m in self.models[brand]}
                    g.wildcard = True
                for m in list(g.models):
                    if m not in self.models[brand]:
                        if strict:
                            raise ValueError(f"suffix grammar {g.id}: {m!r} is not a canonical {brand} model")
                        del g.models[m]
                        continue
                    g.compile_for(m)  # surfaces unknown placeholders / bad regex now
                if g.models:
                    gl.append(g)
            self._grammars[brand] = gl

    # -- brand / model identity ----------------------------------------------------------
    def brand_name(self, brand: str) -> str | None:
        return self._brand_by_key.get(mkey(brand))

    def canonical_model(self, brand: str, model: str) -> str | None:
        """EXACT canonical identity (key equality or explicit alias). Never a prefix match."""
        b = self.brand_name(brand)
        if b is None:
            return None
        return self._keys[b].get(mkey(model))

    def prefix_pairs(self):
        """(brand, shorter, longer) for every pair of canonical models where one is a whole-word prefix of the other."""
        out = []
        for b, ms in self.models.items():
            ks = [(mkey(m), m) for m in ms]
            for ka, a in ks:
                for kb, c in ks:
                    if ka != kb and kb.startswith(ka + " "):
                        out.append((b, a, c))
        return sorted(out)

    # -- resolution ----------------------------------------------------------------------
    def _trim_keys(self, brand: str, model: str) -> set[str]:
        ks = {mkey(t) for t in ((self.trims.get(brand) or {}).get(model) or [])}
        ks |= {mkey(t) for t in ((self.rules.get("qualifier_trims") or {}).get(brand) or {}).get(model, [])}
        ks.discard("")
        ks.discard("other")
        return ks

    def resolve(self, brand: str, name: str) -> Resolution:
        b = self.brand_name(brand)
        if b is None:
            return Resolution(brand, name, "unresolved", None, flags=["brand_not_in_catalog"])
        nk = mkey(name)
        best_k = None
        for k in self._keys[b]:
            if nk == k or nk.startswith(k + " "):
                if best_k is None or len(k) > len(best_k):
                    best_k = k
        if best_k is None:
            return Resolution(b, name, "unresolved", None, flags=["no_canonical_model_prefix"])
        model = self._keys[b][best_k]
        rem = nk[len(best_k):].strip()
        if not rem:
            return Resolution(b, name, "exact", model, remainder="")
        if _ENGINE_START.match(rem):
            return Resolution(b, name, "engine_descriptor", model, remainder=rem)
        # qualifier = words before the first engine descriptor
        toks = rem.split(" ")
        q: list[str] = []
        for i, t in enumerate(toks):
            if _ENGINE_START.match(" ".join(toks[i:])):
                break
            q.append(t)
        qual = " ".join(q)
        dist = ((self.rules.get("qualifier_distinct") or {}).get(b) or {}).get(model) or {}
        if qual in {mkey(x) for x in dist}:
            return Resolution(b, name, "distinct_vehicle_qualifier", model, remainder=rem, qualifier=qual)
        if qual in self._trim_keys(b, model):
            return Resolution(b, name, "trim_qualifier", model, remainder=rem, qualifier=qual, flags=self._overlap_flags(b, model, qual))
        if self.use_suffix_rules:
            for g in self._grammars.get(b, ()):
                if g.accepts(model, qual):
                    return Resolution(
                        b, name, "suffix_rule", model, remainder=rem, qualifier=qual,
                        flags=self._overlap_flags(b, model, qual) + [f"variant:{f}" for f in g.flags], rule=g.id,
                    )
        return Resolution(b, name, "ambiguous_qualifier", model, remainder=rem, qualifier=qual)

    def _overlap_flags(self, b: str, model: str, qual: str) -> list[str]:
        """The qualifier word(s) plus the model tokens spell another catalog model (e.g. 'Corolla' + 'GR' vs 'GR Corolla')."""
        target = sorted(mkey(model).split() + qual.split())
        return [f"qualifier_overlaps_other_model:{o}" for o in self.models[b] if o != model and sorted(mkey(o).split()) == target]

    def accepts(self, brand: str, selected_model: str, name: str) -> Resolution:
        """Resolution of `name` plus whether it belongs to `selected_model` (canonical identity, exact)."""
        r = self.resolve(brand, name)
        sel = self.canonical_model(brand, selected_model)
        r_ok = r.accepted and sel is not None and r.model == sel
        if not r_ok and r.accepted:
            r = replace(r, flags=r.flags + ["belongs_to_other_model"])
        return r

    # -- suffix-rule safety --------------------------------------------------------------------
    def sibling_safety_violations(self) -> list[dict]:
        """A grammar for model M must never accept the tail of a longer sibling model L = 'M tail' (catalog or alias).
        Returns every violation; the shipped rules must produce none."""
        out = []
        for b, grammars in self._grammars.items():
            keys = self._keys[b]
            for g in grammars:
                for m in g.models:
                    mk = mkey(m)
                    for lk, lcanon in keys.items():
                        if lcanon != m and lk.startswith(mk + " "):
                            tail = lk[len(mk) + 1:]
                            if g.accepts(m, tail):
                                out.append({"brand": b, "grammar": g.id, "model": m, "sibling": lcanon, "tail": tail})
        return out

    def matching_grammars(self, brand: str, model: str, qualifier: str) -> list[str]:
        """Ids of every grammar that accepts this qualifier for this model (more than one = overlapping rules)."""
        return [g.id for g in self._grammars.get(brand, ()) if g.accepts(model, qualifier)]

    def has_grammar(self, brand: str, model: str) -> bool:
        """True if a model-specific (non-wildcard) grammar covers this model."""
        return any(model in g.models for g in self._grammars.get(brand, ()) if not g.wildcard)

    def model_keys(self, brand: str) -> dict[str, str]:
        return dict(self._keys[brand])

    def grammar_ids(self) -> list[str]:
        return [g.id for gl in self._grammars.values() for g in gl]

    # -- dataset-level utilities -----------------------------------------------------------
    def split_dataset_rows(self, brand: str, selected_model: str, rows: list[dict], name_key: str = "name"):
        """Partition dataset rows (dicts carrying `name`) for one selected model.
        -> (accepted_rows, excluded) where excluded is {reason: [row,...]}."""
        sel = self.canonical_model(brand, selected_model)
        accepted, excluded = [], defaultdict(list)
        for row in rows:
            r = self.resolve(brand, row[name_key])
            row = dict(row)
            row["_boundary"] = {"status": r.status, "resolved_model": r.model, "qualifier": r.qualifier, "flags": r.flags}
            if sel is not None and r.accepted and r.model == sel:
                accepted.append(row)
            elif r.accepted:
                excluded[f"belongs_to:{r.model}"].append(row)
            else:
                excluded[r.status + (f":{r.model}" if r.model else "")].append(row)
        return accepted, dict(excluded)


def legacy_family_match(dataset_name: str, family: str) -> bool:
    """The OLD app-mirroring rule (catalog_audit_readonly.name_matches_family) - kept only to measure contamination."""
    dn, fl = dataset_name.strip().lower(), family.strip().lower()
    if not dn or not fl:
        return False
    return dn == fl or dn.startswith(fl + " ") or dn.split()[0] == fl


def collision_report(idx: ModelIndex, ds: dict) -> dict:
    """For every catalog prefix pair (short, long): how many dataset names the OLD rule would give to `short`
    that actually belong to `long`, and how the new resolver treats them. Also counts quarantined qualifiers."""
    brands = {b["id"]: b["name"] for b in ds["brands"]}
    names_by_brand: dict[str, list[str]] = defaultdict(list)
    for m in ds["models"]:
        names_by_brand[brands[m["brand_id"]]].append(m["name"])
    pairs = []
    old_contaminated_total = 0
    for b, short, long_ in idx.prefix_pairs():
        names = names_by_brand.get(b, [])
        # only report the pair if the old rule could make `short` swallow `long`'s dataset rows
        swallowed = [n for n in names if legacy_family_match(n, short) and idx.resolve(b, n).model == long_ and idx.resolve(b, n).accepted]
        old_contaminated_total += len(swallowed)
        pairs.append(
            {
                "brand": b,
                "shorter_model": short,
                "longer_model": long_,
                "dataset_rows_old_rule_gives_to_shorter_but_belong_to_longer": len(swallowed),
                "examples": swallowed[:3],
            }
        )
    quarantined = defaultdict(Counter)
    for b, names in names_by_brand.items():
        for n in names:
            r = idx.resolve(b, n)
            if r.status in ("ambiguous_qualifier", "distinct_vehicle_qualifier"):
                quarantined[(b, r.model)][r.qualifier] += 1
    watch_flags = []
    for b, names in names_by_brand.items():
        for n in names:
            r = idx.resolve(b, n)
            for f in r.flags:
                if f.startswith("qualifier_overlaps_other_model"):
                    watch_flags.append({"brand": b, "dataset_name": n, "resolved_model": r.model, "flag": f})
    return {
        "schema_version": "carnet.model_collisions/1",
        "catalog_prefix_pair_count": len(pairs),
        "pairs_where_old_rule_contaminates": sum(1 for p in pairs if p["dataset_rows_old_rule_gives_to_shorter_but_belong_to_longer"]),
        "dataset_rows_contaminating_shorter_models_under_old_rule": old_contaminated_total,
        "pairs": pairs,
        "quarantined_qualifiers": [
            {"brand": b, "model": m, "qualifiers": dict(c.most_common()), "rows": sum(c.values())}
            for (b, m), c in sorted(quarantined.items(), key=lambda kv: (-sum(kv[1].values()), kv[0]))
        ],
        "qualifier_overlaps_other_model": watch_flags[:50],
        "qualifier_overlaps_other_model_count": len(watch_flags),
    }


def load_index(use_suffix_rules: bool = True) -> tuple[ModelIndex, dict, dict]:
    cat = json.loads((REPO / "assets" / "car_catalog.json").read_text(encoding="utf-8"))
    ds = json.loads((REPO / "assets" / "car_spec_dataset.json").read_text(encoding="utf-8"))
    return ModelIndex(cat, use_suffix_rules=use_suffix_rules, strict_suffix_rules=True), cat, ds


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    if not argv or argv[0] not in ("report", "resolve"):
        print(__doc__)
        return 2
    idx, _cat, ds = load_index()
    if argv[0] == "resolve":
        r = idx.resolve(argv[1], argv[2])
        print(json.dumps(r.__dict__, indent=2, ensure_ascii=False))
        return 0
    sys.path.insert(0, str(HERE))
    from enrichment_lib import write_json  # refuses to write under assets/ or lib/

    rep = collision_report(idx, ds)
    out = HERE / "reports" / "model_collisions.json"
    write_json(out, rep)
    print(f"wrote {out.relative_to(REPO)}  pairs={rep['catalog_prefix_pair_count']}  contaminating_pairs={rep['pairs_where_old_rule_contaminates']}  rows={rep['dataset_rows_contaminating_shorter_models_under_old_rule']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
