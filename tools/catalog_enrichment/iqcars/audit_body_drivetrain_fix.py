"""READ-ONLY before/after audit of the body-type / drivetrain normalization fix.

BEFORE = the accepted source audit (generated/car_spec_body_drivetrain_audit.json, produced with the old
         `unknown -> Sedan` / `blank -> FWD` defaults through the real Flutter resolver).
AFTER  = `_body_drive_probe.json`, written by audit/body_drivetrain_dump_test.dart against the FIXED app
         code (real resolver, real default Search ladders, vehicleResolved = true).

The Python `body_keys` / `drive_key` below transcribe lib/services/car_spec_index_body_drive.dart ONLY to
attribute causes (Crossover vs SUV, Liftback vs Hatchback ...); they are cross-checked against the real
Dart output for every distinct raw tuple of the dataset.

Writes generated/car_spec_body_drivetrain_fix_audit.json and .md (canonical CRLF).
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

BODY_TOKENS = {
    'sedan': 'Sedan', 'saloon': 'Sedan',
    'suv': 'SUV', 'off road vehicle': 'SUV', 'sport utility': 'SUV', 'crossover': 'SUV', 'cuv': 'SUV',
    'sav': 'SUV', 'sac': 'SUV',
    'hatchback': 'Hatchback', 'liftback': 'Hatchback',
    'coupe': 'Coupe',
    'pick up': 'Pickup', 'pickup': 'Pickup',
    'station wagon (estate)': 'Wagon', 'station wagon': 'Wagon', 'wagon': 'Wagon', 'estate': 'Wagon',
    'variant': 'Wagon',
    'cabriolet': 'Convertible', 'roadster': 'Convertible', 'targa': 'Convertible',
    'convertible': 'Convertible',
    'minivan': 'Minivan', 'mpv': 'Minivan',
    'van': 'Van',
}
LADDER_ORDER = ['Sedan', 'SUV', 'Hatchback', 'Coupe', 'Convertible', 'Wagon', 'Pickup', 'Van', 'Minivan']


def tokens(raw):
    out = []
    for part in re.split(r'\s*,\s*|\s+-\s+', raw or ''):
        t = re.sub(r'\s+', ' ', part.lower().replace('-', ' ')).strip()
        if t:
            out.append(t)
    return out


def body_keys(raw):
    return {BODY_TOKENS[t] for t in tokens(raw) if t in BODY_TOKENS}


def unmapped_tokens(raw):
    return [t for t in tokens(raw) if t not in BODY_TOKENS]


def drive_field(s):
    t = (s or '').lower().replace('-', ' ').strip()
    if not t:
        return None
    f = set()
    if re.search(r'\bawd\b', t) or 'all wheel' in t or '4x4' in t or re.search(r'\b4 ?wd\b', t) or 'four wheel' in t:
        f.add('AWD')
    if re.search(r'\brwd\b', t) or 'rear wheel' in t:
        f.add('RWD')
    if re.search(r'\bfwd\b', t) or 'front wheel' in t:
        f.add('FWD')
    return next(iter(f)) if len(f) == 1 else None


def drive_key(dt, tr):
    a, b = drive_field(dt), drive_field(tr)
    if a and b:
        return a if a == b else None
    return a or b


def spaced(s):
    return re.sub(r'\s+', ' ', re.sub(r'[-_]', ' ', s.strip().lower()))


def real(lst):
    return [x for x in lst if x != 'Any']


def main():
    ds = json.loads((ROOT / 'assets' / 'car_spec_dataset.json').read_text(encoding='utf-8'))
    before = json.loads((GEN / 'car_spec_body_drivetrain_audit.json').read_text(encoding='utf-8'))
    after = json.loads((ROOT / '_body_drive_probe.json').read_text(encoding='utf-8'))

    # cross-check of the transcription vs the real Dart resolver
    mism = []
    for c in after['combos']:
        exp_b = sorted(body_keys(c['body_raw']))
        exp_d = [drive_key(c['drivetrain_raw'], c['traction_raw'])] if drive_key(c['drivetrain_raw'], c['traction_raw']) else []
        if sorted(c['app_body']) != exp_b or sorted(c['app_drive']) != exp_d:
            mism.append({'combo': c, 'python': [exp_b, exp_d]})

    brands = {b['id']: b['name'] for b in ds['brands']}
    trims = defaultdict(list)
    for t in ds['trims']:
        trims[t['model_id']].append(t)
    specs = {s['trim_id']: s for s in ds['specs']}
    rows_by = defaultdict(list)
    for m in ds['models']:
        rows_by[(spaced(brands[m['brand_id']]), m['name'])].append(m)

    def spec_of(m):
        tr = trims[m['id']]
        return specs.get(tr[0]['id']) if tr else None

    # ---- vocabulary after the fix
    body_vocab = Counter(s.get('body_type') for s in ds['specs'])
    body_rows = []
    unmapped_rows = Counter()
    unmapped_partial = Counter()
    for raw, n in sorted(body_vocab.items(), key=lambda kv: -kv[1]):
        k = body_keys(raw)
        um = unmapped_tokens(raw)
        body_rows.append({'raw': raw, 'rows': n, 'app_values': sorted(k, key=LADDER_ORDER.index),
                          'unmapped_tokens': um})
        if not k:
            unmapped_rows[raw] += n
        for t in um:
            if k:
                unmapped_partial[raw] += n
    drive_vocab = Counter((s.get('drivetrain'), (s.get('raw_spec_pairs') or {}).get('Traction:')) for s in ds['specs'])
    drive_rows = []
    for (dv, tv), n in sorted(drive_vocab.items(), key=lambda kv: -kv[1]):
        drive_rows.append({'raw_drivetrain': dv, 'raw_traction': tv, 'rows': n, 'app_value': drive_key(dv, tv)})
    row_none_body = sum(n for r, n in body_vocab.items() if not body_keys(r))
    row_none_drive = sum(x['rows'] for x in drive_rows if x['app_value'] is None)

    # ---- before / after per model
    bmods = {(m['brand'], m['model']): m for m in before['models']}
    amods = {(m['brand'], m['model']): m for m in after['models']}
    assert set(bmods) == set(amods) and len(amods) == 1635

    metrics = Counter()
    lists = defaultdict(list)
    transitions = Counter()
    per_model = []
    for key in sorted(amods):
        b, a = bmods[key], amods[key]
        bb, ab = set(real(b['search_body'])), set(real(a['search_body']))
        bd, ad = set(real(b['search_drive'])), set(real(a['search_drive']))
        fam_rows = []
        for nm in a['family_names']:
            fam_rows += rows_by.get((spaced(key[0]), nm), [])
        raws = [spec_of(r) for r in fam_rows]
        raws = [s for s in raws if s]
        tok_sets = [set(tokens(s.get('body_type'))) for s in raws]
        any_sedan_src = any({'sedan', 'saloon'} & ts for ts in tok_sets)
        any_fwd_src = any(drive_key(s.get('drivetrain'), (s.get('raw_spec_pairs') or {}).get('Traction:')) == 'FWD'
                          for s in raws)

        def tag(lst, name):
            lists[name].append(f'{key[0]} {key[1]}')
        # Sedan / FWD removed from models that HAVE dataset rows (the false/default ones)
        if fam_rows and 'Sedan' in bb and 'Sedan' not in ab:
            metrics['sedan_removed_false_default_models_with_data'] += 1
            if any_sedan_src:
                metrics['sedan_removed_but_had_explicit_source_SHOULD_BE_0'] += 1
        if 'Sedan' in ab:
            metrics['sedan_kept_with_explicit_source'] += 1
        if fam_rows and 'FWD' in bd and 'FWD' not in ad:
            metrics['fwd_removed_false_default_models_with_data'] += 1
            if any_fwd_src:
                metrics['fwd_removed_but_had_fwd_source_SHOULD_BE_0'] += 1
        for lab in ('Pickup', 'Wagon', 'Convertible', 'Minivan'):
            if lab in ab and lab not in bb:
                metrics[f'gain_{lab.lower()}'] += 1
        # SUV gain due to crossover-family tokens only
        if 'SUV' in ab and 'SUV' not in bb:
            metrics['gain_suv_total'] += 1
            direct = any({'suv', 'off road vehicle', 'sport utility'} & ts for ts in tok_sets)
            cross = any({'crossover', 'cuv', 'sav', 'sac'} & ts for ts in tok_sets)
            if cross and not direct:
                metrics['gain_suv_due_to_crossover_cuv_sav_sac_only'] += 1
            elif cross:
                metrics['gain_suv_crossover_plus_direct'] += 1
        if 'Hatchback' in ab and 'Hatchback' not in bb:
            metrics['gain_hatchback_total'] += 1
            direct = any({'hatchback'} & ts for ts in tok_sets)
            if any('liftback' in ts for ts in tok_sets) and not direct:
                metrics['gain_hatchback_due_to_liftback_only'] += 1
        if fam_rows and 'Van' in bb and 'Van' not in ab:
            metrics['van_removed_models_with_data(minivan_is_no_longer_van)'] += 1
        n_rows = len(fam_rows)
        if n_rows == 0:
            # no dataset rows at all: BEFORE showed the whole generic ladder, AFTER shows Any only.
            # Counted separately so the per-value transitions below only describe real data changes.
            metrics['no_data_models_full_ladder_removed_body'] += int(bool(bb) and not ab)
            metrics['no_data_models_full_ladder_removed_drive'] += int(bool(bd) and not ad)
        else:
            metrics['models_with_data'] += 1
            for lab in bb - ab:
                transitions[f'body_lost_{lab}'] += 1
            for lab in ab - bb:
                transitions[f'body_gained_{lab}'] += 1
            for lab in bd - ad:
                transitions[f'drive_lost_{lab}'] += 1
            for lab in ad - bd:
                transitions[f'drive_gained_{lab}'] += 1
        if len(ab) == 0:
            metrics['search_body_any_only'] += 1
            metrics['search_body_any_only_no_dataset_rows' if n_rows == 0 else 'search_body_any_only_rows_but_no_recognized_body'] += 1
            if n_rows:
                lists['body_any_only_with_rows'].append(f'{key[0]} {key[1]} ({n_rows} rows)')
        if len(ad) == 0:
            metrics['search_drive_any_only'] += 1
            metrics['search_drive_any_only_no_dataset_rows' if n_rows == 0 else 'search_drive_any_only_rows_but_no_evidence'] += 1
            if n_rows:
                lists['drive_any_only_with_rows'].append(f'{key[0]} {key[1]} ({n_rows} rows)')
        if bb != ab or bd != ad:
            metrics['models_with_any_change'] += 1
        per_model.append({'brand': key[0], 'model': key[1], 'rows': n_rows,
                          'before_body': real(b['search_body']), 'after_body': real(a['search_body']),
                          'before_drive': real(b['search_drive']), 'after_drive': real(a['search_drive']),
                          'before_body_ladder_shown': not b['search_body_narrowed'],
                          'before_drive_ladder_shown': not b['search_drive_narrowed']})
    # "before" Any-only counts (old behavior: Any-only never happened once Brand+Model selected)
    metrics['before_search_body_any_only'] = sum(1 for m in bmods.values() if len(real(m['search_body'])) == 0)
    metrics['before_search_drive_any_only'] = sum(1 for m in bmods.values() if len(real(m['search_drive'])) == 0)
    metrics['before_models_showing_full_body_ladder'] = sum(1 for m in bmods.values() if not m['search_body_narrowed'])
    metrics['before_models_showing_full_drive_ladder'] = sum(1 for m in bmods.values() if not m['search_drive_narrowed'])

    focus = {('Volkswagen', 'Golf'), ('Volkswagen', 'Golf R'), ('Toyota', 'Land Cruiser'),
             ('Toyota', 'Land Cruiser Prado'), ('Toyota', 'Hilux'), ('BMW', 'X1'), ('BMW', 'X3'),
             ('BMW', 'X5'), ('Ford', 'Mustang'), ('Nissan', 'Patrol')}
    focus_rows = [m for m in per_model if (m['brand'], m['model']) in focus]

    result = {
        'meta': {'read_only': True, 'before': 'car_spec_body_drivetrain_audit.json (old defaults)',
                 'after': 'real Flutter resolver on the fixed code'},
        'transcription_crosscheck': {'distinct_raw_tuples': len(after['combos']), 'mismatches': len(mism),
                                     'samples': mism[:3]},
        'metrics': dict(sorted(metrics.items())),
        'transitions': dict(sorted(transitions.items())),
        'dataset_rows_without_any_body': row_none_body,
        'dataset_rows_without_drive_evidence': row_none_drive,
        'remaining_unmapped_body_values': {
            'entirely_unmapped_rows': dict(unmapped_rows),
            'partially_unmapped_combined_values(rows)': dict(unmapped_partial),
        },
        'body_vocabulary_after': body_rows,
        'drivetrain_vocabulary_after': drive_rows,
        'focus_models': focus_rows,
        'lists': {k: v for k, v in lists.items()},
        'models': per_model,
    }
    write_text_canonical(GEN / 'car_spec_body_drivetrain_fix_audit.json',
                         json.dumps(result, indent=1, ensure_ascii=False) + '\n')
    write_text_canonical(GEN / 'car_spec_body_drivetrain_fix_audit.md', render(result) + '\n')
    print(json.dumps({'crosscheck_mismatches': len(mism), 'metrics': result['metrics'],
                      'transitions': result['transitions'],
                      'unmapped': result['remaining_unmapped_body_values'],
                      'rows_no_body': row_none_body, 'rows_no_drive': row_none_drive}, indent=1))


def render(r):
    L = ['# Body type / drivetrain normalization fix - before / after audit', '',
         'READ ONLY. BEFORE = old defaults (`unknown -> Sedan`, `blank -> FWD`, full ladders for models without data). '
         'AFTER = the fixed Flutter resolver (real Search ladders, Brand + Model selected).', '',
         f"Transcription cross-check vs the real Dart resolver: {r['transcription_crosscheck']['distinct_raw_tuples']} distinct raw tuples, "
         f"{r['transcription_crosscheck']['mismatches']} mismatches.", '', '## Metrics (1,635 catalog models)', '']
    for k, v in r['metrics'].items():
        L.append(f'- {k}: **{v}**')
    L += ['', '## Value transitions (models)', '']
    for k, v in r['transitions'].items():
        L.append(f'- {k}: {v}')
    L += ['', f"Dataset rows with no recognised body: {r['dataset_rows_without_any_body']}; rows with no drivetrain evidence: {r['dataset_rows_without_drive_evidence']}", '',
          '## Remaining unmapped body vocabulary', '']
    um = r['remaining_unmapped_body_values']
    for k, v in um['entirely_unmapped_rows'].items():
        L.append(f'- `{k}`: {v} rows (no category emitted)')
    for k, v in um['partially_unmapped_combined_values(rows)'].items():
        L.append(f'- `{k}`: {v} rows (recognised part emitted, unmapped part ignored)')
    L += ['', '## Body vocabulary after the fix', '', '| raw | rows | app values | unmapped tokens |', '|---|---|---|---|']
    for x in r['body_vocabulary_after']:
        L.append(f"| {x['raw']} | {x['rows']} | {', '.join(x['app_values']) or '(none)'} | {', '.join(x['unmapped_tokens'])} |")
    L += ['', '## Drivetrain vocabulary after the fix', '', '| drivetrain | traction | rows | app value |', '|---|---|---|---|']
    for x in r['drivetrain_vocabulary_after']:
        L.append(f"| {x['raw_drivetrain'] or '(blank)'} | {x['raw_traction'] or '(blank)'} | {x['rows']} | {x['app_value'] or '(none)'} |")
    L += ['', '## Focus models', '', '| model | before body | after body | before drive | after drive |', '|---|---|---|---|---|']
    for m in r['focus_models']:
        L.append(f"| {m['brand']} {m['model']} | {', '.join(m['before_body'])} | {', '.join(m['after_body']) or 'Any only'} | "
                 f"{', '.join(m['before_drive'])} | {', '.join(m['after_drive']) or 'Any only'} |")
    L += ['', '## Models with rows but Search body = Any only', '']
    L += [f'- {x}' for x in r['lists'].get('body_any_only_with_rows', [])] or ['- none']
    L += ['', '## Models with rows but Search drive = Any only', '']
    L += [f'- {x}' for x in r['lists'].get('drive_any_only_with_rows', [])] or ['- none']
    return '\n'.join(L)


if __name__ == '__main__':
    main()
