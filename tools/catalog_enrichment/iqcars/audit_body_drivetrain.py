"""READ-ONLY body-type / drivetrain source audit (no app, dataset or overlay change).

Inputs (all read-only):
  assets/car_spec_dataset.json            raw CarNet/Autodata-style spec dataset
  assets/car_catalog.json                 app catalog (1,635 models)
  _body_drive_probe.json                  output of audit/body_drivetrain_dump_test.dart
                                          (real Flutter resolver: per-tuple app values and per-model
                                          family names + Search lists)

Outputs:
  tools/catalog_enrichment/iqcars/generated/car_spec_body_drivetrain_audit.json
  tools/catalog_enrichment/iqcars/generated/car_spec_body_drivetrain_audit.md

The Python `norm_body` / `norm_drive` below are a line-by-line transcription of
`CarSpecIndex._mapSpecToFormFields` (lib/services/car_spec_index_helpers.dart) used ONLY to
label the rule that fired; they are cross-checked against the real Dart output for every distinct
raw tuple of the dataset (see `normalizer_crosscheck`).
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from canonical_io import write_text_canonical  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEN = ROOT / 'tools' / 'catalog_enrichment' / 'iqcars' / 'generated'

SEARCH_BODY_LADDER = ['Sedan', 'SUV', 'Hatchback', 'Coupe', 'Convertible', 'Wagon',
                      'Pickup', 'Van', 'Minivan']
SEARCH_DRIVE_LADDER = ['FWD', 'RWD', 'AWD']


# ---------------------------------------------------------------- transcription of the Dart code
def norm_body(raw: str | None):
    """-> (app_label, rule). rule 'DEFAULT' means nothing matched and the app falls back to Sedan."""
    b = (raw or '').lower()
    if 'suv' in b:
        return 'SUV', "contains 'suv'"
    if 'sport-utility' in b:
        return 'SUV', "contains 'sport-utility'"
    if 'off-road' in b:
        return 'SUV', "contains 'off-road'"
    if 'wagon' in b and 'sport' in b:
        return 'SUV', "contains 'wagon'+'sport'"
    if 'hatch' in b:
        return 'Hatchback', "contains 'hatch'"
    if 'coupe' in b:
        return 'Coupe', "contains 'coupe'"
    if 'pickup' in b:
        return 'Pickup', "contains 'pickup'"
    if 'truck' in b:
        return 'Pickup', "contains 'truck'"
    if 'van' in b:
        return 'Van', "contains 'van'"
    if 'sedan' in b:
        return 'Sedan', "contains 'sedan'"
    if 'saloon' in b:
        return 'Sedan', "contains 'saloon'"
    return 'Sedan', 'DEFAULT'


def norm_drive(drivetrain: str | None, traction: str | None):
    dr = f"{drivetrain or ''} {(traction or '')}".lower()
    if 'awd' in dr:
        return 'AWD', "contains 'awd'"
    if '4wd' in dr or '4-wd' in dr:
        return '4WD', "contains '4wd'"
    if 'rwd' in dr or 'rear-wheel' in dr:
        return 'RWD', "contains 'rwd'"
    if 'fwd' in dr or 'front-wheel' in dr:
        return 'FWD', "contains 'fwd'"
    return 'FWD', 'DEFAULT'


def drive_consistency(drivetrain, traction):
    """True when both source fields exist and name different drive layouts."""
    def lay(s):
        s = (s or '').lower()
        if 'rear' in s or 'rwd' in s:
            return 'RWD'
        if 'front' in s or 'fwd' in s:
            return 'FWD'
        if 'all wheel' in s or 'awd' in s or '4x4' in s:
            return 'AWD'
        return None
    a, b = lay(drivetrain), lay(traction)
    return a is not None and b is not None and a != b


def spaced(s: str) -> str:
    return re.sub(r'\s+', ' ', re.sub(r'[-_]', ' ', s.strip().lower()))


def alnum(s: str) -> str:
    return re.sub(r'[^a-z0-9]', '', s.lower())


def main() -> None:
    ds = json.loads((ROOT / 'assets' / 'car_spec_dataset.json').read_text(encoding='utf-8'))
    cat = json.loads((ROOT / 'assets' / 'car_catalog.json').read_text(encoding='utf-8'))
    probe = json.loads((ROOT / '_body_drive_probe.json').read_text(encoding='utf-8'))

    brands = {b['id']: b['name'] for b in ds['brands']}
    trims_by_model = defaultdict(list)
    for t in ds['trims']:
        trims_by_model[t['model_id']].append(t)
    spec_by_trim = {s['trim_id']: s for s in ds['specs']}
    rows_by_brand_name = defaultdict(list)  # (brand_key, name) -> [model row]
    for m in ds['models']:
        rows_by_brand_name[(spaced(brands[m['brand_id']]), m['name'])].append(m)

    def row_info(m):
        tr = trims_by_model[m['id']]
        sp = [spec_by_trim[t['id']] for t in tr if t['id'] in spec_by_trim]
        s = sp[0] if sp else {}
        pairs = s.get('raw_spec_pairs') or {}
        body_raw, drive_raw, tract = s.get('body_type'), s.get('drivetrain'), pairs.get('Traction:')
        bl, br = norm_body(body_raw)
        dl, dr = norm_drive(drive_raw, tract)
        return {
            'dataset_model_id': m['id'],
            'raw_name': m['name'],
            'year': tr[0]['year'] if tr else None,
            'year_end': tr[0]['year_end'] if tr else None,
            'raw_body': body_raw,
            'raw_drivetrain': drive_raw,
            'raw_traction': tract,
            'raw_fuel': s.get('fuel_type'),
            'seats': s.get('seats'),
            'app_body': bl,
            'body_rule': br,
            'body_via_default': br == 'DEFAULT',
            'app_drive': dl,
            'drive_rule': dr,
            'drive_via_default': dr == 'DEFAULT',
            'drive_source_conflict': drive_consistency(drive_raw, tract),
        }

    # ---------------------------------------------------------------- 3/4: vocabulary + cross-check
    combos = probe['combos']
    mism = []
    for c in combos:
        bl, _ = norm_body(c['body_raw'])
        dl, _ = norm_drive(c['drivetrain_raw'], c['traction_raw'])
        if c['app_body'] != [bl] or c['app_drive'] != [dl]:
            mism.append({'combo': c, 'python': [bl, dl]})
    crosscheck = {
        'distinct_raw_tuples_checked_against_real_dart_resolver': len(combos),
        'mismatches': len(mism),
        'mismatch_samples': mism[:5],
    }

    specs = ds['specs']
    body_vocab = Counter(s.get('body_type') for s in specs)
    body_table = []
    for raw, n in sorted(body_vocab.items(), key=lambda kv: -kv[1]):
        lab, rule = norm_body(raw)
        low = (raw or '').lower()
        flags = []
        if not raw:
            flags.append('BLANK')
        if rule == 'DEFAULT':
            flags.append('FALLS_THROUGH_TO_DEFAULT_SEDAN')
        if 'pick' in low:
            flags.append('PICKUP_VARIANT')
        if any(k in low for k in ('suv', 'off-road', 'crossover', 'sav', 'cuv', 'sac')):
            flags.append('SUV_OFFROAD_CROSSOVER_FAMILY')
        if any(k in low for k in ('wagon', 'estate')):
            flags.append('WAGON_ESTATE_FAMILY')
        if 'minivan' in low or 'mpv' in low:
            flags.append('MINIVAN_MPV_FAMILY')
        if raw and ',' in raw:
            flags.append('MULTI_VALUE')
        if lab != (raw or '') and rule != 'DEFAULT':
            flags.append('ALIAS_NOT_EXACT')
        body_table.append({'raw': raw, 'app_value': lab, 'rule': rule, 'rows': n, 'flags': flags})
    case_variants = defaultdict(set)
    for raw in body_vocab:
        case_variants[(raw or '').lower().replace('-', '').replace(' ', '')].add(raw)
    body_spelling_variants = [sorted(v) for v in case_variants.values() if len(v) > 1]

    drive_vocab = Counter((s.get('drivetrain'), (s.get('raw_spec_pairs') or {}).get('Traction:'))
                          for s in specs)
    drive_table = []
    for (dv, tv), n in sorted(drive_vocab.items(), key=lambda kv: -kv[1]):
        lab, rule = norm_drive(dv, tv)
        flags = []
        if not dv and not tv:
            flags.append('BLANK_BOTH')
        if rule == 'DEFAULT':
            flags.append('FALLS_THROUGH_TO_DEFAULT_FWD')
        if drive_consistency(dv, tv):
            flags.append('DRIVETRAIN_VS_TRACTION_CONFLICT')
        drive_table.append({'raw_drivetrain': dv, 'raw_traction': tv, 'app_value': lab,
                            'rule': rule, 'rows': n, 'flags': flags})

    trans_vocab = Counter(s.get('transmission') for s in specs)
    fuel_vocab = Counter(s.get('fuel_type') for s in specs)
    seat_vocab = Counter(s.get('seats') for s in specs)

    def seat_label(n):
        if n is None or n <= 0:
            return None
        if str(n) in ('2', '4', '5', '6', '7', '8'):
            return str(n)
        for lim, lab in ((2, '2'), (4, '4'), (5, '5'), (6, '6'), (7, '7')):
            if n <= lim:
                return lab
        return '8'
    seat_table = [{'raw': k, 'app_value': seat_label(k), 'rows': v,
                   'remapped': k is not None and seat_label(k) != str(k)}
                  for k, v in sorted(seat_vocab.items(), key=lambda kv: (kv[0] is None, kv[0] or 0))]

    # ---------------------------------------------------------------- 5: every catalog model
    models_out = []
    flag_counts = Counter()
    for pm in probe['models']:
        b, m = pm['brand'], pm['model']
        rows = []
        for nm in pm['family_names']:
            rows += rows_by_brand_name.get((spaced(b), nm), [])
        infos = [row_info(r) for r in rows]
        body = defaultdict(lambda: {'rows': 0, 'rule_rows': 0, 'default_rows': 0, 'raw': Counter()})
        drive = defaultdict(lambda: {'rows': 0, 'rule_rows': 0, 'default_rows': 0,
                                     'conflict_rows': 0, 'raw': Counter()})
        for i in infos:
            e = body[i['app_body']]
            e['rows'] += 1
            e['default_rows' if i['body_via_default'] else 'rule_rows'] += 1
            e['raw'][i['raw_body']] += 1
            e = drive[i['app_drive']]
            e['rows'] += 1
            e['default_rows' if i['drive_via_default'] else 'rule_rows'] += 1
            e['conflict_rows'] += int(i['drive_source_conflict'])
            e['raw'][f"{i['raw_drivetrain']}|{i['raw_traction']}"] += 1

        def fin(d):
            return {k: {**v, 'raw': dict(v['raw'])} for k, v in sorted(d.items())}
        body, drive = fin(body), fin(drive)
        flags = []
        # computed-vs-Dart cross check (baseline sets from the real resolver)
        if infos:
            if sorted(body) != pm['baseline_body']:
                flags.append('PY_VS_DART_BODY_MISMATCH')
            if sorted(drive) != pm['baseline_drive']:
                flags.append('PY_VS_DART_DRIVE_MISMATCH')
        sb = [x for x in pm['search_body'] if x != 'Any']
        sd = [x for x in pm['search_drive'] if x != 'Any']
        # BODY flags
        if not pm['search_body_narrowed']:
            flags.append('BODY_NO_MODEL_DATA_FULL_LADDER_SHOWN')
        else:
            if 'Sedan' in body and body['Sedan']['rule_rows'] == 0:
                flags.append('BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK')
            if 'Sedan' in body and body['Sedan']['default_rows'] > 0:
                flags.append('BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK')
            for lab, v in body.items():
                if v['default_rows']:
                    break
            if any(v['default_rows'] for v in body.values()):
                flags.append('BODY_ANY_ROW_USES_DEFAULT')
            pick_rows = sum(n for lab in body for raw, n in body[lab]['raw'].items()
                            if raw and 'pick' in raw.lower() and lab != 'Pickup')
            if pick_rows:
                flags.append('BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP')
            if 'SUV' in body and 'Sedan' in body and body['Sedan']['rule_rows'] == 0:
                flags.append('BODY_SUV_WITH_UNSUPPORTED_SEDAN')
            if 'Hatchback' in body and 'Van' in body:
                flags.append('BODY_HATCHBACK_PLUS_VAN')
            if 'Pickup' not in body and any(r['raw_body'] and 'pick' in r['raw_body'].lower()
                                            for r in infos):
                flags.append('BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION')
            if len(sb) >= 4:
                flags.append('BODY_4PLUS_CATEGORIES')
            if len(sb) >= 5:
                flags.append('BODY_5PLUS_CATEGORIES')
            minivan_rows = sum(n for lab in body for raw, n in body[lab]['raw'].items()
                               if raw and 'minivan' in raw.lower() and lab == 'Van')
            if minivan_rows:
                flags.append('BODY_MINIVAN_RAW_MAPPED_TO_VAN')
        # DRIVE flags
        if not pm['search_drive_narrowed']:
            flags.append('DRIVE_NO_MODEL_DATA_FULL_LADDER_SHOWN')
        else:
            if 'FWD' in drive and drive['FWD']['rule_rows'] == 0:
                flags.append('DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT')
            if 'FWD' in drive and drive['FWD']['default_rows'] > 0:
                flags.append('DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT')
            if any(v['default_rows'] for v in drive.values()):
                flags.append('DRIVE_ANY_ROW_USES_DEFAULT')
            if any(v['conflict_rows'] for v in drive.values()):
                flags.append('DRIVE_SOURCE_FIELDS_CONFLICT')
            if 'RWD' in drive and drive['RWD']['conflict_rows'] == drive['RWD']['rows']:
                flags.append('DRIVE_RWD_ONLY_FROM_CONFLICTING_ROWS')
            if len(sd) >= 3:
                flags.append('DRIVE_EVERY_OPTION')
        for f in flags:
            flag_counts[f] += 1
        models_out.append({
            'brand': b, 'model': m,
            'dataset_rows_in_family': len(infos),
            'has_coverage': pm['has_coverage'],
            'search_body': pm['search_body'], 'search_drive': pm['search_drive'],
            'search_body_narrowed': pm['search_body_narrowed'],
            'search_drive_narrowed': pm['search_drive_narrowed'],
            'body': body, 'drive': drive, 'flags': flags,
        })

    def has(f):
        return [x for x in models_out if f in x['flags']]

    body_fallback_models = [x for x in models_out if 'BODY_ANY_ROW_USES_DEFAULT' in x['flags']]
    body_displayed_unsupported = [x for x in models_out if 'BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK' in x['flags']]
    drive_fallback_models = [x for x in models_out if 'DRIVE_ANY_ROW_USES_DEFAULT' in x['flags']]
    drive_displayed_unsupported = [x for x in models_out if 'DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT' in x['flags']]
    nodata_body = has('BODY_NO_MODEL_DATA_FULL_LADDER_SHOWN')
    nodata_drive = has('DRIVE_NO_MODEL_DATA_FULL_LADDER_SHOWN')

    # ---------------------------------------------------------------- 1/2/6: row level for key models
    cat_models = {b: ms for b, ms in cat['models'].items()}

    def resolve(brand, wants):
        out = []
        for want in wants:
            hit = [m for m in cat_models.get(brand, []) if alnum(m) == alnum(want)]
            out.append((want, hit[0] if hit else None))
        return out

    HP = {
        'Volkswagen': ['Golf', 'Golf R', 'Tiguan', 'Passat'],
        'Toyota': ['Land Cruiser', 'Land Cruiser Prado', 'Corolla', 'Corolla Cross', 'Hilux',
                   'Camry', 'RAV4'],
        'BMW': ['3-Series', '4-Series', '5-Series', 'X1', 'X3', 'X5'],
        'Lexus': ['LX', 'GX', 'RX'],
        'Ford': ['Everest', 'Bronco', 'Mustang'],
        'Nissan': ['Patrol'],
    }
    by_key = {(x['brand'], x['model']): x for x in models_out}
    probe_by_key = {(x['brand'], x['model']): x for x in probe['models']}
    hp_out = []
    for brand, wants in HP.items():
        for want, got in resolve(brand, wants):
            if got is None:
                hp_out.append({'brand': brand, 'requested': want, 'catalog_model': None})
                continue
            mo = by_key[(brand, got)]
            siblings = [m for m in cat_models[brand]
                        if spaced(m).startswith(spaced(got) + ' ')]
            hp_out.append({
                'brand': brand, 'requested': want, 'catalog_model': got,
                'catalog_longer_siblings': siblings,
                'dataset_rows': mo['dataset_rows_in_family'],
                'search_body': mo['search_body'], 'search_drive': mo['search_drive'],
                'body': {k: {'rows': v['rows'], 'via_rule': v['rule_rows'], 'via_default': v['default_rows'],
                             'raw': v['raw']} for k, v in mo['body'].items()},
                'drive': {k: {'rows': v['rows'], 'via_rule': v['rule_rows'], 'via_default': v['default_rows'],
                              'source_conflict_rows': v['conflict_rows'], 'raw': v['raw']}
                          for k, v in mo['drive'].items()},
                'flags': mo['flags'],
            })

    def detail_rows(brand, model):
        pm = probe_by_key[(brand, model)]
        rows = []
        for nm in pm['family_names']:
            rows += rows_by_brand_name.get((spaced(brand), nm), [])
        sibs = [m for m in cat_models[brand] if spaced(m).startswith(spaced(model) + ' ')]
        out = []
        fam = spaced(model)
        for r in sorted(rows, key=lambda r: (trims_by_model[r['id']][0]['year']
                                             if trims_by_model[r['id']] else 0, r['id'])):
            i = row_info(r)
            rest = spaced(r['name'])[len(fam):].strip()
            tok = rest.split(' ')[0] if rest else ''
            i['why_matches'] = (f"dataset name starts with canonical '{model}' (spaced-prefix match) "
                                f"and no longer catalog sibling claims it")
            i['absorbed_subname_token'] = tok
            i['subname_is_alpha_word'] = bool(re.fullmatch(r'[a-zA-Z][a-zA-Z\-]+', tok)) if tok else False
            i['more_specific_catalog_sibling_exists'] = bool(sibs)
            i['catalog_longer_siblings'] = sibs
            out.append(i)
        return out

    detail = {}
    for brand, model in (('Volkswagen', 'Golf'), ('Toyota', 'Land Cruiser')):
        rows = detail_rows(brand, model)
        sel = {}
        for lab in sorted({r['app_body'] for r in rows}):
            sel[f'body={lab}'] = [r for r in rows if r['app_body'] == lab]
        for lab in sorted({r['app_drive'] for r in rows}):
            sel[f'drive={lab}'] = [r for r in rows if r['app_drive'] == lab]
        detail[f'{brand}|{model}'] = {
            'catalog_longer_siblings': rows[0]['catalog_longer_siblings'] if rows else [],
            'family_row_count': len(rows),
            'search_body': probe_by_key[(brand, model)]['search_body'],
            'search_drive': probe_by_key[(brand, model)]['search_drive'],
            'by_value': sel,
        }

    # rows for every high priority model that contribute a suspicious value (compact)
    hp_suspicious = {}
    for h in hp_out:
        if h.get('catalog_model') is None:
            continue
        rows = detail_rows(h['brand'], h['catalog_model'])
        sus = [r for r in rows if r['body_via_default'] or r['drive_via_default']
               or r['drive_source_conflict']
               or (r['raw_body'] and 'pick' in r['raw_body'].lower())
               or (r['raw_body'] and 'minivan' in r['raw_body'].lower())]
        hp_suspicious[f"{h['brand']}|{h['catalog_model']}"] = {
            'suspicious_row_count': len(sus), 'sample_rows': sus[:12]}

    # source rows of the 5 conflicting drive rows and blank rows summary
    conflict_rows = []
    blank_drive_by_brand = Counter()
    pick_rows_total = 0
    for m in ds['models']:
        tr = trims_by_model[m['id']]
        s = spec_by_trim.get(tr[0]['id']) if tr else None
        if not s:
            continue
        t = (s.get('raw_spec_pairs') or {}).get('Traction:')
        if drive_consistency(s.get('drivetrain'), t):
            conflict_rows.append({'brand': brands[m['brand_id']], 'name': m['name'],
                                  'year': tr[0]['year'], 'drivetrain': s.get('drivetrain'),
                                  'traction': t})
        if not s.get('drivetrain') and not t:
            blank_drive_by_brand[brands[m['brand_id']]] += 1

    summary = {
        'catalog_models_audited': len(models_out),
        'dataset_spec_rows': len(specs),
        'body_default_to_sedan_rows': sum(n for r, n in body_vocab.items() if norm_body(r)[1] == 'DEFAULT'),
        'body_blank_rows': body_vocab.get(None, 0) + body_vocab.get('', 0),
        'drive_default_to_fwd_rows': sum(x['rows'] for x in drive_table if x['rule'] == 'DEFAULT'),
        'drive_conflict_rows': sum(x['rows'] for x in drive_table if 'DRIVETRAIN_VS_TRACTION_CONFLICT' in x['flags']),
        'models_with_any_body_default_row': len(body_fallback_models),
        'models_with_sedan_only_from_default': len(body_displayed_unsupported),
        'models_with_any_drive_default_row': len(drive_fallback_models),
        'models_with_fwd_only_from_blank_default': len(drive_displayed_unsupported),
        'models_with_no_body_data_full_ladder': len(nodata_body),
        'models_with_no_drive_data_full_ladder': len(nodata_drive),
        'flag_counts': dict(sorted(flag_counts.items())),
    }

    def top(lst, keyfn, n=25):
        return [{'brand': x['brand'], 'model': x['model'], 'rows': x['dataset_rows_in_family'],
                 'search_body': [b for b in x['search_body'] if b != 'Any'],
                 'search_drive': [d for d in x['search_drive'] if d != 'Any'],
                 'flags': x['flags']} for x in sorted(lst, key=keyfn)[:n]]

    suspicious_body = [x for x in models_out if any(f in x['flags'] for f in (
        'BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK', 'BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP',
        'BODY_SUV_WITH_UNSUPPORTED_SEDAN', 'BODY_HATCHBACK_PLUS_VAN', 'BODY_5PLUS_CATEGORIES'))]
    suspicious_drive = [x for x in models_out if any(f in x['flags'] for f in (
        'DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT', 'DRIVE_RWD_ONLY_FROM_CONFLICTING_ROWS',
        'DRIVE_SOURCE_FIELDS_CONFLICT', 'DRIVE_EVERY_OPTION'))]

    result = {
        'meta': {'read_only': True, 'note': 'No Flutter, dataset or overlay change. IQ overlay supplies neither body nor drivetrain.'},
        'summary': summary,
        'normalizer_crosscheck': crosscheck,
        'normalizer_audit': NORMALIZER_AUDIT,
        'vocabulary': {
            'body': body_table, 'body_spelling_case_variants': body_spelling_variants,
            'drivetrain': drive_table,
            'transmission': [{'raw': k, 'app_value': 'Manual' if k and 'manual' in k.lower() else 'Automatic',
                              'rows': v} for k, v in trans_vocab.items()],
            'fuel': [{'raw': k, 'rows': v} for k, v in fuel_vocab.items()],
            'seats': seat_table,
        },
        'drivetrain_conflict_rows': conflict_rows,
        'blank_drivetrain_rows_by_brand': dict(blank_drive_by_brand.most_common()),
        'detail_golf_land_cruiser': detail,
        'high_priority_models': hp_out,
        'high_priority_suspicious_rows': hp_suspicious,
        'top_suspicious_body_models': top(suspicious_body, lambda x: (-len(x['flags']), -x['dataset_rows_in_family'])),
        'top_suspicious_drive_models': top(suspicious_drive, lambda x: (-len(x['flags']), -x['dataset_rows_in_family'])),
        'models': models_out,
    }
    GEN.mkdir(parents=True, exist_ok=True)
    write_text_canonical(GEN / 'car_spec_body_drivetrain_audit.json',
                         json.dumps(result, indent=1, ensure_ascii=False) + '\n')
    write_text_canonical(GEN / 'car_spec_body_drivetrain_audit.md', render_md(result) + '\n')
    print(json.dumps(summary, indent=1))
    print('crosscheck', crosscheck['mismatches'], 'of', crosscheck['distinct_raw_tuples_checked_against_real_dart_resolver'])


NORMALIZER_AUDIT = [
    {'field': 'body', 'where': 'lib/services/car_spec_index_helpers.dart `_mapSpecToFormFields` (bodyType, ~L397-414)',
     'default': "String bodyType = 'sedan' is assigned BEFORE any rule runs; the final else-if is `sedan||saloon` (redundant)",
     'unknown_or_blank_becomes': 'Sedan', 'fabricates_fact': True,
     'detail': "Any raw value that contains none of suv/sport-utility/off-road/(wagon+sport)/hatch/coupe/pickup/truck/van/sedan/saloon silently becomes Sedan: Station wagon (estate), Pick-up (hyphen!), Cabriolet, MPV, Roadster, Liftback, Fastback, Crossover, Targa, SAV, SAC, CUV, Grand Tourer, Quadricycle. A blank body also becomes Sedan (none exist today). `Minivan` matches `van` and becomes Van."},
    {'field': 'body label', 'where': 'lib/services/car_spec_index_sell_labels.dart `sellFlowBodyLabel` `default:`',
     'default': "default -> 'Sedan'", 'unknown_or_blank_becomes': 'Sedan', 'fabricates_fact': True,
     'detail': 'Second, independent default: any api value other than suv/hatchback/coupe/pickup/van is labelled Sedan. Used by sellFieldOptionsUnion, Sell autofill and the Search/Sell lists.'},
    {'field': 'drivetrain', 'where': 'lib/services/car_spec_index_helpers.dart `_mapSpecToFormFields` (driveType, ~L384-395)',
     'default': "String driveType = 'fwd' assigned before any rule", 'unknown_or_blank_becomes': 'FWD',
     'fabricates_fact': True,
     'detail': "Blank drivetrain with no Traction text (1,777 dataset rows) becomes FWD. `rear-wheel`/`front-wheel` hyphenated hints never match the dataset's `Rear wheel drive` / `Front wheel drive` (space), so Traction text only helps through `awd`/`4wd` substrings; the explicit `drivetrain` field is what really decides. When the two source fields disagree (5 rows: drivetrain RWD vs Traction Front wheel drive) RWD wins silently. `4WD` can only be produced from literal `4wd` text which the dataset never contains (4x4 is stored as AWD)."},
    {'field': 'drivetrain label', 'where': '`sellFlowDriveLabel` `default:`', 'default': "default -> 'FWD'",
     'unknown_or_blank_becomes': 'FWD', 'fabricates_fact': True,
     'detail': 'Second default. Also the Search drive ladder is only FWD/RWD/AWD, so a 4WD label could never be offered in Search even if produced.'},
    {'field': 'transmission', 'where': '`_mapSpecToFormFields` + `sellFlowTransmissionLabel`',
     'default': "'automatic' unless the text contains 'manual'", 'unknown_or_blank_becomes': 'Automatic',
     'fabricates_fact': True,
     'detail': 'Dataset has no blank transmission today (Automatic 25,506 / Manual 16,624), so no effect now, but a blank or CVT/DCT/semi-auto value would silently be Automatic or Manual-by-substring.'},
    {'field': 'fuel', 'where': '`_mapSpecToFormFields` + `sellFlowFuelLabel`',
     'default': "'gasoline' unless diesel/electric/hybrid substring", 'unknown_or_blank_becomes': 'Gasoline',
     'fabricates_fact': True,
     'detail': "Dataset has only Petrol (Gasoline) / Diesel / Electric (no blanks). `hybrid` can never be produced from this dataset (hybrids are stored as Petrol), so every hybrid is Gasoline. A blank fuel would become Gasoline."},
    {'field': 'seats', 'where': '`_mapSpecToFormFields` + `sellFlowNearestSeatingLabel`',
     'default': 'null seats -> no option (correct)', 'unknown_or_blank_becomes': 'no option',
     'fabricates_fact': False,
     'detail': "Blank seats are NOT defaulted (1,245 rows give no option). But counts are rounded to the nearest offered label: 1->2, 3->4, 9/10/14->8 (a changed fact, but derived from a real value)."},
    {'field': 'Search narrowing fallback', 'where': '`narrowOptionsToCatalog` (car_spec_index_types.dart) used by `HomeVehicleFieldOptions.resolve`',
     'default': 'known == null or empty -> the FULL generic ladder', 'unknown_or_blank_becomes': 'every option',
     'fabricates_fact': True,
     'detail': "When a selected model has no body/drivetrain data (no dataset coverage, or no family rows) Search shows the whole body ladder (Sedan..Minivan) and FWD/RWD/AWD as if all applied. Only cylinders/engine size get the `Any only` treatment today."},
]


FINDINGS = """## Findings (answers)

