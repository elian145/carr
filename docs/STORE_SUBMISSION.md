# CARZO Store Submission Notes

Use this document when completing Google Play Data Safety, Apple App Privacy, and reviewer notes. Keep the answers aligned with the final backend configuration and privacy policy.

## Store Listing Inputs

- App name: `CARZO`
- Bundle/package ID: `com.carzo.app`
- Category: Auto & Vehicles / Shopping marketplace
- Support email: set `SUPPORT_EMAIL` on the backend to your real monitored inbox (default in API/legal pages is `support@carzo.app` until overridden).
- Privacy policy URL: required before submission. Hosted at `{API_BASE}/privacy` after deploy (or set `PRIVACY_URL`).
- Terms URL: recommended before submission. Hosted at `{API_BASE}/terms` after deploy (or set `TERMS_URL`).
- Production API base: `https://carr-5hrm.onrender.com` unless a custom domain replaces it.

## Permission Justifications

- Camera: scan VIN codes and take listing photos/videos.
- Photos and videos: select listing media, profile pictures, and dealer cover photos.
- Microphone: capture audio when the user records listing videos.
- Notifications: receive chat, listing, and account notifications.
- Internet: API, maps, media upload/download, push, and deep links.

## Data Collected Or Processed

- Account data: username, first/last name, email, phone number, password hash on backend, auth tokens on device.
- Listing data: vehicle details, price, location text, seller/dealer profile data, listing photos and videos.
- User-generated content: chat messages, reports, favorites, saved searches, viewed listings, profile/dealer content.
- Device/app data: push notification token, app locale/theme preferences, diagnostic/server logs.
- Location-related data: dealer/listing location fields and map/place selections entered by users.
- Payments: payment screens/routes exist, but confirm the final payment provider and data flow before marking payment data as collected.

## Data Sharing And Disclosure

- Backend/API hosting provider: Render or the selected production host.
- Database provider: production PostgreSQL host.
- Object storage provider: persistent disk or R2/S3 if configured for uploads.
- Firebase: push notifications and platform app configuration.
- Google Maps/Places: map display and place lookup.
- Airbridge: only if Airbridge app name/token are configured for attribution/deep links.
- Email/SMS providers: Resend/SendGrid/SMTP and configured SMS provider for verification and password reset flows.

## Store Form Guidance

- Google Play Data Safety: mark account info, contact info, user content, app activity, app info/performance, and device identifiers as collected if enabled by production configuration.
- Apple App Privacy: include contact info, user content, identifiers, usage data, diagnostics, and location if dealer/listing map flows are considered location-related in your privacy policy.
- Declare that data is encrypted in transit because production API builds require HTTPS.
- Declare account deletion/support instructions in the privacy policy or support page before submission.

## Reviewer Notes

- Provide a test account with listing/chat permissions, or clear steps to create one.
- Mention that camera/photos/microphone are used only when creating listings or profile/dealer media.
- Mention that push notifications are used for chat/listing/account updates.
- Include the production deep-link test URL: `https://carr-5hrm.onrender.com/listing/<valid-listing-id>`.

## Hard Blockers Before Upload

- `android/app/src/prod/google-services.json` must exist and target `com.carzo.app`.
- `https://carr-5hrm.onrender.com/.well-known/assetlinks.json` must return 200 with the Play App Signing SHA-256 fingerprint.
- Privacy policy URL and support contact must be real and reachable.
- Final screenshots and app icon/splash assets must be approved.
