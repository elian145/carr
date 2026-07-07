"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchUserDetail, updateUserStatus } from "@/lib/api";
import { listingPublicUrl } from "@/lib/export";
import {
  displayName,
  formatDate,
  formatNumber,
  formatPrice,
  listingTitle,
} from "@/lib/format";

export default function UserDetailPage() {
  const params = useParams();
  const userId = String(params.id || "");
  const [busy, setBusy] = useState(false);

  const { data, error, loading, reload } = useAsyncData(
    () => fetchUserDetail(userId),
    [userId],
  );

  async function toggleActive(current: boolean) {
    setBusy(true);
    try {
      await updateUserStatus(userId, !current);
      reload();
    } catch (e) {
      alert(e instanceof Error ? e.message : "Failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <AsyncPageBody
      title="User details"
      description={userId}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <Link href="/users" className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5">
          ← Back
        </Link>
      }
    >
      {(detail) => {
        const u = detail.user;
        return (
          <div className="space-y-8">
            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <h2 className="text-xl font-semibold">{displayName(u)}</h2>
                  <p className="mt-1 text-sm text-surface-muted">@{u.username}</p>
                </div>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => toggleActive(!!u.is_active)}
                  className="rounded-lg bg-brand-700 px-4 py-2 text-sm hover:bg-brand-600 disabled:opacity-50"
                >
                  {u.is_active ? "Deactivate account" : "Activate account"}
                </button>
              </div>
              <dl className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                <div>
                  <dt className="text-xs text-surface-muted">Email</dt>
                  <dd className="mt-1 text-sm">{u.email || "—"}</dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Phone</dt>
                  <dd className="mt-1 text-sm">{u.phone_number || "—"}</dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Account</dt>
                  <dd className="mt-1 text-sm capitalize">
                    {u.account_type || "user"}
                    {u.dealer_status && u.dealer_status !== "none" ? ` · ${u.dealer_status}` : ""}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Status</dt>
                  <dd className="mt-1 text-sm">
                    {u.is_active ? "Active" : "Inactive"}
                    {u.is_admin ? " · Admin" : ""}
                    {u.is_verified ? " · Verified" : ""}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Joined</dt>
                  <dd className="mt-1 text-sm">{formatDate(u.created_at)}</dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Last login</dt>
                  <dd className="mt-1 text-sm">{formatDate(u.last_login)}</dd>
                </div>
              </dl>
            </section>

            <section>
              <h3 className="mb-3 text-lg font-medium">Listings ({detail.cars.length})</h3>
              <DataTable empty={detail.cars.length === 0}>
                <thead>
                  <tr>
                    <Th>Listing</Th>
                    <Th>Price</Th>
                    <Th>Status</Th>
                    <Th>Views</Th>
                    <Th></Th>
                  </tr>
                </thead>
                <tbody>
                  {detail.cars.map((c) => (
                    <tr key={c.id}>
                      <Td>
                        <Link href={`/listings/${c.id}`} className="font-medium text-brand-300 hover:underline">
                          {listingTitle(c)}
                        </Link>
                      </Td>
                      <Td>{formatPrice(c.price)}</Td>
                      <Td>{c.is_active ? "Active" : "Inactive"}</Td>
                      <Td>{formatNumber(c.views_count)}</Td>
                      <Td>
                        <a href={listingPublicUrl(c.id)} target="_blank" rel="noreferrer" className="text-xs text-brand-400 hover:underline">
                          Public ↗
                        </a>
                      </Td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>
            </section>

            <section>
              <h3 className="mb-3 text-lg font-medium">Recent actions</h3>
              <DataTable empty={detail.recent_actions.length === 0}>
                <thead>
                  <tr>
                    <Th>Action</Th>
                    <Th>Target</Th>
                    <Th>When</Th>
                  </tr>
                </thead>
                <tbody>
                  {detail.recent_actions.map((a) => (
                    <tr key={a.id}>
                      <Td className="font-medium">{a.action_type}</Td>
                      <Td className="text-surface-muted">
                        {a.target_type ? `${a.target_type}: ` : ""}
                        {a.target_id || "—"}
                      </Td>
                      <Td className="text-surface-muted">{formatDate(a.created_at)}</Td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>
            </section>
          </div>
        );
      }}
    </AsyncPageBody>
  );
}