1. **Golf Sedan** - 205 of 657 Golf rows (0 of them say Sedan). Raw body is `Station wagon (estate)` (152), `Cabriolet` (44) and
   `Station wagon (estate), Crossover` (9). None contains a recognised keyword, so `_mapSpecToFormFields` leaves the pre-assigned
   `bodyType = 'sedan'`. Classification: **C - missing/unmapped body defaults to Sedan** (mapping fallback, not model matching).
2. **Golf Van** - 46 rows, raw body is literally `Minivan` (Golf Plus / Sportsvan style rows with plain `Golf N N ...` names, 2004-2019).
   The source says Minivan (model years 2004-2019); the app maps it to **Van** because `'minivan'.contains('van')`, although the Search ladder has
   its own `Minivan` entry that is never produced. Classification: **B - alias mapped to the wrong app value**. Matching note: these rows have plain
   `Golf N N ...` dataset names with no sub-name token, so the strict matcher cannot tell whether they belong to a sibling such as catalog `Golf Plus`
   (not inferred; reported only).
3. **Golf RWD** - exactly 1 row: id 8780 `Golf GLi 1 6 (110 Hp)` 1979-1982, raw drivetrain `RWD` but raw Traction `Front wheel drive`.
   Source field conflict (a malformed source value). The app takes `rwd` first. It is not a default and not a leak.
