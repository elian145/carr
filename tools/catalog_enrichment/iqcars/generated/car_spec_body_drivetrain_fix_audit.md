# Body type / drivetrain normalization fix - before / after audit

READ ONLY. BEFORE = old defaults (`unknown -> Sedan`, `blank -> FWD`, full ladders for models without data). AFTER = the fixed Flutter resolver (real Search ladders, Brand + Model selected).

Transcription cross-check vs the real Dart resolver: 423 distinct raw tuples, 0 mismatches.

## Metrics (1,635 catalog models)

- before_models_showing_full_body_ladder: **779**
- before_models_showing_full_drive_ladder: **779**
- before_search_body_any_only: **0**
- before_search_drive_any_only: **0**
- fwd_removed_false_default_models_with_data: **34**
- gain_convertible: **107**
- gain_hatchback_due_to_liftback_only: **21**
- gain_hatchback_total: **21**
- gain_minivan: **78**
- gain_pickup: **46**
- gain_suv_due_to_crossover_cuv_sav_sac_only: **47**
- gain_suv_total: **47**
- gain_wagon: **116**
- models_with_any_change: **1171**
- models_with_data: **856**
- no_data_models_full_ladder_removed_body: **779**
- no_data_models_full_ladder_removed_drive: **779**
- search_body_any_only: **782**
- search_body_any_only_no_dataset_rows: **779**
- search_body_any_only_rows_but_no_recognized_body: **3**
- search_drive_any_only: **785**
- search_drive_any_only_no_dataset_rows: **779**
- search_drive_any_only_rows_but_no_evidence: **6**
- sedan_kept_with_explicit_source: **270**
- sedan_removed_false_default_models_with_data: **187**
- van_removed_models_with_data(minivan_is_no_longer_van): **62**

## Value transitions (models)

- body_gained_Convertible: 107
- body_gained_Coupe: 16
- body_gained_Hatchback: 21
- body_gained_Minivan: 78
- body_gained_Pickup: 46
- body_gained_SUV: 47
- body_gained_Wagon: 116
- body_lost_Sedan: 187
- body_lost_Van: 62
- drive_lost_FWD: 34
- drive_lost_RWD: 2

Dataset rows with no recognised body: 343; rows with no drivetrain evidence: 1782

## Remaining unmapped body vocabulary

- `Fastback`: 236 rows (no category emitted)
- `Grand Tourer`: 95 rows (no category emitted)
- `Quadricycle`: 12 rows (no category emitted)
- `Sedan, Fastback`: 53 rows (recognised part emitted, unmapped part ignored)
- `Coupe, Fastback`: 20 rows (recognised part emitted, unmapped part ignored)
- `SUV, Fastback`: 3 rows (recognised part emitted, unmapped part ignored)
- `Hatchback, Fastback`: 2 rows (recognised part emitted, unmapped part ignored)
- `Crossover, Fastback`: 2 rows (recognised part emitted, unmapped part ignored)

## Body vocabulary after the fix

