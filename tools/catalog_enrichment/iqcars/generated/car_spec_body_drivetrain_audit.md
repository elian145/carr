# CarNet spec dataset - body type / drivetrain source audit

READ ONLY. No Flutter code, dataset or overlay was changed. The IQ Cars overlay supplies neither body type nor drivetrain; everything below comes from the CarNet spec dataset through the existing Flutter resolver.

Normalizer cross-check: 423 distinct raw tuples run through the REAL Dart resolver, 0 mismatches against the transcription used for rule labelling.

## Summary

- catalog_models_audited: **1635**
- dataset_spec_rows: **42130**
- body_default_to_sedan_rows: **12096**
- body_blank_rows: **0**
- drive_default_to_fwd_rows: **1777**
- drive_conflict_rows: **5**
- models_with_any_body_default_row: **291**
- models_with_sedan_only_from_default: **187**
- models_with_any_drive_default_row: **85**
- models_with_fwd_only_from_blank_default: **34**
- models_with_no_body_data_full_ladder: **779**
- models_with_no_drive_data_full_ladder: **779**

### Flag counts (models)

- BODY_4PLUS_CATEGORIES: 1
- BODY_5PLUS_CATEGORIES: 1
- BODY_ANY_ROW_USES_DEFAULT: 291
- BODY_HATCHBACK_PLUS_VAN: 5
- BODY_MINIVAN_RAW_MAPPED_TO_VAN: 63
- BODY_NO_MODEL_DATA_FULL_LADDER_SHOWN: 779
- BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP: 46
- BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION: 46
- BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK: 187
- BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK: 291
- BODY_SUV_WITH_UNSUPPORTED_SEDAN: 20
- DRIVE_ANY_ROW_USES_DEFAULT: 85
- DRIVE_EVERY_OPTION: 48
- DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT: 34
- DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT: 85
- DRIVE_NO_MODEL_DATA_FULL_LADDER_SHOWN: 779
- DRIVE_RWD_ONLY_FROM_CONFLICTING_ROWS: 2
- DRIVE_SOURCE_FIELDS_CONFLICT: 4

## Findings (answers)

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
7. **Models affected by body fallback:** 291 of the 856 models with dataset coverage have at least one family row
   whose body fell through to the Sedan default; for 187 the offered Sedan has NO supporting explicit Sedan row.
   A further 779 models have no dataset rows at all and Search shows them the full generic body ladder.
8. **Models affected by drivetrain fallback:** 85 models have at least one blank-source row turned into FWD; for
   34 the offered FWD is supported only by blank rows. 779 models with no dataset rows show the
   full FWD/RWD/AWD ladder. 5 rows have conflicting drivetrain-vs-Traction text.
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



## Normalizer audit (fallback behaviour)

### body
- where: lib/services/car_spec_index_helpers.dart `_mapSpecToFormFields` (bodyType, ~L397-414)
- default: String bodyType = 'sedan' is assigned BEFORE any rule runs; the final else-if is `sedan||saloon` (redundant)
- unknown/blank becomes: **Sedan**  (silently factual: True)
- Any raw value that contains none of suv/sport-utility/off-road/(wagon+sport)/hatch/coupe/pickup/truck/van/sedan/saloon silently becomes Sedan: Station wagon (estate), Pick-up (hyphen!), Cabriolet, MPV, Roadster, Liftback, Fastback, Crossover, Targa, SAV, SAC, CUV, Grand Tourer, Quadricycle. A blank body also becomes Sedan (none exist today). `Minivan` matches `van` and becomes Van.

### body label
- where: lib/services/car_spec_index_sell_labels.dart `sellFlowBodyLabel` `default:`
- default: default -> 'Sedan'
- unknown/blank becomes: **Sedan**  (silently factual: True)
- Second, independent default: any api value other than suv/hatchback/coupe/pickup/van is labelled Sedan. Used by sellFieldOptionsUnion, Sell autofill and the Search/Sell lists.

### drivetrain
- where: lib/services/car_spec_index_helpers.dart `_mapSpecToFormFields` (driveType, ~L384-395)
- default: String driveType = 'fwd' assigned before any rule
- unknown/blank becomes: **FWD**  (silently factual: True)
- Blank drivetrain with no Traction text (1,777 dataset rows) becomes FWD. `rear-wheel`/`front-wheel` hyphenated hints never match the dataset's `Rear wheel drive` / `Front wheel drive` (space), so Traction text only helps through `awd`/`4wd` substrings; the explicit `drivetrain` field is what really decides. When the two source fields disagree (5 rows: drivetrain RWD vs Traction Front wheel drive) RWD wins silently. `4WD` can only be produced from literal `4wd` text which the dataset never contains (4x4 is stored as AWD).

### drivetrain label
- where: `sellFlowDriveLabel` `default:`
- default: default -> 'FWD'
- unknown/blank becomes: **FWD**  (silently factual: True)
- Second default. Also the Search drive ladder is only FWD/RWD/AWD, so a 4WD label could never be offered in Search even if produced.