4. **Land Cruiser Sedan** - 3 rows (ids 3683, 3684, 3732: `Land Cruiser 4 2 D 24V`, `4 5 D-4D V8`, `4 0 i V6`, 2012-2021), raw body `Pick-up`.
   `'pick-up'` does not contain `'pickup'` (hyphen), so it falls through to the default Sedan. Classification: **B - another raw body type
   (Pick-up) is incorrectly mapped to Sedan**; the same rows are Land Cruiser 70-series pickups whose dataset name has no `70` token,
   so they also cannot be separated from catalog sibling `Land Cruiser 70 Pickup` without inference (reported separately, not changed).
5. **Unknown body -> Sedan fallback exists: YES** (two independent defaults: `bodyType = 'sedan'` and `sellFlowBodyLabel` `default`).
6. **Unknown/blank drivetrain -> a factual drivetrain: YES** (`driveType = 'fwd'`, `sellFlowDriveLabel` default `FWD`). 1,777 dataset rows have
   blank drivetrain AND no Traction text and become FWD. Transmission (Automatic), fuel (Gasoline) default the same way but have no blank source rows today.
7. **Models affected by body fallback:** {models_with_any_body_default_row} of the 856 models with dataset coverage have at least one family row
   whose body fell through to the Sedan default; for {models_with_sedan_only_from_default} the offered Sedan has NO supporting explicit Sedan row.
   A further {models_with_no_body_data_full_ladder} models have no dataset rows at all and Search shows them the full generic body ladder.
