# Payments (CarNet)

CarNet is a listing and messaging marketplace. **Vehicle purchase payments are arranged off-platform** between buyer and seller. The production app does **not** integrate a payment gateway, in-app purchase (IAP), or card vault for vehicle deals.

## What this means for stores

- Google Play Data Safety / Apple App Privacy: **do not** mark payment card or financial account data as collected for vehicle purchases.
- Privacy Policy and Terms state that deals are off-platform.
- Help Center FAQ: payments are arranged directly between buyer and seller.

## Optional promotions

Admin platform settings may store informational prices for featured listings or dealer subscriptions (`featured_listing_price`, `dealer_subscription_price`). Those fields support offline/manual billing messaging only unless you later ship an in-app checkout. If you enable real in-app payments:

1. Update `kk/legal/privacy.html` and `kk/legal/terms.html`
2. Update Google Play Data Safety and Apple App Privacy answers
3. Document the processor (Stripe, local PSP, etc.) in this file
