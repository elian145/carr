"use client";

import Link from "next/link";

const SECTIONS = [
  {
    title: "Moderation",
    body: "Use Reports for abuse, Dealers for applications, and Listings/Users for activate, feature, and soft-delete. Soft-delete hides data but keeps rows for audit.",
  },
  {
    title: "Roles",
    body: "Super admins manage roles on a user detail page. Moderators handle listings/dealers/reports. Support focuses on users/reports. Marketing can broadcast notifications. Settings and System require super admin.",
  },
  {
    title: "Vehicle catalog",
    body: "Seed brands/models/trims from the bundled car_catalog.json, then edit in Catalog. Public API: /api/catalog/brands, /models, /trims, /body-types. The mobile app can overlay this on top of its asset catalog after deploy.",
  },
  {
    title: "Notifications",
    body: "Send now or schedule for later. Celery beat delivers due schedules every minute; without beat, use Process due now on the Notifications page.",
  },
  {
    title: "Hard purge",
    body: "Super admins only. Listing purge permanently deletes the row and related messages/reports. User purge anonymizes PII and deactivates listings (keeps FK integrity).",
  },
  {
    title: "Payments",
    body: "In-app payments are out of scope. Featured listing and dealer subscription prices in Settings are reference values for ops/comms only.",
  },
  {
    title: "Deploy checklist",
    body: "After pull: flask db upgrade, redeploy Flask web + Celery worker + beat, redeploy admin-web. Set NEXT_PUBLIC_API_BASE / API_PROXY_TARGET for the admin proxy.",
  },
];

export default function HelpPage() {
  return (
    <div className="mx-auto max-w-3xl space-y-8">
      <div>
        <h1 className="text-2xl font-semibold">Help</h1>
        <p className="mt-1 text-sm text-surface-muted">
          Ops guide for the CarNet admin dashboard.
        </p>
      </div>
      {SECTIONS.map((s) => (
        <section
          key={s.title}
          className="rounded-xl border border-surface-border bg-surface-card p-5"
        >
          <h2 className="text-lg font-medium">{s.title}</h2>
          <p className="mt-2 text-sm leading-relaxed text-surface-muted">
            {s.body}
          </p>
        </section>
      ))}
      <p className="text-sm text-surface-muted">
        Need something else? Start from{" "}
        <Link href="/dashboard" className="text-brand-400 hover:underline">
          Dashboard
        </Link>{" "}
        or{" "}
        <Link href="/system" className="text-brand-400 hover:underline">
          System health
        </Link>
        .
      </p>
    </div>
  );
}
