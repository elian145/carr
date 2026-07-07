"use client";

import Link from "next/link";
import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { approveDealer, fetchDealers, fetchPendingDealers, rejectDealer } from "@/lib/api";
import { displayName, formatDate } from "@/lib/format";
import type { User } from "@/lib/types";

export default function DealersPage() {
  const [tab, setTab] = useState<"pending" | "all" | "approved" | "rejected">("pending");
  const [busyId, setBusyId] = useState<string | null>(null);

  const { data, error, loading, reload } = useAsyncData(async () => {
    if (tab === "pending") {
      return { dealers: (await fetchPendingDealers()).dealers };
    }
    const status = tab === "all" ? "all" : tab;
    return fetchDealers(status);
  }, [tab]);

  async function handleApprove(dealer: User) {
    setBusyId(dealer.id);
    try {
      await approveDealer(dealer.id);
      reload();
    } catch (e) {
      alert(e instanceof Error ? e.message : "Approve failed");
    } finally {
      setBusyId(null);
    }
  }

  async function handleReject(dealer: User) {
    const reason = window.prompt("Rejection reason (optional):") ?? "";
    setBusyId(dealer.id);
    try {
      await rejectDealer(dealer.id, reason.trim() || undefined);
      reload();
    } catch (e) {
      alert(e instanceof Error ? e.message : "Reject failed");
    } finally {
      setBusyId(null);
    }
  }

  const tabs = [
    { id: "pending" as const, label: "Pending" },
    { id: "all" as const, label: "All dealers" },
    { id: "approved" as const, label: "Approved" },
    { id: "rejected" as const, label: "Rejected" },
  ];

  return (
    <AsyncPageBody
      title="Dealers"
      description="Dealer applications and accounts"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <div className="flex gap-1 rounded-lg border border-surface-border p-1">
          {tabs.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => setTab(t.id)}
              className={`rounded-md px-3 py-1.5 text-sm ${
                tab === t.id ? "bg-brand-600 text-white" : "text-surface-muted hover:bg-white/5"
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>
      }
    >
      {(result) => (
        <DataTable empty={result.dealers.length === 0}>
          <thead>
            <tr>
              <Th>Applicant</Th>
              <Th>Dealership</Th>
              <Th>Contact</Th>
              <Th>Status</Th>
              <Th>Applied</Th>
              <Th>Actions</Th>
            </tr>
          </thead>
          <tbody>
            {result.dealers.map((d) => (
              <tr key={d.id}>
                <Td>
                  <Link href={`/users/${d.id}`} className="font-medium text-brand-300 hover:underline">
                    {displayName(d)}
                  </Link>
                  <p className="text-xs text-surface-muted">{d.username}</p>
                </Td>
                <Td>{d.dealership_name || "—"}</Td>
                <Td className="text-surface-muted">
                  <p>{d.email || "—"}</p>
                  <p className="text-xs">{d.phone_number || ""}</p>
                </Td>
                <Td>{d.dealer_status || "—"}</Td>
                <Td className="text-surface-muted">{formatDate(d.created_at)}</Td>
                <Td>
                  {d.dealer_status === "pending" ? (
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        disabled={busyId === d.id}
                        onClick={() => handleApprove(d)}
                        className="rounded-lg bg-emerald-700 px-3 py-1.5 text-xs disabled:opacity-50"
                      >
                        Approve
                      </button>
                      <button
                        type="button"
                        disabled={busyId === d.id}
                        onClick={() => handleReject(d)}
                        className="rounded-lg border border-surface-border px-3 py-1.5 text-xs disabled:opacity-50"
                      >
                        Reject
                      </button>
                    </div>
                  ) : (
                    <Link href={`/users/${d.id}`} className="text-xs text-brand-400 hover:underline">
                      Profile →
                    </Link>
                  )}
                </Td>
              </tr>
            ))}
          </tbody>
        </DataTable>
      )}
    </AsyncPageBody>
  );
}
