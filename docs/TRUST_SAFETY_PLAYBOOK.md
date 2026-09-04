# Trust & safety playbook (UGC reports)

Goal: act on reported listings and users within **24 hours** (Apple Guideline 1.2 expectation for user-generated content).

## Intake

1. Users report via in-app **Report listing** / **Report user** (also available in chat).
2. Reports land in the admin queue (`admin-web` Reports + `/api/admin` report endpoints).
3. Check the support email (`SUPPORT_EMAIL`) at least once daily for web/email escalations.

## Triage (same day)

| Severity | Examples | Action |
|----------|----------|--------|
| Critical | Scam payment ask, stolen vehicle, CSAM, threats | Remove listing / suspend user immediately; preserve evidence in admin notes |
| High | Fake dealer, phishing link, harassment | Hide listing pending review; warn or block user |
| Medium | Spam keywords, wrong category, mild abuse | Hold for review; request edit or remove |
| Low | Duplicate listing, minor policy issues | Queue for next review pass |

## Resolve within 24 hours

1. Open the report in admin → open listing/user → decide: **remove listing**, **suspend/ban user**, **dismiss**, or **request more info**.
2. Prefer removing the content and restricting the poster when scam indicators are present (wire/shipping/gift-card language, refusal to meet, pressure to pay off-platform deposits).
3. Reply to the reporter only if they contacted support by email (in-app report is acknowledgment-only today).
4. Log the outcome in admin notes (who acted, when, why).

## Escalation

- Legal threats, law enforcement, or child-safety: escalate to the operator listed in Terms/Privacy immediately; preserve logs.
- Repeat offenders: ban account and block related phone numbers where tooling allows.

## Owners

- Primary: person monitoring `SUPPORT_EMAIL` and admin reports daily.
- Backup: second admin with `is_admin` access.

Update this file when roles change. Revisit SLA before each store submission.
