# iOS testing: Codemagic + Sideloadly

This guide gets the CARZO app onto your iPhone for testing using **Codemagic** (cloud build) and **Sideloadly** (install without App Store). The app is configured to use your **Render** backend by default.

## Prerequisites

- **Codemagic** account (free tier is enough): [codemagic.io](https://codemagic.io)
- **Sideloadly** installed on your Windows PC: [sideloadly.io](https://sideloadly.io)
- **Apple ID** (free or paid). Free Apple ID: app expires after **7 days**; paid Developer account: **1 year**.
- iPhone and PC on the same Wi‑Fi (for API_BASE if you use a local backend).

## 1. Connect the repo to Codemagic

1. Sign in at [codemagic.io](https://codemagic.io) and add your Git provider (GitHub/GitLab/Bitbucket).
2. Add this repository as an application.
3. Codemagic will detect `codemagic.yaml` in the repo root. No extra config file needed.

## 2. Configure environment (optional)

The app talks to your **Render** backend. The workflow default is your Render web service URL.

- In Codemagic: **Application → Environment variables** (optional override).
- **API_BASE** – Backend base URL **without** `/api` (the app adds `/api` itself).
  - **Default:** `https://carr-5hrm.onrender.com` (this project’s Render URL).
  - **Custom domain:** If you added one in Render (e.g. `api.yourdomain.com`), set `API_BASE=https://api.yourdomain.com`.
- You can leave it unset to use the default; override only if your Render URL or custom domain differs.

## 3. Start an iOS build

1. In Codemagic, open your app and go to **Workflows**.
2. Select the workflow **iOS (IPA for Sideloadly)**.
3. Click **Start new build** (you can leave branch as default, e.g. `main`).
4. Wait for the build to finish (about 5–15 minutes).

## 4. Download the IPA

1. When the build succeeds, open the build and go to **Artifacts**.
2. Download **Runner-unsigned.ipa**.

## 5. Install on iPhone with Sideloadly

1. **Connect your iPhone** to the PC with a USB cable. Unlock the device and tap “Trust” if asked.
2. **Open Sideloadly** on the PC.
3. **Drag and drop** `Runner-unsigned.ipa` into Sideloadly (or use “Select IPA”).
4. **Sign in** with your Apple ID when Sideloadly asks (this is used only for signing, not stored by the app).
5. Click **Start** and wait for the install to complete.
6. On the iPhone: go to **Settings → General → VPN & Device Management** and **trust** the developer profile for your Apple ID.
7. Open **CARZO** from the home screen.

## 6. Backend not working in the app

If listings don’t load, login fails, or you see “API request failed” or “Loading…” forever:

### 6.1 Check Render in the browser

1. Open [Render Dashboard](https://dashboard.render.com) and confirm your web service is **Live**.
2. In a browser, open:
   - `https://carr-5hrm.onrender.com/health` → should show `{"status":"ok"}`.
   - `https://carr-5hrm.onrender.com/api/cars` → should return JSON (can be `{"cars":[]}`).
3. If you use a **custom domain**, use that URL instead (e.g. `https://api.yourdomain.com`).

### 6.2 Point the app at the correct backend

- **Option A – Without rebuilding (iOS Sideload only)**  
  In the app: **Settings** → tap **API** → enter your backend URL (e.g. `https://carr-5hrm.onrender.com`) → **Save**. Then pull to refresh listings. The app remembers this override.
- **Option B – Rebuild**  
  In Codemagic, set environment variable **API_BASE** to your Render URL (no `/api`), then run **iOS (IPA for Sideloadly)** again and reinstall the new IPA.

### 6.3 Cold start (free tier)

On Render’s free tier the service sleeps after ~15 minutes of no traffic. The **first** request after that can take **30–60 seconds**. If the app shows “Loading…” or times out, wait a minute and try again (or open the health URL in the browser first to wake the server), then refresh in the app.

## Summary

| Step | Where | Action |
|------|--------|--------|
| 1 | Codemagic | Connect repo, use workflow **iOS (IPA for Sideloadly)** |
| 2 | Codemagic | (Optional) Set **API_BASE** in env vars |
| 3 | Codemagic | Start build, wait for success |
| 4 | Codemagic | Download **Runner-unsigned.ipa** from Artifacts |
| 5 | Sideloadly | Connect iPhone → drag IPA → sign with Apple ID → Start → Trust profile on device |

After that, the app is ready to test on your iPhone.

---

**Note:** The repo also has `ios/ExportOptions.plist` (method: ad-hoc) for **signed** IPA builds (e.g. with Codemagic’s App Store Connect integration). For Sideloadly you use the **unsigned** IPA from the **iOS (IPA for Sideloadly)** workflow; Sideloadly re-signs the app with your Apple ID. If you later set up Ad Hoc distribution, replace `YOUR_TEAM_ID` in `ExportOptions.plist` with your Apple Developer Team ID.
