# Qualifier-quarantine audit (Flutter strict matcher vs ModelIndex tooling)

READ-ONLY. Nothing in lib/ or assets/ was changed.

```json
{
 "1_total_quarantined_rows": 2265,
 "2_affected_models": 316,
 "3_SAFE_TRIM_OR_VARIANT": 1136,
 "4_OTHER_MODEL_OR_SIBLING": 570,
 "5_AMBIGUOUS": 557,
 "6_MALFORMED_OR_NOISY": 2,
 "7_models_whose_engines_change": 93,
 "8_models_whose_cylinders_change": 39,
 "9_models_whose_other_fields_change": 110,
 "9_detail": {
  "body": 37,
  "fuel": 67,
  "drive": 51,
  "transmission": 33,
  "seating": 50
 },
 "10_models_that_would_lose_all_baseline_coverage": 27,
 "10_list": [
  "Audi RS e-tron",
  "BAIC BJ30",
  "BYD Destroyer 05",
  "BYD Seal 6",
  "BYD Sealion 5",
  "BYD Shark 6",
  "Chevrolet Bolt",
  "Chevrolet Silverado EV",
  "Dodge Hornet",
  "Ferrari 360",
  "Ford F-250",
  "Ford F-350",
  "Ford Mustang Mach-E",
  "Ford Transit",
  "Foton Tunland",
  "Geely Azkarra",
  "Geely Emgrand",
  "Geely Monjaro",
  "Genesis GV60",
  "Infiniti FX",
  "Infiniti JX",
  "Infiniti M",
  "Lincoln Corsair",
  "Mercedes-Benz AMG GT 4-door Coupe",
  "Renault Zoe",
  "Suzuki SX4",
  "Volvo 440"
 ],
 "has_coverage_changed": 27,
 "effective_search_engines_changed": 73,
 "effective_search_cylinders_changed": 11,
 "effective_sell_cylinders_changed": 11,
 "models_with_no_runtime_change_at_all": 157,
 "models_changed_outside_the_316 (must be 0)": [],
 "dart_dump_parity_failures (must be 0)": [],
 "rows_shared_by_more_than_one_catalog_model": 0,
 "rule_counts": {
  "safe_grade_vocabulary": 597,
  "other_family": 567,
  "ambiguous_unclassified": 547,
  "safe_series_name": 284,
  "safe_engine_notation": 172,
  "safe_phrase": 77,
  "safe_repeated_model_name": 6,
  "ambiguous_other_model_name_in_qualifier": 5,
  "ambiguous_weak_token_no_reference": 4,
  "other_numbered_model": 3,
  "noise_split_model_number": 2,
  "ambiguous_weak_token_body_differs": 1
 },
 "rows_with_body_not_in_model_reference": 76,
 "rows_with_other_model_evidence": 47,
 "lost_options_not_in_iq": 70,
 "high_confidence_contamination_candidates": 16,
 "medium_confidence_candidates": 0,
 "models_whose_quarantined_rows_are_ALL_SAFE": 133,
 "models_with_at_least_one_OTHER_row": 12,
 "models_with_at_least_one_AMBIGUOUS_or_NOISE_row": 173
}
```

## Recommendation

**PORT ONLY SELECTED QUALIFIER EXCLUSIONS (a reviewed, explicit exclusion list); do NOT port the tooling quarantine unchanged; keep the current Flutter behaviour for every other row**

- Porting the tooling quarantine unchanged would remove 2265 rows from 316 models, change engines for 93, cylinders for 39 and other fields for 110 models, and leave 27 models with NO baseline coverage at all.
- Only 570 of the 2265 rows (25%) show a different vehicle line; 1136 are clearly trims / engine designations / series names of the matched model (e.g. F-250 'Super Duty', Infiniti FX '35 V6', BYD 'DM-i', Porsche 'Carrera GTS'), so a blanket quarantine would delete correct data (it would remove every F-250/F-350 row).
- 557 rows cannot be classified automatically (mostly single-letter grades 'S', 'R', 'V', 'E', 'K', 'M', 'N', 'drw', Mercedes 'E 200 T'); they are not shown to contaminate anything provable, so they keep today's behaviour until reviewed.
- The OTHER_MODEL rows are concentrated in a tiny, reviewable vocabulary: 24 distinct qualifier phrases in 13 models (572 rows). Measured on the app's own resolvers, excluding only them changes engines for 7 models, cylinders for 4, other fields for 8, and removes ALL baseline rows of 2 models (Suzuki SX4, Ford Transit), whose only dataset rows belong to another vehicle (Transit Connect, SX4 S-Cross); those models then fall back to the already-approved behaviour (IQ overlay data, otherwise Search 'Any only' / Sell manual).
- 16 of the 16 high-confidence contamination candidates (a CarNet option that exists only through a quarantined row, is absent from IQ Cars, and whose qualifier names another vehicle line) belong to a model that has an exclusion entry.

Precise rule:

- Add a small, explicit, reviewed map of dataset-name prefixes that must NOT be attributed to a shorter catalog model, next to the existing _reviewedDatasetFamilyPrefixes alias (same style, same tests): key = '<brand>|<model>' -> list of '<model> <qualifier>' spaced keys.
- A dataset row is dropped from model M when its spaced name equals or starts with '<M> <key> ' for any key listed for M (whole-word prefix, same folding as today).
- The list is generated from this audit (exclusion_entries below): OTHER_MODEL rows plus the two model-number/displacement splits (Tiggo 2 + '0'/'4').
- Do not port the tooling's suffix grammars, engine-start regex or trim vocabulary; do not touch the sibling matcher, slash families, Ram 2500 alias, BMW folding, IQ cylinder sets, engine-qualifier identity, Search 'Any only' or the Sell fallback.
- Add tests: each entry removes its rows and nothing else; the models left without baseline rows (Transit, SX4) behave as the resolver already does for a model with no baseline data.

