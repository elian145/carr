# IQ Cars cylinder / engine quality audit (read-only)

Nothing in the runtime overlay, the candidate or the app was changed. Verdicts are suggestions only.

## Summary numbers

- **catalog_models_audited**: 1635
- **app_has_coverage**: 856
- **app_no_coverage**: 779
- **app_no_coverage_but_tooling_maps_carnet_dataset_rows**: 0
- **search_generic_cylinder_fallback_models**: 0
- **sell_generic_cylinder_fallback_models**: 119
- **search_generic_cylinder_fallback_reasons**: {}
- **search_generic_engine_fallback_models**: 0
- **search_generic_engine_fallback_reasons**: {}
- **models_with_iq_approved_cylinder_data(parsed, not default-list)**: 1511
- **models_whose_runtime_asset_carries_full_cylinder_set**: 1510
- **models_where_iq_cylinders_do_not_reach_app**: 1
- **baseline_mismatch_tooling_has_app_empty**: 0
- **suspicious_cylinder_models(REVIEW + new QUARANTINE)**: 34
- **rare_singleton_iq_models**: 46
- **rare_singleton_iq_by_count**: {1: 2, 2: 6, 10: 7, 12: 29, 16: 2}
- **rare_singleton_iq_models_confirmed_by_carnet(SAFE)**: 25
- **rare_singleton_effective_models**: 44
- **rare_singleton_effective_by_count**: {1: 2, 2: 7, 10: 7, 12: 26, 16: 2}
- **passenger_model_rare_count_models**: 46
- **repeated_cylinder_signatures(shared_pattern, excl. default list)**: 7
- **repeated_cylinder_signatures_incl_default_list**: 8
- **suspicious_engine_models(REVIEW + new QUARANTINE)**: 44
- **repeated_engine_signatures(shared_pattern, excl. default list)**: 0
- **repeated_engine_signatures_incl_default_list**: 1
- **cylinder_verdicts**: {'SAFE': 1544, 'REVIEW': 33, 'QUARANTINE': 58}
- **engine_verdicts**: {'SAFE': 1481, 'REVIEW': 44, 'QUARANTINE': 110}
- **quarantine_cylinders_total_incl_already_excluded**: 58
- **quarantine_cylinders_NEW_recommendations**: 1
- **quarantine_engines_total_incl_already_excluded**: 110
- **quarantine_engines_NEW_recommendations**: 0
- **models_with_placeholder_cylinder_values(values-only quarantine, not exported)**: 108
- **models_with_placeholder_engine_values(values-only quarantine, not exported)**: 12
- **review_cylinder_models**: 33
- **review_engine_models**: 44
- **models_with_exact_brand_new_rows**: 57

## Flag counts

| flag | models |
|---|---|
| cyl:GENERIC_FALLBACK_SEARCH | 0 |
| cyl:GENERIC_FALLBACK_SELL | 119 |
| cyl:RARE_SINGLETON_IQ | 46 |
| cyl:RARE_SINGLETON_EFFECTIVE | 44 |
| cyl:LARGE_DISAGREEMENT_TOOLING | 1 |
| cyl:LARGE_DISAGREEMENT_APP | 1 |
| cyl:SHARED_RESPONSE_PATTERN | 62 |
| cyl:PASSENGER_MODEL_RARE_COUNT | 46 |
| cyl:KNOWN_DEFAULT_CYLINDER_LIST | 57 |
| cyl:PLACEHOLDER_OR_UNPARSEABLE_CYLINDER_VALUE | 108 |
| cyl:BASELINE_MISMATCH_TOOLING_HAS_APP_EMPTY | 0 |
| cyl:IQ_CYLINDERS_NOT_REACHING_APP | 1 |
| cyl:ENGINE_CYLINDER_CONFLICT_ELECTRIC_ENGINES_WITH_CYLINDERS | 0 |
| eng:GENERIC_ENGINE_FALLBACK | 0 |
| eng:KNOWN_DEFAULT_ENGINE_LIST | 110 |
| eng:SHARED_ENGINE_SIGNATURE | 0 |
| eng:LARGE_ENGINE_LIST | 1 |
| eng:PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 12 |
| eng:MALFORMED_ENGINE_VALUE | 0 |
| eng:TWO_DECIMAL_DISPLACEMENT_ROUNDED | 11 |
| eng:SUSPICIOUS_ENGINE_SINGLETON | 0 |
| eng:DISJOINT_CARNET_VS_IQ_ENGINES | 15 |
| eng:DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 14 |
| exact:EXACT_CYLINDER_NOT_IN_IQ_MODEL_LEVEL | 1 |
| exact:EXACT_CYLINDER_DISJOINT_FROM_IQ_MODEL_LEVEL | 1 |
| exact:EXACT_CYLINDER_NOT_IN_APP_BASELINE | 0 |
| exact:RARE_IQ_CYLINDER_NOT_CONFIRMED_BY_EXACT | 1 |
| exact:EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL | 8 |
| exact:EXACT_SAME_ENGINE_MULTIPLE_CYLINDER_COUNTS | 0 |
| exact:DEFAULT_LIST_CONTRADICTED_BY_EXACT | 1 |

