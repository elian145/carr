"use client";

import Link from "next/link";
import { Fragment, Suspense, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { DataTable, Td, Th } from "@/components/DataTable";
import { FilterSelect } from "@/components/FilterSelect";
import { Pagination } from "@/components/Pagination";
import { StatCard } from "@/components/StatCard";
import { useAuth } from "@/context/AuthContext";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import {
  fetchAutoModerationRun,
  fetchAutoModerationRuns,
  fetchAutoModerationSettings,
  fetchAutoModerationStats,
  overrideAutoModerationRun,
  reevaluateAutoModerationRun,
  setAutoModerationKillSwitch,
  updateAutoModerationSettings,
} from "@/lib/api";
import { formatDate, formatPrice } from "@/lib/format";
import { hasPermission } from "@/lib/permissions";
import { buildUrlQuery, paramPage, paramString } from "@/lib/urlParams";
import type {
  AutoModerationOverrideAction,
  AutoModerationRun,
  AutoModerationSettings,
  AutoModerationSettingsResponse,
  AutoModerationView,
} from "@/lib/types";

type Tab = "overview" | "queue" | "settings";

const MODE_LABEL: Record<string, string> = {
  off: "Off",
  shadow: "Shadow (no publishing)",
  live: "Live (auto-approve)",
};

const DECISION_LABEL: Record<string, string> = {
  AUTO_APPROVE: "Auto-approve",
  NEEDS_REVIEW: "Needs review",
  HOLD: "Hold",
};

function pct(v: number | null | undefined): string {
  return v == null ? "—" : `${(v * 100).toFixed(1)}%`;
}

function decisionClass(d: string | null): string {
  if (d === "AUTO_APPROVE") return "text-emerald-300";
  if (d === "NEEDS_REVIEW") return "text-amber-300";
  if (d === "HOLD") return "text-red-300";
  return "text-surface-muted";
}

function ModeBanner({ data }: { data: AutoModerationSettingsResponse }) {
  const live = data.effective_mode === "live";
  return (
    <div
      className={`mb-6 rounded-xl border p-4 text-sm ${
        data.kill_switch_active
          ? "border-red-900/60 bg-red-950/30 text-red-100"
          : live
            ? "border-emerald-900/60 bg-emerald-950/20 text-emerald-100"
            : "border-surface-border bg-surface-card/60"
      }`}
    >
      <p className="font-medium">
        Effective mode: {MODE_LABEL[data.effective_mode] || data.effective_mode}
        {data.kill_switch_active ? " — KILL SWITCH ACTIVE" : ""}
      </p>
      <p className="mt-1 text-surface-muted">
        {data.environment.disabled
          ? "Automation is disabled by the server environment."
          : data.kill_switch_active
            ? `Nothing is auto-approved.${
                data.settings.kill_switch_reason
                  ? ` Reason: ${data.settings.kill_switch_reason}`
                  : ""
              }`
            : data.effective_mode === "shadow"
              ? "Decisions are recorded and compared with your decisions. Nothing is published automatically."
              : live
                ? "Listings that pass every check are published automatically. Everything else waits for you."
                : "Automation is off."}
      </p>
      {data.settings.mode === "live" && data.effective_mode !== "live" ? (
        <p className="mt-1 text-amber-300">
          Configured as live but not active (server environment or kill switch).
        </p>
      ) : null}
      {data.warning ? <p className="mt-1 text-amber-300">{data.warning}</p> : null}
    </div>
  );
}

function Overview({
  settings,
  reload,
}: {
  settings: AutoModerationSettingsResponse;
  reload: () => void;
}) {
  const { user } = useAuth();
  const toast = useToast();
  const { confirm, prompt } = useConfirm();
  const canKill = hasPermission(user, "auto_moderation.killswitch");
  const { data: stats, error, loading } = useAsyncData(
    () => fetchAutoModerationStats(30),
    [],
  );
  const report = settings.shadow_report;

  async function toggleKill() {
    const engage = !settings.kill_switch_active;
    let reason: string | undefined;
    if (engage) {
      const r = await prompt({
        title: "Engage the kill switch?",
        description:
          "Automatic publication stops immediately. Decisions keep being recorded in shadow mode.",
        inputLabel: "Reason (optional)",
        confirmLabel: "Engage kill switch",
        tone: "danger",
      });
      if (r === null) return;
      reason = r.trim() || undefined;
    } else {
      const ok = await confirm({
        title: "Release the kill switch?",
        description:
          "Automation returns to the configured mode. In live mode, listings may be published automatically again.",
        confirmLabel: "Release",
        tone: "warning",
      });
      if (!ok) return;
    }
    try {
      await setAutoModerationKillSwitch(engage, reason);
      toast.success(engage ? "Kill switch engaged" : "Kill switch released");
      reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed");
    }
  }

  return (
    <div className="space-y-6">
      <ModeBanner data={settings} />
      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          disabled={!canKill}
          onClick={toggleKill}
          className={`rounded-lg px-4 py-2 text-sm text-white disabled:opacity-40 ${
            settings.kill_switch_active
              ? "bg-emerald-700 hover:bg-emerald-600"
              : "bg-red-700 hover:bg-red-600"
          }`}
          title={canKill ? undefined : "Requires the auto_moderation.killswitch permission"}
        >
          {settings.kill_switch_active ? "Release kill switch" : "Engage kill switch"}
        </button>
        <span className="text-xs text-surface-muted">
          AI provider: {settings.environment.ai_provider}
          {settings.environment.ai_model ? ` (${settings.environment.ai_model})` : ""}
          {settings.environment.ai_configured ? "" : " — not configured"}
        </span>
      </div>

      {error ? <p className="text-sm text-red-300">{error}</p> : null}
      {loading && !stats ? <p className="text-sm text-surface-muted">Loading statistics…</p> : null}
      {stats ? (
        <>
          <h3 className="text-sm font-medium text-surface-muted">Last {stats.days} days</h3>
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard label="Evaluated" value={stats.evaluated} />
            <StatCard
              label="Auto-approved"
              value={stats.auto_approved}
              sub={`${stats.post_approval_reversals} later hidden/rejected by an admin (${pct(stats.post_approval_reversal_rate)})`}
            />
            <StatCard
              label="Error rate"
              value={pct(stats.error_rate)}
              sub={`${stats.failed_evaluations} failed / held for service problems`}
            />
            <StatCard
              label="AI provider unavailable"
              value={pct(stats.ai.unavailable_rate)}
              sub={`${stats.ai.calls} calls · avg ${stats.ai.avg_latency_ms ?? "—"} ms`}
            />
          </div>
          <div className="grid gap-4 sm:grid-cols-3">
            <StatCard label="Stale results discarded" value={stats.stale_discards} />
            <StatCard label="Apply refused (state changed)" value={stats.apply_refusals} />
            <StatCard label="Alerts sent" value={stats.alerts_sent} />
          </div>
          <section className="rounded-xl border border-surface-border bg-surface-card p-5">
            <h3 className="mb-3 font-medium">Decisions by mode</h3>
            <ul className="grid gap-1 text-sm sm:grid-cols-2">
              {Object.entries(stats.by_mode_decision).map(([k, v]) => (
                <li key={k} className="flex justify-between border-b border-surface-border/50 py-1">
                  <span className="text-surface-muted">{k}</span>
                  <span>{v}</span>
                </li>
              ))}
              {Object.keys(stats.by_mode_decision).length === 0 ? (
                <li className="text-surface-muted">No decisions recorded yet.</li>
              ) : null}
            </ul>
          </section>
        </>
      ) : null}

      {report ? (
        <section className="rounded-xl border border-surface-border bg-surface-card p-5">
          <h3 className="font-medium">Shadow-mode comparison with admin decisions</h3>
          <p className="mt-1 text-xs text-surface-muted">
            Measured from your own decisions over the last {report.window_days} days. These are
            the numbers that gate enabling live mode; no accuracy is assumed.
          </p>
          <div className="mt-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <StatCard
              label="Would have auto-approved (with outcome)"
              value={report.would_auto_approve}
              sub={`${report.awaiting_human_outcome} still awaiting an admin decision`}
            />
            <StatCard
              label="Unsafe approvals"
              value={report.unsafe_approvals}
              sub={`${pct(report.unsafe_approve_rate)} — admin rejected what automation would have approved`}
            />
            <StatCard
              label="Over-flagged"
              value={report.over_flagged}
              sub={`${pct(report.over_flag_rate)} — sent to you but approved as-is`}
            />
            <StatCard label="Agreement" value={pct(report.agreement_rate)} sub={`${report.compared} compared`} />
          </div>
          <p className={`mt-4 text-sm ${report.gate.passed ? "text-emerald-300" : "text-amber-300"}`}>
            Live-mode gate: {report.gate.passed ? "passed" : "not passed"} (needs ≥{" "}
            {report.gate.min_samples} compared auto-approve decisions and an unsafe rate ≤{" "}
            {pct(report.gate.max_unsafe_approve_rate)})
          </p>
          {report.gate.problems.map((p) => (
            <p key={p} className="text-xs text-surface-muted">
              • {p}
            </p>
          ))}
        </section>
      ) : null}
    </div>
  );
}

function RunDetail({
  runId,
  onChanged,
}: {
  runId: string;
  onChanged: () => void;
}) {
  const { user } = useAuth();
  const toast = useToast();
  const { confirm, prompt } = useConfirm();
  const canWrite = hasPermission(user, "listings.write");
  const { data, error, loading, reload } = useAsyncData(
    () => fetchAutoModerationRun(runId),
    [runId],
  );
  const [busy, setBusy] = useState(false);

  async function act(run: AutoModerationRun, action: AutoModerationOverrideAction) {
    const labels: Record<AutoModerationOverrideAction, string> = {
      approve: "Approve this listing now?",
      revoke: "Revoke this automatic approval (hide the listing)?",
      require_review: "Pin this listing to manual review?",
      clear_review_pin: "Remove the manual-review pin?",
    };
    const note = await prompt({
      title: labels[action],
      description:
        action === "approve"
          ? "Uses the normal manual approval; the seller is notified as usual."
          : undefined,
      inputLabel: "Note (kept in the moderation history)",
      confirmLabel: "Confirm",
      tone: action === "revoke" ? "danger" : "brand",
    });
    if (note === null) return;
    setBusy(true);
    try {
      await overrideAutoModerationRun(run.id, action, note.trim() || undefined);
      toast.success("Done");
      reload();
      onChanged();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Override failed");
      reload();
    } finally {
      setBusy(false);
    }
  }

  async function reevaluate(run: AutoModerationRun) {
    const ok = await confirm({
      title: "Re-run the automatic checks?",
      confirmLabel: "Re-run",
    });
    if (!ok) return;
    try {
      await reevaluateAutoModerationRun(run.id);
      toast.success("Queued");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to queue");
    }
  }

  if (loading && !data) return <p className="p-4 text-sm text-surface-muted">Loading…</p>;
  if (error && !data) return <p className="p-4 text-sm text-red-300">{error}</p>;
  if (!data) return null;
  const run = data.run;
  const awaiting =
    run.listing.status === "pending" || run.subject_type === "revision";
  return (
    <div className="space-y-4 p-4 text-sm">
      <div className="grid gap-4 md:grid-cols-2">
        <div>
          <h4 className="mb-2 font-medium">Why</h4>
          <ul className="space-y-1">
            {(run.reasons || []).map((r) => (
              <li key={`${r.code}-${r.detail}`}>
                <span
                  className={
                    r.level === "hold"
                      ? "text-red-300"
                      : r.level === "review"
                        ? "text-amber-300"
                        : "text-surface-muted"
                  }
                >
                  {r.code}
                </span>
                {r.suspicious ? <span className="ml-1 text-xs text-red-400">suspicious</span> : null}
                {r.detail ? <span className="ml-2 text-xs text-surface-muted">{r.detail}</span> : null}
              </li>
            ))}
            {(run.reasons || []).length === 0 ? (
              <li className="text-surface-muted">All mandatory checks passed.</li>
            ) : null}
          </ul>
          {run.error ? <p className="mt-2 text-xs text-red-300">Error: {run.error}</p> : null}
          <p className="mt-3 text-xs text-surface-muted">
            AI output is advisory only; it is not proof of ownership, authenticity or condition.
          </p>
        </div>
        <div>
          <h4 className="mb-2 font-medium">History</h4>
          <ul className="space-y-1">
            {(run.events || []).map((e) => (
              <li key={e.id} className="flex justify-between gap-3">
                <span>
                  {e.type}
                  {e.actor ? <span className="text-surface-muted"> · {e.actor}</span> : null}
                </span>
                <span className="text-xs text-surface-muted">{formatDate(e.created_at)}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {canWrite && awaiting ? (
          <>
            <button
              type="button"
              disabled={busy}
              onClick={() => act(run, "approve")}
              className="rounded-lg bg-brand-600 px-3 py-1.5 text-white hover:bg-brand-500 disabled:opacity-50"
            >
              Approve
            </button>
            <button
              type="button"
              disabled={busy}
              onClick={() => act(run, "require_review")}
              className="rounded-lg border border-surface-border px-3 py-1.5 hover:bg-white/5 disabled:opacity-50"
            >
              Pin to manual review
            </button>
          </>
        ) : null}
        {canWrite && run.outcome === "published" && run.subject_type === "listing" ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => act(run, "revoke")}
            className="rounded-lg bg-red-800 px-3 py-1.5 text-white hover:bg-red-700 disabled:opacity-50"
          >
            Revoke approval
          </button>
        ) : null}
        {canWrite ? (
          <button
            type="button"
            onClick={() => act(run, "clear_review_pin")}
            className="rounded-lg border border-surface-border px-3 py-1.5 hover:bg-white/5"
          >
            Clear pin
          </button>
        ) : null}
        <button
          type="button"
          onClick={() => reevaluate(run)}
          className="rounded-lg border border-surface-border px-3 py-1.5 hover:bg-white/5"
        >
          Re-run checks
        </button>
        {run.listing.id ? (
          <Link
            href={
              run.subject_type === "revision" && run.revision_id
                ? `/listing-edits/${run.revision_id}`
                : `/listings/${run.listing.id}`
            }
            className="text-brand-300 hover:underline"
          >
            Open {run.subject_type === "revision" ? "edit review" : "listing"}
          </Link>
        ) : null}
      </div>
      {run.override_action ? (
        <p className="text-xs text-surface-muted">
          Last override: {run.override_action} by {run.override_by} ({formatDate(run.override_at)})
          {run.override_note ? ` — ${run.override_note}` : ""}
        </p>
      ) : null}
    </div>
  );
}

function Queue() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const page = paramPage(searchParams);
  const view = paramString(searchParams, "view", "flagged") as AutoModerationView;
  const [open, setOpen] = useState<string | null>(null);

  const { data, error, loading, reload } = useAsyncData(
    () => fetchAutoModerationRuns({ view, page, per_page: 20 }),
    [view, page],
  );

  function replace(patch: Record<string, string | number | undefined>) {
    router.replace(
      `${pathname}${buildUrlQuery({ tab: "queue", view, ...patch }, { page: 1 })}`,
    );
  }

  return (
    <AsyncPageBody
      title="Moderation decisions"
      description="Every automatic decision, with reasons. Shadow rows show what automation WOULD have done."
      count={data?.pagination.total}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(result) => (
        <>
          <div className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-surface-border bg-surface-card/50 p-4">
            <FilterSelect
              label="View"
              value={view}
              onChange={(v) => replace({ view: v, page: undefined })}
              options={[
                { value: "flagged", label: "Flagged for review" },
                { value: "held", label: "Held (media / service)" },
                { value: "auto_approved", label: "Auto-approved (published)" },
                { value: "would_approve", label: "Would auto-approve (shadow)" },
                { value: "errors", label: "Errors" },
                { value: "all", label: "All" },
              ]}
            />
          </div>
          <DataTable
            empty={result.runs.length === 0}
            emptyTitle="Nothing here"
            emptyDescription="No moderation decisions match this view."
          >
            <thead>
              <tr>
                <Th>Listing</Th>
                <Th>Type</Th>
                <Th>Mode</Th>
                <Th>Decision</Th>
                <Th>Reasons</Th>
                <Th>Admin outcome</Th>
                <Th>When</Th>
                <Th></Th>
              </tr>
            </thead>
            <tbody>
              {result.runs.map((r) => (
                <Fragment key={r.id}>
                  <tr className="hover:bg-white/[0.02]">
                    <Td>
                      <p className="font-medium">{r.listing.title || r.listing.id}</p>
                      <p className="text-xs text-surface-muted">
                        {r.seller?.username || "—"} ·{" "}
                        {formatPrice(r.listing.price ?? null, r.listing.currency)}
                      </p>
                    </Td>
                    <Td>{r.subject_type === "revision" ? "Edit" : "New"}</Td>
                    <Td>{r.mode}</Td>
                    <Td>
                      <span className={decisionClass(r.decision)}>
                        {r.decision ? DECISION_LABEL[r.decision] : r.status}
                      </span>
                      {r.suspicious ? (
                        <span className="ml-1 text-xs text-red-400">suspicious</span>
                      ) : null}
                      <p className="text-xs text-surface-muted">{r.outcome}</p>
                    </Td>
                    <Td className="max-w-xs text-xs text-surface-muted">
                      {r.reason_codes.join(", ") || "—"}
                    </Td>
                    <Td>{r.admin_outcome || "—"}</Td>
                    <Td className="text-surface-muted">{formatDate(r.created_at)}</Td>
                    <Td>
                      <button
                        type="button"
                        onClick={() => setOpen(open === r.id ? null : r.id)}
                        className="text-brand-300 hover:underline"
                      >
                        {open === r.id ? "Close" : "Inspect"}
                      </button>
                    </Td>
                  </tr>
                  {open === r.id ? (
                    <tr>
                      <td colSpan={8} className="bg-black/20">
                        <RunDetail runId={r.id} onChanged={reload} />
                      </td>
                    </tr>
                  ) : null}
                </Fragment>
              ))}
            </tbody>
          </DataTable>
          <Pagination
            pagination={result.pagination}
            onPageChange={(p) => replace({ page: p > 1 ? p : undefined })}
          />
        </>
      )}
    </AsyncPageBody>
  );
}

