"use client";

import Link from "next/link";
import { StatCard } from "@/components/StatCard";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { ActionBarChart } from "@/components/ActionBarChart";
import { QuickActionCard } from "@/components/QuickActionCard";
import { fetchDashboard } from "@/lib/api";
import { displayName, formatDate, formatNumber, listingTitle } from "@/lib/format";

export default function DashboardPage() {
  const { data, error, loading, reload } = useAsyncData(fetchDashboard, []);

  return (
    <AsyncPageBody
      title="Dashboard"
      description="Platform overview and recent activity"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(dashboard) => {
        const s = dashboard.stats;
        return (
          <div className="space-y-8">
            {(s.pending_reports ?? 0) > 0 || (s.pending_dealers ?? 0) > 0 ? (
              <section className="grid gap-4 sm:grid-cols-2">
                <QuickActionCard
                  title="Pending reports"
                  count={s.pending_reports ?? 0}
                  description={`${s.pending_user_reports ?? 0} user · ${s.pending_listing_reports ?? 0} listing`}
                  href="/reports"
                  tone={(s.pending_reports ?? 0) > 0 ? "danger" : "brand"}
                />
                <QuickActionCard
                  title="Dealer applications"
                  count={s.pending_dealers ?? 0}
                  description="Awaiting approval"
                  href="/dealers"
                  tone={(s.pending_dealers ?? 0) > 0 ? "warning" : "brand"}
                />
              </section>
            ) : null}

            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <StatCard
                label="Users"
                value={formatNumber(s.total_users)}
                sub={`${formatNumber(s.active_users)} active · ${formatNumber(s.inactive_users ?? 0)} inactive`}
              />
              <StatCard
                label="Listings"
                value={formatNumber(s.total_cars)}
                sub={`${formatNumber(s.active_cars)} active · ${formatNumber(s.featured_cars ?? 0)} featured`}
              />
              <StatCard
                label="Dealers"
                value={formatNumber(s.dealer_accounts ?? 0)}
                sub={`${formatNumber(s.pending_dealers ?? 0)} pending approval`}
              />
              <StatCard
                label="Messages"
                value={formatNumber(s.total_messages)}
                sub={`${formatNumber(s.total_notifications)} notifications`}
              />
            </div>

            <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <StatCard label="Listing views" value={formatNumber(s.total_listing_views ?? 0)} />
              <StatCard label="Listing messages" value={formatNumber(s.total_listing_messages ?? 0)} />
              <StatCard label="Listing calls" value={formatNumber(s.total_listing_calls ?? 0)} />
              <StatCard label="Favorites" value={formatNumber(s.total_listing_favorites ?? 0)} />
            </div>

            <section className="rounded-xl border border-surface-border bg-surface-card p-5">
              <h2 className="mb-4 text-lg font-medium">Activity breakdown</h2>
              <ActionBarChart items={dashboard.user_actions} />
            </section>

            <div className="grid gap-6 xl:grid-cols-3">
              <section>
                <div className="mb-3 flex items-center justify-between">
                  <h2 className="text-lg font-medium">Recent users</h2>
                  <Link href="/users" className="text-sm text-brand-400 hover:underline">
                    View all
                  </Link>
                </div>
                <DataTable empty={dashboard.recent_activity.users.length === 0}>
                  <thead>
                    <tr>
                      <Th>User</Th>
                      <Th>Joined</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {dashboard.recent_activity.users.map((u) => (
                      <tr key={u.id} className="hover:bg-white/[0.02]">
                        <Td>
                          <Link
                            href={`/users/${u.id}`}
                            className="font-medium text-brand-300 hover:underline"
                          >
                            {displayName(u)}
                          </Link>
                          <p className="text-xs text-surface-muted">{u.username}</p>
                        </Td>
                        <Td className="text-surface-muted">{formatDate(u.created_at)}</Td>
                      </tr>
                    ))}
                  </tbody>
                </DataTable>
              </section>

              <section>
                <div className="mb-3 flex items-center justify-between">
                  <h2 className="text-lg font-medium">Recent listings</h2>
                  <Link href="/listings" className="text-sm text-brand-400 hover:underline">
                    View all
                  </Link>
                </div>
                <DataTable empty={dashboard.recent_activity.cars.length === 0}>
                  <thead>
                    <tr>
                      <Th>Listing</Th>
                      <Th>Created</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {dashboard.recent_activity.cars.map((c) => (
                      <tr key={c.id} className="hover:bg-white/[0.02]">
                        <Td>
                          <p className="font-medium">{listingTitle(c)}</p>
                          <p className="text-xs text-surface-muted">{c.location}</p>
                        </Td>
                        <Td className="text-surface-muted">{formatDate(c.created_at)}</Td>
                      </tr>
                    ))}
                  </tbody>
                </DataTable>
              </section>

              <section>
                <div className="mb-3 flex items-center justify-between">
                  <h2 className="text-lg font-medium">Recent messages</h2>
                  <Link href="/messages" className="text-sm text-brand-400 hover:underline">
                    View all
                  </Link>
                </div>
                <DataTable empty={dashboard.recent_activity.messages.length === 0}>
                  <thead>
                    <tr>
                      <Th>Preview</Th>
                      <Th>Sent</Th>
                    </tr>
                  </thead>
                  <tbody>
                    {dashboard.recent_activity.messages.map((m) => (
                      <tr key={m.id}>
                        <Td className="max-w-xs truncate">
                          {(m.content || "").slice(0, 80) || "—"}
                        </Td>
                        <Td className="text-surface-muted">{formatDate(m.created_at)}</Td>
                      </tr>
                    ))}
                  </tbody>
                </DataTable>
              </section>
            </div>
          </div>
        );
      }}
    </AsyncPageBody>
  );
}