## Repeated IQ response signatures: Cylinders[] (top 30)

`CarNet contradicts` = share of members that have CarNet cylinder data where that data does not contain all IQ counts.

| signature (counts) | placeholders | models | brands | shared | CarNet contradicts | examples |
|---|---|---|---|---|---|---|
| [4] | 0 | 724 | 104 | False | 0% | Acura ILX; Acura Integra; Alfa Romeo 4C; Alfa Romeo Giulia; Alfa Romeo Giulietta |
| [4, 6] | 0 | 227 | 54 | False | 9% | Acura RDX; Acura TLX; Alfa Romeo 147; Alfa Romeo GT Coupe; Alfa Romeo Spider |
| [6] | 0 | 95 | 34 | False | 0% | Acura MDX; Acura NSX; Alfa Romeo Giulia Quadrifoglio; Alfa Romeo Stelvio Quadrifoglio; Audi Q8 |
| [6, 8] | 0 | 89 | 28 | False | 5% | Audi RS5; Audi S4; Audi S5; Audi S6; Audi S7 |
| [3, 4] | 0 | 76 | 26 | False | 13% | Audi A1; Audi Q2; BMW X1; BMW X2; Chery S11 QQ |
| [8] | 0 | 73 | 24 | False | 0% | Aston Martin DB11 Volante; Aston Martin DBX; Aston Martin V8 Vantage; Aston Martin V8 Vantage Roadster; Aston Martin V8 Vantage S |
| [1, 2, 3, 4, 5, 6, 8, 10, 12, 16] (default list) | 17 | 57 | 40 | True | 100% | Austin 12; Avatr 06; BAIC BJ40 Pro; BMW i7; BYD M9 |
| [4, 6, 8] | 0 | 47 | 17 | False | 14% | Audi A6; Audi Q7; Buick Regal; Cadillac CT5; Cadillac CT6 |
| [12] | 0 | 29 | 5 | True | 0% | Aston Martin DB9; Aston Martin DB9 Volante; Aston Martin DBS; Aston Martin One-77; Aston Martin Rapide |
| [] | 2 | 22 | 13 | False | n/a | Audi Q4 e-tron; Avatr 07; Avatr 12; BMW i4; BMW i5 |
| [4, 5, 6] | 0 | 21 | 8 | False | 6% | Alfa Romeo 156; Alfa Romeo 159; Alfa Romeo 166; Alfa Romeo Brera; Audi TT |
| [3] | 0 | 18 | 9 | False | 8% | BMW i8; BYD F0; BYD F1; Buick Encore GX; Buick Envista |
| [4] | 1 | 15 | 5 | False | 0% | BYD Destroyer 05; BYD QIN L DM-i; BYD Qin Plus; BYD SONG PRO DM-i; BYD Seal 05 DM-i |
| [] | 1 | 15 | 10 | False | 0% | BMW i3; BMW iX3; BYD ATTO 3; BYD Seagull; BYD e2 |
| [4] | 1 | 12 | 6 | False | 0% | BYD Leopard 5; BYD Leopard 7; BYD Leopard 8; BYD Shark 6; BYD Tang |
| [4, 5] | 0 | 11 | 5 | False | 0% | Ford Mondeo; Mazda BT-50; Seat Cupra Formentor; Volkswagen Beetle; Volkswagen Golf |
| [] | 1 | 9 | 7 | False | n/a | Audi RS e-tron; BMW iX; BYD ATTO 8; BYD Leopard 3; Hongqi E-HS9 |
| [8, 10] | 0 | 8 | 2 | True | 42% | Audi R8; Audi RS6; Audi S8; Ford E-350; Ford Econoline |
| [10] | 0 | 7 | 3 | True | 0% | Dodge Viper; Lamborghini Gallardo; Lamborghini Huracan; Lamborghini Huracan EVO Spyder; Lamborghini Huracan STO |
| [4] | 2 | 7 | 5 | False | 0% | Avatr 11; BYD HAN; BYD SEAL 7; BYD SONG PLUS; Deepal G318 |
| [2] | 0 | 6 | 1 | False | n/a | Polaris General XP 4 1000; Polaris RZR; Polaris RZR PRO XP 4 Turbo; Polaris Ranger 1000; Polaris Ranger Crew 1000 |
| [6, 8, 12] | 0 | 6 | 5 | True | 0% | Audi A8; BMW 8-Series; Bentley Bentayga; Bentley Flying Spur; Mercedes-Benz S-Class |
| [8, 12] | 0 | 6 | 3 | True | 0% | Aston Martin DB11; Bentley Continental; Bentley Continental GT; Bentley Continental GTC; Mercedes-Benz CL-Class |
| [3, 4, 6] | 0 | 4 | 3 | False | 0% | BMW 1-Series; BMW 2-Series; Chevrolet Tracker; Ford Escape |
| [2, 4] | 0 | 3 | 2 | True | n/a | Fiat 500; Fiat 500L; Polaris ProStar |
| [4, 6, 8, 12] | 0 | 3 | 3 | True | 0% | BMW 7-Series; Jaguar XJ; Mercedes-Benz SL-Class |
| [4] | 2 | 3 | 2 | False | 0% | JAECOO J5; Kia Niro; Kia Soul |
| [] | 2 | 3 | 2 | False | n/a | Smart Smart 1; Tesla Model 3; Tesla Model Y |
| [16] | 0 | 2 | 1 | False | n/a | Bugatti Chiron; Bugatti Veyron |
| [1] | 0 | 2 | 1 | False | n/a | Polaris Ranger 570; Polaris Ranger Crew 570 |

