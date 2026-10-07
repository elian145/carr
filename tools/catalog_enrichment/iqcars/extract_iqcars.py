#!/usr/bin/env python3
"""Read-only IQ Cars catalog extractor (RAW stage). Writes only under tools/catalog_enrichment/iqcars/raw/.

Never touches assets/, lib/ or any CarNet production file.

Data sources (all unauthenticated `publicCar/...` GETs that the official app issues in normal use):
  initial_data     1 request  -> FilterConfig.Brands[].Models[].ModelSFXes[]   (brand -> model -> trims, with IQ IDs + year ranges)
  cylinder_engine  1 / model  -> {Cylinders[], Engines[], Specifications[]}    (MODEL-LEVEL option lists)
  brand_new_cars   1 + 1/entry-> exact trim -> engine -> cylinder rows for ~56 curated new cars only

Commands (run from anywhere):
  sample   --brand Toyota --model "Land Cruiser"   small, safe: 1 cached initial_data + 1 model request
  bulk     --confirm-bulk [--brands Toyota,Kia] [--limit N] [--delay 1.5]     one request per model, cache-first, resumable
  new-cars --confirm-bulk [--delay 1.5]                                       curated brand-new-car catalog (~57 requests)
  assemble                                                                    offline: raw/cache -> raw/iqcars_catalog.json

Exit codes: 0 ok, 2 usage/not found, 3 server pushed back (401/403/429/5xx/network) -> stopped, re-run later to resume.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from canonical_io import NEWLINE, write_text_canonical  # noqa: E402
from iqcars_client import BASE_URL, ENDPOINTS, IqCarsClient, StopRequested  # noqa: E402

RAW_DIR = HERE / "raw"
CACHE_DIR = RAW_DIR / "cache"
SAMPLES_DIR = RAW_DIR / "samples"
CATALOG_PATH = RAW_DIR / "iqcars_catalog.json"
LANG = "en"  # one response carries en/ar/ku names for every entity


def _write_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    write_text_canonical(path, json.dumps(obj, ensure_ascii=False, indent=1) + "\n")


def _brands(client: IqCarsClient) -> list[dict]:
    data, cached = client.get("initial_data", lang=LANG)
    print(f"initial_data: {'cache' if cached else 'network'}")
    return data["FilterConfig"]["Brands"]


def _slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", s.casefold()).strip("_")


def _cyl_engine_summary(resp: dict) -> dict:
    """RAW: the complete response exactly as returned (all keys, original order). Nothing is dropped or cleaned."""
    return resp


def cmd_sample(args) -> int:
    client = IqCarsClient(CACHE_DIR, delay_s=args.delay, max_requests=5)
    brands = _brands(client)
    b = next((x for x in brands if x["BrandNameen"].casefold() == args.brand.casefold()), None)
    if not b:
        print(f"brand not found: {args.brand}")
        return 2
    m = next((x for x in b["Models"] if x["ModelNameen"].casefold() == args.model.casefold()), None)
    if not m:
        print(f"model not found under {b['BrandNameen']}: {args.model}")
        return 2
    resp, cached = client.get("cylinder_engine", model_id=m["ID"])
    print(f"cylinder_engine ModelId={m['ID']}: {'cache' if cached else 'network'}")
    sample = {
        "_meta": {
            "note": "RAW, unnormalized. Values are exactly as returned (including stray whitespace/case).",
            "initial_data_endpoint": BASE_URL + ENDPOINTS["initial_data"][0].format(lang=LANG),
            "cylinder_engine_endpoint": BASE_URL + ENDPOINTS["cylinder_engine"][0].format(model_id=m["ID"]),
            "captured_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        },
        "brand": {k: b[k] for k in ("ID", "BrandNameen", "BrandNamear", "BrandNameku")},
        "model": m,  # verbatim, includes ModelSFXes (trims)
        "cylinder_engine": _cyl_engine_summary(resp),
    }
    out = SAMPLES_DIR / f"{_slug(b['BrandNameen'])}_{_slug(m['ModelNameen'])}.raw.json"
    _write_json(out, sample)
    print(f"wrote {out}")
    return 0


def cmd_bulk(args) -> int:
    if not args.confirm_bulk:
        print("refusing: bulk needs --confirm-bulk (one request per model; see README for pacing).")
        return 2
    client = IqCarsClient(CACHE_DIR, delay_s=args.delay, max_requests=args.max_requests)
    brands = _brands(client)
    wanted = {x.strip().casefold() for x in args.brands.split(",")} if args.brands else None
    todo = [(b, m) for b in brands if not wanted or b["BrandNameen"].casefold() in wanted for m in (b.get("Models") or [])]
    if args.limit:
        todo = todo[: args.limit]
    pending = [m["ID"] for _, m in todo if not (CACHE_DIR / ENDPOINTS["cylinder_engine"][1].format(model_id=m["ID"])).exists()]
    print(f"models in scope: {len(todo)}; already cached: {len(todo) - len(pending)}; to fetch: {len(pending)}; "
          f"est. time at {client.delay_s:.1f}s/req: {len(pending) * client.delay_s / 60:.1f} min")
    t0, done = time.monotonic(), 0
    started = datetime.now(timezone.utc)
    stopped, stop_reason = False, None
    try:
        for b, m in todo:
            _, cached = client.get("cylinder_engine", model_id=m["ID"])
            if not cached:
                done += 1
                if done % 50 == 0:
                    print(f"  fetched {done}/{len(pending)}  ({b['BrandNameen']} / {m['ModelNameen']})", flush=True)
    except StopRequested as e:
        stopped, stop_reason = True, str(e)
        print(f"STOPPED: {e}")
    still = [m["ID"] for _, m in todo if not (CACHE_DIR / ENDPOINTS["cylinder_engine"][1].format(model_id=m["ID"])).exists()]
    _record_run("bulk_used_car_cylinder_engine", started, client, models_in_scope=len(todo), models_pending_at_start=len(pending),
                skipped_models_not_fetched=still, stopped=stopped, stop_reason=stop_reason, delay_s=client.delay_s)
    print(f"{'STOPPED' if stopped else 'done'}. fetched this run: {done}; cache hits: {client.cache_hits}; "
          f"not fetched: {len(still)}; elapsed {time.monotonic() - t0:.0f}s")
    return 3 if stopped else 0


def _record_run(kind: str, started: datetime, client: IqCarsClient, **extra) -> None:
    rec = {"run": kind, "start_utc": started.isoformat(timespec="seconds"),
           "end_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "duration_s": round((datetime.now(timezone.utc) - started).total_seconds(), 1), **client.stats(), **extra}
    with open(RAW_DIR / "run_summaries.jsonl", "a", encoding="utf-8", newline=NEWLINE) as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def cmd_new_cars(args) -> int:
    if not args.confirm_bulk:
        print("refusing: new-cars needs --confirm-bulk (~57 requests).")
        return 2
    client = IqCarsClient(CACHE_DIR, delay_s=args.delay, max_requests=args.max_requests)
    t0, done = time.monotonic(), 0
    started = datetime.now(timezone.utc)
    stopped, stop_reason, ids = False, None, []
    try:
        lst, _ = client.get("brand_new_cars", location_id=0)
        ids = sorted({e["ID"] for key in ("BrandNewCars", "Brands") for e in (lst.get(key) or [])})
        print(f"brand-new entries: {len(ids)}")
        for i in ids:
            _, cached = client.get("brand_new_sfxes", bnc_id=i)
            done += 0 if cached else 1
    except StopRequested as e:
        stopped, stop_reason = True, str(e)
        print(f"STOPPED: {e}")
    still = [i for i in ids if not (CACHE_DIR / ENDPOINTS["brand_new_sfxes"][1].format(bnc_id=i)).exists()]
    _record_run("brand_new_catalog", started, client, entries_in_scope=len(ids), skipped_entries_not_fetched=still,
                stopped=stopped, stop_reason=stop_reason, delay_s=client.delay_s)
    print(f"{'STOPPED' if stopped else 'done'}. fetched this run: {done}; elapsed {time.monotonic() - t0:.0f}s")
    return 3 if stopped else 0


def _read_runs() -> list[dict]:
    p = RAW_DIR / "run_summaries.jsonl"
    if not p.exists():
        return []
    return [json.loads(line) for line in p.read_text(encoding="utf-8").splitlines() if line.strip()]


def cmd_assemble(_args) -> int:
    """Offline: build raw/iqcars_catalog.json strictly from raw/cache (no network)."""
    client = IqCarsClient(CACHE_DIR, offline=True)
    brands = _brands(client)
    cyl: dict[str, dict] = {}
    missing: list[int] = []
    for b in brands:
        for m in b.get("Models") or []:
            f = CACHE_DIR / ENDPOINTS["cylinder_engine"][1].format(model_id=m["ID"])
            if f.exists():
                cyl[str(m["ID"])] = _cyl_engine_summary(json.loads(f.read_text(encoding="utf-8")))
            else:
                missing.append(m["ID"])
    bnc_entries, bnc_sfx = {}, {}
    lst_f = CACHE_DIR / ENDPOINTS["brand_new_cars"][1].format(location_id=0)
    if lst_f.exists():
        lst = json.loads(lst_f.read_text(encoding="utf-8"))
        for key in ("BrandNewCars", "Brands"):
            for e in lst.get(key) or []:
                bnc_entries[str(e["ID"])] = e
        for i in bnc_entries:
            f = CACHE_DIR / ENDPOINTS["brand_new_sfxes"][1].format(bnc_id=i)
            if f.exists():
                bnc_sfx[i] = json.loads(f.read_text(encoding="utf-8")).get("BrandNewCarSFXes")
    catalog = {
        "_meta": {
            "source": "IQ Cars public catalog endpoints (cp.iqcars.net/api), same calls the Android app makes",
            "app_package": "com.redfoxpro.iqcars",
            "assembled_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "assembled_from": "raw/cache (verbatim responses; no network used by this command)",
            "endpoints": {k: BASE_URL + v[0] for k, v in ENDPOINTS.items()},
            "counts": {
                "brands": len(brands),
                "models": sum(len(b.get("Models") or []) for b in brands),
                "models_with_cylinder_engine_response": len(cyl),
                "models_without_cylinder_engine_response": len(missing),
                "brand_new_car_entries": len(bnc_entries),
                "brand_new_car_entries_with_sfxes": sum(1 for v in bnc_sfx.values() if v),
            },
            "models_without_cylinder_engine_response": missing,
            "extraction_runs": _read_runs(),
            "notes": [
                "RAW artifact: nothing is cleaned. initial_data brands/models/ModelSFXes are verbatim.",
                "cylinder_engine_by_model_id holds each complete response verbatim (Cylinders, Engines, SeatNumbers, "
                "Specifications, in original order). Used-car lists are MODEL-LEVEL and independent: no trim/engine/cylinder links.",
                "brand_new_cars holds the curated brand-new-car records verbatim; its rows are the only source of exact "
                "trim->engine->cylinder links and are kept separate.",
            ],
        },
        "initial_data_brands": brands,
        "cylinder_engine_by_model_id": cyl,
        "brand_new_cars": {"entries_by_id": bnc_entries, "sfxes_by_brand_new_car_id": bnc_sfx},
    }
    _write_json(CATALOG_PATH, catalog)
    print(f"wrote {CATALOG_PATH}")
    print(json.dumps(catalog["_meta"]["counts"], indent=1))
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sample")
    s.add_argument("--brand", required=True)
    s.add_argument("--model", required=True)
    s.add_argument("--delay", type=float, default=1.5)
    s.set_defaults(fn=cmd_sample)
    for name, fn in (("bulk", cmd_bulk), ("new-cars", cmd_new_cars)):
        b = sub.add_parser(name)
        b.add_argument("--confirm-bulk", action="store_true")
        b.add_argument("--delay", type=float, default=1.5)
        b.add_argument("--max-requests", type=int, default=3000)
        if name == "bulk":
            b.add_argument("--brands", default="", help="comma-separated brand names (default: all)")
            b.add_argument("--limit", type=int, default=0)
        b.set_defaults(fn=fn)
    a = sub.add_parser("assemble")
    a.set_defaults(fn=cmd_assemble)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