8. **Models affected by drivetrain fallback:** {models_with_any_drive_default_row} models have at least one blank-source row turned into FWD; for
   {models_with_fwd_only_from_blank_default} the offered FWD is supported only by blank rows. {models_with_no_drive_data_full_ladder} models with no dataset rows show the
   full FWD/RWD/AWD ladder. {drive_conflict_rows} rows have conflicting drivetrain-vs-Traction text.
9. **Biggest single defect:** `Pick-up` (3,383 rows, 46 catalog models incl. Toyota Hilux 84/84 rows) is mapped to Sedan; the app can never offer Pickup
   from this dataset. Station wagon (4,795), Cabriolet (1,352), MPV, Roadster, Liftback, Fastback, Crossover, Targa, SAV, SAC, CUV, Grand Tourer
   also become Sedan. The Search ladder entries Convertible, Wagon and Minivan are therefore unreachable.
10. **Recommended smallest fix** (not implemented): see section "Proposed semantics" below.

## Proposed semantics (report only)

Body (explicit alias table, unmapped -> no option, nothing defaulted):
- `Sedan` -> Sedan; `SUV`, `Off-road vehicle`, `SUV, Crossover`/`Crossover`/`CUV`/`SAV`/`SAC` -> only if the project decides these are SUV (else no option);
- `Hatchback`, `Liftback` -> Hatchback only if approved; `Coupe` -> Coupe; `Pick-up`/`Pickup`/`Pick up` -> Pickup;
- `Van` -> Van; `Minivan`/`MPV` -> Minivan (the ladder already has it); `Station wagon (estate)` -> Wagon; `Cabriolet`/`Roadster`/`Targa` -> Convertible
  (all three ladder entries already exist in Search and Sell);