## Repeated IQ response signatures: Engines[] (top 20)

| #engines | models | brands | shared | engines | examples |
|---|---|---|---|---|---|
| 139 (default list) | 110 | 55 | True | 0.2, 0.6, 0.8, 0.9, 1.0, 1.0T, 1.0TC I4, 1.1, 1.2, 1.2D... | Audi Q4 e-tron; Audi RS e-tron; Austin 12; Avatr 06 |
| 1 | 52 | 24 | False | 1.5T | Avatr 07; Avatr 11; Avatr 12; BAIC BJ20 |
| 1 | 51 | 21 | False | 1.5 | Austin A55 Cambridge; BAIC A315; BAIC Q35; BAIC X25 |
| 1 | 41 | 24 | False | 2.0T | BAIC BJ40 Pro; BAIC BJ40 SE; BAIC Senova X65; BAW F7 Pick up |
| 2 | 28 | 14 | False | 1.5T, 2.0T | Acura Integra; BYD Tang; Bestune B70S; Bestune T99 |
| 2 | 27 | 14 | False | 1.3, 1.5 | BAIC A1 Hatchback; BAIC A1 Sedan; BAIC D20; Brilliance BS2 |
| 2 | 18 | 9 | False | 1.5, 1.5T | BAIC D50; BAIC U5 PLUS; BAIC X3; BAIC X35 |
| 2 | 18 | 12 | False | 2.0, 2.4 | Acura ILX; BYD F6; BYD S6; Chery B11 Oriental Son |
| 1 | 16 | 11 | False | 2.0 | Chery A520; Hawtai A25; Hyundai Elantra Touring; Lexus UX |
| 1 | 15 | 11 | False | 1.6 | Chery A11 Windcloud; Daihatsu Applause; Daihatsu Feroza; Daihatsu Taft F20 |
| 2 | 13 | 9 | False | 1.5, 1.6 | Brilliance FRV Cross; Brilliance FSV; Brilliance V5; Changan Victory |
| 2 | 12 | 7 | False | 1.8, 2.0 | Chery E8; Daewoo Prince; Haima 7; Jonway A380 |
| 1 | 12 | 6 | False | 3.5 | Chrysler 300M; Ford Taurus X; Honda MR-V; Honda Odyssey |
| 1 | 12 | 6 | False | 3.8 | Hyundai Entourage; Kia Telluride; McLaren 540C Coupe; McLaren 570GT Coupe |
| 1 | 10 | 6 | False | 1.0 | BYD F0; BYD F1; FAW Carrier; GAC Gonow Way M1 |
| 2 | 10 | 5 | False | 2.0T, 2.0TD | BAIC BJ60; Maxus D90; Maxus G10; POER COMMERCIAL |
| 2 | 9 | 9 | False | 1.6, 1.8 | Brilliance BS4; Haima Family; Iran Khodro Tara; Lifan 620 |
| 1 | 9 | 5 | False | 4.0T | Aston Martin DB11 Volante; Aston Martin DBX; Audi RS7; Audi RSQ8 |
| 2 | 8 | 7 | False | 1.0, 1.3 | Chevrolet Metro; Daihatsu Charade; Daihatsu Sirion; FAW N5 |
| 1 | 8 | 5 | False | 1.3 | Chery A1; Chery P10; FAW V2; Lifan 320 |

