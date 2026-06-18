#!/usr/bin/env python3
"""
Extract brands, models, and trims from kk/legacy/app.py and from JSON listing data,
then print Dart CarCatalog code. Run from repo root: python tools/extract_car_catalog.py
"""
import ast
import json
import re
import sys
from pathlib import Path
from collections import defaultdict

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_PY = REPO_ROOT / "kk" / "legacy" / "app.py"
# JSON files that contain car listings with brand, model, trim (merged into catalog)
JSON_DATA_PATHS = [
    REPO_ROOT / "tools" / "data" / "cars.json",
    REPO_ROOT / "tools" / "data" / "tmp_api_cars.json",
]
# Full catalog from recovered-ui branch (assets/data/*.json): brands, models, trims
RECOVERED_BRANDS = REPO_ROOT / "tools" / "data" / "recovered_brands.json"
RECOVERED_MODELS = REPO_ROOT / "tools" / "data" / "recovered_models.json"
RECOVERED_TRIMS = REPO_ROOT / "tools" / "data" / "recovered_trims.json"

# Slug (lowercase API key) -> Display name for Flutter
BRAND_DISPLAY = {
    "mercedes-benz": "Mercedes-Benz",
    "land-rover": "Land Rover",
    "great-wall": "Great Wall",
    "li-auto": "Li Auto",
    "ssangyong": "SsangYong",
    "jac-motors": "JAC Motors",
    "jac-trucks": "JAC Trucks",
    "iran-khodro": "Iran Khodro",
    "faw-jiefang": "FAW Jiefang",
    "alfa-romeo": "Alfa Romeo",
    "aston-martin": "Aston Martin",
    "rolls-royce": "Rolls-Royce",
    "bentley": "Bentley",
    "mclaren": "McLaren",
    "maserati": "Maserati",
    "bugatti": "Bugatti",
    "pagani": "Pagani",
    "koenigsegg": "Koenigsegg",
    "citroen": "Citroën",
    "skoda": "Škoda",
    "seat": "SEAT",
    "chery": "Chery",
    "byd": "BYD",
    "faw": "FAW",
    "roewe": "Roewe",
    "proton": "Proton",
    "perodua": "Perodua",
    "tata": "Tata",
    "mahindra": "Mahindra",
    "lada": "Lada",
    "zaz": "ZAZ",
    "daewoo": "Daewoo",
    "changan": "Changan",
    "haval": "Haval",
    "wuling": "Wuling",
    "baojun": "Baojun",
    "nio": "Nio",
    "xpeng": "XPeng",
    "vinfast": "VinFast",
    "polestar": "Polestar",
    "rivian": "Rivian",
    "lucid": "Lucid",
    "genesis": "Genesis",
    "ram": "RAM",
    "gmc": "GMC",
    "buick": "Buick",
    "cadillac": "Cadillac",
    "lincoln": "Lincoln",
    "acura": "Acura",
    "infiniti": "Infiniti",
    "tesla": "Tesla",
    "mini": "Mini",
    "smart": "Smart",
    "bmw": "BMW",
    "audi": "Audi",
    "toyota": "Toyota",
    "volkswagen": "Volkswagen",
    "honda": "Honda",
    "nissan": "Nissan",
    "ford": "Ford",
    "chevrolet": "Chevrolet",
    "hyundai": "Hyundai",
    "kia": "Kia",
    "volvo": "Volvo",
    "lexus": "Lexus",
    "porsche": "Porsche",
    "jaguar": "Jaguar",
    "subaru": "Subaru",
    "mazda": "Mazda",
    "mitsubishi": "Mitsubishi",
    "suzuki": "Suzuki",
    "peugeot": "Peugeot",
    "dacia": "Dacia",
}


def slug_to_display(slug: str) -> str:
    if slug in BRAND_DISPLAY:
        return BRAND_DISPLAY[slug]
    return slug.replace("-", " ").title()