### transmission
- where: `_mapSpecToFormFields` + `sellFlowTransmissionLabel`
- default: 'automatic' unless the text contains 'manual'
- unknown/blank becomes: **Automatic**  (silently factual: True)
- Dataset has no blank transmission today (Automatic 25,506 / Manual 16,624), so no effect now, but a blank or CVT/DCT/semi-auto value would silently be Automatic or Manual-by-substring.

### fuel
- where: `_mapSpecToFormFields` + `sellFlowFuelLabel`
- default: 'gasoline' unless diesel/electric/hybrid substring
- unknown/blank becomes: **Gasoline**  (silently factual: True)
- Dataset has only Petrol (Gasoline) / Diesel / Electric (no blanks). `hybrid` can never be produced from this dataset (hybrids are stored as Petrol), so every hybrid is Gasoline. A blank fuel would become Gasoline.

### seats
- where: `_mapSpecToFormFields` + `sellFlowNearestSeatingLabel`
- default: null seats -> no option (correct)
- unknown/blank becomes: **no option**  (silently factual: False)
- Blank seats are NOT defaulted (1,245 rows give no option). But counts are rounded to the nearest offered label: 1->2, 3->4, 9/10/14->8 (a changed fact, but derived from a real value).

### Search narrowing fallback
- where: `narrowOptionsToCatalog` (car_spec_index_types.dart) used by `HomeVehicleFieldOptions.resolve`
- default: known == null or empty -> the FULL generic ladder
- unknown/blank becomes: **every option**  (silently factual: True)
- When a selected model has no body/drivetrain data (no dataset coverage, or no family rows) Search shows the whole body ladder (Sedan..Minivan) and FWD/RWD/AWD as if all applied. Only cylinders/engine size get the `Any only` treatment today.

## Raw vocabulary: body

