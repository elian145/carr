# Feature flags / remote config

CARZO uses a lightweight remote-config surface on the existing public app config endpoint — not Firebase Remote Config.

## Client contract

`GET /api/config/app` includes:

```json
{
  "feature_flags": {
    "sell": true,
    "chat": true,
    "dealers": true,
    "comparison": true,
    "saved_searches": true
  }
}
```

Unknown keys are ignored. Missing keys default to **enabled** (fail-open) so an API outage does not brick core flows.

Flutter: `lib/services/feature_flags.dart` (`FeatureFlags.load` / `FeatureFlags.current`).  
`AppVersionGate.load` warms the same cache from one HTTP call at startup.

Currently gated in-app when disabled:

- **sell** → `SellDraftGatePage` (dialog + back)
- **chat** → `ChatListPage` (dialog + pop)

Other flags are available for future gates.

## Admin / env

- **Admin web** → Settings → Feature flags (stored in `app_setting` platform JSON).
- **Env defaults** (when no DB override): `FEATURE_FLAG_SELL=0`, `FEATURE_FLAG_CHAT=0`, etc.

Clearing overrides in admin (`feature_flags: null`) restores env defaults.