def brand_to_slug(brand: str) -> str:
    """Normalize brand string to slug (lowercase, spaces to hyphens)."""
    if not brand or not isinstance(brand, str):
        return ""
    return brand.strip().lower().replace(" ", "-").replace("_", "-")


def normalize_model(s: str) -> str:
    """Title-case model name for consistency (e.g. 'c-class' -> 'C-Class')."""
    if not s or not isinstance(s, str):
        return ""
    return s.strip().title()


# Junk trim values from listings / imports (matched case-insensitively after normalize_trim_key).
_JUNK_TRIM_KEYS = frozenset({
    "",
    "-",
    "--",
    "n/a",
    "na",
    "none",
    "null",
    "unknown",
    "notspecified",
    "unspecified",
    "notavailable",
    "tbd",
    "test",
    "default",
    "standardtrim",
    "trim",
})

# Known duplicate spellings → preferred display label (key = normalize_trim_key).
TRIM_ALIASES: dict[str, str] = {
    "m135i": "M135i",
    "m140i": "M140i",
    "m240i": "M240i",
    "m340i": "M340i",
    "m440i": "M440i",
    "m550i": "M550i",
    "m850i": "M850i",
    "m2": "M2",
    "m3": "M3",
    "m4": "M4",
    "m5": "M5",
    "m6": "M6",
    "m8": "M8",
    "m1": "1M",
    "sportline": "Sport Line",
    "sport-line": "Sport Line",
    "msport": "M Sport",
    "m-sport": "M Sport",
    "rline": "R-Line",
    "r-line": "R-Line",
    "txl": "TXL",
    "tx-l": "TX-L",
    "gxr": "GXR",
    "gxl": "GXL",
    "vxr": "VXR",
    "vxl": "VXL",
    "xle": "XLE",
    "xse": "XSE",
    "gli": "GLI",
    "glihybrid": "GLI Hybrid",
    "xli": "XLI",
    "glx": "GLX",
    "gle": "GLE",
    "grsport": "GR-Sport",
    "gr-sport": "GR-Sport",
    "grcorolla": "GR Corolla",
    "gr-corolla": "GR Corolla",
    "grsupra": "GR Supra",
    "gr-supra": "GR Supra",
    "trdpro": "TRD Pro",
    "trd-pro": "TRD Pro",
    "trdoffroad": "TRD Off-Road",
    "trd-off-road": "TRD Off-Road",
    "trdoff-road": "TRD Off-Road",
    "sr5premium": "SR5 Premium",
    "sr5-premium": "SR5 Premium",
    "seplus": "SE Plus",
    "se+": "SE Plus",
    "splus": "S Plus",
    "s+": "S Plus",
    "hybridle": "Hybrid LE",
    "hybridse": "Hybrid SE",
    "hybridxle": "Hybrid XLE",
    "hybridxse": "Hybrid XSE",
    "limitedspecialedition": "Limited Special Edition",
    "montecarlo": "Monte Carlo",
    "monte-carlo": "Monte Carlo",
    "nightshade": "Nightshade",
    "type-s": "Type S",
    "types": "Type S",
    "aspec": "A-Spec",
    "a-spec": "A-Spec",
    "advancepackage": "Advance",
    "technologypackage": "Technology",
    "other": "Other",
}

# Equipment-line suffixes scraped as separate trims (e.g. C300 Luxury → C300).
# Longest matches first.
_PACKAGE_SUFFIXES: tuple[str, ...] = (
    "Premium Plus",
    "Premium Luxury",
    "Luxury Plus",
    "Business Edition",
    "Luxury Edition",
    "Motorsport Edition",
    "Petronas Edition",
    "Luxury Line",
    "Luxury-Line",
    "Luxury-line",
    "Sport Line",
    "Sport-line",
    "Urban-line",
    "AMG Line",
    "Avantgarde",
    "Elegance",
    "Progressive",
    "Luxury",
    "Sport",
)

