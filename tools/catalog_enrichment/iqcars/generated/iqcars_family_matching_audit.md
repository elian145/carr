# Flutter model-family matcher: sibling isolation audit

```json
{
 "catalog_models": 1635,
 "models_whose_matched_rows_changed": 35,
 "models_whose_baseline_engines_changed": 13,
 "models_whose_baseline_cylinders_changed": 7,
 "models_whose_other_options_changed": 17,
 "models_whose_coverage_changed": 0,
 "models_whose_effective_search_engines_changed": 13,
 "models_whose_effective_search_cylinders_changed": 6,
 "models_whose_effective_sell_cylinders_changed": 6,
 "classification": {
  "CLEAR SIBLING CONTAMINATION": 35
 },
 "python_vs_dart_parity_failures": [],
 "strict_rows_total_old": 33632,
 "strict_rows_total_new": 33056,
 "NOT_PORTED_qualifier_quarantine": {
  "note": "The tooling additionally quarantines a row when the text between the model and the engine is not a known trim/grammar (e.g. 'Corolla Verso 1 8'). That is a separate, much broader filter; it is NOT part of the sibling boundary and is not ported.",
  "rows_kept_by_strict_but_not_accepted_by_tooling_by_tooling_status": {
   "ambiguous_qualifier": 2265
  },
  "models_affected": 316,
  "rows_accepted_by_tooling_but_not_in_strict_by_tooling_status": {
   "engine_descriptor": 22
  }
 }
}
```

## Changed models

