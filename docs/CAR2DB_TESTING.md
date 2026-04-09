# Car2DB Coverage Testing

This gives you a repeatable way to measure whether Car2DB is good enough for your sell-flow auto-fill.

## 1) Prepare test input CSV

Use `tools/data/car2db_test_sample.csv` as a template.

Required columns:
- `year`
- `make`
- `model`
- `trim`

Optional:
- `market_origin` (for your own analysis)

## 2) Set your test API key

PowerShell:

```powershell
$env:CAR2DB_API_KEY="YOUR_TEST_KEY"
```

## 3) Run coverage test

Replace endpoint/header with values from your Car2DB docs/dashboard.

```powershell
python tools/car2db_coverage_test.py `
  --input tools/data/car2db_test_sample.csv `
  --endpoint "https://car2db.com/api/v1/search" `
  --query-param "query" `
  --query-format "{year} {make} {model} {trim}" `
  --api-key-header "x-api-key" `
  --output-dir tools/out/car2db_test
```

## 4) Review outputs

- `tools/out/car2db_test/summary.json`
- `tools/out/car2db_test/coverage_report.csv`

Statuses:
- `exact`: high-confidence match + mandatory fields found
- `partial`: match exists but missing mandatory fields
- `wrong`: low-confidence/wrong match
- `not_found`: no usable result

## 5) Decision rule

Suggested go-live threshold:
- `exact_rate >= 0.75`
- `wrong_rate <= 0.05`

If below threshold, keep auto-fill disabled and show suggestion/manual mode.