# Letter+digit variant codes: C300, A 250, GLC250, CLA200, C43 AMG, etc.
_VARIANT_CODE_RE = re.compile(
    r"^[A-Za-z]{1,4}\s?\d+[a-zA-Z0-9]*(?:\s+(?:AMG|4MATIC|4Matic|4Matic\+))?$",
    re.IGNORECASE,
)
# BMW-style: 328i, 530i, xDrive35i
_BMW_VARIANT_RE = re.compile(
    r"^(?:xDrive|sDrive)?\d{3}[a-zA-Z]+(?:\s+(?:AMG|4MATIC|4Matic))?$",
    re.IGNORECASE,
)
# Audi-style: 45 TFSI quattro, 35 TFSI Sport
_AUDI_VARIANT_RE = re.compile(
    r"^\d{1,2}\s+TFSI\b.*$",
    re.IGNORECASE,
)


def normalize_trim_key(s: str) -> str:
    """Fold spacing/punctuation for duplicate detection."""
    s = re.sub(r"\s+", " ", (s or "").strip())
    return re.sub(r"[\s\-_+.]+", "", s.lower())


# Whole-trim labels that must not be split (even if they end with a suffix word).
_PROTECTED_TRIM_KEYS = frozenset(
    normalize_trim_key(name)
    for name in (
        "M Sport",
        "GR Sport",
        "GR-Sport",
        "TRD Sport",
        "Sport",
        "Luxury",
        "Sport Line",
        "Range Rover Sport",
        "Bronco Sport",
        "Rogue Sport",
        "Outlander Sport",
        "Pajero Sport",
        "Montero Sport",
        "Discovery Sport",
        "EcoSport",
    )
)


def _looks_like_variant_code(base: str) -> bool:
    base = re.sub(r"\s+", " ", base.strip())
    if not base:
        return False
    if _VARIANT_CODE_RE.match(base):
        return True
    if _BMW_VARIANT_RE.match(base):
        return True
    if _AUDI_VARIANT_RE.match(base):
        return True
    return False


def strip_package_suffix(label: str) -> str:
    """Remove trailing package-line words from variant codes (C300 Luxury → C300)."""
    key = normalize_trim_key(label)
    if key in _PROTECTED_TRIM_KEYS:
        return label

    for suffix in _PACKAGE_SUFFIXES:
        label_lower = label.lower()
        suffix_lower = suffix.lower()
        if not label_lower.endswith(suffix_lower):
            continue
        cut = len(label) - len(suffix)
        if cut < 2:
            continue
        sep = label[cut - 1]
        if sep not in (" ", "-"):
            continue
        base = label[: cut - 1].strip()
        if not base or not _looks_like_variant_code(base):
            continue
        return base
    return label


def canonicalize_trim(raw: str) -> str | None:
    """Normalize one trim label; return None if junk."""
    if not raw or not isinstance(raw, str):
        return None
    label = re.sub(r"\s+", " ", raw.strip())
    if not label:
        return None
    key = normalize_trim_key(label)
    if key in _JUNK_TRIM_KEYS:
        return None
    label = strip_package_suffix(label)
    key = normalize_trim_key(label)
    return TRIM_ALIASES.get(key, label)


def _trim_label_score(label: str) -> tuple:
    """Lower tuple = preferred display spelling when deduping."""
    key = normalize_trim_key(label)
    is_other = key == "other"
    spaces = label.count(" ")
    all_upper = label.isupper() and len(label) > 2
    all_lower = label.islower() and len(label) > 1
    alias_hit = label == TRIM_ALIASES.get(key)
    return (is_other, not alias_hit, spaces, all_upper, all_lower, len(label))


def _prefer_trim_label(a: str, b: str) -> str:
    return a if _trim_label_score(a) < _trim_label_score(b) else b


