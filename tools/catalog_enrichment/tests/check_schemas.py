"""Validate evidence / union / comparison files against schemas/ (needs `pip install jsonschema`)."""
import json
import sys
from pathlib import Path

import jsonschema

H = Path(__file__).resolve().parents[1]
pairs = [
    ("evidence_record.schema.json", sorted((H / "evidence").glob("*.json"))),
    ("model_union.schema.json", sorted((H / "generated").glob("*.union.json"))),
    ("pilot_comparison.schema.json", [H / "reports" / "pilot_comparison.json"]),
]
bad = 0
for sch, files in pairs:
    schema = json.loads((H / "schemas" / sch).read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator.check_schema(schema)
    v = jsonschema.Draft202012Validator(schema)
    for f in files:
        errs = sorted(v.iter_errors(json.loads(f.read_text(encoding="utf-8"))), key=lambda e: list(e.path))
        print(f"{f.name}: {'OK' if not errs else str(len(errs)) + ' errors'}")
        for e in errs[:8]:
            print("   ", "/".join(map(str, e.path)), "->", e.message[:160])
        bad += bool(errs)
sys.exit(1 if bad else 0)
