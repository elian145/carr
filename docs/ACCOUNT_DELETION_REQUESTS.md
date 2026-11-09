# Web account-deletion requests: operator runbook

Public form: `GET /delete-account` posting to `POST /api/account-deletion-request`
(URLs unchanged). Requests are stored in `account_deletion_request` **before** the
visitor sees success; the email to `SUPPORT_EMAIL` is only a best-effort notification.

## What is stored (privacy)

* Phone, optional email and details (needed to verify ownership), an HMAC digest of the
  IP (never the raw IP), timestamps and notification bookkeeping.
* On completion the phone is masked (`***1234`), email and details are cleared and the
  dedupe key is replaced with a one-way digest. No retention period is defined for the
  remaining non-identifying row (status, resolution, timestamps).
* The public response is identical for new and duplicate submissions and does not
  reveal whether an account exists. The endpoint is limited to 5 requests/hour/IP
  (shared limiter; with Redis down in production it fails closed with 503).

## Working the queue (admin API; `users.read` to list, `users.write` to act)

```text
GET  /api/admin/account-deletion-requests?status=pending|completed|all
     -> requests[] (status, phone, email, details, notified, last_notify_error,
        account_exists for pending rows) + counts {pending, pending_unnotified}
POST /api/admin/account-deletion-requests/<id>/complete
     {"resolution": "account_deleted" | "no_account_found" | "declined", "note": "..."}
POST /api/admin/account-deletion-requests/retry-notifications
```

Procedure: verify ownership out of band -> delete the account (the in-app flow's
deletion routine, or `kk/routes/auth.py::delete_account` equivalent) -> complete the
request with the matching `resolution`.

**"completed" does not by itself mean deleted.** The server refuses
`account_deleted` and `no_account_found` (409 `account_still_exists`) while an account
with that phone (any spelling, active or not) still exists; `declined` (ownership not
verified / request rejected) is always allowed. The first resolution stands.

## Failed email notifications

A provider outage never loses a request. Un-notified pending requests are visible
(`notified: false`, `last_notify_error`, `counts.pending_unnotified`) and are retried by
(a) a repeat submission for the same phone and (b) the retry endpoint above. Operators
should check `counts.pending_unnotified` and the queue itself daily; do not rely on the
email alone.

## Rollback / downgrade

Downgrading below `a7d3e1c9b5f2` drops this table **with every request, pending and
completed**. A code-only rollback does not need a downgrade. Export all rows first and
process every pending request: see `docs/ROLLBACK.md` ("Database", Option 1 and the
required exports; current head `b8e4f2a6c1d3`).