## Proposed selective exclusion - measured runtime impact

```json
{
 "rule": "exclude a row from model M when its qualifier is on the explicit OTHER_MODEL list (curated lexicon, each phrase with a reason) or is a model-number/displacement split; keep everything else exactly as the Flutter matcher does today",
 "rows_removed": 572,
 "models_with_rows_removed": 13,
 "runtime_impact": {
  "engines": 7,
  "cylinders": 4,
  "coverage": 2,
  "search_engines": 7,
  "search_cylinders": 3,
  "sell_cylinders": 3,
  "body": 4,
  "fuel": 3,
  "drive": 4,
  "transmission": 2,
  "seating": 6,
  "other_fields_any": 8
 },
 "models_that_would_lose_all_baseline_coverage": [
  "Suzuki SX4",
  "Ford Transit"
 ],
 "deny_list_distinct_qualifiers": 24
}
```

| model | rows removed | changed | lost |
|---|---|---|---|
| Toyota Avensis | 6 | seating | {'seating': ['7']} |
| Toyota Corolla | 27 | engines, search_engines, seating | {'engines': ['2.2 TD'], 'seating': ['7']} |
| Toyota Crown | 23 | engines, cylinders, search_engines | {'engines': ['4.0', '4.3', '4.6'], 'cylinders': ['8']} |
| Toyota Urban Cruiser | 4 | cylinders, search_cylinders, sell_cylinders | {'cylinders': ['3']} |
| Mercedes-Benz EQS | 11 | body, seating | {'body': ['SUV'], 'seating': ['4']} |
| Hyundai Ioniq | 3 | body, drive, seating | {'body': ['SUV'], 'drive': ['AWD', 'RWD'], 'seating': ['6']} |
| Suzuki SX4 | 42 | engines, cylinders, coverage, search_engines, search_cylinders, sell_cylinders, body, fuel, drive, transmission, seating | {'engines': ['1.0', '1.4', '1.5', '1.6', '1.6 D', '1.9 D', '2.0', '2.0 D'], 'cylinders': ['3', '4'], 'body': ['Hatchback', 'SUV', 'Sedan'], 'fuel': ['Diesel', 'Gasoline'], 'drive': ['AWD', 'FWD'], 'transmission': ['Automatic', 'Manual'], 'seating': ['5']} |
| Suzuki Vitara | 7 | engines, search_engines, fuel | {'engines': ['1.3 D'], 'fuel': ['Electric']} |
| Chery Tiggo 2 | 2 | engines, search_engines, drive | {'engines': ['2.0', '2.4'], 'drive': ['AWD']} |
| GMC Sierra | 274 | engines, search_engines | {'engines': ['6.6', '6.6 D']} |
| Ford Transit | 151 | engines, cylinders, coverage, search_engines, search_cylinders, sell_cylinders, body, fuel, drive, transmission, seating | {'engines': ['1.0 T', '1.5 D', '1.5 T', '1.6 D', '1.6 T', '1.8 D', '2.0', '2.0 D', '2.5'], 'cylinders': ['3', '4'], 'body': ['Van'], 'fuel': ['Diesel', 'Electric', 'Gasoline'], 'drive': ['FWD'], 'transmission': ['Automatic', 'Manual'], 'seating': ['2', '5', '6']} |

### Exclusion entries (exclude_prefix, rows)

- Ford / Transit: `transit connect` (151 rows)
- GMC / Sierra: `sierra 3500hd` (149 rows)
- GMC / Sierra: `sierra 2500hd` (125 rows)
- Suzuki / SX4: `sx4 s cross` (42 rows)
- Toyota / Crown: `crown majesta` (23 rows)
- Toyota / Corolla: `corolla verso` (20 rows)
- Volkswagen / Polo: `polo vivo` (13 rows)
- Mercedes-Benz / EQS: `eqs suv` (11 rows)
- Renault / Megane: `megane grandcoupe` (9 rows)
- Toyota / Avensis: `avensis verso` (6 rows)
- Toyota / Corolla: `corolla spacio` (5 rows)
- Suzuki / Vitara: `vitara brezza` (4 rows)
- Toyota / Urban Cruiser: `urban cruiser hyryder` (4 rows)
- Hyundai / Ioniq: `ioniq 9` (3 rows)
- Suzuki / Vitara: `vitara e vitara` (3 rows)
- Toyota / Corolla: `corolla rumion` (2 rows)
- Chery / Tiggo 2: `tiggo 2 0` (1 rows)
- Chery / Tiggo 2: `tiggo 2 4` (1 rows)

## Top qualifier groups (by phrase)