- every multi-value raw string: use the FIRST listed value only when it is in the alias table, otherwise no option;
- `Fastback`, `Grand Tourer`, `Quadricycle`, blank/unknown -> **no option** (never Sedan).
Drivetrain: `FWD`/`RWD`/`AWD` map 1:1; `4WD`/`4x4`/`All wheel drive (4x4)` -> AWD (existing dataset semantics) ; blank/unknown -> **no option**;
when drivetrain and Traction disagree -> no option for that row.
`sellFlowBodyLabel` / `sellFlowDriveLabel` / transmission / fuel labels must stop returning a default for unknown input (return null).
Search with Brand+Model selected: body/drivetrain list = `Any` + only the values supported by an explicit source row; if none -> `Any only`
(same rule already used for cylinders and engine size), instead of the full generic ladder.
Matching (separate topic): plain-named rows that belong to a catalog sibling (Golf Plus/Sportsvan, Land Cruiser 70 Pickup) cannot be separated
without inference; no change proposed here.

"""


def fmt_rows(rows, limit=60):
    lines = ['| id | raw dataset name | years | raw body | raw drivetrain | raw traction | app body | body path | app drive | drive path |',
             '|---|---|---|---|---|---|---|---|---|---|']
    for r in rows[:limit]:
        lines.append(f"| {r['dataset_model_id']} | {r['raw_name']} | {r['year']}-{r['year_end']} | {r['raw_body']} | "
                     f"{r['raw_drivetrain'] or '(blank)'} | {r['raw_traction'] or '(blank)'} | {r['app_body']} | "
                     f"{'**DEFAULT fallback**' if r['body_via_default'] else r['body_rule']} | {r['app_drive']} | "
                     f"{'**DEFAULT fallback**' if r['drive_via_default'] else r['drive_rule']}"
                     f"{' **(sources conflict)**' if r['drive_source_conflict'] else ''} |")
    if len(rows) > limit:
        lines.append(f'| ... | {len(rows) - limit} more rows | | | | | | | | |')
    return lines


def render_md(r) -> str:
    L = []
    s = r['summary']
    L += ['# CarNet spec dataset - body type / drivetrain source audit', '',
          'READ ONLY. No Flutter code, dataset or overlay was changed. The IQ Cars overlay supplies neither '
          'body type nor drivetrain; everything below comes from the CarNet spec dataset through the '
          'existing Flutter resolver.', '',
          f"Normalizer cross-check: {r['normalizer_crosscheck']['distinct_raw_tuples_checked_against_real_dart_resolver']} "
          f"distinct raw tuples run through the REAL Dart resolver, {r['normalizer_crosscheck']['mismatches']} mismatches "
          'against the transcription used for rule labelling.', '', '## Summary', '']
    for k, v in s.items():
        if k != 'flag_counts':
            L.append(f'- {k}: **{v}**')
    L += ['', '### Flag counts (models)', '']
    for k, v in s['flag_counts'].items():
        L.append(f'- {k}: {v}')
    L += ['', FINDINGS.format(**s)]

    L += ['', '## Normalizer audit (fallback behaviour)', '']
    for n in r['normalizer_audit']:
        L += [f"### {n['field']}", f"- where: {n['where']}", f"- default: {n['default']}",
              f"- unknown/blank becomes: **{n['unknown_or_blank_becomes']}**  (silently factual: {n['fabricates_fact']})",
              f"- {n['detail']}", '']

    L += ['## Raw vocabulary: body', '', '| raw | app value | rule | rows | flags |', '|---|---|---|---|---|']
    for x in r['vocabulary']['body']:
        L.append(f"| {x['raw']} | {x['app_value']} | {'**DEFAULT**' if x['rule'] == 'DEFAULT' else x['rule']} | {x['rows']} | {', '.join(x['flags'])} |")
    L += ['', 'Spelling/case variants (same text ignoring case, hyphen, space): ' +
          (str(r['vocabulary']['body_spelling_case_variants']) if r['vocabulary']['body_spelling_case_variants'] else 'none'), '']
    L += ['## Raw vocabulary: drivetrain (drivetrain + Traction:)', '',
          '| raw drivetrain | raw traction | app value | rule | rows | flags |', '|---|---|---|---|---|---|']
    for x in r['vocabulary']['drivetrain']:
        L.append(f"| {x['raw_drivetrain'] or '(blank)'} | {x['raw_traction'] or '(blank)'} | {x['app_value']} | "
                 f"{'**DEFAULT**' if x['rule'] == 'DEFAULT' else x['rule']} | {x['rows']} | {', '.join(x['flags'])} |")
    L += ['', '## Raw vocabulary: transmission / fuel / seats', '']
    for x in r['vocabulary']['transmission']:
        L.append(f"- transmission {x['raw']} -> {x['app_value']}: {x['rows']}")
    for x in r['vocabulary']['fuel']:
        L.append(f"- fuel {x['raw']}: {x['rows']}")
    for x in r['vocabulary']['seats']:
        L.append(f"- seats {x['raw']} -> {x['app_value']}{' (remapped)' if x['remapped'] else ''}: {x['rows']}")
    L += ['', 'Drivetrain vs Traction conflict rows:', '']
    for c in r['drivetrain_conflict_rows']:
        L.append(f"- {c['brand']} {c['name']} ({c['year']}): drivetrain={c['drivetrain']} traction={c['traction']}")

    for key, d in r['detail_golf_land_cruiser'].items():
        L += ['', f'## Row-level trace: {key}', '',
              f"Family rows accepted by the current matcher: {d['family_row_count']}; catalog longer siblings: {d['catalog_longer_siblings']}",
              f"Search body: {d['search_body']}; Search drive: {d['search_drive']}", '']
        for sel, rows in d['by_value'].items():
            if sel in ('body=Sedan', 'body=Van', 'drive=RWD') or key.endswith('Land Cruiser') and sel == 'body=Sedan':
                L += [f'### {key} -> {sel} ({len(rows)} rows)', ''] + fmt_rows(rows) + ['']
        other = [s2 for s2 in d['by_value'] if s2 not in ('body=Sedan', 'body=Van', 'drive=RWD')]
        L.append('Other values: ' + ', '.join(f"{s2} ({len(d['by_value'][s2])})" for s2 in other))

    L += ['', '## High-priority models', '',
          '| model | rows | Search body | Search drive | body (rows via default) | drive (rows via default) | flags |', '|---|---|---|---|---|---|---|']
    for h in r['high_priority_models']:
        if h.get('catalog_model') is None:
            L.append(f"| {h['brand']} {h['requested']} | model not in catalog | | | | | |")
            continue
        bd = ', '.join(f"{k} {v['rows']}({v['via_default']})" for k, v in h['body'].items())
        dd = ', '.join(f"{k} {v['rows']}({v['via_default']})" for k, v in h['drive'].items())
        L.append(f"| {h['brand']} {h['catalog_model']} | {h['dataset_rows']} | {', '.join(x for x in h['search_body'] if x != 'Any') or 'Any only'} | "
                 f"{', '.join(x for x in h['search_drive'] if x != 'Any') or 'Any only'} | {bd} | {dd} | {', '.join(h['flags'])} |")

    L += ['', '## Top suspicious models (body)', '', '| model | rows | body | drive | flags |', '|---|---|---|---|---|']
    for x in r['top_suspicious_body_models']:
        L.append(f"| {x['brand']} {x['model']} | {x['rows']} | {', '.join(x['search_body'])} | {', '.join(x['search_drive'])} | {', '.join(x['flags'])} |")
    L += ['', '## Top suspicious models (drivetrain)', '', '| model | rows | body | drive | flags |', '|---|---|---|---|---|']
    for x in r['top_suspicious_drive_models']:
        L.append(f"| {x['brand']} {x['model']} | {x['rows']} | {', '.join(x['search_body'])} | {', '.join(x['search_drive'])} | {', '.join(x['flags'])} |")
    L += ['']
    return '\n'.join(L)


if __name__ == '__main__':
    main()