| raw | app value | rule | rows | flags |
|---|---|---|---|---|
| Sedan | Sedan | contains 'sedan' | 9021 |  |
| SUV | SUV | contains 'suv' | 6032 | SUV_OFFROAD_CROSSOVER_FAMILY |
| Hatchback | Hatchback | contains 'hatch' | 5746 |  |
| Station wagon (estate) | Sedan | **DEFAULT** | 4795 | FALLS_THROUGH_TO_DEFAULT_SEDAN, WAGON_ESTATE_FAMILY |
| Coupe | Coupe | contains 'coupe' | 3425 |  |
| Pick-up | Sedan | **DEFAULT** | 3383 | FALLS_THROUGH_TO_DEFAULT_SEDAN, PICKUP_VARIANT |
| Minivan | Van | contains 'van' | 2114 | MINIVAN_MPV_FAMILY, ALIAS_NOT_EXACT |
| Cabriolet | Sedan | **DEFAULT** | 1352 | FALLS_THROUGH_TO_DEFAULT_SEDAN |
| Van | Van | contains 'van' | 1230 |  |
| SUV, Crossover | SUV | contains 'suv' | 861 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| MPV | Sedan | **DEFAULT** | 567 | FALLS_THROUGH_TO_DEFAULT_SEDAN, MINIVAN_MPV_FAMILY |
| Minivan, MPV | Van | contains 'van' | 432 | MINIVAN_MPV_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Roadster | Sedan | **DEFAULT** | 424 | FALLS_THROUGH_TO_DEFAULT_SEDAN |
| Liftback | Sedan | **DEFAULT** | 398 | FALLS_THROUGH_TO_DEFAULT_SEDAN |
| Off-road vehicle | SUV | contains 'off-road' | 384 | SUV_OFFROAD_CROSSOVER_FAMILY, ALIAS_NOT_EXACT |
| Crossover | Sedan | **DEFAULT** | 271 | FALLS_THROUGH_TO_DEFAULT_SEDAN, SUV_OFFROAD_CROSSOVER_FAMILY |
| Coupe, SUV | SUV | contains 'suv' | 244 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Fastback | Sedan | **DEFAULT** | 236 | FALLS_THROUGH_TO_DEFAULT_SEDAN |
| Station wagon (estate), Crossover | Sedan | **DEFAULT** | 218 | FALLS_THROUGH_TO_DEFAULT_SEDAN, SUV_OFFROAD_CROSSOVER_FAMILY, WAGON_ESTATE_FAMILY, MULTI_VALUE |
| Coupe - Cabriolet | Coupe | contains 'coupe' | 143 | ALIAS_NOT_EXACT |
| Targa | Sedan | **DEFAULT** | 118 | FALLS_THROUGH_TO_DEFAULT_SEDAN |
| SAV | Sedan | **DEFAULT** | 102 | FALLS_THROUGH_TO_DEFAULT_SEDAN, SUV_OFFROAD_CROSSOVER_FAMILY |
| Grand Tourer | Sedan | **DEFAULT** | 95 | FALLS_THROUGH_TO_DEFAULT_SEDAN |
| SAC | Sedan | **DEFAULT** | 56 | FALLS_THROUGH_TO_DEFAULT_SEDAN, SUV_OFFROAD_CROSSOVER_FAMILY |
| Sedan, Fastback | Sedan | contains 'sedan' | 53 | MULTI_VALUE, ALIAS_NOT_EXACT |
| Coupe, Liftback | Coupe | contains 'coupe' | 49 | MULTI_VALUE, ALIAS_NOT_EXACT |
| MPV, Van | Van | contains 'van' | 43 | MINIVAN_MPV_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| CUV | Sedan | **DEFAULT** | 40 | FALLS_THROUGH_TO_DEFAULT_SEDAN, SUV_OFFROAD_CROSSOVER_FAMILY |
| Off-road vehicle, SUV | SUV | contains 'suv' | 38 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Hatchback, Crossover | Hatchback | contains 'hatch' | 34 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Minivan, Crossover | Van | contains 'van' | 30 | SUV_OFFROAD_CROSSOVER_FAMILY, MINIVAN_MPV_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Off-road vehicle, Cabriolet | SUV | contains 'off-road' | 26 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Cabriolet, SUV | SUV | contains 'suv' | 22 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Coupe, Fastback | Coupe | contains 'coupe' | 20 | MULTI_VALUE, ALIAS_NOT_EXACT |
| Station wagon (estate), MPV | Sedan | **DEFAULT** | 14 | FALLS_THROUGH_TO_DEFAULT_SEDAN, WAGON_ESTATE_FAMILY, MINIVAN_MPV_FAMILY, MULTI_VALUE |
| Quadricycle | Sedan | **DEFAULT** | 12 | FALLS_THROUGH_TO_DEFAULT_SEDAN |
| Coupe, Crossover | Coupe | contains 'coupe' | 11 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Coupe, Hatchback | Hatchback | contains 'hatch' | 10 | MULTI_VALUE, ALIAS_NOT_EXACT |
| Coupe, SUV, Crossover | SUV | contains 'suv' | 10 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Off-road vehicle, Cabriolet, SUV | SUV | contains 'suv' | 9 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| SUV, MPV | SUV | contains 'suv' | 9 | SUV_OFFROAD_CROSSOVER_FAMILY, MINIVAN_MPV_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Crossover, MPV | Sedan | **DEFAULT** | 9 | FALLS_THROUGH_TO_DEFAULT_SEDAN, SUV_OFFROAD_CROSSOVER_FAMILY, MINIVAN_MPV_FAMILY, MULTI_VALUE |
| Coupe - Cabriolet, Roadster | Coupe | contains 'coupe' | 8 | MULTI_VALUE, ALIAS_NOT_EXACT |
| Off-road vehicle, Station wagon (estate) | SUV | contains 'off-road' | 5 | SUV_OFFROAD_CROSSOVER_FAMILY, WAGON_ESTATE_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Cabriolet, Coupe | Coupe | contains 'coupe' | 5 | MULTI_VALUE, ALIAS_NOT_EXACT |
| Cabriolet, Hatchback | Hatchback | contains 'hatch' | 5 | MULTI_VALUE, ALIAS_NOT_EXACT |
| Pick-up, Targa | Sedan | **DEFAULT** | 4 | FALLS_THROUGH_TO_DEFAULT_SEDAN, PICKUP_VARIANT, MULTI_VALUE |
| SUV, Targa | SUV | contains 'suv' | 3 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| SUV, Fastback | SUV | contains 'suv' | 3 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Hatchback, Fastback | Hatchback | contains 'hatch' | 2 | MULTI_VALUE, ALIAS_NOT_EXACT |
| Off-road vehicle, Pick-up | SUV | contains 'off-road' | 2 | PICKUP_VARIANT, SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Coupe, CUV | Coupe | contains 'coupe' | 2 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Off-road vehicle, Coupe | SUV | contains 'off-road' | 2 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |
| Crossover, Fastback | Sedan | **DEFAULT** | 2 | FALLS_THROUGH_TO_DEFAULT_SEDAN, SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE |
| Sedan, Crossover | Sedan | contains 'sedan' | 1 | SUV_OFFROAD_CROSSOVER_FAMILY, MULTI_VALUE, ALIAS_NOT_EXACT |

Spelling/case variants (same text ignoring case, hyphen, space): none

## Raw vocabulary: drivetrain (drivetrain + Traction:)

| raw drivetrain | raw traction | app value | rule | rows | flags |
|---|---|---|---|---|---|
| FWD | Front wheel drive | FWD | contains 'fwd' | 19152 |  |
| AWD | All wheel drive (4x4) | AWD | contains 'awd' | 11512 |  |
| RWD | Rear wheel drive | RWD | contains 'rwd' | 9684 |  |
| (blank) | (blank) | FWD | **DEFAULT** | 1777 | BLANK_BOTH, FALLS_THROUGH_TO_DEFAULT_FWD |
| RWD | Front wheel drive | RWD | contains 'rwd' | 5 | DRIVETRAIN_VS_TRACTION_CONFLICT |