| qualifier | rows | models | classes | examples |
|---|---|---|---|---|
| `super duty` | 284 | 2 | {'SAFE_TRIM_OR_VARIANT': 284} | F-250 Super Duty 6 2 V8 (385 Hp) Automatic; F-250 Super Duty 6 2 V8 (385 Hp) 4x4 Automatic |
| `connect` | 151 | 1 | {'OTHER_MODEL_OR_SIBLING': 151} | Transit Connect 2 0 EcoBlue (102 Hp); Transit Connect 2 0 EcoBlue (122 Hp) DSG |
| `3500hd` | 149 | 1 | {'OTHER_MODEL_OR_SIBLING': 149} | Sierra 3500HD 6 0 V8 (360 Hp) DRW Automatic; Sierra 3500HD 6 0 V8 (360 Hp) SRW Automatic |
| `2500hd` | 125 | 1 | {'OTHER_MODEL_OR_SIBLING': 125} | Sierra 2500HD 6 0 V8 (360 Hp) Automatic; Sierra 2500HD 6 6 Duramax TD V8 (445 Hp) Automatic |
| `rs` | 68 | 8 | {'SAFE_TRIM_OR_VARIANT': 68} | Fabia RS 1 9 TDI (130 Hp); Fabia RS 1 4 TSI (180 Hp) DSG |
| `s` | 55 | 14 | {'AMBIGUOUS': 55} | Matrix S 2 4 (160 Hp) Automatic; Matrix S 2 4 (160 Hp) AWD Automatic |
| `gt` | 45 | 18 | {'SAFE_TRIM_OR_VARIANT': 45} | SLS AMG GT 6 2 V8 (591 Hp) AMG SPEEDSHIFT DCT; Cerato GT 1 6 T-GDI (204 Hp) DCT |
| `s cross` | 42 | 1 | {'OTHER_MODEL_OR_SIBLING': 42} | SX4 S-Cross 1 6 i 16V VVT 2WD (107 Hp); SX4 S-Cross 1 6 i 16V VVT 2WD (107 Hp) Automatic |
| `r` | 37 | 13 | {'AMBIGUOUS': 37} | AMG GT R 4 0 V8 (585 Hp) DCT; Arteon R 2 0 TSI (320 Hp) 4MOTION DSG |
| `verso` | 26 | 2 | {'OTHER_MODEL_OR_SIBLING': 26} | Avensis Verso 2 0 (150 Hp); Avensis Verso 2 0 D-4D (116 Hp) |
| `drw` | 24 | 1 | {'AMBIGUOUS': 24} | RAM DRW 5 9 Cummins TD (160 Hp) 4x4 Automatic; RAM DRW 5 9 Cummins TD (160 Hp) Automatic |
| `majesta` | 23 | 1 | {'OTHER_MODEL_OR_SIBLING': 23} | Crown Majesta 3 0i V6 24V (230 Hp) Automatic; Crown Majesta 4 0i V8 32V (260 Hp) 4x4 Automatic |
| `carrera 4 gts` | 18 | 1 | {'SAFE_TRIM_OR_VARIANT': 18} | 911 Carrera 4 GTS 3 8 (430 Hp); 911 Carrera 4 GTS 3 8 (430 Hp) PDK |
| `carrera gts` | 18 | 1 | {'SAFE_TRIM_OR_VARIANT': 18} | 911 Carrera GTS 3 8 (430 Hp); 911 Carrera GTS 3 8 (430 Hp) PDK |
| `gti` | 18 | 4 | {'SAFE_TRIM_OR_VARIANT': 18} | Polo GTI 1 8 (150 Hp) 3-d; Polo GTI 1 8 (150 Hp) 5-d |
| `standard range` | 18 | 7 | {'SAFE_TRIM_OR_VARIANT': 18} | EV6 Standard Range 58 kWh (170 Hp); EV6 Standard Range 63 kWh (170 Hp) |
| `xtr` | 18 | 1 | {'SAFE_TRIM_OR_VARIANT': 18} | BT-50 XTR 3 2 (200 Hp) 4x4; BT-50 XTR 3 2 (200 Hp) 4x4 Automatic |
| `ev` | 17 | 8 | {'SAFE_TRIM_OR_VARIANT': 17} | Soul EV 31 kWh (110 Hp); Soul EV 33 kWh (110 Hp) |
| `recharge` | 16 | 7 | {'SAFE_TRIM_OR_VARIANT': 16} | S60 Recharge 2 0 T8 (455 Hp) Plug-in Hybrid AWD Geartronic; S60 Recharge 2 0 T6 (350 Hp) Plug-in Hybrid AWD Geartronic |
| `z28` | 16 | 1 | {'SAFE_TRIM_OR_VARIANT': 16} | Camaro Z28 5 7 i V8 (275 Hp); Camaro Z28 5 7 i V8 (285 Hp) |
| `gtd` | 15 | 1 | {'SAFE_TRIM_OR_VARIANT': 15} | Golf GTD 2 0 TDI (184 Hp); Golf GTD 2 0 TDI (184 Hp) DSG |
| `sport` | 15 | 7 | {'SAFE_TRIM_OR_VARIANT': 15} | 323 Sport 2 0i 16V (130 Hp); 323 Sport 2 0i 16V (130 Hp) Automatic |
| `v` | 15 | 7 | {'AMBIGUOUS': 15} | CT4 V 2 7 Turbo (329 Hp) Automatic; CT5 V 3 0 V6 (360 Hp) Automatic |
| `e` | 13 | 6 | {'AMBIGUOUS': 13} | Compass e 74 kWh (213 Hp) Electric; 2008 e-2008 50 kWh (136 Hp) |
| `k` | 13 | 1 | {'AMBIGUOUS': 13} | 440 K 1 6 i (82 Hp); 440 K 1 7 (102 Hp) |
| `performance` | 13 | 8 | {'SAFE_TRIM_OR_VARIANT': 13} | Ariya Performance 90 kWh (394 Hp) e-4ORCE; Taycan Performance 79 2 kWh (408 Hp) |
| `speed` | 13 | 2 | {'SAFE_TRIM_OR_VARIANT': 13} | Bentayga SPEED 6 0 TSI W12 (635 Hp) AWD Automatic; Bentayga Speed 6 0 W12 TSI (635 Hp) AWD Automatic |
| `vivo` | 13 | 1 | {'OTHER_MODEL_OR_SIBLING': 13} | Polo Vivo 1 4 (75 Hp); Polo Vivo 1 4 (86 Hp) |
| `e transporter` | 12 | 1 | {'AMBIGUOUS': 12} | Transporter e-Transporter 70 9 kWh (136 Hp) L1H1; Transporter e-Transporter 70 9 kWh (218 Hp) L1H1 |
| `e tron` | 11 | 5 | {'AMBIGUOUS': 11} | A3 e-tron 1 4 TFSI (204 Hp) Plug-in Hybrid S tronic; A6 e-tron 100 kWh (476 Hp) quattro |
| `long range` | 11 | 5 | {'SAFE_TRIM_OR_VARIANT': 11} | EV6 Long Range 77 4 kWh (229 Hp); EV6 Long Range 77 4 kWh (325 Hp) AWD |
| `grandcoupe` | 9 | 1 | {'OTHER_MODEL_OR_SIBLING': 9} | Megane GrandCoupe 1 6 SCe (114 Hp); Megane GrandCoupe 1 2 Energy TCe (130 Hp) EDC |
| `gts` | 9 | 5 | {'SAFE_TRIM_OR_VARIANT': 9} | Scirocco GTS 2 0 TSI (220 Hp); Scirocco GTS 2 0 TSI (220 Hp) DSG |
| `m` | 9 | 4 | {'AMBIGUOUS': 9} | X3 M 3 0 (480 Hp) xDrive Steptronic; X4 M 3 0 (480 Hp) xDrive Steptronic |
| `4s` | 8 | 2 | {'SAFE_TRIM_OR_VARIANT': 8} | 911 4S 3 8 (400 Hp); 911 4S 3 8 (400 Hp) PDK |
| `dm i` | 8 | 3 | {'SAFE_TRIM_OR_VARIANT': 8} | Destroyer 05 DM-i 1 5L 8 3 kWh (180 Hp) Plug-in Hybrid E-CVT; Destroyer 05 DM-i 1 5L 18 3 kWh (197 Hp) Plug-in Hybrid E-CVT |
| `e traveller` | 8 | 1 | {'AMBIGUOUS': 8} | Traveller e-Traveller 50 kWh (136 Hp); Traveller e-Traveller 75 kWh (136 Hp) |
| `extended range` | 8 | 2 | {'SAFE_TRIM_OR_VARIANT': 8} | Atto 3 Extended Range 60 48 kWh (204 Hp) BEV; Mustang Mach-E Extended Range 98 7 kWh (294 Hp) |
| `g tron` | 8 | 3 | {'SAFE_TRIM_OR_VARIANT': 8} | A3 G-tron 1 4 TFSI CNG (110 Hp) S tronic; A3 G-tron 1 4 TFSI CNG (110 Hp) |
| `iv` | 8 | 3 | {'SAFE_TRIM_OR_VARIANT': 8} | Kodiaq iV 1 5 TSI (204 Hp) Plug-in Hybrid DSG; Octavia iV 1 4 TSI (204 Hp) Plug-in Hybrid DSG |