# Static popularity hints (higher = show earlier). Listing counts override via scale.
_TRIM_POPULARITY_RANK: dict[str, int] = {
    # Entry / base
    "base": 980,
    "standard": 970,
    "l": 960,
    "e": 950,
    "le": 940,
    "gl": 930,
    "lx": 925,
    "ce": 920,
    # Gulf / regional volume sellers
    "gli": 915,
    "xli": 910,
    "glx": 905,
    "gle": 900,
    "gx": 895,
    "tx": 890,
    "exr": 885,
    "gxr": 880,
    "gxl": 875,
    "vxr": 870,
    "vxl": 865,
    "txl": 860,
    "tzg": 855,
    # Mid trims
    "se": 850,
    "sport": 845,
    "altis": 840,
    "ex": 835,
    "exl": 830,
    "ambition": 825,
    "active": 820,
    "style": 815,
    "comfort": 810,
    # Upper mid / luxury
    "xle": 800,
    "xse": 795,
    "limited": 790,
    "touring": 785,
    "elegance": 780,
    "avantgarde": 775,
    "premium": 770,
    "premiumplus": 765,
    "progressive": 760,
    "platinum": 755,
    "prestige": 750,
    "royal": 745,
    "grande": 740,
    # Performance / sporty (often searched)
    "msport": 820,
    "amgline": 815,
    "trd": 810,
    "trdpro": 805,
    "trdoffroad": 800,
    "types": 795,
    "aspec": 790,
    "rs": 785,
    "vrs": 780,
    "gr": 775,
    "grsport": 770,
    # SUV / truck common
    "sr5": 780,
    "sr5premium": 775,
    "xlt": 770,
    "lariat": 765,
    "wildtrak": 760,
    "rubicon": 755,
    "sportline": 750,
    "rline": 745,
    "r-design": 740,
    # Hybrid variants
    "hybrid": 700,
    "hybridle": 695,
    "hybridse": 690,
    "hybridxle": 685,
    "hybridxse": 680,
    "prime": 675,
    # Mercedes / BMW common variant codes
    "c180": 720,
    "c200": 715,
    "c220": 710,
    "c250": 705,
    "c300": 700,
    "e200": 720,
    "e300": 715,
    "e350": 710,
    "glc200": 715,
    "glc300": 710,
    "320i": 705,
    "328i": 700,
    "330i": 695,
    "520i": 705,
    "530i": 700,
    "x3": 690,
    "x5": 685,
    "a200": 700,
    "a220": 695,
    "a250": 690,
    # AMG / M high intent
    "c43amg": 650,
    "c63amg": 645,
    "c63s": 640,
    "e43amg": 650,
    "e53amg": 645,
    "m135i": 630,
    "m240i": 625,
    "m340i": 620,
    "m440i": 615,
    "m550i": 610,
}


def _trim_popularity_score(label: str, listing_counts: dict[str, int]) -> int:
    key = normalize_trim_key(label)
    if key == "other":
        return -10_000_000
    listing = listing_counts.get(key, 0)
    static = _TRIM_POPULARITY_RANK.get(key, 0)
    variant_boost = 280 if static == 0 and listing == 0 and _looks_like_variant_code(label) else 0
    return listing * 100 + static + variant_boost


def _trim_popularity_sort_key(label: str, listing_counts: dict[str, int]) -> tuple:
    if normalize_trim_key(label) == "other":
        return (1, 0, label.lower())
    return (0, -_trim_popularity_score(label, listing_counts), label.lower())


def count_trim_popularity_from_listings() -> dict[str, dict[str, dict[str, int]]]:
    """brand_slug -> canonical_model -> trim_key -> listing count."""
    counts: dict[str, dict[str, dict[str, int]]] = defaultdict(
        lambda: defaultdict(lambda: defaultdict(int))
    )
    model_keys_by_slug: dict[str, dict[str, str]] = defaultdict(dict)

    def canonical_model(slug: str, model: str) -> str:
        lower = model.lower()
        existing = model_keys_by_slug[slug].get(lower)
        if existing:
            return existing
        model_keys_by_slug[slug][lower] = model
        return model

    for path in JSON_DATA_PATHS:
        if not path.exists():
            continue
        try:
            raw = path.read_bytes()
            if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
                text = raw.decode("utf-16", errors="replace")
            else:
                text = raw.decode("utf-8", errors="replace")
            data = json.loads(text)
        except (json.JSONDecodeError, OSError, UnicodeDecodeError):
            continue
        cars = data.get("cars", data) if isinstance(data, dict) else data
        if not isinstance(cars, list):
            continue
        for car in cars:
            if not isinstance(car, dict):
                continue
            brand_raw = car.get("brand") or car.get("make")
            model_raw = car.get("model")
            trim_raw = car.get("trim")
            if not brand_raw or not model_raw or not trim_raw:
                continue
            slug = brand_to_slug(str(brand_raw))
            if not slug:
                continue
            model = canonical_model(slug, normalize_model(str(model_raw)))
            label = canonicalize_trim(str(trim_raw))
            if label is None:
                continue
            counts[slug][model][normalize_trim_key(label)] += 1
    return {
        slug: {model: dict(trim_counts) for model, trim_counts in models.items()}
        for slug, models in counts.items()
    }