## Raw vocabulary: transmission / fuel / seats

- transmission Manual -> Manual: 16624
- transmission Automatic -> Automatic: 25506
- fuel Petrol (Gasoline): 28386
- fuel Diesel: 11691
- fuel Electric: 2053
- seats 1 -> 2 (remapped): 7
- seats 2 -> 2: 2274
- seats 3 -> 4 (remapped): 837
- seats 4 -> 4: 5059
- seats 5 -> 5: 29004
- seats 6 -> 6: 993
- seats 7 -> 7: 2090
- seats 8 -> 8: 401
- seats 9 -> 8 (remapped): 176
- seats 10 -> 8 (remapped): 22
- seats 11 -> 8 (remapped): 2
- seats 14 -> 8 (remapped): 9
- seats 15 -> 8 (remapped): 4
- seats 17 -> 8 (remapped): 7
- seats None -> None: 1245

Drivetrain vs Traction conflict rows:

- Volkswagen Golf GLi 1 6 (110 Hp) (1979): drivetrain=RWD traction=Front wheel drive
- BMW X1 20i (192 Hp) sDrive Steptronic (2015): drivetrain=RWD traction=Front wheel drive
- Kia Optima 2 0 GDI (205 Hp) Plug-in Hybrid Automatic (2017): drivetrain=RWD traction=Front wheel drive
- Renault Clio E-TECH 1 6 (140 Hp) Hybrid Multi-Mode (2020): drivetrain=RWD traction=Front wheel drive
- Geely Jia Ji 1 5TD (258 Hp) Plug-in Hybrid DCT (2019): drivetrain=RWD traction=Front wheel drive

## Row-level trace: Volkswagen|Golf

Family rows accepted by the current matcher: 657; catalog longer siblings: ['Golf Plus', 'Golf R']
Search body: ['Any', 'Sedan', 'Hatchback', 'Van']; Search drive: ['Any', 'FWD', 'RWD', 'AWD']

### Volkswagen|Golf -> body=Sedan (205 rows)