## Top head tokens

| head token | rows | models | classes |
|---|---|---|---|
| `super` | 285 | 3 | {'AMBIGUOUS': 1, 'SAFE_TRIM_OR_VARIANT': 284} |
| `connect` | 151 | 1 | {'OTHER_MODEL_OR_SIBLING': 151} |
| `3500hd` | 149 | 1 | {'OTHER_MODEL_OR_SIBLING': 149} |
| `2500hd` | 125 | 1 | {'OTHER_MODEL_OR_SIBLING': 125} |
| `s` | 102 | 16 | {'AMBIGUOUS': 60, 'OTHER_MODEL_OR_SIBLING': 42} |
| `e` | 93 | 26 | {'AMBIGUOUS': 85, 'SAFE_TRIM_OR_VARIANT': 5, 'OTHER_MODEL_OR_SIBLING': 3} |
| `rs` | 77 | 10 | {'SAFE_TRIM_OR_VARIANT': 76, 'AMBIGUOUS': 1} |
| `gt` | 56 | 23 | {'SAFE_TRIM_OR_VARIANT': 49, 'AMBIGUOUS': 7} |
| `carrera` | 45 | 1 | {'SAFE_TRIM_OR_VARIANT': 45} |
| `r` | 38 | 14 | {'AMBIGUOUS': 38} |
| `gti` | 32 | 5 | {'AMBIGUOUS': 2, 'SAFE_TRIM_OR_VARIANT': 30} |
| `verso` | 26 | 2 | {'OTHER_MODEL_OR_SIBLING': 26} |
| `dm` | 24 | 6 | {'SAFE_TRIM_OR_VARIANT': 24} |
| `drw` | 24 | 1 | {'AMBIGUOUS': 24} |
| `majesta` | 23 | 1 | {'OTHER_MODEL_OR_SIBLING': 23} |
| `standard` | 23 | 9 | {'SAFE_TRIM_OR_VARIANT': 23} |
| `v` | 23 | 8 | {'AMBIGUOUS': 23} |
| `recharge` | 22 | 7 | {'SAFE_TRIM_OR_VARIANT': 16, 'AMBIGUOUS': 6} |
| `z28` | 20 | 1 | {'SAFE_TRIM_OR_VARIANT': 20} |
| `ev` | 19 | 9 | {'SAFE_TRIM_OR_VARIANT': 19} |
| `srt` | 19 | 7 | {'SAFE_TRIM_OR_VARIANT': 14, 'AMBIGUOUS': 5} |
| `xtr` | 18 | 1 | {'SAFE_TRIM_OR_VARIANT': 18} |
| `sport` | 17 | 9 | {'SAFE_TRIM_OR_VARIANT': 16, 'AMBIGUOUS': 1} |
| `g` | 16 | 4 | {'AMBIGUOUS': 8, 'SAFE_TRIM_OR_VARIANT': 8} |
| `m` | 16 | 5 | {'AMBIGUOUS': 16} |