## Generic cylinder ladder shown with Brand+Model selected: why


## Generic engine ladder shown with Brand+Model selected: why


## App baseline empty although the tooling maps CarNet dataset rows (family-name matching gap)


## Cylinder QUARANTINE recommendations (not already excluded)

- Geely Cityray: IQ model-level [3] is disjoint from exact brand-new rows [4] (CarNet agrees with exact: [4])

## Engine QUARANTINE recommendations (not already excluded)

- none

## Exact brand-new cross-check (58 models): flagged

- Audi Q3: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL; exact cyl [4] eng ['1.4']; IQ cyl [4]; CarNet(app baseline) cyl ['4']
- Deepal G318: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL; exact cyl [4] eng ['1.5']; IQ cyl [4]; CarNet(app baseline) cyl ['4']
- Foton Tunland G7: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL; exact cyl [4] eng ['2.0T']; IQ cyl [4]; CarNet(app baseline) cyl ['4']
- Geely Cityray: EXACT_CYLINDER_NOT_IN_IQ_MODEL_LEVEL, EXACT_CYLINDER_DISJOINT_FROM_IQ_MODEL_LEVEL; exact cyl [4] eng ['1.5T']; IQ cyl [3]; CarNet(app baseline) cyl ['4']
- Land Rover Discovery Sport: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL; exact cyl [4] eng ['2.0']; IQ cyl [3, 4]; CarNet(app baseline) cyl ['3', '4']
- Mercedes-Benz S-Class: RARE_IQ_CYLINDER_NOT_CONFIRMED_BY_EXACT; exact cyl [6, 8] eng ['3.0T', '4.0T']; IQ cyl [6, 8, 12]; CarNet(app baseline) cyl ['4', '5', '6', '8', '12']
- Nissan Urvan: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL; exact cyl [4] eng ['2.5', '2.5TD']; IQ cyl [4]; CarNet(app baseline) cyl []
- Rolls Royce Phantom: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL; exact cyl [12] eng ['6.8']; IQ cyl [12]; CarNet(app baseline) cyl ['12']
- Ssangyong Musso Grand: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL; exact cyl [4] eng ['2.0T']; IQ cyl [4]; CarNet(app baseline) cyl []
- Volkswagen Taos: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL; exact cyl [4] eng ['1.5']; IQ cyl [4]; CarNet(app baseline) cyl ['4']
- Voyah Taishan: DEFAULT_LIST_CONTRADICTED_BY_EXACT; exact cyl [4] eng ['1.5T']; IQ cyl [1, 2, 3, 4, 5, 6, 8, 10, 12, 16]; CarNet(app baseline) cyl []

## Cylinder REVIEW models

- Aston Martin DB9 Volante: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [12] | app baseline [] | tooling []
- Aston Martin V12 Vantage Roadster: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [12] | app baseline [] | tooling []
- Aston Martin Vanquish Volante: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [12] | app baseline [] | tooling []
- Bentley Continental GT: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [8, 12] | app baseline [] | tooling []
- Bentley Continental GTC: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [8, 12] | app baseline [] | tooling []
- Bugatti Chiron: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [16] | app baseline [] | tooling []
- Bugatti Veyron: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [16] | app baseline [] | tooling []
- Ferrari 599 GTB Fiorano: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [12] | app baseline [] | tooling []
- Ferrari 812 Superfast: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [12] | app baseline [] | tooling []
- Ferrari F12 Berlinetta: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [12] | app baseline [] | tooling []
- Fiat 500: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [2, 4] | app baseline [] | tooling []
- Fiat 500L: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [2, 4] | app baseline [] | tooling []
- Ford E-350: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [8, 10] | app baseline [] | tooling []
- Ford Econoline: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [8, 10] | app baseline ['6', '8'] | tooling [6, 8]
- Ford F-250: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [8, 10] | app baseline ['8'] | tooling []
- Ford F-350: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [8, 10] | app baseline ['8'] | tooling []
- Lamborghini Aventador Roadster: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [12] | app baseline [] | tooling []
- Lamborghini Huracan EVO Spyder: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [10] | app baseline [] | tooling []
- Lamborghini Huracan STO: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [10] | app baseline [] | tooling []
- Lamborghini Huracan Spyder: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [10] | app baseline [] | tooling []
- Mercedes-Benz CL-Class: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [8, 12] | app baseline [] | tooling []
- Mercedes-Benz S-Class Maybach: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [8, 12] | app baseline [] | tooling []
- Mercedes-Benz SL-Class: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [4, 6, 8, 12] | app baseline [] | tooling []
- Polaris General XP 4 1000: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [2] | app baseline [] | tooling []
- Polaris ProStar: SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [2, 4] | app baseline [] | tooling []
- Polaris RZR: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [2] | app baseline [] | tooling []
- Polaris RZR PRO XP 4 Turbo: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [2] | app baseline [] | tooling []
- Polaris Ranger 1000: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [2] | app baseline [] | tooling []
- Polaris Ranger 570: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [1] | app baseline [] | tooling []
- Polaris Ranger Crew 1000: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [2] | app baseline [] | tooling []
- Polaris Ranger Crew 570: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [1] | app baseline [] | tooling []
- Polaris SPORTSMAN XP 1000: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET | IQ [2] | app baseline [] | tooling []
- Rolls Royce Drophead Coupe: RARE_SINGLETON_NOT_CONFIRMED_BY_CARNET, PASSENGER_MODEL_RARE_COUNT_NOT_CONFIRMED_BY_CARNET, SHARED_UNUSUAL_RESPONSE_NOT_CONFIRMED_BY_CARNET | IQ [12] | app baseline [] | tooling []