| raw | rows | app values | unmapped tokens |
|---|---|---|---|
| Sedan | 9021 | Sedan |  |
| SUV | 6032 | SUV |  |
| Hatchback | 5746 | Hatchback |  |
| Station wagon (estate) | 4795 | Wagon |  |
| Coupe | 3425 | Coupe |  |
| Pick-up | 3383 | Pickup |  |
| Minivan | 2114 | Minivan |  |
| Cabriolet | 1352 | Convertible |  |
| Van | 1230 | Van |  |
| SUV, Crossover | 861 | SUV |  |
| MPV | 567 | Minivan |  |
| Minivan, MPV | 432 | Minivan |  |
| Roadster | 424 | Convertible |  |
| Liftback | 398 | Hatchback |  |
| Off-road vehicle | 384 | SUV |  |
| Crossover | 271 | SUV |  |
| Coupe, SUV | 244 | SUV, Coupe |  |
| Fastback | 236 | (none) | fastback |
| Station wagon (estate), Crossover | 218 | SUV, Wagon |  |
| Coupe - Cabriolet | 143 | Coupe, Convertible |  |
| Targa | 118 | Convertible |  |
| SAV | 102 | SUV |  |
| Grand Tourer | 95 | (none) | grand tourer |
| SAC | 56 | SUV |  |
| Sedan, Fastback | 53 | Sedan | fastback |
| Coupe, Liftback | 49 | Hatchback, Coupe |  |
| MPV, Van | 43 | Van, Minivan |  |
| CUV | 40 | SUV |  |
| Off-road vehicle, SUV | 38 | SUV |  |
| Hatchback, Crossover | 34 | SUV, Hatchback |  |
| Minivan, Crossover | 30 | SUV, Minivan |  |
| Off-road vehicle, Cabriolet | 26 | SUV, Convertible |  |
| Cabriolet, SUV | 22 | SUV, Convertible |  |
| Coupe, Fastback | 20 | Coupe | fastback |
| Station wagon (estate), MPV | 14 | Wagon, Minivan |  |
| Quadricycle | 12 | (none) | quadricycle |
| Coupe, Crossover | 11 | SUV, Coupe |  |
| Coupe, Hatchback | 10 | Hatchback, Coupe |  |
| Coupe, SUV, Crossover | 10 | SUV, Coupe |  |
| Off-road vehicle, Cabriolet, SUV | 9 | SUV, Convertible |  |
| SUV, MPV | 9 | SUV, Minivan |  |
| Crossover, MPV | 9 | SUV, Minivan |  |
| Coupe - Cabriolet, Roadster | 8 | Coupe, Convertible |  |
| Off-road vehicle, Station wagon (estate) | 5 | SUV, Wagon |  |
| Cabriolet, Coupe | 5 | Coupe, Convertible |  |
| Cabriolet, Hatchback | 5 | Hatchback, Convertible |  |
| Pick-up, Targa | 4 | Convertible, Pickup |  |
| SUV, Targa | 3 | SUV, Convertible |  |
| SUV, Fastback | 3 | SUV | fastback |
| Hatchback, Fastback | 2 | Hatchback | fastback |
| Off-road vehicle, Pick-up | 2 | SUV, Pickup |  |
| Coupe, CUV | 2 | SUV, Coupe |  |
| Off-road vehicle, Coupe | 2 | SUV, Coupe |  |
| Crossover, Fastback | 2 | SUV | fastback |
| Sedan, Crossover | 1 | Sedan, SUV |  |

## Drivetrain vocabulary after the fix

| drivetrain | traction | rows | app value |
|---|---|---|---|
| FWD | Front wheel drive | 19152 | FWD |
| AWD | All wheel drive (4x4) | 11512 | AWD |
| RWD | Rear wheel drive | 9684 | RWD |
| (blank) | (blank) | 1777 | (none) |
| RWD | Front wheel drive | 5 | (none) |

## Focus models

| model | before body | after body | before drive | after drive |
|---|---|---|---|---|
| BMW X1 | Sedan, SUV | SUV | FWD, RWD, AWD | FWD, RWD, AWD |
| BMW X3 | Sedan, SUV | SUV | RWD, AWD | RWD, AWD |
| BMW X5 | Sedan, SUV | SUV | RWD, AWD | RWD, AWD |
| Ford Mustang | Sedan, Coupe | Coupe, Convertible | RWD | RWD |
| Nissan Patrol | SUV | SUV, Wagon | FWD, AWD | AWD |
| Toyota Hilux | Sedan | Pickup | FWD, RWD, AWD | RWD, AWD |
| Toyota Land Cruiser | Sedan, SUV | SUV, Pickup | AWD | AWD |
| Toyota Land Cruiser Prado | SUV | SUV | AWD | AWD |
| Volkswagen Golf | Sedan, Hatchback, Van | SUV, Hatchback, Convertible, Wagon, Minivan | FWD, RWD, AWD | FWD, AWD |
| Volkswagen Golf R | Sedan, Hatchback | Hatchback, Convertible, Wagon | FWD, AWD | FWD, AWD |

## Models with rows but Search body = Any only

- Aston Martin Rapide (6 rows)
- Audi RS e-tron (3 rows)
- Renault Twizy (1 rows)

## Models with rows but Search drive = Any only

- Cadillac Fleetwood (3 rows)
- Chevrolet Bel Air (2 rows)
- Ford Freestar (2 rows)
- Geely FC (1 rows)
- Toyota Granvia (1 rows)
- Volvo 740 (30 rows)