## Top 30 high-risk models

| # | model | score | rows | lost options | not in IQ | reasons |
|---|---|---|---|---|---|---|
| 1 | Suzuki SX4 | 106.8 | 42 | {'engines': ['1.0', '1.4', '1.5', '1.6', '1.6 D', '1.9 D', '2.0', '2.0 D'], 'cylinders': ['3', '4'], 'body': ['Hatchback', 'SUV', 'Sedan'], 'fuel': ['Diesel', 'Gasoline'], 'drive': ['AWD', 'FWD'], 'transmission': ['Automatic', 'Manual'], 'seating': ['5']} | ['engine 1.0', 'engine 1.4', 'engine 1.9 D', 'cylinders 3'] | 8 engine option(s) disappear (3 not supported by IQ); 2 cylinder count(s) disappear: 3, 4 (1 not supported by IQ); 3 body type(s) disappear: Hatchback, SUV, Sedan; 7 fuel/drive/transmission/seat option(s) disappear; 42 row(s) classified OTHER_MODEL / MALFORMED; 42 row(s) where another known model name appears in the qualifier; model would lose ALL baseline coverage |
| 2 | Ford Transit | 85.4 | 151 | {'engines': ['1.0 T', '1.5 D', '1.5 T', '1.6 D', '1.6 T', '1.8 D', '2.0', '2.0 D', '2.5'], 'cylinders': ['3', '4'], 'body': ['Van'], 'fuel': ['Diesel', 'Electric', 'Gasoline'], 'drive': ['FWD'], 'transmission': ['Automatic', 'Manual'], 'seating': ['2', '5', '6']} | ['engine 1.0 T', 'engine 1.5 D', 'engine 1.5 T', 'engine 1.6 D', 'engine 1.6 T', 'engine 1.8 D', 'engine 2.5', 'cylinders 3'] | 9 engine option(s) disappear (7 not supported by IQ); 2 cylinder count(s) disappear: 3, 4 (1 not supported by IQ); 1 body type(s) disappear: Van; 9 fuel/drive/transmission/seat option(s) disappear; 151 row(s) classified OTHER_MODEL / MALFORMED; model would lose ALL baseline coverage |
| 3 | Mercedes-Benz EQS | 49.3 | 11 | {'body': ['SUV'], 'seating': ['4']} | [] | 1 body type(s) disappear: SUV; 1 fuel/drive/transmission/seat option(s) disappear; 11 row(s) classified OTHER_MODEL / MALFORMED; 11 row(s) with a body type not on the model's reference rows |
| 4 | Toyota Corolla | 48.3 | 34 | {'engines': ['2.2 TD'], 'seating': ['7']} | ['engine 2.2 TD'] | 1 engine option(s) disappear (1 not supported by IQ); 1 fuel/drive/transmission/seat option(s) disappear; 27 row(s) classified OTHER_MODEL / MALFORMED; 25 row(s) with a body type not on the model's reference rows |
| 5 | Toyota Crown | 44.0 | 23 | {'engines': ['4.0', '4.3', '4.6'], 'cylinders': ['8']} | ['engine 4.3', 'engine 4.6'] | 3 engine option(s) disappear (2 not supported by IQ); 1 cylinder count(s) disappear: 8; 23 row(s) classified OTHER_MODEL / MALFORMED |
| 6 | Renault Megane | 40.2 | 19 | {'body': ['SUV']} | [] | 1 body type(s) disappear: SUV; 9 row(s) classified OTHER_MODEL / MALFORMED; 6 row(s) with a body type not on the model's reference rows |
| 7 | GMC Sierra | 34.0 | 274 | {'engines': ['6.6', '6.6 D']} | [] | 2 engine option(s) disappear; 274 row(s) classified OTHER_MODEL / MALFORMED |
| 8 | Volkswagen Polo | 32.0 | 30 | {'engines': ['1.8 T', '2.0 T']} | ['engine 2.0 T'] | 2 engine option(s) disappear (1 not supported by IQ); 13 row(s) classified OTHER_MODEL / MALFORMED |
| 9 | Infiniti M | 29.9 | 15 | {'engines': ['3.0', '3.0 D', '3.5', '3.7', '4.5', '5.6'], 'cylinders': ['6', '8'], 'body': ['Coupe', 'Sedan'], 'fuel': ['Diesel', 'Gasoline'], 'drive': ['AWD', 'RWD'], 'transmission': ['Automatic'], 'seating': ['2', '5']} | ['engine 3.0', 'engine 3.0 D'] | 6 engine option(s) disappear (2 not supported by IQ); 2 cylinder count(s) disappear: 6, 8; 2 body type(s) disappear: Coupe, Sedan; 7 fuel/drive/transmission/seat option(s) disappear; 2 row(s) where another known model name appears in the qualifier; model would lose ALL baseline coverage |
| 10 | Toyota Avensis | 27.3 | 6 | {'seating': ['7']} | [] | 1 fuel/drive/transmission/seat option(s) disappear; 6 row(s) classified OTHER_MODEL / MALFORMED; 6 row(s) with a body type not on the model's reference rows |
| 11 | Toyota Urban Cruiser | 27.0 | 4 | {'cylinders': ['3']} | ['cylinders 3'] | 1 cylinder count(s) disappear: 3 (1 not supported by IQ); 4 row(s) classified OTHER_MODEL / MALFORMED; 4 row(s) with a body type not on the model's reference rows |
| 12 | Suzuki Vitara | 22.6 | 7 | {'engines': ['1.3 D'], 'fuel': ['Electric']} | ['engine 1.3 D'] | 1 engine option(s) disappear (1 not supported by IQ); 1 fuel/drive/transmission/seat option(s) disappear; 7 row(s) classified OTHER_MODEL / MALFORMED |
| 13 | Volvo 440 | 22.0 | 13 | {'engines': ['1.6', '1.7', '1.7 T', '1.8', '1.9 TD', '2.0'], 'cylinders': ['4'], 'body': ['Hatchback'], 'fuel': ['Diesel', 'Gasoline'], 'drive': ['FWD'], 'transmission': ['Automatic', 'Manual'], 'seating': ['5']} | [] | 6 engine option(s) disappear; 1 cylinder count(s) disappear: 4; 1 body type(s) disappear: Hatchback; 6 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 14 | Hyundai Ioniq | 19.8 | 3 | {'body': ['SUV'], 'drive': ['AWD', 'RWD'], 'seating': ['6']} | [] | 1 body type(s) disappear: SUV; 3 fuel/drive/transmission/seat option(s) disappear; 3 row(s) classified OTHER_MODEL / MALFORMED; 3 row(s) with a body type not on the model's reference rows |
| 15 | Mercedes-Benz AMG GT 4-door Coupe | 19.3 | 5 | {'engines': ['3.0', '4.0'], 'cylinders': ['6', '8'], 'body': ['Coupe'], 'fuel': ['Electric', 'Gasoline'], 'drive': ['AWD'], 'transmission': ['Automatic'], 'seating': ['4', '5']} | [] | 2 engine option(s) disappear; 2 cylinder count(s) disappear: 6, 8; 1 body type(s) disappear: Coupe; 6 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 16 | Foton Tunland | 16.5 | 6 | {'engines': ['2.0 D'], 'cylinders': ['4'], 'body': ['Sedan'], 'fuel': ['Diesel'], 'drive': ['AWD', 'RWD'], 'transmission': ['Automatic', 'Manual'], 'seating': ['5']} | [] | 1 engine option(s) disappear; 1 cylinder count(s) disappear: 4; 1 body type(s) disappear: Sedan; 6 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 17 | Ferrari 360 | 16.3 | 3 | {'engines': ['3.6'], 'cylinders': ['8'], 'body': ['Coupe', 'Sedan'], 'fuel': ['Gasoline'], 'drive': ['RWD'], 'transmission': ['Manual'], 'seating': ['2']} | [] | 1 engine option(s) disappear; 1 cylinder count(s) disappear: 8; 2 body type(s) disappear: Coupe, Sedan; 4 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 18 | BAIC BJ30 | 15.2 | 3 | {'engines': ['1.5'], 'cylinders': ['4'], 'body': ['SUV'], 'fuel': ['Gasoline'], 'drive': ['AWD', 'FWD'], 'transmission': ['Automatic'], 'seating': ['5']} | [] | 1 engine option(s) disappear; 1 cylinder count(s) disappear: 4; 1 body type(s) disappear: SUV; 5 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 19 | Dodge Hornet | 14.7 | 2 | {'engines': ['1.3 T', '2.0 T'], 'cylinders': ['4'], 'body': ['Sedan'], 'fuel': ['Electric', 'Gasoline'], 'drive': ['AWD'], 'transmission': ['Automatic'], 'seating': ['5']} | [] | 2 engine option(s) disappear; 1 cylinder count(s) disappear: 4; 1 body type(s) disappear: Sedan; 5 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 20 | Renault Zoe | 14.1 | 10 | {'body': ['Hatchback'], 'fuel': ['Electric'], 'drive': ['FWD'], 'transmission': ['Automatic'], 'seating': ['5']} | [] | 1 body type(s) disappear: Hatchback; 4 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 21 | Chery Tiggo 2 | 13.0 | 2 | {'engines': ['2.0', '2.4'], 'drive': ['AWD']} | ['engine 2.0', 'engine 2.4'] | 2 engine option(s) disappear (2 not supported by IQ); 1 fuel/drive/transmission/seat option(s) disappear; 2 row(s) classified OTHER_MODEL / MALFORMED |
| 22 | Infiniti FX | 12.5 | 14 | {'engines': ['3.0 D', '3.5', '3.7', '4.5', '5.0'], 'cylinders': ['6', '8'], 'body': ['Sedan'], 'fuel': ['Diesel', 'Gasoline'], 'drive': ['AWD', 'RWD'], 'transmission': ['Automatic'], 'seating': ['5']} | ['engine 3.0 D'] | 5 engine option(s) disappear (1 not supported by IQ); 2 cylinder count(s) disappear: 6, 8; 1 body type(s) disappear: Sedan; 6 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 23 | Ford F-350 | 12.2 | 175 | {'engines': ['6.2', '6.7 D', '6.8', '7.3'], 'cylinders': ['8'], 'body': ['Sedan'], 'fuel': ['Diesel', 'Gasoline'], 'drive': ['AWD', 'RWD'], 'transmission': ['Automatic'], 'seating': ['4', '5', '6']} | [] | 4 engine option(s) disappear; 1 cylinder count(s) disappear: 8; 1 body type(s) disappear: Sedan; 8 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 24 | Ford F-250 | 12.2 | 109 | {'engines': ['6.2', '6.7 D', '6.8', '7.3'], 'cylinders': ['8'], 'body': ['Sedan'], 'fuel': ['Diesel', 'Gasoline'], 'drive': ['AWD', 'RWD'], 'transmission': ['Automatic'], 'seating': ['4', '5', '6']} | [] | 4 engine option(s) disappear; 1 cylinder count(s) disappear: 8; 1 body type(s) disappear: Sedan; 8 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 25 | Dodge Viper | 12.0 | 7 | {'body': ['Coupe']} | [] | 1 body type(s) disappear: Coupe; 7 row(s) with a body type not on the model's reference rows |
| 26 | Chevrolet Silverado EV | 11.9 | 6 | {'body': ['Sedan'], 'fuel': ['Electric'], 'drive': ['AWD'], 'transmission': ['Automatic'], 'seating': ['5']} | [] | 1 body type(s) disappear: Sedan; 4 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 27 | Ford Mustang Mach-E | 11.1 | 19 | {'body': ['SUV'], 'fuel': ['Electric'], 'drive': ['AWD', 'RWD'], 'transmission': ['Automatic'], 'seating': ['5']} | [] | 1 body type(s) disappear: SUV; 5 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 28 | Genesis GV60 | 11.1 | 8 | {'body': ['SUV'], 'fuel': ['Electric'], 'drive': ['AWD', 'RWD'], 'transmission': ['Automatic'], 'seating': ['5']} | [] | 1 body type(s) disappear: SUV; 5 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 29 | Infiniti JX | 10.9 | 2 | {'engines': ['3.5'], 'cylinders': ['6'], 'body': ['Sedan'], 'fuel': ['Gasoline'], 'drive': ['AWD', 'FWD'], 'transmission': ['Automatic'], 'seating': ['7']} | [] | 1 engine option(s) disappear; 1 cylinder count(s) disappear: 6; 1 body type(s) disappear: Sedan; 5 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |
| 30 | Geely Monjaro | 10.8 | 1 | {'engines': ['2.0'], 'cylinders': ['4'], 'body': ['SUV'], 'fuel': ['Gasoline'], 'drive': ['AWD'], 'transmission': ['Automatic'], 'seating': ['5']} | [] | 1 engine option(s) disappear; 1 cylinder count(s) disappear: 4; 1 body type(s) disappear: SUV; 4 fuel/drive/transmission/seat option(s) disappear; model would lose ALL baseline coverage |

