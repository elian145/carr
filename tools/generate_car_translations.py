#!/usr/bin/env python3
"""
Extract all brands, models, and trims from lib/data/car_catalog.dart and generate
lib/data/car_name_translations.dart with full Arabic and Kurdish coverage.
Uses existing translations when present, otherwise transliterates to Arabic/Kurdish script.
Run from repo root: python tools/generate_car_translations.py
"""
import re
from pathlib import Path
from collections import OrderedDict

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPO_ROOT / "lib" / "data" / "car_catalog.dart"
OUTPUT_PATH = REPO_ROOT / "lib" / "data" / "car_name_translations.dart"

# Simple Latin -> Arabic script transliteration (common for loanwords)
def latin_to_arabic(s):
    if not s:
        return s
    s = s.strip()
    # Character map: approximate phonetic
    ar = {
        'a': 'ا', 'b': 'ب', 'c': 'ك', 'd': 'د', 'e': 'ي', 'f': 'ف', 'g': 'ج', 'h': 'ه',
        'i': 'ي', 'j': 'ج', 'k': 'ك', 'l': 'ل', 'm': 'م', 'n': 'ن', 'o': 'و', 'p': 'ب',
        'q': 'ك', 'r': 'ر', 's': 'س', 't': 'ت', 'u': 'و', 'v': 'ف', 'w': 'و', 'x': 'كس',
        'y': 'ي', 'z': 'ز',
        'á': 'ا', 'é': 'ي', 'í': 'ي', 'ó': 'و', 'ú': 'و', 'ü': 'و', 'ö': 'و', 'ä': 'ا',
        'ß': 'س', 'š': 'ش', 'č': 'تش', 'ž': 'ژ', 'ć': 'تش', 'ñ': 'ن',
    }
    out = []
    for c in s.lower():
        if c in ar:
            out.append(ar[c])
        elif c in ' \t-/':
            out.append(' ')
        elif c.isdigit():
            out.append(c)
        elif c in '.,':
            out.append(c)
        else:
            out.append(c)
    return ''.join(out).strip() or s

# Latin -> Kurdish (Arabic script with ە ێ ۆ etc.)
def latin_to_kurdish(s):
    if not s:
        return s
    s = s.strip()
    ku = {
        'a': 'ا', 'b': 'ب', 'c': 'ک', 'd': 'د', 'e': 'ێ', 'f': 'ف', 'g': 'گ', 'h': 'ه',
        'i': 'ی', 'j': 'ژ', 'k': 'ک', 'l': 'ڵ', 'm': 'م', 'n': 'ن', 'o': 'ۆ', 'p': 'پ',
        'q': 'ک', 'r': 'ڕ', 's': 'س', 't': 'ت', 'u': 'و', 'v': 'ڤ', 'w': 'و', 'x': 'کس',
        'y': 'ی', 'z': 'ز',
        'á': 'ا', 'é': 'ێ', 'í': 'ی', 'ó': 'ۆ', 'ú': 'و', 'ü': 'و', 'ö': 'ۆ', 'ä': 'ە',
        'ß': 'س', 'š': 'ش', 'č': 'چ', 'ž': 'ژ', 'ć': 'چ', 'ñ': 'ن',
    }
    out = []
    for c in s.lower():
        if c in ku:
            out.append(ku[c])
        elif c in ' \t-/':
            out.append(' ')
        elif c.isdigit():
            out.append(c)
        elif c in '.,':
            out.append(c)
        else:
            out.append(c)
    return ''.join(out).strip() or s


def extract_quoted_strings(content, pattern=None):
    """Extract single-quoted strings from Dart. Returns list of (raw, key) where key is lowercase for lookup."""
    # Match '...' but allow \' inside - simple: '([^'\\]*(?:\\.[^'\\]*)*)'
    regex = re.compile(r"'([^'\\]*(?:\\.[^'\\]*)*)'")
    found = []
    for m in regex.finditer(content):
        raw = m.group(1).replace("\\'", "'").strip()
        key = raw.lower().strip()
        if key and (pattern is None or re.search(pattern, key)):
            found.append((raw, key))
    return found


def extract_brands(content):
    """Extract brand names from static final List<String> brands = [ ... ];"""
    start = content.find("static final List<String> brands = [")
    if start == -1:
        return []
    end = content.find("];", start)
    if end == -1:
        return []
    block = content[start:end + 2]
    brands = re.findall(r"['\"]([^'\"\\]*(?:\\.[^'\"\\]*)*)['\"]", block)
    return list(OrderedDict.fromkeys(b.strip() for b in brands if b.strip()))


