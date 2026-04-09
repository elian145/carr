#!/usr/bin/env python3
"""
Car2DB coverage tester for marketplace inputs.

Usage (PowerShell example):
  $env:CAR2DB_API_KEY="your_test_key"
  python tools/car2db_coverage_test.py `
    --input tools/data/car2db_test_sample.csv `
    --endpoint "https://car2db.com/api/v1/search" `
    --query-param "query" `
    --query-format "{year} {make} {model} {trim}" `
    --output-dir tools/out/car2db_test

Input CSV must contain headers:
  year,make,model,trim
Optional:
  market_origin
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlencode, urlparse, urlunparse, parse_qsl
from urllib.request import Request, urlopen


MANDATORY_FIELDS = (
    "engine_size_liters",
    "cylinders",
    "transmission",
    "seating",
)


@dataclass
class RowResult:
    row_index: int
    input_year: str
    input_make: str
    input_model: str
    input_trim: str
    status: str
    reason: str
    match_score: int
    matched_make: str
    matched_model: str
    matched_trim: str
    matched_year: str
    engine_size_liters: str
    cylinders: str
    transmission: str
    seating: str
    drive_type: str
    body_type: str
    raw_match_snippet: str


def _normalize(s: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def _words(s: str) -> set[str]:
    n = _normalize(s)
    return set(w for w in n.split(" ") if w)


def _score_text(query: str, candidate: str) -> int:
    q = _normalize(query)
    c = _normalize(candidate)
    if not q or not c:
        return 0
    if q == c:
        return 130
    score = 0
    if c.startswith(q):
        score += 90
    if q in c:
        score += 70
    if c in q:
        score += 50
    qw = _words(q)
    cw = _words(c)
    overlap = len(qw & cw)
    if qw:
        coverage = overlap / len(qw)
    else:
        coverage = 0
    score += overlap * 12 + int(coverage * 30)
    return score


def _best_value(obj: Any, aliases: Iterable[str]) -> str:
    """
    Recursively search JSON for first matching key alias (case-insensitive).
    """
    alias_set = {_normalize(a) for a in aliases}
    queue = [obj]
    while queue:
        cur = queue.pop(0)
        if isinstance(cur, dict):
            for k, v in cur.items():
                if _normalize(str(k)) in alias_set:
                    if v is None:
                        continue
                    return str(v).strip()
                if isinstance(v, (dict, list)):
                    queue.append(v)
        elif isinstance(cur, list):
            queue.extend(cur)
    return ""


def _candidate_rows(payload: Any) -> list[dict[str, Any]]:
    """
    Try to locate result rows in common response shapes.
    """
    if isinstance(payload, list):
        return [x for x in payload if isinstance(x, dict)]
    if isinstance(payload, dict):
        for key in (
            "results",
            "items",
            "data",
            "cars",
            "vehicles",
            "rows",
            "matches",
        ):
            v = payload.get(key)
            if isinstance(v, list):
                return [x for x in v if isinstance(x, dict)]
        # Single vehicle object fallback
        if any(k in payload for k in ("make", "model", "trim", "year")):
            return [payload]
    return []


def _pick_best_candidate(rows: list[dict[str, Any]], year: str, make: str, model: str, trim: str):
    best = None
    best_score = -1
    for row in rows:
        mk = _best_value(row, ("make", "brand", "manufacturer"))
        md = _best_value(row, ("model", "model_name"))
        tr = _best_value(row, ("trim", "series", "variant", "submodel", "grade"))
        yr = _best_value(row, ("year", "model_year", "year_from"))
        display = " ".join(p for p in (yr, mk, md, tr) if p)

        score = 0
        score += _score_text(make, mk) * 3
        score += _score_text(model, md) * 3
        score += _score_text(trim, tr if tr else display) * 2
        if yr and year and year == yr:
            score += 40
        elif yr and year:
            y1 = int(re.sub(r"\D", "", year) or 0)
            y2 = int(re.sub(r"\D", "", yr) or 0)
            if y1 and y2 and abs(y1 - y2) <= 1:
                score += 15

        if score > best_score:
            best = row
            best_score = score

    return best, best_score


def _build_request_url(endpoint: str, query_param: str, query_value: str) -> str:
    parsed = urlparse(endpoint)
    params = dict(parse_qsl(parsed.query))
    params[query_param] = query_value
    return urlunparse(
        (
            parsed.scheme,
            parsed.netloc,
            parsed.path,
            parsed.params,
            urlencode(params),
            parsed.fragment,
        )
    )


def _http_get_json(url: str, headers: dict[str, str], timeout_sec: int) -> Any:
    req = Request(url=url, method="GET", headers=headers)
    with urlopen(req, timeout=timeout_sec) as resp:
        raw = resp.read().decode("utf-8", errors="replace")
        return json.loads(raw)


def _extract_specs(row: dict[str, Any]) -> dict[str, str]:
    engine_cc = _best_value(
        row,
        (
            "capacityCm3",
            "engine_capacity_cc",
            "displacement_cc",
            "engine_displacement_cc",
            "capacity_cc",
        ),
    )
    engine_l = _best_value(
        row,
        (
            "displacementL",
            "engine_size_l",
            "engine_size_liters",
            "engine_capacity_l",
            "capacity_l",
        ),
    )
    liters = ""
    if engine_l:
        m = re.search(r"\d+(?:\.\d+)?", engine_l)
        liters = m.group(0) if m else ""
    elif engine_cc:
        m = re.search(r"\d+(?:\.\d+)?", engine_cc)
        if m:
            liters = f"{(float(m.group(0)) / 1000.0):.1f}"

    cylinders = _best_value(
        row,
        ("numberOfCylinders", "cylinders", "engine_cylinders", "cylinder_count"),
    )
    if cylinders:
        m = re.search(r"\d+", cylinders)
        cylinders = m.group(0) if m else cylinders

    transmission = _best_value(
        row,
        ("transmission", "transmission_style", "gearbox", "transmission_type"),
    )
    seating = _best_value(row, ("numberOfSeats", "seating", "seats", "seating_capacity"))
    if seating:
        m = re.search(r"\d+", seating)
        seating = m.group(0) if m else seating
    drive_type = _best_value(row, ("driveWheels", "drive_type", "drivetrain"))
    body_type = _best_value(row, ("bodyType", "body_type"))
    return {
        "engine_size_liters": liters,
        "cylinders": cylinders,
        "transmission": transmission.strip(),
        "seating": seating,
        "drive_type": drive_type.strip(),
        "body_type": body_type.strip(),
    }


def _status_for(match_score: int, specs: dict[str, str], make: str, model: str, row: dict[str, Any]) -> tuple[str, str]:
    mk = _best_value(row, ("make", "brand"))
    md = _best_value(row, ("model",))
    make_ok = _score_text(make, mk) >= 80
    model_ok = _score_text(model, md) >= 70
    mandatory_present = all((specs[k] or "").strip() for k in MANDATORY_FIELDS)

    if not make_ok or not model_ok or match_score < 120:
        return "wrong", "Low-confidence match"
    if mandatory_present:
        return "exact", "Exact/high-confidence with mandatory fields"
    if any((specs[k] or "").strip() for k in specs):
        return "partial", "Match found but missing mandatory fields"
    return "not_found", "No usable spec fields found"


def run(args: argparse.Namespace) -> int:
    api_key = os.environ.get("CAR2DB_API_KEY", "").strip()
    if not api_key:
        print("ERROR: set CAR2DB_API_KEY in environment", file=sys.stderr)
        return 2

    input_path = Path(args.input)
    if not input_path.exists():
        print(f"ERROR: input CSV not found: {input_path}", file=sys.stderr)
        return 2

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    headers = {
        args.api_key_header: api_key,
        "Accept": "application/json",
        "User-Agent": "car2db-coverage-test/1.0",
    }

    results: list[RowResult] = []

    with input_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        required = {"year", "make", "model", "trim"}
        missing_cols = required - set((reader.fieldnames or []))
        if missing_cols:
            print(f"ERROR: missing CSV columns: {sorted(missing_cols)}", file=sys.stderr)
            return 2

        for i, row in enumerate(reader, start=1):
            year = (row.get("year") or "").strip()
            make = (row.get("make") or "").strip()
            model = (row.get("model") or "").strip()
            trim = (row.get("trim") or "").strip()
            if not (year and make and model and trim):
                results.append(
                    RowResult(
                        row_index=i,
                        input_year=year,
                        input_make=make,
                        input_model=model,
                        input_trim=trim,
                        status="not_found",
                        reason="Missing required input values",
                        match_score=0,
                        matched_make="",
                        matched_model="",
                        matched_trim="",
                        matched_year="",
                        engine_size_liters="",
                        cylinders="",
                        transmission="",
                        seating="",
                        drive_type="",
                        body_type="",
                        raw_match_snippet="",
                    )
                )
                continue

            query = args.query_format.format(year=year, make=make, model=model, trim=trim)
            url = _build_request_url(args.endpoint, args.query_param, query)

            try:
                payload = _http_get_json(url, headers, args.timeout_sec)
                rows = _candidate_rows(payload)
                if not rows:
                    raise ValueError("No candidate rows in response")
                best, score = _pick_best_candidate(rows, year, make, model, trim)
                if not best:
                    raise ValueError("No best match candidate")
                specs = _extract_specs(best)
                status, reason = _status_for(score, specs, make, model, best)
                results.append(
                    RowResult(
                        row_index=i,
                        input_year=year,
                        input_make=make,
                        input_model=model,
                        input_trim=trim,
                        status=status,
                        reason=reason,
                        match_score=score,
                        matched_make=_best_value(best, ("make", "brand")),
                        matched_model=_best_value(best, ("model",)),
                        matched_trim=_best_value(best, ("trim", "series", "variant")),
                        matched_year=_best_value(best, ("year", "model_year")),
                        engine_size_liters=specs["engine_size_liters"],
                        cylinders=specs["cylinders"],
                        transmission=specs["transmission"],
                        seating=specs["seating"],
                        drive_type=specs["drive_type"],
                        body_type=specs["body_type"],
                        raw_match_snippet=json.dumps(best, ensure_ascii=False)[:700],
                    )
                )
            except Exception as exc:
                results.append(
                    RowResult(
                        row_index=i,
                        input_year=year,
                        input_make=make,
                        input_model=model,
                        input_trim=trim,
                        status="not_found",
                        reason=f"API error: {exc}",
                        match_score=0,
                        matched_make="",
                        matched_model="",
                        matched_trim="",
                        matched_year="",
                        engine_size_liters="",
                        cylinders="",
                        transmission="",
                        seating="",
                        drive_type="",
                        body_type="",
                        raw_match_snippet="",
                    )
                )

            if args.delay_ms > 0:
                time.sleep(args.delay_ms / 1000.0)

    counts = {"exact": 0, "partial": 0, "wrong": 0, "not_found": 0}
    for r in results:
        counts[r.status] = counts.get(r.status, 0) + 1
    total = len(results) or 1
    summary = {
        "total": len(results),
        "exact": counts["exact"],
        "partial": counts["partial"],
        "wrong": counts["wrong"],
        "not_found": counts["not_found"],
        "exact_rate": round(counts["exact"] / total, 4),
        "wrong_rate": round(counts["wrong"] / total, 4),
    }

    report_csv = out_dir / "coverage_report.csv"
    with report_csv.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=list(RowResult.__dataclass_fields__.keys()),
        )
        writer.writeheader()
        for r in results:
            writer.writerow(r.__dict__)

    report_json = out_dir / "summary.json"
    report_json.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(json.dumps(summary, indent=2))
    print(f"\nWrote:\n- {report_csv}\n- {report_json}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Run Car2DB coverage test from CSV.")
    p.add_argument("--input", required=True, help="Path to input CSV.")
    p.add_argument("--endpoint", required=True, help="Search endpoint URL.")
    p.add_argument("--query-param", default="query", help="Query parameter name.")
    p.add_argument(
        "--query-format",
        default="{year} {make} {model} {trim}",
        help="Template for search query string.",
    )
    p.add_argument(
        "--api-key-header",
        default="x-api-key",
        help="Header name for API key.",
    )
    p.add_argument(
        "--output-dir",
        default="tools/out/car2db_test",
        help="Output directory for reports.",
    )
    p.add_argument("--timeout-sec", type=int, default=20)
    p.add_argument(
        "--delay-ms",
        type=int,
        default=250,
        help="Delay between requests to avoid rate-limit bursts.",
    )
    return p


if __name__ == "__main__":
    parser = build_parser()
    sys.exit(run(parser.parse_args()))
