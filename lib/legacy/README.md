# Legacy app shell

Production UI entry: `main_legacy.dart` → `MyApp` (used from `lib/main.dart`).

## Layout

| File | Role |
|------|------|
| `main_legacy.dart` | App shell, routing, sell flow, profile, chat list, etc. |
| `home_page_legacy.dart` | `part` file — home feed, filters, and listing grid (~8k lines) |
| `sell_flow_legacy.dart` | `part` file — sell entry, drafts, steps 1–5, preview (~9k lines) |

All part files are one library with `main_legacy.dart`. Shared imports live in `main_legacy.dart` only.

## Refactor direction

Prefer new screens under `lib/pages/` and wire them in `MyApp` routes gradually. The modern `lib/pages/home_page.dart` is a separate experiment; `/` still uses legacy `HomePage` until parity is complete.