## Engine REVIEW models

- Alfa Romeo 4C: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 1 engine values
- Aston Martin DB9: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 1 engine values
- Aston Martin Rapide: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 1 engine values
- Aston Martin Vanquish: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 1 engine values
- Aston Martin Zagato: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 1 engine values
- Audi Q3: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL | 3 engine values
- BYD F3: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 3 engine values
- Bentley Arnage: TWO_DECIMAL_DISPLACEMENT_ROUNDED | 2 engine values
- Bentley Azure: TWO_DECIMAL_DISPLACEMENT_ROUNDED | 1 engine values
- Bentley Brooklands: TWO_DECIMAL_DISPLACEMENT_ROUNDED | 1 engine values
- Bentley Continental: TWO_DECIMAL_DISPLACEMENT_ROUNDED | 3 engine values
- Bentley Mulsanne: TWO_DECIMAL_DISPLACEMENT_ROUNDED | 1 engine values
- Changan Raeton: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 2 engine values
- Chery A3: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 2 engine values
- Chevrolet Bel Air: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 6 engine values
- Deepal G318: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL | 1 engine values
- Foton Tunland G7: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL | 1 engine values
- Hyundai Ioniq 5: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 2 engine values
- Hyundai Ioniq 6: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 2 engine values
- Land Rover Discovery Sport: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL | 3 engine values
- Mazda MX-30: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 1 engine values
- Mercedes-Benz E-Class: LARGE_ENGINE_LIST | 13 engine values
- Mercedes-Benz SLR McLaren: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 1 engine values
- Nissan Urvan: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL | 3 engine values
- Porsche 911 GT2: DISJOINT_CARNET_VS_IQ_ENGINES | 1 engine values
- Renault Express: DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 4 engine values
- Rolls Royce Cullinan: TWO_DECIMAL_DISPLACEMENT_ROUNDED, DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES | 1 engine values
- Rolls Royce Drophead Coupe: TWO_DECIMAL_DISPLACEMENT_ROUNDED | 1 engine values
- Rolls Royce Ghost: TWO_DECIMAL_DISPLACEMENT_ROUNDED | 2 engine values
- Rolls Royce Phantom: TWO_DECIMAL_DISPLACEMENT_ROUNDED, DISJOINT_CARNET_VS_IQ_ENGINES, DISJOINT_APP_BASELINE_VS_IQ_ENGINES, EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL | 1 engine values
- Rolls Royce Silver Shadow: TWO_DECIMAL_DISPLACEMENT_ROUNDED | 2 engine values
- Rolls Royce Silver Wraith II: TWO_DECIMAL_DISPLACEMENT_ROUNDED | 1 engine values
- Rox 01: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 2 engine values
- Ssangyong Musso Grand: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL | 1 engine values
- Tesla Cybertruck: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 3 engine values
- Tesla Model 3: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 2 engine values
- Tesla Model S: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 2 engine values
- Tesla Model X: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 2 engine values
- Tesla Model Y: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 2 engine values
- Toyota bZ3: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 1 engine values
- Toyota bZ4X: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 2 engine values
- Toyota bZ5: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 1 engine values
- Volkswagen Taos: EXACT_ENGINE_NOT_IN_IQ_MODEL_LEVEL | 2 engine values
- XEV Yoyo Pro: PLACEHOLDER_OR_NON_DISPLACEMENT_ENGINE | 1 engine values