function NumberField({
  label,
  value,
  onChange,
  step,
}: {
  label: string;
  value: number;
  onChange: (v: number) => void;
  step?: number;
}) {
  return (
    <label className="flex flex-col gap-1 text-xs text-surface-muted">
      <span>{label}</span>
      <input
        type="number"
        step={step}
        value={Number.isFinite(value) ? value : 0}
        onChange={(e) => onChange(Number(e.target.value))}
        className="rounded-lg border border-surface-border bg-black/30 px-2 py-1.5 text-sm text-white"
      />
    </label>
  );
}

function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <label className="flex items-center gap-2 text-sm">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
      {label}
    </label>
  );
}

function SettingsForm({
  initial,
  environment,
  onSaved,
}: {
  initial: AutoModerationSettings;
  environment: AutoModerationSettingsResponse["environment"];
  onSaved: () => void;
}) {
  const { user } = useAuth();
  const toast = useToast();
  const { confirm } = useConfirm();
  const canWrite = hasPermission(user, "auto_moderation.write");
  const [s, setS] = useState<AutoModerationSettings>(initial);
  const [saving, setSaving] = useState(false);
  const [emails, setEmails] = useState(initial.alerts.email_recipients.join(", "));

  function patch<K extends keyof AutoModerationSettings>(k: K, v: AutoModerationSettings[K]) {
    setS((prev) => ({ ...prev, [k]: v }));
  }

  async function save() {
    const body: Record<string, unknown> = {
      mode: s.mode,
      auto_approve_new_listings: s.auto_approve_new_listings,
      auto_approve_revisions: s.auto_approve_revisions,
      require_ai_for_auto_approve: s.require_ai_for_auto_approve,
      min_photos: s.min_photos,
      min_seller_prior_approved: s.min_seller_prior_approved,
      dealers_count_as_trusted: s.dealers_count_as_trusted,
      max_listings_per_24h: s.max_listings_per_24h,
      price_change_review_pct: s.price_change_review_pct,
      flag_contact_in_description: s.flag_contact_in_description,
      listing_payment_required: s.listing_payment_required,
      ai: { only_if_candidate: s.ai.only_if_candidate, send_images: s.ai.send_images, min_confidence: s.ai.min_confidence },
      alerts: {
        enabled: s.alerts.enabled,
        channels: s.alerts.channels,
        include_shadow: s.alerts.include_shadow,
        alert_on_routine: s.alerts.alert_on_routine,
        notify_on_hold: s.alerts.notify_on_hold,
        max_per_hour: s.alerts.max_per_hour,
        email_recipients: emails
          .split(/[,\s]+/)
          .map((x) => x.trim())
          .filter(Boolean),
      },
      gate: s.gate,
    };
    if (s.mode === "live" && initial.mode !== "live") {
      const ok = await confirm({
        title: "Enable automatic publication?",
        description:
          "Listings that pass every check will be published without a human. This is only accepted if the shadow-mode comparison meets the configured gate. You can stop it instantly with the kill switch.",
        confirmLabel: "Enable live mode",
        tone: "warning",
      });
      if (!ok) return;
      body.confirm_live = true;
    }
    setSaving(true);
    try {
      await updateAutoModerationSettings(body);
      toast.success("Settings saved");
      onSaved();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Save failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-6">
      {!canWrite ? (
        <p className="text-sm text-amber-300">You can view these settings but not change them.</p>
      ) : null}
      <fieldset disabled={!canWrite} className="space-y-6">
        <section className="space-y-3 rounded-xl border border-surface-border bg-surface-card p-5">
          <h3 className="font-medium">Mode</h3>
          <FilterSelect
            label="Mode"
            value={s.mode}
            onChange={(v) => patch("mode", v as AutoModerationSettings["mode"])}
            options={[
              { value: "off", label: "Off" },
              { value: "shadow", label: "Shadow — record only, never publish (default)" },
              { value: "live", label: "Live — auto-approve clearly legitimate listings" },
            ]}
          />
          {!environment.live_allowed ? (
            <p className="text-xs text-amber-300">
              Live mode is not permitted by the server environment (AUTO_MODERATION_ALLOW_LIVE).
            </p>
          ) : null}
          <Toggle
            label="Auto-approve new listings"
            checked={s.auto_approve_new_listings}
            onChange={(v) => patch("auto_approve_new_listings", v)}
          />
          <Toggle
            label="Auto-approve edits of published listings"
            checked={s.auto_approve_revisions}
            onChange={(v) => patch("auto_approve_revisions", v)}
          />
          <Toggle
            label="Require an AI check for auto-approval"
            checked={s.require_ai_for_auto_approve}
            onChange={(v) => patch("require_ai_for_auto_approve", v)}
          />
          <Toggle
            label="Listing payment required (cannot be verified yet → always sent to review)"
            checked={s.listing_payment_required}
            onChange={(v) => patch("listing_payment_required", v)}
          />
        </section>

        <section className="grid gap-4 rounded-xl border border-surface-border bg-surface-card p-5 sm:grid-cols-3">
          <h3 className="font-medium sm:col-span-3">Rules</h3>
          <NumberField label="Minimum photos" value={s.min_photos} onChange={(v) => patch("min_photos", v)} />
          <NumberField
            label="Prior human-approved listings (non-dealer sellers)"
            value={s.min_seller_prior_approved}
            onChange={(v) => patch("min_seller_prior_approved", v)}
          />
          <NumberField
            label="Max new listings per seller / 24h"
            value={s.max_listings_per_24h}
            onChange={(v) => patch("max_listings_per_24h", v)}
          />
          <NumberField
            label="Price change that needs review (%)"
            value={s.price_change_review_pct}
            onChange={(v) => patch("price_change_review_pct", v)}
          />
          <NumberField
            label="Minimum AI confidence"
            step={0.05}
            value={s.ai.min_confidence}
            onChange={(v) => setS((p) => ({ ...p, ai: { ...p.ai, min_confidence: v } }))}
          />
          <div className="space-y-2">
            <Toggle
              label="Approved dealers count as trusted"
              checked={s.dealers_count_as_trusted}
              onChange={(v) => patch("dealers_count_as_trusted", v)}
            />
            <Toggle
              label="Flag phone/email in description"
              checked={s.flag_contact_in_description}
              onChange={(v) => patch("flag_contact_in_description", v)}
            />
            <Toggle
              label="Send photos to the AI provider"
              checked={s.ai.send_images}
              onChange={(v) => setS((p) => ({ ...p, ai: { ...p.ai, send_images: v } }))}
            />
            <Toggle
              label="Call the AI only when rules would approve (saves cost)"
              checked={s.ai.only_if_candidate}
              onChange={(v) => setS((p) => ({ ...p, ai: { ...p.ai, only_if_candidate: v } }))}
            />
          </div>
        </section>

        <section className="space-y-3 rounded-xl border border-surface-border bg-surface-card p-5">
          <h3 className="font-medium">Admin alerts</h3>
          <p className="text-xs text-surface-muted">
            Alerts contain only a reason summary and a link to the dashboard — no seller names,
            phone numbers or listing text. Telegram credentials are server-side secrets
            ({environment.telegram_configured ? "configured" : "not configured"}).
          </p>
          <Toggle
            label="Send alerts when a listing needs review"
            checked={s.alerts.enabled}
            onChange={(v) => setS((p) => ({ ...p, alerts: { ...p.alerts, enabled: v } }))}
          />
          <Toggle
            label="Email"
            checked={s.alerts.channels.includes("email")}
            onChange={(v) =>
              setS((p) => ({
                ...p,
                alerts: {
                  ...p.alerts,
                  channels: v
                    ? [...new Set([...p.alerts.channels, "email"])]
                    : p.alerts.channels.filter((c) => c !== "email"),
                },
              }))
            }
          />
          <Toggle
            label="Telegram"
            checked={s.alerts.channels.includes("telegram")}
            onChange={(v) =>
              setS((p) => ({
                ...p,
                alerts: {
                  ...p.alerts,
                  channels: v
                    ? [...new Set([...p.alerts.channels, "telegram"])]
                    : p.alerts.channels.filter((c) => c !== "telegram"),
                },
              }))
            }
          />
          <label className="flex flex-col gap-1 text-xs text-surface-muted">
            <span>Email recipients (comma separated)</span>
            <input
              value={emails}
              onChange={(e) => setEmails(e.target.value)}
              className="rounded-lg border border-surface-border bg-black/30 px-2 py-1.5 text-sm text-white"
            />
          </label>
          <Toggle
            label="Also alert about shadow-mode decisions"
            checked={s.alerts.include_shadow}
            onChange={(v) => setS((p) => ({ ...p, alerts: { ...p.alerts, include_shadow: v } }))}
          />
          <Toggle
            label="Also alert for routine reasons (e.g. brand-new seller)"
            checked={s.alerts.alert_on_routine}
            onChange={(v) => setS((p) => ({ ...p, alerts: { ...p.alerts, alert_on_routine: v } }))}
          />
          <Toggle
            label="Also alert when a listing is held (media / service problem)"
            checked={s.alerts.notify_on_hold}
            onChange={(v) => setS((p) => ({ ...p, alerts: { ...p.alerts, notify_on_hold: v } }))}
          />
          <NumberField
            label="Maximum alerts per hour"
            value={s.alerts.max_per_hour}
            onChange={(v) => setS((p) => ({ ...p, alerts: { ...p.alerts, max_per_hour: v } }))}
          />
        </section>

        <section className="grid gap-4 rounded-xl border border-surface-border bg-surface-card p-5 sm:grid-cols-3">
          <h3 className="font-medium sm:col-span-3">Live-mode gate (your policy, not an accuracy claim)</h3>
          <NumberField
            label="Window (days)"
            value={s.gate.window_days}
            onChange={(v) => setS((p) => ({ ...p, gate: { ...p.gate, window_days: v } }))}
          />
          <NumberField
            label="Minimum compared auto-approve decisions"
            value={s.gate.min_samples}
            onChange={(v) => setS((p) => ({ ...p, gate: { ...p.gate, min_samples: v } }))}
          />
          <NumberField
            label="Maximum unsafe-approval rate (0–1)"
            step={0.005}
            value={s.gate.max_unsafe_approve_rate}
            onChange={(v) =>
              setS((p) => ({ ...p, gate: { ...p.gate, max_unsafe_approve_rate: v } }))
            }
          />
        </section>
      </fieldset>
      {canWrite ? (
        <button
          type="button"
          disabled={saving}
          onClick={save}
          className="rounded-lg bg-brand-600 px-5 py-2 text-white hover:bg-brand-500 disabled:opacity-50"
        >
          {saving ? "Saving…" : "Save settings"}
        </button>
      ) : null}
    </div>
  );
}

function AutoModerationInner() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const { user } = useAuth();
  const tab = paramString(searchParams, "tab", "overview") as Tab;
  const { data, error, loading, reload } = useAsyncData(fetchAutoModerationSettings, []);

  const tabs: { id: Tab; label: string }[] = [
    { id: "overview", label: "Overview" },
    { id: "queue", label: "Decisions" },
    { id: "settings", label: "Settings" },
  ];

  function go(t: Tab) {
    router.replace(`${pathname}?tab=${t}`);
  }

  const tabBar = (
    <div className="mb-6 flex gap-2 border-b border-surface-border">
      {tabs.map((t) => (
        <button
          key={t.id}
          type="button"
          onClick={() => go(t.id)}
          className={`-mb-px border-b-2 px-4 py-2 text-sm ${
            tab === t.id
              ? "border-brand-400 text-white"
              : "border-transparent text-surface-muted hover:text-white"
          }`}
        >
          {t.label}
        </button>
      ))}
    </div>
  );

  if (!hasPermission(user, "auto_moderation.read")) {
    return <p className="text-surface-muted">You do not have access to automated moderation.</p>;
  }

  if (tab === "queue") {
    return (
      <>
        {tabBar}
        <Queue />
      </>
    );
  }

  return (
    <AsyncPageBody
      title="Auto moderation"
      description="Automatically approves clearly legitimate listings and sends everything else to you. Starts in shadow mode: nothing is published automatically until you enable it."
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(settings) => (
        <>
          {tabBar}
          {tab === "settings" ? (
            <SettingsForm
              key={JSON.stringify(settings.settings)}
              initial={settings.settings}
              environment={settings.environment}
              onSaved={reload}
            />
          ) : (
            <Overview settings={settings} reload={reload} />
          )}
        </>
      )}
    </AsyncPageBody>
  );
}

export default function AutoModerationPage() {
  return (
    <Suspense fallback={<p className="text-surface-muted">Loading…</p>}>
      <AutoModerationInner />
    </Suspense>
  );
}
