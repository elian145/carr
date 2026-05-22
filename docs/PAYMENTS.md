# Payments (CARZO)

## Production behavior

The **current production API** (`kk/` blueprints) does **not** process in-app payments. Listings are created and browsed without a payment gateway step.

- Buyers and sellers arrange payment **off-platform** (cash, bank transfer, etc.).
- The in-app **Help Center** states this explicitly (`lib/pages/help_center_page.dart`).

## Legacy / HTML (not used by the Flutter app)

Older modules under `kk/legacy/` and HTML templates (`payment_gateway.html`, FIB integration notes) supported experimental listing-fee flows. Those routes are **not** registered on the production app factory and must not be enabled in production.

## Store privacy forms

When completing Google Play Data Safety or Apple App Privacy:

- **Do not** mark in-app purchase or payment card data as collected unless you ship a new payment integration.
- You may disclose contact info and user-generated content (listings, chat) per `docs/STORE_SUBMISSION.md`.

If you add a payment provider later, update this document, `docs/STORE_SUBMISSION.md`, and the Help Center copy before release.