| id | raw dataset name | years | raw body | raw drivetrain | raw traction | app body | body path | app drive | drive path |
|---|---|---|---|---|---|---|---|---|---|
| 8779 | Golf GLS 1 5 (70 Hp) | 1979-1982 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8780 | Golf GLi 1 6 (110 Hp) | 1979-1982 | Cabriolet | RWD | Front wheel drive | Sedan | **DEFAULT fallback** | RWD | contains 'rwd' **(sources conflict)** |
| 8783 | Golf 1 8 (112 Hp) | 1982-1989 | Cabriolet | (blank) | (blank) | Sedan | **DEFAULT fallback** | FWD | **DEFAULT fallback** |
| 8782 | Golf 1 6 (75 Hp) | 1983-1992 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8784 | Golf 1 8 (90 Hp) | 1983-1992 | Cabriolet | (blank) | (blank) | Sedan | **DEFAULT fallback** | FWD | **DEFAULT fallback** |
| 8785 | Golf 1 8 (95 Hp) | 1983-1993 | Cabriolet | (blank) | (blank) | Sedan | **DEFAULT fallback** | FWD | **DEFAULT fallback** |
| 8781 | Golf 1 6 (72 Hp) | 1986-1990 | Cabriolet | (blank) | (blank) | Sedan | **DEFAULT fallback** | FWD | **DEFAULT fallback** |
| 8786 | Golf 1 8 (98 Hp) | 1989-1994 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8734 | Golf 1 4 (60 Hp) | 1993-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8736 | Golf 1 6 (75 Hp) | 1993-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8737 | Golf 1 8 (75 Hp) | 1993-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8738 | Golf 1 8 (90 Hp) | 1993-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8740 | Golf 1 9 D (65 Hp) | 1993-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8742 | Golf 1 9 TD (75 Hp) | 1993-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8746 | Golf 2 0 (115 Hp) | 1993-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8751 | Golf 1 8 i (75 Hp) | 1993-1998 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8752 | Golf 1 8 i (90 Hp) | 1993-1998 | Cabriolet | (blank) | (blank) | Sedan | **DEFAULT fallback** | FWD | **DEFAULT fallback** |
| 8754 | Golf 2 0i (115 Hp) | 1993-1998 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8735 | Golf 1 6 (101 Hp) | 1994-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8739 | Golf 1 8 Syncro (90 Hp) | 1994-1999 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 8744 | Golf 1 9 TDI (90 Hp) | 1994-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8749 | Golf 2 9 VR6 Syncro (190 Hp) | 1994-1999 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 8750 | Golf 1 6i (101 Hp) | 1994-1995 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 28702 | Golf 1 9 TDI (90 Hp) Automatic | 1994-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8745 | Golf 1 9 TDI Syncro (90 Hp) | 1995-1999 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 8753 | Golf 1 9 TDI (90 Hp) | 1995-1998 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 52203 | Golf 1 6i (101 Hp) | 1995-1998 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8743 | Golf 1 9 TDI (110 Hp) | 1996-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8741 | Golf 1 9 SDI (64 Hp) | 1997-1999 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8707 | Golf 1 6i (101 Hp) | 1998-2000 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8708 | Golf 1 8i (75 Hp) | 1998-2000 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8709 | Golf 1 8i (90 Hp) | 1998-2000 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8710 | Golf 1 9 TDI (110 Hp) | 1998-2000 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8711 | Golf 1 9 TDI (90 Hp) | 1998-2001 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8713 | Golf 2 0i (116 Hp) | 1998-2002 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 28699 | Golf 1 6i (101 Hp) Automatic | 1998-2000 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 28700 | Golf 1 8i (90 Hp) Automatic | 1998-2000 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 28701 | Golf 2 0i (116 Hp) Automatic | 1998-2002 | Cabriolet | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8687 | Golf 1 4 16V (75 Hp) | 1999-2006 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8688 | Golf 1 6 (101 Hp) | 1999-2000 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8691 | Golf 1 8 20V (125 Hp) 4motion | 1999-2006 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 8692 | Golf 1 9 SDI (68 Hp) | 1999-2006 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8694 | Golf 1 9 TDI (110 Hp) | 1999-2002 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8695 | Golf 1 9 TDI (115 Hp) | 1999-2001 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8697 | Golf 1 9 TDI (90 Hp) | 1999-2002 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8699 | Golf 1 9 TDI (115 Hp) 4motion | 1999-2001 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 8701 | Golf 1 9 TDI (90 Hp) 4motion | 1999-2002 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 8702 | Golf 2 0 (116 Hp) | 1999-2001 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8704 | Golf 2 3 V5 (150 Hp) | 1999-2001 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8705 | Golf 2 3 V5 (150 Hp) 4motion | 1999-2001 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 8706 | Golf 2 8 V6 (204 Hp) 4motion | 1999-2003 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 28695 | Golf 1 6 (101 Hp) Automatic | 1999-2000 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 28697 | Golf 1 9 TDI (110 Hp) Automatic | 1999-2002 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 28698 | Golf 2 0 (116 Hp) Automatic | 1999-2001 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8689 | Golf 1 6 16V (105 Hp) | 2000-2006 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8693 | Golf 1 9 TDI (101 Hp) | 2000-2006 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8698 | Golf 1 9 TDI (101 Hp) 4motion | 2000-2006 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 8703 | Golf 2 0 i (116 Hp) 4motion | 2000-2001 | Station wagon (estate) | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 28696 | Golf 1 9 TDI (101 Hp) Automatic | 2000-2006 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| 8696 | Golf 1 9 TDI (130 Hp) | 2001-2006 | Station wagon (estate) | FWD | Front wheel drive | Sedan | **DEFAULT fallback** | FWD | contains 'fwd' |
| ... | 145 more rows | | | | | | | | |

### Volkswagen|Golf -> body=Van (46 rows)

