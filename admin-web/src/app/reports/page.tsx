"use client";

import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchReports, updateReport } from "@/lib/api";
import { listingPublicUrl } from "@/lib/export";
import { formatDate, listingTitle } from "@/lib/format";
import type { AdminReport } from "@/lib/types";

const STATUSES = ["pending", "reviewed", "resolved", "dismissed", "all"] as const;

export default function ReportsPage() {
  const [page, setPage] = useState(1);
  const [status, setStatus] = useState<string>("pending");
  const [busyId, setBusyId] = useState<string | null>(null);
  const [notesFor, setNotesFor] = useState<AdminReport | null>(null);
  const [adminNotes, setAdminNotes] = useState("");

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchReports({
        page,
        per_page: 20,
        status,
        type: "all",
      }),
    [page, status],
  );

  async function handleStatus(
    report: AdminReport,
    newStatus: string,
    notes?: string,
  ) {
    const key = `${report.type}-${report.id}`;
    setBusyId(key);
    try {
      await updateReport(report.type, report.id, newStatus, notes);
      setNotesFor(null);
      setAdminNotes("");
      reload();
    } catch (e) {
      alert(e instanceof Error ? e.message : "Update failed");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <AsyncPageBody
      title="Reports"
      description="Moderate user and listing reports"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <select
          value={status}
          onChange={(e) => {
            setStatus(e.target.value);
            setPage(1);
          }}
          className="rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm"
        >
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {s.charAt(0).toUpperCase() + s.slice(1)}
            </option>
          ))}
        </select>
      }
    >
      {(result) => (
        <>
          {notesFor ? (
            <div className="mb-6 rounded-xl border border-surface-border bg-surface-card p-4">
              <p className="text-sm font-medium">Admin notes (optional)</p>
              <p className="mt-1 text-xs text-surface-muted">
                Report #{notesFor.id} · {notesFor.type}
              </p>
              <textarea
                value={adminNotes}
                onChange={(e) => setAdminNotes(e.target.value)}
                rows={3}
                className="mt-3 w-full rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm"
                placeholder="Internal notes about this resolution…"
              />
              <div className="mt-3 flex gap-2">
                <button
                  type="button"
                  onClick={() => handleStatus(notesFor, "resolved", adminNotes)}
                  className="rounded-lg bg-emerald-700 px-4 py-2 text-sm hover:bg-emerald-600"
                >
                  Resolve with notes
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setNotesFor(null);
                    setAdminNotes("");
                  }}
                  className="rounded-lg border border-surface-border px-4 py-2 text-sm hover:bg-white/5"
                >
                  Cancel
                </button>
              </div>
            </div>
          ) : null}

          <DataTable empty={result.reports.length === 0}>
            <thead>
              <tr>
                <Th>Type</Th>
                <Th>Subject</Th>
                <Th>Reason</Th>
                <Th>Status</Th>
                <Th>Created</Th>
                <Th>Actions</Th>
              </tr>
            </thead>
            <tbody>
              {result.reports.map((r) => {
                const key = `${r.type}-${r.id}`;
                const subject =
                  r.type === "user"
                    ? r.reported_user?.username || "User report"
                    : listingTitle(r.listing || {}) || r.listing?.id || "Listing report";

                return (
                  <tr key={key}>
                    <Td className="capitalize">{r.type}</Td>
                    <Td>
                      <p className="font-medium">{subject}</p>
                      {r.details ? (
                        <p className="mt-1 text-xs text-surface-muted line-clamp-2">
                          {r.details}
                        </p>
                      ) : null}
                      {r.admin_notes ? (
                        <p className="mt-1 text-xs text-brand-300/80">
                          Note: {r.admin_notes}
                        </p>
                      ) : null}
                      {r.type === "listing" && r.listing?.id ? (
                        <a
                          href={listingPublicUrl(r.listing.id)}
                          target="_blank"
                          rel="noreferrer"
                          className="mt-1 inline-block text-xs text-brand-400 hover:underline"
                        >
                          View listing ↗
                        </a>
                      ) : null}
                    </Td>
                    <Td className="text-surface-muted">{r.reason || "—"}</Td>
                    <Td>
                      <span className="inline-flex rounded-full bg-brand-900/30 px-2 py-0.5 text-xs text-brand-200">
                        {r.status}
                      </span>
                    </Td>
                    <Td className="text-surface-muted">{formatDate(r.created_at)}</Td>
                    <Td>
                      {r.status === "pending" ? (
                        <div className="flex flex-wrap gap-1">
                          <button
                            type="button"
                            disabled={busyId === key}
                            onClick={() => handleStatus(r, "resolved")}
                            className="rounded bg-emerald-900/50 px-2 py-1 text-xs hover:bg-emerald-900/70 disabled:opacity-50"
                          >
                            Resolve
                          </button>
                          <button
                            type="button"
                            disabled={busyId === key}
                            onClick={() => {
                              setNotesFor(r);
                              setAdminNotes("");
                            }}
                            className="rounded bg-brand-900/50 px-2 py-1 text-xs hover:bg-brand-900/70 disabled:opacity-50"
                          >
                            Resolve + note
                          </button>
                          <button
                            type="button"
                            disabled={busyId === key}
                            onClick={() => handleStatus(r, "dismissed")}
                            className="rounded bg-surface-border px-2 py-1 text-xs hover:bg-white/10 disabled:opacity-50"
                          >
                            Dismiss
                          </button>
                        </div>
                      ) : (
                        <span className="text-xs text-surface-muted">—</span>
                      )}
                    </Td>
                  </tr>
                );
              })}
            </tbody>
          </DataTable>
          <Pagination pagination={result.pagination} onPageChange={setPage} />
        </>
      )}
    </AsyncPageBody>
  );
}