def sanitize_trim_list(
    trims: list[str],
    listing_counts: dict[str, int] | None = None,
) -> list[str]:
    """Deduplicate, canonicalize, sort by popularity; keep 'Other' last."""
    pop = listing_counts or {}
    best_by_key: dict[str, str] = {}
    for raw in trims:
        label = canonicalize_trim(raw)
        if label is None:
            continue
        key = normalize_trim_key(label)
        prev = best_by_key.get(key)
        best_by_key[key] = label if prev is None else _prefer_trim_label(prev, label)

    regular: list[str] = []
    other: str | None = None
    for label in best_by_key.values():
        if normalize_trim_key(label) == "other":
            other = label
        else:
            regular.append(label)

    regular.sort(key=lambda label: _trim_popularity_sort_key(label, pop))
    if other is not None:
        regular.append(other)
    return regular


def sanitize_trims(
    trim_levels: dict,
    popularity_by_slug: dict[str, dict[str, dict[str, int]]] | None = None,
) -> dict:
    """Apply [sanitize_trim_list] to every brand/model trim list."""
    pop_by_slug = popularity_by_slug or {}
    out: dict = {}
    for brand, models_map in trim_levels.items():
        cleaned_models: dict = {}
        brand_pop = pop_by_slug.get(brand, {})
        for model, trims in models_map.items():
            if not trims:
                continue
            cleaned = sanitize_trim_list(list(trims), brand_pop.get(model, {}))
            if cleaned:
                cleaned_models[model] = cleaned
        if cleaned_models:
            out[brand] = cleaned_models
    return out


def load_json_catalog() -> tuple[dict[str, set[str]], dict[str, dict[str, set[str]]]]:
    """
    Load all JSON listing files and return (models_per_brand, trims_per_brand_model).
    models_per_brand[brand_slug] = set of model names
    trims_per_brand_model[brand_slug][model] = set of trim names
    """
    models_per_brand = defaultdict(set)
    trims_per_brand_model = defaultdict(lambda: defaultdict(set))
    for path in JSON_DATA_PATHS:
        if not path.exists():
            continue
        try:
            raw = path.read_bytes()
            if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
                text = raw.decode("utf-16", errors="replace")
            else:
                text = raw.decode("utf-8", errors="replace")
            data = json.loads(text)
        except (json.JSONDecodeError, OSError, UnicodeDecodeError):
            continue
        cars = data.get("cars", data) if isinstance(data, dict) else data
        if not isinstance(cars, list):
            continue
        for car in cars:
            if not isinstance(car, dict):
                continue
            brand_raw = car.get("brand") or car.get("make")
            model_raw = car.get("model")
            trim_raw = car.get("trim")
            if not brand_raw or not model_raw:
                continue
            slug = brand_to_slug(str(brand_raw))
            model = normalize_model(str(model_raw))
            models_per_brand[slug].add(model)
            if trim_raw and str(trim_raw).strip():
                trims_per_brand_model[slug][model].add(str(trim_raw).strip())
    return dict(models_per_brand), {b: dict(m) for b, m in trims_per_brand_model.items()}