| id | raw dataset name | years | raw body | raw drivetrain | raw traction | app body | body path | app drive | drive path |
|---|---|---|---|---|---|---|---|---|---|
| 8649 | Golf 1 4 16V (75 Hp) | 2004-2006 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 8654 | Golf 1 6 FSI (115 Hp) | 2004-2007 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 8655 | Golf 1 9 TDI (105 Hp) DSG | 2004-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 8656 | Golf 1 9 TDI (105 Hp) | 2004-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 8652 | Golf 1 6 (102 Hp) Automatic | 2005-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 8653 | Golf 1 6 (102 Hp) | 2005-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 8657 | Golf 2 0 TDI (140 Hp) DSG | 2005-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 8658 | Golf 2 0 TDI (140 Hp) | 2005-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 16801 | Golf 1 4 (80 Hp) | 2006-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 8650 | Golf 1 4 TSI (122 Hp) DSG | 2007-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 8651 | Golf 1 4 TSI (122 Hp) | 2007-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 16802 | Golf 1 4 TSI (160 Hp) | 2008-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 16803 | Golf 1 4 TSI (160 Hp) DSG | 2008-2008 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 17901 | Golf 1 4 (80 Hp) | 2008-2014 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 17902 | Golf 1 4 TSI (122 Hp) | 2008-2014 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 17903 | Golf 1 4 TSI (122 Hp) DSG | 2008-2014 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 17904 | Golf 1 4 TSI (160 Hp) | 2008-2014 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 17905 | Golf 1 4 TSI (160 Hp) DSG | 2008-2014 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 17908 | Golf 2 0 TDI (140 Hp) | 2008-2014 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 17909 | Golf 2 0 TDI (140 Hp) DSG | 2008-2014 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 17906 | Golf 1 6 TDI (105 Hp) | 2009-2014 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 17907 | Golf 1 6 TDI (105 Hp) DSG | 2009-2014 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 23264 | Golf 1 2 TSI (85 Hp) | 2012-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19697 | Golf 1 6 TDI (110 Hp) | 2013-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19741 | Golf 1 6 TDI (110 Hp) DSG | 2013-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19694 | Golf 1 2 TSI (110 Hp) | 2014-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19695 | Golf 1 4 TSI (125 Hp) | 2014-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19696 | Golf 1 4 TSI (150 Hp) | 2014-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19738 | Golf 1 2 TSI (110 Hp) DSG | 2014-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19739 | Golf 1 4 TSI (125 Hp) DSG | 2014-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19740 | Golf 1 4 TSI (150 Hp) DSG | 2014-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19742 | Golf 2 0 TDI (150 Hp) | 2014-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 19743 | Golf 2 0 TDI (150 Hp) DSG | 2014-2017 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 23276 | Golf 1 0 TSI (115 Hp) BlueMotion | 2015-2016 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 23286 | Golf 1 0 TSI (115 Hp) BlueMotion DSG | 2015-2016 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 31921 | Golf 1 5 TSI ACT (150 Hp) DSG | 2017-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 31922 | Golf 1 0 TSI (110 Hp) DSG | 2017-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 31923 | Golf 1 5 TSI ACT (131 Hp) DSG | 2017-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 31924 | Golf 1 0 TSI (110 Hp) | 2017-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 31925 | Golf 1 0 TSI (85 Hp) | 2017-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 31926 | Golf 1 5 TSI ACT (131 Hp) | 2017-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 36069 | Golf 1 6 TDI SCR (116 Hp) | 2017-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 36070 | Golf 1 6 TDI SCR (116 Hp) DSG | 2017-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 36071 | Golf 2 0 TDI SCR (150 Hp) DSG | 2017-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 36066 | Golf 1 0 TSI (116 Hp) | 2018-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |
| 36067 | Golf 1 0 TSI (116 Hp) DSG | 2018-2019 | Minivan | FWD | Front wheel drive | Van | contains 'van' | FWD | contains 'fwd' |

### Volkswagen|Golf -> drive=RWD (1 rows)

| id | raw dataset name | years | raw body | raw drivetrain | raw traction | app body | body path | app drive | drive path |
|---|---|---|---|---|---|---|---|---|---|
| 8780 | Golf GLi 1 6 (110 Hp) | 1979-1982 | Cabriolet | RWD | Front wheel drive | Sedan | **DEFAULT fallback** | RWD | contains 'rwd' **(sources conflict)** |

Other values: body=Hatchback (406), drive=AWD (68), drive=FWD (588)

## Row-level trace: Toyota|Land Cruiser

Family rows accepted by the current matcher: 74; catalog longer siblings: ['Land Cruiser 70', 'Land Cruiser 70 Pickup', 'Land Cruiser 76', 'Land Cruiser Prado']
Search body: ['Any', 'Sedan', 'SUV']; Search drive: ['Any', 'AWD']

### Toyota|Land Cruiser -> body=Sedan (3 rows)

| id | raw dataset name | years | raw body | raw drivetrain | raw traction | app body | body path | app drive | drive path |
|---|---|---|---|---|---|---|---|---|---|
| 3683 | Land Cruiser 4 2 D 24V (128 Hp) 4WD | 2012-2012 | Pick-up | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 3684 | Land Cruiser 4 5 D-4D V8 (205 Hp) 4WD | 2012-2021 | Pick-up | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |
| 3732 | Land Cruiser 4 0 i V6 (231 Hp) 4WD | 2012-2012 | Pick-up | AWD | All wheel drive (4x4) | Sedan | **DEFAULT fallback** | AWD | contains 'awd' |

Other values: body=SUV (71), drive=AWD (74)

## High-priority models