## Important models

- Toyota Land Cruiser: **affected** 1 row(s) {'AMBIGUOUS': 1} changed={} lost={} examples=['Land Cruiser GXL 4 5d V8 (272 Hp) AWD Automatic']
- Toyota Land Cruiser Prado: **affected** 1 row(s) {'AMBIGUOUS': 1} changed={} lost={} examples=['Land Cruiser Prado First Edition 2 8 D-4D (204 Hp) 4WD Automatic']
- Toyota Corolla: **affected** 34 row(s) {'OTHER_MODEL_OR_SIBLING': 27, 'SAFE_TRIM_OR_VARIANT': 7} changed={'engines': True, 'seating': True, 'other_fields_any': True, 'effective_search_engines': True} lost={'engines': ['2.2 TD'], 'seating': ['7']} examples=['Corolla Verso 1 6 16V (110 Hp)', 'Corolla Verso 1 8 16V (129 Hp)', 'Corolla Verso 1 8 16V (129 Hp) MultiMode', 'Corolla Verso 1 5 i (110 Hp)']
- Toyota Corolla Cross: **not affected**
- Toyota Camry: **not affected**
- Toyota Hilux: **affected** 4 row(s) {'SAFE_TRIM_OR_VARIANT': 4} changed={} lost={} examples=['Hilux Hi-Rider 2 8d (177 Hp) Automatic', 'Hilux Hi-Rider 2 4d (150 Hp) Automatic', 'Hilux Hi-Rider 2 8d (177 Hp) Automatic', 'Hilux Hi-Rider 2 8d (177 Hp)']
- Toyota RAV4: **affected** 3 row(s) {'AMBIGUOUS': 2, 'SAFE_TRIM_OR_VARIANT': 1} changed={} lost={} examples=['RAV4 Prime 2 5 D-4S (302 Hp) Plug-in Hybrid E-Four e-CVT', 'RAV4 Woodland 2 5 (236 Hp) Hybrid AWD ECVT', 'RAV4 GR Sport 2 5 (324 Hp) Plug-in Hybrid AWD ECVT']
- BMW 3-Series: **not affected**
- BMW 4-Series: **not affected**
- BMW 5-Series: **affected** 5 row(s) {'AMBIGUOUS': 1, 'SAFE_TRIM_OR_VARIANT': 4} changed={} lost={} examples=['5 Series 525i 24V X (192 Hp)', '5 Series 520d Special Edition (163 Hp)', '5 Series 520d Special Edition (163 Hp) Steptronic', '5 Series 520d Special Edition (163 Hp)']
- BMW X1: **not affected**
- BMW X3: **affected** 3 row(s) {'AMBIGUOUS': 3} changed={} lost={} examples=['X3 M 3 0 (480 Hp) xDrive Steptronic', 'X3 M Competition 3 0 (510 Hp) xDrive Steptronic', 'X3 M Competition 3 0 (510 Hp) M xDrive M Steptronic']
- BMW X5: **affected** 2 row(s) {'AMBIGUOUS': 2} changed={} lost={} examples=['X5 M Competition 4 4 V8 (625 Hp) xDrive Steptronic', 'X5 M Competition 4 4 V8 (625 Hp) Mild Hybrid M xDrive M Steptronic']
- Lexus LX: **not affected**
- Lexus GX: **affected** 1 row(s) {'AMBIGUOUS': 1} changed={} lost={} examples=['GX Overtrail 550 V6 (349 Hp) 4WD Direct Shift']
- Lexus RX: **affected** 4 row(s) {'AMBIGUOUS': 4} changed={} lost={} examples=['RX 350 F Sport V6 (295 Hp) Automatic', 'RX 350 F Sport V6 (295 Hp) AWD Automatic', 'RX 450h F Sport V6 (313 Hp) Hybrid E-Four e-CVT', 'RX 350 F Sport V6 (270 Hp) AWD ECT-i']
- Ford Everest: **not affected**
- Ford Bronco: **not affected**
- Ford Mustang: **affected** 9 row(s) {'AMBIGUOUS': 6, 'SAFE_TRIM_OR_VARIANT': 3} changed={} lost={} examples=['Mustang Shelby GT350 R 5 2 V8 (526 Hp)', 'Mustang BULLITT 5 0 Ti-VCT V8 (480 Hp)', 'Mustang Shelby GT500 V8 (760 Hp) Automatic', 'Mustang Mach 1 5 0 Ti-VCT V8 (460 Hp)']
- Volkswagen Golf: **affected** 29 row(s) {'AMBIGUOUS': 4, 'SAFE_TRIM_OR_VARIANT': 25} changed={'drive': True, 'other_fields_any': True} lost={'drive': ['RWD']} examples=['Golf Citystromer 17 3 kWh (27 Hp)', 'Golf GLS 1 5 (70 Hp)', 'Golf GLi 1 6 (110 Hp)', 'Golf GTD 2 0 TDI (184 Hp)']
- Volkswagen Golf R: **affected** 1 row(s) {'AMBIGUOUS': 1} changed={} lost={} examples=['Golf R 20 Years 2 0 TSI (333 Hp) 4MOTION DSG']
- Volkswagen Tiguan: **affected** 3 row(s) {'AMBIGUOUS': 1, 'SAFE_TRIM_OR_VARIANT': 2} changed={} lost={} examples=['Tiguan R 2 0 TSI (320 Hp) 4MOTION DSG', 'Tiguan 330 TSI (186 Hp) DSG', 'Tiguan 380 TSI (220 Hp) 4MOTION DSG']
- Nissan Patrol: **not affected**