# Recovered model id "name" -> preferred display name (to align with app.py e.g. Land Cruiser Prado)
RECOVERED_MODEL_DISPLAY_OVERRIDE: dict[tuple[str, str], str] = {
    ("toyota", "prado"): "Land Cruiser Prado",
}


def _read_json_path(path: Path) -> list | dict | None:
    if not path.exists():
        return None
    try:
        raw = path.read_bytes()
        if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
            text = raw.decode("utf-16", errors="replace")
        else:
            text = raw.decode("utf-8", errors="replace")
        return json.loads(text)
    except (json.JSONDecodeError, OSError, UnicodeDecodeError):
        return None


def load_recovered_catalog() -> tuple[dict[str, set[str]], dict[str, dict[str, set[str]]]]:
    """
    Load recovered-ui assets/data brands, models, trims and return
    (models_per_brand, trims_per_brand_model) for merging.
    """
    models_per_brand: dict[str, set[str]] = defaultdict(set)
    trims_per_brand_model: dict[str, dict[str, set[str]]] = defaultdict(lambda: defaultdict(set))
    brands_data = _read_json_path(RECOVERED_BRANDS)
    models_data = _read_json_path(RECOVERED_MODELS)
    trims_data = _read_json_path(RECOVERED_TRIMS)
    if not isinstance(models_data, list) or not isinstance(trims_data, list):
        return dict(models_per_brand), {b: dict(m) for b, m in trims_per_brand_model.items()}
    # model_id -> (brand_slug, model_display_name)
    model_id_to_brand_model: dict[str, tuple[str, str]] = {}
    def _recovered_brand_slug(bid: str) -> str:
        s = (bid or "").strip().lower().replace(" ", "_")
        return s.replace("_", "-")  # match app.py slugs e.g. mercedes-benz

    for m in models_data:
        if not isinstance(m, dict):
            continue
        mid = m.get("id") or m.get("modelId")
        name = (m.get("name") or "").strip()
        raw_brand = (m.get("brandId") or "").strip().lower().replace(" ", "_")
        brand_slug = _recovered_brand_slug(m.get("brandId") or "")
        if not mid or not brand_slug:
            continue
        display = normalize_model(name)
        override = RECOVERED_MODEL_DISPLAY_OVERRIDE.get((raw_brand, name.lower()))
        if override:
            display = override
        model_id_to_brand_model[str(mid)] = (brand_slug, display)
    for m in models_data:
        if not isinstance(m, dict):
            continue
        mid = m.get("id") or m.get("modelId")
        brand_slug = _recovered_brand_slug(m.get("brandId") or "")
        name = (m.get("name") or "").strip()
        raw_brand = (m.get("brandId") or "").strip().lower().replace(" ", "_")
        if not mid or not brand_slug:
            continue
        display = normalize_model(name)
        override = RECOVERED_MODEL_DISPLAY_OVERRIDE.get((raw_brand, name.lower()))
        if override:
            display = override
        models_per_brand[brand_slug].add(display)
    for t in trims_data:
        if not isinstance(t, dict):
            continue
        model_id = (t.get("modelId") or "").strip()
        trim_name = (t.get("name") or "").strip()
        if not model_id or not trim_name:
            continue
        pair = model_id_to_brand_model.get(model_id)
        if not pair:
            continue
        brand_slug, model_display = pair
        trims_per_brand_model[brand_slug][model_display].add(trim_name)
    return dict(models_per_brand), {b: dict(m) for b, m in trims_per_brand_model.items()}


def _canonical_model_key(brand_models: dict[str, list], brand_trims: dict[str, dict], slug: str, model: str) -> str:
    """Return existing key for this model if one exists (case-insensitive), else return model as-is."""
    model_lower = model.lower()
    for existing in brand_models.get(slug, []) or list((brand_trims.get(slug) or {}).keys()):
        if existing.lower() == model_lower:
            return existing
    return model


