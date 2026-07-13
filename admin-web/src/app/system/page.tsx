"use client";

import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { StatCard } from "@/components/StatCard";
import { fetchSystemHealth } from "@/lib/api";
import { formatNumber } from "@/lib/format";

function StatusPill({ ok, label }: { ok: boolean | null | undefined; label: string }) {
  const tone =
    ok === true
      ? "bg-emerald-900/40 text-emerald-200 border-emerald-800/50"
      : ok === false
        ? "bg-red-900/40 text-red-200 border-red-800/50"
        : "bg-white/5 text-surface-muted border-surface-border";
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${tone}`}
    >
      {label}
    </span>
  );
}

export default function SystemHealthPage() {
  const { data, error, loading, reload } = useAsyncData(fetchSystemHealth, []);

  return (
    <AsyncPageBody
      title="System health"
      description="API, database, storage, push, and platform counts"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(health) => {
        const pushReady = Boolean(health.checks.push?.fcm_ready);
        const redisConfigured = health.checks.redis.configured;
        const redisOk = health.checks.redis.ok;

        return (
          <div className="space-y-8">
            <section className="rounded-xl border border-surface-border bg-surface-card p-5">
              <div className="flex flex-wrap items-center gap-3">
                <h2 className="text-lg font-medium">Overall</h2>
                <StatusPill
                  ok={health.status === "ok"}
                  label={health.status === "ok" ? "Healthy" : health.status}
                />
                {health.environment ? (
                  <span className="text-sm text-surface-muted">
                    Env: {health.environment}
                  </span>
                ) : null}
              </div>
              <div className="mt-4 flex flex-wrap gap-2">
                <StatusPill ok={health.checks.api.ok} label="API" />
                <StatusPill ok={health.checks.database.ok} label="Database" />
                <StatusPill
                  ok={redisConfigured ? redisOk : null}
                  label={
                    redisConfigured
                      ? redisOk
                        ? "Redis"
                        : "Redis down"
                      : "Redis not set"
                  }
                />
                <StatusPill
                  ok={health.checks.storage.mode !== "ephemeral"}
                  label={`Storage: ${health.checks.storage.mode}`}
                />
                <StatusPill
                  ok={pushReady}
                  label={pushReady ? "FCM ready" : "FCM off"}
                />
              </div>
              {health.checks.database.error ? (
                <p className="mt-3 text-sm text-red-300">
                  DB error: {health.checks.database.error}
                </p>
              ) : null}
            </section>

            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <StatCard
                label="Users"
                value={formatNumber(health.counts.users)}
                sub={`${formatNumber(health.counts.active_users)} active`}
              />
              <StatCard
                label="Listings"
                value={formatNumber(health.counts.listings)}
                sub={`${formatNumber(health.counts.active_listings)} active`}
              />
              <StatCard
                label="Pending reports"
                value={formatNumber(health.counts.pending_reports)}
              />
              <StatCard
                label="Pending dealers"
                value={formatNumber(health.counts.pending_dealers)}
              />
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <StatCard
                label="Messages"
                value={formatNumber(health.counts.messages)}
              />
              <StatCard
                label="Notifications"
                value={formatNumber(health.counts.notifications)}
              />
            </div>

            <section className="rounded-xl border border-surface-border bg-surface-card p-5">
              <h2 className="mb-3 text-lg font-medium">Push (FCM)</h2>
              <dl className="grid gap-3 text-sm sm:grid-cols-2">
                {Object.entries(health.checks.push || {}).map(([key, value]) => (
                  <div key={key}>
                    <dt className="text-xs text-surface-muted">{key}</dt>
                    <dd className="mt-1 break-all">
                      {value === null || value === undefined
                        ? "—"
                        : typeof value === "object"
                          ? JSON.stringify(value)
                          : String(value)}
                    </dd>
                  </div>
                ))}
              </dl>
            </section>
          </div>
        );
      }}
    </AsyncPageBody>
  );
}
