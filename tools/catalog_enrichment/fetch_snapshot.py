#!/usr/bin/env python3
"""Re-fetch evidence sources, preserve the retrieved content and re-validate the EXISTING quotes against it.

Tooling only (never writes under assets/ or lib/). One explicit URL per source - no crawling, no search.

  python tools/catalog_enrichment/fetch_snapshot.py --evidence evidence/ford_everest.json               # sources not yet verified
  python tools/catalog_enrichment/fetch_snapshot.py --evidence evidence/ford_everest.json --source FE-S2 --force
  python tools/catalog_enrichment/fetch_snapshot.py --evidence evidence/toyota_camry.json --dry-run     # fetch + classify, write nothing

For every selected source the tool
  1. GETs the source URL (browser-like headers, redirects followed, size/time limits),
  2. extracts text deterministically (PDF -> pypdf, HTML -> html-text/1),
  3. preserves the extracted text as <evidence dir>/_source_text/<SOURCE_ID>.txt and records its sha256,
  4. checks every EXISTING supporting_text segment of the records citing the source against that preserved text.

Outcome per source (rules/source_rules.json -> evidence_integrity.revalidation):
  all quotes found            -> FULL_TEXT_VERIFIED / PDF_VERIFIED
  some quotes missing         -> verified state + integrity.unconfirmed_record_ids (those records never verify; reported)
  no quote found              -> RETRIEVED_UNVERIFIABLE (current content no longer supports the citation; nothing is preserved)
  not retrievable / no text   -> UNAVAILABLE
Authored quotes, record ids, model identity and source URLs are NEVER edited. Existing verified+matching sources are skipped
unless --force. The validators (enrichment_lib.verify_snapshots) stay strict: this tool cannot make a value VERIFIED by itself.
"""
from __future__ import annotations

import argparse
import copy
import datetime as _dt
import hashlib
import io
import json
import re
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import enrichment_lib as L  # noqa: E402

FETCHER = "fetch_snapshot.py/1"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 CarNetEnrichmentFetcher/1"
MAX_BYTES = 60_000_000
MIN_TEXT_CHARS = 200
EXTRACTOR_HTML = "html-text/1"