def merge_json_into_catalog(
    car_models: dict,
    trim_levels: dict,
    json_models: dict[str, set[str]],
    json_trims: dict[str, dict[str, set[str]]],
) -> tuple[dict, dict]:
    """Merge JSON-derived brands/models/trims into backend catalog. Returns (car_models_merged, trim_levels_merged)."""
    cm = {k: list(v) for k, v in car_models.items()}
    tl = {}
    for brand, models_map in trim_levels.items():
        tl[brand] = {m: list(trims) for m, trims in models_map.items()}
    for slug, models_set in json_models.items():
        if slug not in cm:
            cm[slug] = []
        for model in models_set:
            canonical = _canonical_model_key(cm, tl, slug, model)
            if canonical not in cm[slug]:
                cm[slug].append(canonical)
    for slug, models_map in json_trims.items():
        if slug not in tl:
            tl[slug] = {}
        for model, trims_set in models_map.items():
            canonical = _canonical_model_key(cm, tl, slug, model)
            existing = set(tl[slug].get(canonical, []))
            tl[slug][canonical] = list(existing | trims_set)
    return cm, tl


def extract_dict_from_source(source: str, dict_name: str):
    """Find a top-level assignment like `dict_name = { ... }` and parse the value."""
    pattern = rf"^({re.escape(dict_name)})\s*=\s*(\{{.*?\}})\s*$"
    for match in re.finditer(pattern, source, re.MULTILINE | re.DOTALL):
        try:
            return ast.literal_eval(match.group(2))
        except (ValueError, SyntaxError):
            pass
    # Fallback: find the line where dict_name = { starts, then collect until balanced }
    start = source.find(f"{dict_name} = {{")
    if start == -1:
        return None
    depth = 0
    i = start + len(dict_name) + 3  # skip "dict_name = {"
    begin = i
    while i < len(source):
        c = source[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == -1:
                snippet = source[begin - 1 : i + 1]  # include leading {
                try:
                    return ast.literal_eval(snippet)
                except (ValueError, SyntaxError):
                    return None
        elif c in ('"', "'"):
            quote = c
            i += 1
            while i < len(source) and source[i] != quote:
                if source[i] == "\\":
                    i += 1
                i += 1
        i += 1
    return None


def extract_car_models(source: str):
    """Extract car_models dict from populate_car_models()."""
    # Find "car_models = {" inside populate_car_models
    idx = source.find("def populate_car_models")
    if idx == -1:
        return None
    block = source[idx:]
    start = block.find("car_models = {")
    if start == -1:
        return None
    start += len("car_models = ")
    depth = 0
    i = start
    begin = start
    while i < len(block):
        c = block[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                snippet = block[begin : i + 1]
                try:
                    return ast.literal_eval(snippet)
                except (ValueError, SyntaxError):
                    return None
        elif c in ('"', "'"):
            quote = c
            i += 1
            while i < len(block) and block[i] != quote:
                if block[i] == "\\":
                    i += 1
                i += 1
        i += 1
    return None


def extract_trim_levels(source: str):
    """Extract trim_levels from get_trims()."""
    idx = source.find("def get_trims(brand, model)")
    if idx == -1:
        return None
    block = source[idx:]
    start = block.find("trim_levels = {")
    if start == -1:
        return None
    start += len("trim_levels = ")
    depth = 0
    i = start
    begin = start
    while i < len(block):
        c = block[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                snippet = block[begin : i + 1]
                try:
                    return ast.literal_eval(snippet)
                except (ValueError, SyntaxError):
                    return None
        elif c in ('"', "'"):
            quote = c
            i += 1
            while i < len(block) and block[i] != quote:
                if block[i] == "\\":
                    i += 1
                i += 1
        i += 1
    return None


def dart_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def emit_dart(car_models: dict, trim_levels: dict) -> str:
    # Collect all brands: from car_models (has models) and trim_levels (has trims)
    brand_slugs = set(car_models.keys()) | set(trim_levels.keys())
    display_names = [slug_to_display(s) for s in brand_slugs]
    display_names.sort(key=lambda x: x.lower())

    lines = []
    lines.append("/// Single source of truth for car brands, models, and trims.")
    lines.append("/// Generated from kk/legacy/app.py, tools/data/*.json, and recovered_*.json - run: python tools/extract_car_catalog.py")
    lines.append("class CarCatalog {")
    lines.append("  CarCatalog._();")
    lines.append("")
    lines.append("  static final List<String> brands = [")
    for b in display_names:
        lines.append(f"    '{dart_escape(b)}',")
    lines.append("  ];")
    lines.append("")

    # models: Map<displayBrand, List<model>>
    # Merge from car_models (full list) and trim_levels (models that have trims) so every brand has models
    slug_to_display_map = {s: slug_to_display(s) for s in brand_slugs}

    def get_models_for_brand(slug: str) -> list:
        from_cm = list(car_models[slug]) if slug in car_models else []
        from_tl = list(trim_levels.get(slug, {}).keys())
        seen = set(from_cm)
        for m in from_tl:
            if m not in seen:
                from_cm.append(m)
                seen.add(m)
        return from_cm

    lines.append("  static final Map<String, List<String>> models = {")
    for slug in sorted(brand_slugs, key=lambda x: slug_to_display(x).lower()):
        model_list = get_models_for_brand(slug)
        if not model_list:
            continue
        display = slug_to_display_map[slug]
        lines.append(f"    '{dart_escape(display)}': [")
        for m in sorted(model_list, key=lambda x: x.lower()):
            lines.append(f"      '{dart_escape(m)}',")
        lines.append("    ],")
    lines.append("  };")
    lines.append("")

    # trimsByBrandModel: only real data from trim_levels (no generic defaults)
    lines.append("  static final Map<String, Map<String, List<String>>> trimsByBrandModel = {")
    for slug in sorted(trim_levels.keys(), key=lambda x: slug_to_display(x).lower()):
        display = slug_to_display_map.get(slug, slug_to_display(slug))
        models_map = trim_levels[slug]
        lines.append(f"    '{dart_escape(display)}': {{")
        for model_name in sorted(models_map.keys(), key=lambda x: x.lower()):
            trims_list = models_map[model_name]
            if not trims_list:
                continue
            lines.append(f"      '{dart_escape(model_name)}': [")
            for t in trims_list:
                lines.append(f"        '{dart_escape(t)}',")
            lines.append("      ],")
        lines.append("    },")
    lines.append("  };")
    lines.append("")
    lines.append("  /// Trims for a given brand and model; returns ['Base'] only when no trim data exists.")
    lines.append("  static List<String> trimsFor(String? brand, String? model) {")
    lines.append("    if (brand == null || model == null) return ['Base'];")
    lines.append("    return trimsByBrandModel[brand]?[model] ?? ['Base'];")
    lines.append("  }")
    lines.append("}")
    return "\n".join(lines)


def main():
    if not APP_PY.exists():
        print(f"Not found: {APP_PY}", file=sys.stderr)
        sys.exit(1)
    source = APP_PY.read_text(encoding="utf-8")
    car_models = extract_car_models(source)
    trim_levels = extract_trim_levels(source)
    if not car_models:
        print("Could not extract car_models", file=sys.stderr)
        sys.exit(1)
    if not trim_levels:
        print("Could not extract trim_levels", file=sys.stderr)
        sys.exit(1)
    json_models, json_trims = load_json_catalog()
    car_models, trim_levels = merge_json_into_catalog(
        car_models, trim_levels, json_models, json_trims
    )
    # Merge full list from recovered-ui branch (brands, models, trims)
    rec_models, rec_trims = load_recovered_catalog()
    car_models, trim_levels = merge_json_into_catalog(
        car_models, trim_levels, rec_models, rec_trims
    )
    trim_popularity = count_trim_popularity_from_listings()
    trim_levels = sanitize_trims(trim_levels, trim_popularity)
    dart = emit_dart(car_models, trim_levels)
    out_path = REPO_ROOT / "lib" / "data" / "car_catalog.dart"
    out_path.write_text(dart, encoding="utf-8")
    print(f"Wrote {out_path}", file=sys.stderr)
    print(dart)


if __name__ == "__main__":
    main()
