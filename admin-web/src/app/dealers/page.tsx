"use client";

import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { approveDealer, fetchPendingDealers, rejectDealer } from "@/lib/api";
import { displayName, formatDate } from "@/lib/format";
import type { User } from "@/lib/types";

export default function DealersPage() {
  const [busyId, setBusyId] = useState<string | null>(null);
  const { data, error, loading, reload } = useAsyncData(fetchPendingDealers, []);

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

  return (
    <AsyncPageBody
      title="Dealer approvals"
      description="Review pending dealer applications"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(result) => (
        <DataTable empty={result.dealers.length === 0}>
          <thead>
            <tr>
              <Th>Applicant</Th>
              <Th>Dealership</Th>
              <Th>Contact</Th>
              <Th>Applied</Th>
              <Th>Actions</Th>
            </tr>
          </thead>
          <tbody>
            {result.dealers.map((d) => (
              <tr key={d.id}>
                <Td>
                  <p className="font-medium">{displayName(d)}</p>
                  <p className="text-xs text-surface-muted">{d.username}</p>
                </Td>
                <Td>{d.dealership_name || "—"}</Td>
                <Td className="text-surface-muted">
                  <p>{d.email || "—"}</p>
                  <p className="text-xs">{d.phone_number || ""}</p>
                </Td>
                <Td className="text-surface-muted">{formatDate(d.created_at)}</Td>
                <Td>
                  <div className="flex flex-wrap gap-2">
                    <button
                      type="button"
                      disabled={busyId === d.id}
                      onClick={() => handleApprove(d)}
                      className="rounded-lg bg-emerald-700 px-3 py-1.5 text-xs font-medium hover:bg-emerald-600 disabled:opacity-50"
                    >
                      Approve
                    </button>
                    <button
                      type="button"
                      disabled={busyId === d.id}
                      onClick={() => handleReject(d)}
                      className="rounded-lg border border-surface-border px-3 py-1.5 text-xs hover:bg-white/5 disabled:opacity-50"
                    >
                      Reject
                    </button>
                  </div>
                </Td>
              </tr>
            ))}
          </tbody>
        </DataTable>
      )}
    </AsyncPageBody>
  );
}
