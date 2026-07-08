"""Find model-matching car photos via Wikimedia Commons (free, commercial use)."""

from __future__ import annotations

import json
import re
import time
import urllib.parse
import urllib.request

USER_AGENT = "CarListingApp/1.0 (seed script; contact: dev@carlistings.local)"

MAX_IMAGE_URL_LEN = 200

_SKIP_TITLE = re.compile(
    r"(dashboard|interior|cockpit|engine bay|engine_room|logo|emblem|badge|"
    r"steering wheel|wheel only|tire only|seat|upholstery|trunk interior|"
    r"cutaway|diagram|brochure|advertisement|render|concept drawing|"
    r"crash test|police|taxi livery|rc car|toy car|model car|diecast)",
    re.I,
)

_PREFER_TITLE = re.compile(
    r"(front|rear|side|profile|exterior|sedan|suv|pickup|coupe|hatchback|wagon|"
    r"\b20[0-2][0-9]\b)",
    re.I,
)


def _normalize_key(brand: str, model: str) -> str:
    return f"{brand.strip().lower()}|{model.strip().lower()}"


def _wikimedia_search(query: str, *, limit: int = 8) -> list[dict]:
    params = urllib.parse.urlencode(
        {
            "action": "query",
            "generator": "search",
            "gsrsearch": query,
            "gsrnamespace": "6",
            "gsrlimit": str(limit),
            "prop": "imageinfo",
            "iiprop": "url|size|mime",
            "iiurlwidth": "1200",
            "format": "json",
        }
    )
    req = urllib.request.Request(
        f"https://commons.wikimedia.org/w/api.php?{params}",
        headers={"User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read().decode("utf-8"))

    pages = data.get("query", {}).get("pages", {})
    out: list[dict] = []
    for page in pages.values():
        title = str(page.get("title") or "")
        if not title.startswith("File:"):
            continue
        info = (page.get("imageinfo") or [{}])[0]
        mime = str(info.get("mime") or "")
        if not mime.startswith("image/"):
            continue
        width = int(info.get("width") or 0)
        if width < 800:
            continue
        url = info.get("url") or info.get("thumburl")
        if not url or len(url) > MAX_IMAGE_URL_LEN:
            continue
        out.append({"title": title, "url": url, "width": width})
    return out


def _score_candidate(title: str, brand: str, model: str) -> int:
    t = title.lower()
    b = brand.lower().replace("-", " ")
    m = model.lower().replace("-", " ")
    score = 0
    if _SKIP_TITLE.search(t):
        score -= 100
    if b.replace(" ", "") in t.replace(" ", "").replace("_", ""):
        score += 20
    elif any(part in t for part in b.split() if len(part) > 2):
        score += 10
    if m.replace(" ", "") in t.replace(" ", "").replace("_", ""):
        score += 25
    elif any(part in t for part in m.split() if len(part) > 2):
        score += 12
    if _PREFER_TITLE.search(t):
        score += 8
    if "jpg" in t or "jpeg" in t:
        score += 2
    return score


def find_matching_images(
    brand: str,
    model: str,
    *,
    year: int | None = None,
    count: int = 3,
) -> list[str]:
    """Return up to `count` Wikimedia image URLs matching brand/model."""
    brand_disp = brand.replace("-", " ").title()
    model_disp = model.strip()
    queries = [
        f"{brand_disp} {model_disp} car",
        f"{brand_disp} {model_disp} automobile",
        f"{brand_disp} {model_disp}",
    ]
    if year:
        queries.insert(0, f"{year} {brand_disp} {model_disp}")

    seen: set[str] = set()
    ranked: list[tuple[int, str]] = []

    for q in queries:
        try:
            candidates = _wikimedia_search(q, limit=10)
        except Exception:
            continue
        for c in candidates:
            url = c["url"]
            if url in seen:
                continue
            seen.add(url)
            score = _score_candidate(c["title"], brand_disp, model_disp)
            if score > 0:
                ranked.append((score, url))
        if len(ranked) >= count:
            break
        time.sleep(0.25)

    ranked.sort(key=lambda x: (-x[0], x[1]))
    return [url for _, url in ranked[:count]]


def build_image_map(listings: list[dict], *, count: int = 3) -> dict[str, list[str]]:
    """Build brand|model -> [urls] for all listings."""
    out: dict[str, list[str]] = {}
    for item in listings:
        brand = str(item["brand"])
        model = str(item["model"])
        key = _normalize_key(brand, model)
        if key in out:
            continue
        year = int(item.get("year") or 0) or None
        urls = find_matching_images(brand, model, year=year, count=count)
        out[key] = urls
    return out