# ----------------------------------------------------------------------------------------------------------------
# fetching + deterministic text extraction
# ----------------------------------------------------------------------------------------------------------------
def fetch(url: str, timeout: int = 45) -> dict:
    """-> {ok, status, final_url, content_type, raw, error}. Never raises."""
    import requests

    out = {"ok": False, "status": None, "final_url": None, "content_type": None, "raw": b"", "error": None}
    try:
        r = requests.get(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/pdf,*/*;q=0.8", "Accept-Language": "en"}, timeout=timeout, stream=True, allow_redirects=True)
        out.update(status=r.status_code, final_url=r.url, content_type=(r.headers.get("Content-Type") or "").split(";")[0].strip().lower() or None)
        if r.status_code != 200:
            out["error"] = f"HTTP {r.status_code}"
            return out
        chunks, n = [], 0
        for chunk in r.iter_content(65536):
            n += len(chunk)
            if n > MAX_BYTES:
                out["error"] = f"response larger than {MAX_BYTES} bytes"
                return out
            chunks.append(chunk)
        out["raw"] = b"".join(chunks)
        out["ok"] = True
    except Exception as e:  # network errors are an outcome, not a crash
        out["error"] = f"{type(e).__name__}: {str(e)[:160]}"
    return out


_BLOCK = {
    "p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "header", "footer", "nav", "main", "aside", "form",
    "table", "thead", "tbody", "tfoot", "br", "hr", "blockquote", "pre", "figure", "figcaption", "dl", "dt", "dd", "details", "summary", "fieldset", "address",
}
_SKIP = {"script", "style", "noscript", "template", "svg", "head", "iframe"}


def html_to_text(raw: bytes) -> str:
    """Visible text, block elements on separate lines, table rows as '| a | b |', numeric footnote <sup> spaced out."""
    from bs4 import BeautifulSoup, Comment, NavigableString, Tag

    soup = BeautifulSoup(raw, "html.parser")

    def flat(node) -> str:
        parts: list[str] = []
        walk(node, parts)
        return " ".join("".join(parts).split())

    def walk(node, out: list[str]):
        for ch in node.children:
            if isinstance(ch, Comment):
                continue
            if isinstance(ch, NavigableString):
                out.append(str(ch))
            elif isinstance(ch, Tag):
                n = ch.name
                if n in _SKIP:
                    continue
                if n == "tr":
                    cells = [flat(c) for c in ch.find_all(["td", "th"], recursive=False)]
                    if any(cells):
                        out.append("\n| " + " | ".join(cells) + " |\n")
                elif n == "sup":
                    t = flat(ch)
                    out.append(f" {t} " if t.isdigit() else t)
                elif n in _BLOCK:
                    out.append("\n")
                    walk(ch, out)
                    out.append("\n")
                else:
                    walk(ch, out)

    parts: list[str] = []
    title = soup.find("title")
    if title and title.get_text().strip():
        parts.append(" ".join(title.get_text().split()) + "\n")
    walk(soup.body or soup, parts)
    lines = [" ".join(ln.split()) for ln in "".join(parts).split("\n")]
    return "\n".join(ln for ln in lines if ln)


def pdf_to_text(raw: bytes) -> tuple[str, str]:
    import pypdf

    reader = pypdf.PdfReader(io.BytesIO(raw))
    if reader.is_encrypted:
        reader.decrypt("")
    pages = [(p.extract_text() or "") for p in reader.pages]
    return "\n".join(pages), f"pypdf/{pypdf.__version__}"


def extract(raw: bytes, content_type: str | None, url: str) -> tuple[str, str, bool]:
    """-> (text, extractor, is_pdf). Raises on undecodable input (caller treats as UNAVAILABLE)."""
    if raw[:5] == b"%PDF-" or (content_type or "") == "application/pdf":
        text, name = pdf_to_text(raw)
        return text, name, True
    return html_to_text(raw), EXTRACTOR_HTML, False


# ----------------------------------------------------------------------------------------------------------------
# classification (pure: testable without a network)
# ----------------------------------------------------------------------------------------------------------------
def _sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def snapshot_bytes(text: str) -> bytes:
    return (text.rstrip("\n") + "\n").encode("utf-8")


def _fold(t: str) -> str:
    t = unicodedata.normalize("NFKC", t)
    for a, b in (("\u2019", "'"), ("\u2018", "'"), ("\u201c", '"'), ("\u201d", '"'), ("\u2013", "-"), ("\u2014", "-")):
        t = t.replace(a, b)
    return " ".join(t.casefold().split())


def _alnum(t: str) -> str:
    return re.sub(r"[\W_]+", "", unicodedata.normalize("NFKC", t).casefold())


def _diagnose(segments: list[str], norm_text: str) -> str:
    """Why a quote is not in the snapshot. DIAGNOSTIC ONLY: nothing is ever verified on the strength of this.
    typographic_or_case_only = would match after folding quotes/dashes/case; punctuation_or_layout_only = would match
    ignoring every non-alphanumeric character; not_found_verbatim = the cited text is not in the retrieved content verbatim (the page changed, or the original quote was reflowed / paraphrased / taken from a different extraction)."""
    f, a = _fold(norm_text), _alnum(norm_text)
    if all(_fold(g) in f for g in segments):
        return "typographic_or_case_only"
    if all(_alnum(g) in a for g in segments):
        return "punctuation_or_layout_only"
    return "not_found_verbatim"


def classify_source(doc: dict, sid: str, result: dict, now: str, snapshot_dir: Path, root: Path = HERE, origin: str | None = None) -> tuple[dict, dict, bytes | None, dict]:
    """-> (new integrity block, new source fields, snapshot bytes or None, review entry).

    Never edits records. `result` is the dict returned by fetch().
    `origin` (default None -> the revalidation origins) is used for sources AUTHORED in this run (new research: the snapshot is
    created at authoring time, there is no earlier state to re-validate); pass 'authored'."""
    s = doc["sources"][sid]
    prev = L.source_integrity_state(s)
    recs = [r for r in doc["records"] if r["evidence"]["source_id"] == sid]
    base = {"retrieved_at": now, "retrieved_by": FETCHER, "final_url": result.get("final_url"), "http_status": result.get("status"), "content_type": result.get("content_type"), "previous_state": prev}
    entry = {
        "source_id": sid, "url": s["url"], "tier": s["tier"], "previous_state": prev, "http_status": result.get("status"), "final_url": result.get("final_url"),
        "content_type": result.get("content_type"), "records_total": len(recs), "records_confirmed": 0, "records_unconfirmed": [], "error": result.get("error"),
    }
    text, extractor, is_pdf, err = "", None, False, result.get("error")
    if result.get("ok"):
        try:
            text, extractor, is_pdf = extract(result["raw"], result.get("content_type"), s["url"])
        except Exception as e:
            err = f"text extraction failed: {type(e).__name__}: {str(e)[:120]}"
        if err is None and len(text.strip()) < MIN_TEXT_CHARS:
            err = f"retrieved content has no usable text ({len(text.strip())} chars; JavaScript-rendered or image-only?)"
    if err is not None:
        # a source that only ever existed as a search-result snippet stays SNIPPET_ONLY when the re-fetch fails;
        # anything else that cannot be re-fetched is UNAVAILABLE. Either way it is non-verified.
        keep = "SNIPPET_ONLY" if s.get("retrieval") == "search_snippet_only" else "UNAVAILABLE"
        entry.update(outcome="UNAVAILABLE", new_state=keep, error=err, retrieved_at=now)
        integ = dict(base, state=keep, content_sha256=None, snapshot_path=None, origin=origin or "revalidation:refetch_unavailable",
                     note=f"Re-fetch attempt failed: {err}. The quotes could not be validated against retrieved content" + (" (the source remains a search-result snippet)." if keep == "SNIPPET_ONLY" else "."))
        return integ, {}, None, entry
    snap = snapshot_bytes(text)
    norm = L._ws(snap.decode("utf-8"))
    missing = {}
    for r in recs:
        segs = [g for g in L.quote_segments(r["evidence"]["supporting_text"]) if g not in norm]
        if segs:
            missing[r["record_id"]] = segs
    entry.update(extractor=extractor, raw_sha256=_sha(result["raw"]), content_sha256=_sha(snap), records_confirmed=len(recs) - len(missing),
                 records_unconfirmed=[{"record_id": k, "diagnosis": _diagnose(v, norm), "missing_segments": [g[:140] for g in v]} for k, v in sorted(missing.items())])
    base.update(raw_sha256=_sha(result["raw"]), extractor=extractor)
    if recs and len(missing) == len(recs):
        keep = "SNIPPET_ONLY" if s.get("retrieval") == "search_snippet_only" else "RETRIEVED_UNVERIFIABLE"
        entry.update(outcome="CONTENT_MISMATCH", new_state=keep, retrieved_at=now)
        integ = dict(base, state=keep, content_sha256=None, snapshot_path=None, origin=origin or "revalidation:refetch_content_mismatch",
                     note=f"Re-fetched (HTTP {result.get('status')}, extracted text sha256 {entry['content_sha256'][:16]}...) but none of the {len(recs)} cited quotes occur in the current content (page changed or extraction differs). Original quotes unchanged; needs an authoritative archived source.")
        return integ, {}, None, entry
    state = "PDF_VERIFIED" if (is_pdf and L.is_pdf_source(s)) else "FULL_TEXT_VERIFIED"
    path = (snapshot_dir / f"{sid}.txt").resolve().relative_to(root.resolve()).as_posix()
    integ = dict(base, state=state, content_sha256=entry["content_sha256"], snapshot_path=path, origin=origin or "revalidation:refetch",
                 note=("Re-fetched and preserved; " + (f"{len(missing)} of {len(recs)} records' quotes are NOT in the current content (listed in unconfirmed_record_ids, never verified)." if missing else "every cited quote was found in the preserved content.")))
    if missing:
        integ["unconfirmed_record_ids"] = sorted(missing)
    fields = {}
    if s["retrieval"] == "search_snippet_only":  # the content was genuinely retrieved now; keep the history in notes
        fields["retrieval"] = "pdf_downloaded_and_parsed" if is_pdf else "fetched_full_text"
        fields["notes"] = ((s.get("notes") + " | ") if s.get("notes") else "") + "Originally cited from a search-result snippet; content re-fetched and preserved during integrity revalidation."
    entry.update(outcome="PARTIAL_CONFIRMED" if missing else "CONFIRMED", new_state=state)
    entry["retrieved_at"] = now
    entry["note"] = integ["note"]
    return integ, fields, snap, entry


def revalidate_doc(doc: dict, snapshot_dir: Path, now: str, only: list[str] | None = None, force: bool = False, fetcher=fetch, root: Path = HERE, write: bool = True, origin: str | None = None) -> tuple[dict, list[dict]]:
    """Re-fetch the selected sources of `doc`. Returns (new doc, review entries). Writes snapshots when `write`.
    `origin='authored'` marks sources that are being retrieved for the first time while the evidence is authored."""
    doc = copy.deepcopy(doc)
    entries = []
    for sid in sorted(doc["sources"]):
        if only and sid not in only:
            continue
        s = doc["sources"][sid]
        if not force and L.source_integrity_state(s) in L.VERIFIED_ELIGIBLE_STATES and (s["integrity"].get("origin") or "").startswith(("revalidation:", "quote_repair:", "authored", "migration:cached")):
            entries.append({"source_id": sid, "url": s["url"], "tier": s["tier"], "outcome": "SKIPPED_ALREADY_VERIFIED", "new_state": s["integrity"]["state"]})
            continue
        result = fetcher(s["url"])
        integ, fields, snap, entry = classify_source(doc, sid, result, now, snapshot_dir, root, origin)
        if snap is not None and write:
            snapshot_dir.mkdir(parents=True, exist_ok=True)
            (snapshot_dir / f"{sid}.txt").write_bytes(snap)
        s.update(fields)
        s["integrity"] = {k: v for k, v in integ.items() if v is not None or k in ("content_sha256", "snapshot_path")}
        doc["sources"][sid] = L._order_source(s)
        entries.append(entry)
    return doc, entries


# ----------------------------------------------------------------------------------------------------------------
# command line
# ----------------------------------------------------------------------------------------------------------------
def utc_now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--evidence", required=True, help="evidence file relative to tools/catalog_enrichment/ (or absolute)")
    ap.add_argument("--source", action="append", help="only this source id (repeatable)")
    ap.add_argument("--force", action="store_true", help="re-fetch even sources that are already verified")
    ap.add_argument("--dry-run", action="store_true", help="fetch and classify; write nothing")
    ap.add_argument("--report", help="review report path (default reports/<evidence stem>_revalidation.json)")
    ap.add_argument("--origin", choices=["authored"], help="mark the integrity origin as 'authored' (first retrieval of a newly researched source) instead of 'revalidation:*'")
    a = ap.parse_args(argv)
    p = Path(a.evidence)
    p = p if p.is_absolute() else HERE / p
    doc = L.read_json(p)
    snap_dir = p.parent / "_source_text"
    new, entries = revalidate_doc(doc, snap_dir, utc_now(), a.source, a.force, write=not a.dry_run, origin=a.origin)
    for e in entries:
        extra = f" confirmed={e.get('records_confirmed')}/{e.get('records_total')} unconfirmed={[u['record_id'] for u in e['records_unconfirmed']]}" if e.get("records_unconfirmed") else ""
        print(f"{e['source_id']:7} t{e['tier']} {e['outcome']:22} {e.get('previous_state') or '-':24} -> {e['new_state']:22} http={e.get('http_status')}{extra}")
    if a.dry_run:
        return 0
    new = L.prepare_evidence(new)  # refresh derived record fields (source_integrity, confidence)
    L.write_json(p, new)
    rp = Path(a.report) if a.report else HERE / "reports" / f"{p.stem}_revalidation.json"
    rp = rp if rp.is_absolute() else HERE / rp
    prev = L.read_json(rp) if rp.exists() else {"schema_version": "carnet.source_revalidation/1", "evidence_file": p.relative_to(HERE).as_posix(), "attempts": []}
    prev["attempts"] = [x for x in prev["attempts"] if x["source_id"] not in {e["source_id"] for e in entries if e["outcome"] != "SKIPPED_ALREADY_VERIFIED"}] + [e for e in entries if e["outcome"] != "SKIPPED_ALREADY_VERIFIED"]
    prev["attempts"].sort(key=lambda x: (x["source_id"].split("-S")[0], int(x["source_id"].split("-S")[1])))
    L.write_json(rp, prev)
    print(f"updated {p.relative_to(HERE)}; review report {rp.relative_to(HERE)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