| model | rows | Search body | Search drive | body (rows via default) | drive (rows via default) | flags |
|---|---|---|---|---|---|---|
| Volkswagen Golf | 657 | Sedan, Hatchback, Van | FWD, RWD, AWD | Hatchback 406(0), Sedan 205(205), Van 46(0) | AWD 68(0), FWD 588(11), RWD 1(0) | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_HATCHBACK_PLUS_VAN, BODY_MINIVAN_RAW_MAPPED_TO_VAN, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_SOURCE_FIELDS_CONFLICT, DRIVE_RWD_ONLY_FROM_CONFLICTING_ROWS, DRIVE_EVERY_OPTION |
| Volkswagen Golf R | 29 | Sedan, Hatchback | FWD, AWD | Hatchback 24(0), Sedan 5(5) | AWD 28(0), FWD 1(0) | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT |
| Volkswagen Tiguan | 156 | SUV | FWD, AWD | SUV 156(0) | AWD 86(0), FWD 70(0) |  |
| Volkswagen Passat | 446 | Sedan, Hatchback | FWD, AWD | Hatchback 23(0), Sedan 423(223) | AWD 94(0), FWD 352(31) | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Toyota Land Cruiser | 74 | Sedan, SUV | AWD | SUV 71(0), Sedan 3(3) | AWD 74(0) | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_SUV_WITH_UNSUPPORTED_SEDAN, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION |
| Toyota Land Cruiser Prado | 77 | SUV | AWD | SUV 77(0) | AWD 77(0) |  |
| Toyota Corolla | 231 | Sedan, Hatchback, Coupe | FWD, RWD, AWD | Coupe 10(0), Hatchback 79(0), Sedan 142(46) | AWD 10(0), FWD 194(63), RWD 27(0) | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Toyota Corolla Cross | 15 | SUV | FWD, AWD | SUV 15(0) | AWD 5(0), FWD 10(0) |  |
| Toyota Hilux | 84 | Sedan | FWD, RWD, AWD | Sedan 84(84) | AWD 43(0), FWD 9(9), RWD 32(0) | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Toyota Camry | 114 | Sedan, Hatchback, Coupe | FWD, AWD | Coupe 15(0), Hatchback 3(0), Sedan 96(16) | AWD 4(0), FWD 110(0) | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT |
| Toyota RAV4 | 101 | SUV | FWD, AWD | SUV 101(0) | AWD 70(0), FWD 31(0) |  |
| BMW 3-Series | 836 | Sedan, Hatchback, Coupe | RWD, AWD | Coupe 132(0), Hatchback 18(0), Sedan 686(352) | AWD 203(0), RWD 633(0) | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT |
| BMW 4-Series | 213 | Sedan, Coupe | RWD, AWD | Coupe 160(0), Sedan 53(53) | AWD 89(0), RWD 124(0) | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT |
| BMW 5-Series | 480 | Sedan | RWD, AWD | Sedan 480(206) | AWD 118(0), RWD 362(0) | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT |
| BMW X1 | 100 | Sedan, SUV | FWD, RWD, AWD | SUV 88(0), Sedan 12(12) | AWD 52(0), FWD 28(0), RWD 20(0) | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_SUV_WITH_UNSUPPORTED_SEDAN, DRIVE_SOURCE_FIELDS_CONFLICT, DRIVE_EVERY_OPTION |
| BMW X3 | 95 | Sedan, SUV | RWD, AWD | SUV 53(0), Sedan 42(42) | AWD 83(0), RWD 12(0) | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_SUV_WITH_UNSUPPORTED_SEDAN |
| BMW X5 | 63 | Sedan, SUV | RWD, AWD | SUV 27(0), Sedan 36(36) | AWD 57(0), RWD 6(0) | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_SUV_WITH_UNSUPPORTED_SEDAN |
| Lexus LX | 16 | SUV | AWD | SUV 16(0) | AWD 16(0) |  |
| Lexus GX | 11 | SUV | AWD | SUV 11(0) | AWD 11(0) |  |
| Lexus RX | 39 | SUV | FWD, AWD | SUV 39(0) | AWD 25(0), FWD 14(0) |  |
| Ford Everest | 11 | SUV | RWD, AWD | SUV 11(0) | AWD 5(0), RWD 6(0) |  |
| Ford Bronco | 40 | SUV | AWD | SUV 40(0) | AWD 40(0) |  |
| Ford Mustang | 125 | Sedan, Coupe | RWD | Coupe 45(0), Sedan 80(80) | RWD 125(0) | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT |
| Nissan Patrol | 60 | SUV | FWD, AWD | SUV 60(0) | AWD 49(0), FWD 11(11) | DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |

## Top suspicious models (body)