def extract_models_map(content):
    """Extract models map: brand -> list of model names from the models = { } block."""
    start = content.find("static final Map<String, List<String>> models = {")
    if start == -1:
        return {}
    # Models block ends at first "  };"
    end = content.find("  };", start)
    if end == -1:
        end = len(content)
    else:
        end += 4
    section = content[start:end]
    models = {}
    lines = section.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip() == "};":
            break
        # Match "    'Brand': ["
        key_m = re.match(r"\s+'([^']+)':\s*\[", line)
        if key_m:
            brand = key_m.group(1).strip()
            models[brand] = []
            i += 1
            while i < len(lines) and not re.match(r"\s+\],", lines[i]):
                # Match "      'Model'," or "      'Model'"
                m = re.search(r"'([^'\\]*(?:\\.[^'\\]*)*)'", lines[i])
                if m:
                    model = m.group(1).replace("\\'", "'").strip()
                    if model:
                        models[brand].append(model)
                i += 1
            i += 1  # skip the ],
        i += 1
    return models


def extract_trims_set(content):
    """Extract all unique trim strings from trimsByBrandModel."""
    start = content.find("static final Map<String, Map<String, List<String>>> trimsByBrandModel = {")
    if start == -1:
        return set()
    # We only need trim list entries: they appear after "]: [" or "]: [" and before "],"
    trims = set()
    # Match pattern like 'Model': [ 'Trim1', 'Trim2', ... ],
    # Trim strings are in the innermost lists
    i = 0
    in_trim_list = False
    depth = 0
    brace_depth = 0
    while i < len(content):
        if content[i:i+4] == "': [":
            # Start of a trim list
            j = i + 4
            brace_depth = 0
            in_trim_list = True
            current = ""
            in_str = None
            while j < len(content):
                c = content[j]
                if in_str:
                    if c == in_str and (j == 0 or content[j-1] != "\\"):
                        in_str = None
                        t = current.strip().strip("'\"")
                        if t:
                            trims.add(t)
                        current = ""
                    elif c != "\\":
                        current += c
                elif c in "\"'" and (j == 0 or content[j-1] != "\\"):
                    in_str = c
                    current = ""
                elif c == "[":
                    brace_depth += 1
                elif c == "]":
                    brace_depth -= 1
                    if brace_depth < 0:
                        break
                j += 1
            i = j
        i += 1
        if i >= len(content):
            break
    return trims


def extract_trims_simple(content):
    """Extract trim strings by finding all 'TrimName' inside trimsByBrandModel section."""
    start = content.find("trimsByBrandModel = {")
    if start == -1:
        return set()
    end = content.find("};", start)
    if end == -1:
        end = len(content)
    section = content[start:end]
    # Every quoted string that looks like a trim (not a brand or model key) - we get all quoted strings in the trim list values
    # Models are keys like 'ILX':; trims are list elements. So we want strings that are inside [ ... ] and are not immediately followed by :
    strings = re.findall(r"'([^'\\]*(?:\\.[^'\\]*)*)'", section)
    trims = set()
    for s in strings:
        t = s.replace("\\'", "'").strip()
        if not t:
            continue
        # Skip if it looks like a model name (all caps or CamelCase short)
        if t in ("Acura", "Aston Martin", "Audi", "Baic", "Baojun", "Bentley", "BMW", "Buick", "BYD", "Cadillac"):
            continue
        if len(t) > 1 and not t.isupper() or " " in t or "/" in t or "-" in t or t.isdigit() or any(c.isdigit() for c in t):
            trims.add(t)
    return trims


def extract_trims_by_scan(content):
    """Scan for trim lists only inside trimsByBrandModel section. Pattern: 'Model': [ 'Trim', ... ],"""
    start = content.find("static final Map<String, Map<String, List<String>>> trimsByBrandModel = {")
    if start == -1:
        return set()
    end = content.find("\n  };", start + 10)
    if end == -1:
        end = len(content)
    section = content[start:end]
    trims = set()
    pos = 0
    while True:
        # Find "': [" which starts a trim list (after model name)
        idx = section.find("': [", pos)
        if idx == -1:
            break
        list_start = idx + 4
        depth = 1
        i = list_start
        in_quote = None
        cur = []
        buf = ""
        while i < len(section) and depth >= 0:
            c = section[i]
            if in_quote:
                if c == in_quote and (i == 0 or section[i-1] != "\\"):
                    in_quote = None
                    cur.append(buf.strip().strip("'\""))
                    buf = ""
                elif c != "\\":
                    buf += c
            elif c in "\"'" and (i == 0 or section[i-1] != "\\"):
                in_quote = c
                buf = ""
            elif c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    for t in cur:
                        if t:
                            trims.add(t)
                    break
            i += 1
        pos = list_start + 1
    return trims