| model | old rows | strict rows | removed rows belong to | engines old -> strict | cylinders old -> strict | class |
|---|---|---|---|---|---|---|
| Alfa Romeo Giulia | 30 | 26 | {'Giulia Quadrifoglio': 4} | 8 -> 7 | 4,6 -> 4,6 | CLEAR SIBLING CONTAMINATION |
| Aston Martin V8 Vantage | 28 | 23 | {'V8 Vantage S': 3} | 4 -> 4 | 8 -> 8 | CLEAR SIBLING CONTAMINATION |
| Cadillac ATS | 19 | 13 | {'ATS-V': 3} | 3 -> 3 | 4,6 -> 4,6 | CLEAR SIBLING CONTAMINATION |
| Cadillac CTS | 41 | 32 | {'CTS-V': 5} | 9 -> 6 | 4,6,8 -> 4,6 | CLEAR SIBLING CONTAMINATION |
| Chery Tiggo 7 | 11 | 10 | {'Tiggo 7 Pro': 1} | 4 -> 4 | 4 -> 4 | CLEAR SIBLING CONTAMINATION |
| Chery Tiggo 8 | 21 | 13 | {'Tiggo 8 Pro': 8} | 4 -> 4 | 4 -> 4 | CLEAR SIBLING CONTAMINATION |
| Chevrolet Silverado | 400 | 394 | {'Silverado EV': 6} | 10 -> 10 | 4,6,8 -> 4,6,8 | CLEAR SIBLING CONTAMINATION |
| Ford Bronco | 42 | 40 | {'Bronco Sport': 2} | 13 -> 11 | 3,4,6,8 -> 4,6,8 | CLEAR SIBLING CONTAMINATION |
| Ford Mustang | 144 | 125 | {'Mustang Mach-E': 13} | 16 -> 16 | 4,6,8 -> 4,6,8 | CLEAR SIBLING CONTAMINATION |
| Ford Taurus | 44 | 42 | {'Taurus X': 2} | 9 -> 9 | 4,6,8 -> 4,6,8 | CLEAR SIBLING CONTAMINATION |
| Foton Tunland | 12 | 6 | {'Tunland G7': 4} | 2 -> 1 | 4 -> 4 | CLEAR SIBLING CONTAMINATION |
| Geely Emgrand | 16 | 4 | {'Emgrand GS': 1, 'Emgrand GT': 4, 'Emgrand X7': 7} | 5 -> 1 | 4,6 ->  | CLEAR SIBLING CONTAMINATION |
| Honda Civic | 212 | 199 | {'Civic Type R': 9} | 16 -> 16 | 3,4 -> 3,4 | CLEAR SIBLING CONTAMINATION |
| Hyundai Ioniq | 27 | 9 | {'Ioniq 5': 11, 'Ioniq 6': 7} | 1 -> 1 | 4 -> 4 | CLEAR SIBLING CONTAMINATION |
| Land Rover Discovery | 110 | 59 | {'Discovery Sport': 51} | 14 -> 12 | 3,4,5,6,8 -> 4,5,6,8 | CLEAR SIBLING CONTAMINATION |
| Lexus RC | 12 | 9 | {'RC F': 3} | 3 -> 2 | 4,6,8 -> 4,6 | CLEAR SIBLING CONTAMINATION |
| Mercedes-Benz AMG GT | 21 | 16 | {'AMG GT 4-door Coupe': 5} | 3 -> 2 | 4,6,8 -> 4,8 | CLEAR SIBLING CONTAMINATION |
| Mitsubishi Eclipse | 55 | 45 | {'Eclipse Cross': 9} | 8 -> 6 | 4,6 -> 4,6 | CLEAR SIBLING CONTAMINATION |
| Mitsubishi Lancer | 110 | 93 | {'Lancer Evolution': 12} | 11 -> 11 | 4,6 -> 4,6 | CLEAR SIBLING CONTAMINATION |
| Mitsubishi Montero | 30 | 7 | {'Montero Sport': 23} | 5 -> 3 | 4,6 -> 6 | CLEAR SIBLING CONTAMINATION |
| Mitsubishi Pajero | 101 | 78 | {'Pajero Sport': 21} | 15 -> 14 | 4,6 -> 4,6 | CLEAR SIBLING CONTAMINATION |
| Nissan Rogue | 21 | 17 | {'Rogue Sport': 4} | 4 -> 4 | 3,4 -> 3,4 | CLEAR SIBLING CONTAMINATION |
| Porsche 911 | 306 | 250 | {'911 GT2': 5, '911 GT3': 14, '911 Turbo': 21} | 15 -> 13 | 6 -> 6 | CLEAR SIBLING CONTAMINATION |
| Renault Clio | 226 | 221 | {'Clio RS': 5} | 13 -> 13 | 3,4,6 -> 3,4,6 | CLEAR SIBLING CONTAMINATION |
| Renault Megane | 435 | 376 | {'Megane GT': 14, 'Megane RS': 16} | 13 -> 13 | 3,4 -> 3,4 | CLEAR SIBLING CONTAMINATION |
| Subaru Impreza | 129 | 110 | {'Impreza WRX': 7, 'Impreza WRX STI': 6} | 7 -> 7 | 4 -> 4 | CLEAR SIBLING CONTAMINATION |
| Subaru Impreza WRX | 19 | 13 | {'Impreza WRX STI': 6} | 2 -> 2 | 4 -> 4 | CLEAR SIBLING CONTAMINATION |
| Toyota Corolla | 273 | 258 | {'Corolla Cross': 12} | 15 -> 15 | 3,4 -> 3,4 | CLEAR SIBLING CONTAMINATION |
| Toyota Land Cruiser | 151 | 74 | {'Land Cruiser Prado': 50} | 25 -> 22 | 4,5,6,8 -> 4,5,6,8 | CLEAR SIBLING CONTAMINATION |
| Toyota Prius | 18 | 17 | {'Prius Prime': 1} | 3 -> 3 | 4 -> 4 | CLEAR SIBLING CONTAMINATION |
| Toyota Yaris | 84 | 75 | {'Yaris Cross': 9} | 10 -> 10 | 3,4 -> 3,4 | CLEAR SIBLING CONTAMINATION |
| Volkswagen Golf | 686 | 657 | {'Golf R': 17} | 26 -> 26 | 3,4,5,6 -> 3,4,5,6 | CLEAR SIBLING CONTAMINATION |
| Volkswagen Passat | 493 | 446 | {'Passat CC': 47} | 25 -> 25 | 4,5,6,8 -> 4,5,6,8 | CLEAR SIBLING CONTAMINATION |
| Volvo S60 | 98 | 95 | {'S60 Polestar': 3} | 10 -> 10 | 4,5,6 -> 4,5,6 | CLEAR SIBLING CONTAMINATION |
| Volvo V60 | 104 | 101 | {'V60 Polestar': 3} | 8 -> 8 | 4,5,6 -> 4,5,6 | CLEAR SIBLING CONTAMINATION |