| model | rows | body | drive | flags |
|---|---|---|---|---|
| Volkswagen Golf | 657 | Sedan, Hatchback, Van | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_HATCHBACK_PLUS_VAN, BODY_MINIVAN_RAW_MAPPED_TO_VAN, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_SOURCE_FIELDS_CONFLICT, DRIVE_RWD_ONLY_FROM_CONFLICTING_ROWS, DRIVE_EVERY_OPTION |
| Dodge Ram | 106 | Sedan | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Toyota Hilux | 84 | Sedan | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Land Rover Defender | 69 | Sedan, SUV | FWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_SUV_WITH_UNSUPPORTED_SEDAN, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Dodge Dakota | 33 | Sedan | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Nissan Titan | 30 | Sedan | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Renault Megane | 367 | Sedan, SUV, Hatchback, Coupe, Van | FWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_HATCHBACK_PLUS_VAN, BODY_4PLUS_CATEGORIES, BODY_5PLUS_CATEGORIES, BODY_MINIVAN_RAW_MAPPED_TO_VAN |
| BMW X1 | 100 | Sedan, SUV | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_SUV_WITH_UNSUPPORTED_SEDAN, DRIVE_SOURCE_FIELDS_CONFLICT, DRIVE_EVERY_OPTION |
| Nissan Sunny | 78 | Sedan, Hatchback, Coupe | FWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Toyota Land Cruiser | 74 | Sedan, SUV | AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_SUV_WITH_UNSUPPORTED_SEDAN, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION |
| Toyota Celica | 45 | Sedan, Coupe | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Renault Duster | 40 | Sedan, SUV | FWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_SUV_WITH_UNSUPPORTED_SEDAN, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION |
| Cadillac Escalade | 39 | Sedan, SUV | RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_SUV_WITH_UNSUPPORTED_SEDAN, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION |
| Isuzu D-Max | 34 | Sedan, SUV | RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_SUV_WITH_UNSUPPORTED_SEDAN, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION |
| Aston Martin V8 Vantage | 23 | Sedan, Coupe | FWD, RWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Ford Maverick | 19 | Sedan, SUV | FWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_SUV_WITH_UNSUPPORTED_SEDAN, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION |
| Aston Martin DB7 | 18 | Sedan, Coupe | FWD, RWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Nissan Cube | 11 | Sedan, Van | FWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_MINIVAN_RAW_MAPPED_TO_VAN, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| GMC Hummer EV | 7 | Sedan, SUV | AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_SUV_WITH_UNSUPPORTED_SEDAN, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION |
| Dodge Magnum | 6 | Sedan | FWD, RWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| MG Midget | 3 | Sedan | FWD, RWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Chevrolet Silverado | 394 | Sedan | RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION |
| Skoda Octavia | 349 | Sedan, Hatchback | FWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| GMC Sierra | 267 | Sedan | RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION |
| BMW 2-Series | 176 | Sedan, Coupe, Van | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_MINIVAN_RAW_MAPPED_TO_VAN, DRIVE_EVERY_OPTION |

## Top suspicious models (drivetrain)

| model | rows | body | drive | flags |
|---|---|---|---|---|
| Volkswagen Golf | 657 | Sedan, Hatchback, Van | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_HATCHBACK_PLUS_VAN, BODY_MINIVAN_RAW_MAPPED_TO_VAN, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_SOURCE_FIELDS_CONFLICT, DRIVE_RWD_ONLY_FROM_CONFLICTING_ROWS, DRIVE_EVERY_OPTION |
| Dodge Ram | 106 | Sedan | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Toyota Hilux | 84 | Sedan | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Land Rover Defender | 69 | Sedan, SUV | FWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_SUV_WITH_UNSUPPORTED_SEDAN, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Dodge Dakota | 33 | Sedan | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Nissan Titan | 30 | Sedan | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Mercedes-Benz E-Class | 725 | Sedan, Coupe | FWD, RWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Toyota Crown | 112 | Sedan, SUV | FWD, RWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| BMW X1 | 100 | Sedan, SUV | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_SUV_WITH_UNSUPPORTED_SEDAN, DRIVE_SOURCE_FIELDS_CONFLICT, DRIVE_EVERY_OPTION |
| Ford Scorpio | 51 | Sedan, Hatchback | FWD, RWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Toyota Celica | 45 | Sedan, Coupe | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Aston Martin V8 Vantage | 23 | Sedan, Coupe | FWD, RWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Aston Martin DB7 | 18 | Sedan, Coupe | FWD, RWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Dodge Magnum | 6 | Sedan | FWD, RWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| MG Midget | 3 | Sedan | FWD, RWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Toyota Corolla | 231 | Sedan, Hatchback, Coupe | FWD, RWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| BMW 2-Series | 176 | Sedan, Coupe, Van | FWD, RWD, AWD | BODY_SEDAN_ONLY_FROM_DEFAULT_FALLBACK, BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, BODY_MINIVAN_RAW_MAPPED_TO_VAN, DRIVE_EVERY_OPTION |
| Volkswagen Jetta | 162 | Sedan | FWD, RWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Ford Escort | 153 | Sedan, Hatchback | FWD, RWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Mercedes-Benz G-Class | 128 | SUV | FWD, AWD | BODY_PICKUP_RAW_MAPPED_TO_NON_PICKUP, BODY_PICKUP_RAW_PRESENT_BUT_NO_PICKUP_OPTION, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Ford Sierra | 94 | Sedan, Hatchback | FWD, RWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Mitsubishi Lancer | 93 | Sedan, Hatchback | FWD, RWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Volvo 240 | 41 | Sedan | FWD, RWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |
| Toyota Mark II | 34 | Sedan | FWD, RWD, AWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT, DRIVE_EVERY_OPTION |
| Volvo 740 | 30 | Sedan | FWD | BODY_SEDAN_PARTLY_FROM_DEFAULT_FALLBACK, BODY_ANY_ROW_USES_DEFAULT, DRIVE_FWD_ONLY_FROM_BLANK_DEFAULT, DRIVE_FWD_PARTLY_FROM_BLANK_DEFAULT, DRIVE_ANY_ROW_USES_DEFAULT |