def main():
    content = CATALOG_PATH.read_text(encoding="utf-8")

    brands = extract_brands(content)
    print(f"Brands: {len(brands)}")

    models_map = extract_models_map(content)
    total_models = sum(len(v) for v in models_map.values())
    print(f"Models: {total_models} across {len(models_map)} brands")

    # Build brand|model keys (lowercase)
    model_keys = set()
    for brand, models in models_map.items():
        for m in models:
            model_keys.add((brand.lower().strip(), m.lower().strip()))

    trims = extract_trims_by_scan(content)
    print(f"Trims: {len(trims)}")

    # Load existing translations to preserve them
    existing_path = REPO_ROOT / "lib" / "data" / "car_name_translations.dart"
    existing = existing_path.read_text(encoding="utf-8")

    def extract_map(name, ar_or_ku):
        pattern = rf"static const Map<String, String> _{name}{ar_or_ku}\s*=\s*\{{([^}}]+)\}}"
        m = re.search(pattern, existing, re.DOTALL)
        if not m:
            return {}
        block = m.group(1)
        out = {}
        for m2 in re.finditer(r"'([^']+)'\s*:\s*'([^']*(?:\\'[^']*)*)'", block):
            k, v = m2.group(1).replace("\\'", "'"), m2.group(2).replace("\\'", "'")
            out[k] = v
        return out

    existing_brand_ar = extract_map("brand", "Ar")
    existing_brand_ku = extract_map("brand", "Ku")
    existing_model_ar = {}
    existing_model_ku = {}
    # Parse _modelAr and _modelKu (key is "brand|model")
    for m in re.finditer(r"'([^|]+)\|\s*([^']+)'\s*:\s*'([^']*(?:\\'[^']*)*)'", existing):
        k = f"{m.group(1)}|{m.group(2)}"
        existing_model_ar[k] = m.group(3).replace("\\'", "'")
    for m in re.finditer(r"'([^|]+)\|\s*([^']+)'\s*:\s*'([^']*(?:\\'[^']*)*)'", existing):
        k = f"{m.group(1)}|{m.group(2)}"
        if k not in existing_model_ku:
            # Need to find _modelKu block
            pass
    # Simpler: extract _modelKu block and parse same way
    ku_block = re.search(r"static const Map<String, String> _modelKu\s*=\s*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}", existing, re.DOTALL)
    if ku_block:
        for m in re.finditer(r"'([^|]+)\|\s*([^']+)'\s*:\s*'([^']*(?:\\'[^']*)*)'", ku_block.group(1)):
            k = f"{m.group(1)}|{m.group(2)}"
            existing_model_ku[k] = m.group(3).replace("\\'", "'")

    # Re-extract _modelAr from existing file (full block)
    model_ar_block = re.search(r"static const Map<String, String> _modelAr\s*=\s*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}", existing, re.DOTALL)
    if model_ar_block:
        for m in re.finditer(r"'([^|]+)\|\s*([^']+)'\s*:\s*'([^']*(?:\\'[^']*)*)'", model_ar_block.group(1)):
            k = f"{m.group(1).lower()}|{m.group(2).lower()}"
            existing_model_ar[k] = m.group(3).replace("\\'", "'")
    model_ku_block = re.search(r"static const Map<String, String> _modelKu\s*=\s*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}", existing, re.DOTALL)
    if model_ku_block:
        for m in re.finditer(r"'([^|]+)\|\s*([^']+)'\s*:\s*'([^']*(?:\\'[^']*)*)'", model_ku_block.group(1)):
            k = f"{m.group(1).lower()}|{m.group(2).lower()}"
            existing_model_ku[k] = m.group(3).replace("\\'", "'")

    existing_trim_ar = extract_map("trim", "Ar")
    existing_trim_ku = extract_map("trim", "Ku")

    # Build full brand maps (all brands, existing or transliterated)
    brand_ar = {}
    brand_ku = {}
    for b in brands:
        key = b.lower().strip()
        brand_ar[key] = existing_brand_ar.get(key) or latin_to_arabic(b)
        brand_ku[key] = existing_brand_ku.get(key) or latin_to_kurdish(b)
    # Normalize brand keys: "mercedes-benz" etc.
    for k in list(existing_brand_ar.keys()):
        if k not in brand_ar:
            brand_ar[k] = existing_brand_ar[k]
    for k in list(existing_brand_ku.keys()):
        if k not in brand_ku:
            brand_ku[k] = existing_brand_ku[k]

    # Build full model maps
    model_ar = dict(existing_model_ar)
    model_ku = dict(existing_model_ku)
    for (brand_l, model_l) in model_keys:
        key = f"{brand_l}|{model_l}"
        if key not in model_ar:
            # Use display form for transliteration (capitalize)
            disp = model_l.title() if model_l else model_l
            model_ar[key] = latin_to_arabic(disp)
        if key not in model_ku:
            disp = model_l.title() if model_l else model_l
            model_ku[key] = latin_to_kurdish(disp)

    # Build full trim maps
    trim_ar = dict(existing_trim_ar)
    trim_ku = dict(existing_trim_ku)
    for t in trims:
        key = t.lower().strip()
        if key not in trim_ar:
            trim_ar[key] = latin_to_arabic(t)
        if key not in trim_ku:
            trim_ku[key] = latin_to_kurdish(t)

    # Write Dart file
    def dart_map(name, m, max_entries_per_line=1):
        lines = []
        for k, v in sorted(m.items(), key=lambda x: x[0]):
            # Escape single quotes in value
            v_esc = v.replace("\\", "\\\\").replace("'", "\\'")
            k_esc = k.replace("\\", "\\\\").replace("'", "\\'")
            lines.append(f"    '{k_esc}': '{v_esc}',")
        return "\n".join(lines)

    out = '''import 'package:flutter/widgets.dart';

/// Arabic and Kurdish names for car brands, models, and trims.
/// Keys are lowercase; lookup is case-insensitive. Generated with full catalog coverage.
class CarNameTranslations {
  CarNameTranslations._();

  static const Map<String, String> _brandAr = {
''' + dart_map("_brandAr", brand_ar) + '''
  };

  static const Map<String, String> _brandKu = {
''' + dart_map("_brandKu", brand_ku) + '''
  };

  /// Model translations: key "brand|model" lowercase.
  static const Map<String, String> _modelAr = {
''' + dart_map("_modelAr", model_ar) + '''
  };

  static const Map<String, String> _modelKu = {
''' + dart_map("_modelKu", model_ku) + '''
  };

  /// Trim translations: key = lowercase trim name.
  static const Map<String, String> _trimAr = {
''' + dart_map("_trimAr", trim_ar) + '''
  };

  static const Map<String, String> _trimKu = {
''' + dart_map("_trimKu", trim_ku) + '''
  };

  static String _key(String? s) => (s ?? '').trim().toLowerCase();

  static String getLocalizedBrand(BuildContext context, String? brand) {
    if (brand == null || brand.isEmpty) return '';
    final k = _key(brand);
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'ar') return _brandAr[k] ?? brand;
    if (locale == 'ku') return _brandKu[k] ?? brand;
    return brand;
  }

  static String getLocalizedModel(BuildContext context, String? brand, String? model) {
    if (model == null || model.isEmpty) return '';
    final key = '${_key(brand)}|${_key(model)}';
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'ar') return _modelAr[key] ?? model;
    if (locale == 'ku') return _modelKu[key] ?? model;
    return model;
  }

  /// Returns localized trim name for current locale, or original if not found.
  static String getLocalizedTrim(BuildContext context, String? trim) {
    if (trim == null || trim.isEmpty) return '';
    final k = _key(trim);
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'ar') return _trimAr[k] ?? trim;
    if (locale == 'ku') return _trimKu[k] ?? trim;
    return trim;
  }

  /// Returns localized "Brand Model" or "Brand Model Trim" for display.
  static String getLocalizedCarTitle(BuildContext context, Map<String, dynamic>? car) {
    if (car == null) return '';
    final brand = car['brand']?.toString().trim() ?? '';
    final model = car['model']?.toString().trim() ?? '';
    final trim = car['trim']?.toString().trim();
    final year = car['year']?.toString().trim();

    final locBrand = getLocalizedBrand(context, brand.isEmpty ? null : brand);
    final locModel = getLocalizedModel(context, brand.isEmpty ? null : brand, model.isEmpty ? null : model);
    final parts = <String>[locBrand, locModel];
    if (trim != null && trim.isNotEmpty) {
      parts.add(getLocalizedTrim(context, trim));
    }
    var title = parts.join(' ').trim();
    if (year != null && year.isNotEmpty) {
      title = '{dollar}title {dollar}year'.trim();
    }
    return title.isEmpty ? (car['title']?.toString() ?? '') : title;
  }

  /// Brand + model only (no trim, no year). Caller can append translated trim.
  static String getLocalizedCarTitleNoYear(BuildContext context, Map<String, dynamic>? car) {
    if (car == null) return '';
    final brand = car['brand']?.toString().trim() ?? '';
    final model = car['model']?.toString().trim() ?? '';

    final locBrand = getLocalizedBrand(context, brand.isEmpty ? null : brand);
    final locModel = getLocalizedModel(context, brand.isEmpty ? null : brand, model.isEmpty ? null : model);
    final title = [locBrand, locModel].join(' ').trim();
    return title.isEmpty ? (car['title']?.toString() ?? '') : title;
  }
}
'''.replace("{dollar}", "$")
    OUTPUT_PATH.write_text(out, encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH} ({len(brand_ar)} brands, {len(model_ar)} models, {len(trim_ar)} trims)")


if __name__ == "__main__":
    main()