## IQ-corroborated contamination candidates

high confidence (16): lost option not in IQ AND every contributing quarantined row looks like another model

- Ford Transit: engine 1.0 T (7 rows, {'OTHER_MODEL_OR_SIBLING': 7}) qualifiers=['connect']
- Ford Transit: engine 1.5 D (71 rows, {'OTHER_MODEL_OR_SIBLING': 71}) qualifiers=['connect']
- Ford Transit: engine 1.5 T (71 rows, {'OTHER_MODEL_OR_SIBLING': 71}) qualifiers=['connect']
- Ford Transit: engine 1.6 D (30 rows, {'OTHER_MODEL_OR_SIBLING': 30}) qualifiers=['connect']
- Ford Transit: engine 1.6 T (30 rows, {'OTHER_MODEL_OR_SIBLING': 30}) qualifiers=['connect']
- Ford Transit: engine 1.8 D (26 rows, {'OTHER_MODEL_OR_SIBLING': 26}) qualifiers=['connect']
- Ford Transit: engine 2.5 (4 rows, {'OTHER_MODEL_OR_SIBLING': 4}) qualifiers=['connect']
- Ford Transit: cylinders 3 (7 rows, {'OTHER_MODEL_OR_SIBLING': 7}) qualifiers=['connect']
- Suzuki SX4: engine 1.0 (2 rows, {'OTHER_MODEL_OR_SIBLING': 2}) qualifiers=['s cross']
- Suzuki SX4: engine 1.4 (14 rows, {'OTHER_MODEL_OR_SIBLING': 14}) qualifiers=['s cross']
- Suzuki SX4: engine 1.9 D (1 rows, {'OTHER_MODEL_OR_SIBLING': 1}) qualifiers=['s cross']
- Suzuki SX4: cylinders 3 (2 rows, {'OTHER_MODEL_OR_SIBLING': 2}) qualifiers=['s cross']
- Toyota Corolla: engine 2.2 TD (7 rows, {'OTHER_MODEL_OR_SIBLING': 7}) qualifiers=['rumion', 'spacio', 'verso']
- Toyota Crown: engine 4.3 (5 rows, {'OTHER_MODEL_OR_SIBLING': 5}) qualifiers=['majesta']
- Toyota Crown: engine 4.6 (1 rows, {'OTHER_MODEL_OR_SIBLING': 1}) qualifiers=['majesta']
- Toyota Urban Cruiser: cylinders 3 (1 rows, {'OTHER_MODEL_OR_SIBLING': 1}) qualifiers=['hyryder']

medium confidence (0): lost option not in IQ AND at least one contributing row looks like another model

