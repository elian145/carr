"use client";

import Link from "next/link";
import { Suspense, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { refreshNavBadges } from "@/components/NavBadges";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import { fetchReports, updateReport } from "@/lib/api";
import { listingPublicUrl } from "@/lib/export";
import { formatDate, listingTitle } from "@/lib/format";
import { buildUrlQuery, paramPage, paramString } from "@/lib/urlParams";
import type { AdminReport } from "@/lib/types";

const STATUSES = ["pending", "reviewed", "resolved", "dismissed", "all"] as const;
const TYPES = ["all", "user", "listing"] as const;

function ReportsPageInner() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const toast = useToast();
  const { confirm } = useConfirm();

  const page = paramPage(searchParams);
  const status = paramString(searchParams, "status", "pending");
  const type = paramString(searchParams, "type", "all");

  const [busyId, setBusyId] = useState<string | null>(null);
  const [notesFor, setNotesFor] = useState<AdminReport | null>(null);
  const [adminNotes, setAdminNotes] = useState("");

  function replaceFilters(
    patch: {
      status?: string;
      type?: string;
      page?: number;
    },
    resetPage = true,
  ) {
    const nextStatus = patch.status ?? status;
    const nextType = patch.type ?? type;
    const nextPage = resetPage ? 1 : (patch.page ?? page);
    router.replace(
      `${pathname}${buildUrlQuery(
        {
          status: nextStatus === "pending" ? undefined : nextStatus,
          type: nextType === "all" ? undefined : nextType,
          page: nextPage > 1 ? nextPage : undefined,
        },
        { page: 1 },
      )}`,
    );
  }

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchReports({
        page,
        per_page: 20,
        status,
        type,
      }),
    [page, status, type],
  );

  async function handleStatus(
    report: AdminReport,
    newStatus: string,
    notes?: string,
  ) {
    if (newStatus === "dismissed") {
      const ok = await confirm({
        title: "Dismiss report?",
        description: "This marks the report as dismissed without further action.",
        confirmLabel: "Dismiss",
        tone: "warning",
      });
      if (!ok) return;
    }

    const key = `${report.type}-${report.id}`;
    setBusyId(key);
    try {
      await updateReport(report.type, report.id, newStatus, notes);
      setNotesFor(null);
      setAdminNotes("");
      toast.success(
        newStatus === "resolved" ? "Report resolved" : "Report updated",
      );
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Update failed");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <AsyncPageBody
      title="Reports"
      description="Moderate user and listing reports"
      count={data?.pagination.total}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <div className="flex flex-wrap gap-2">
          <FilterSelect
            label="Type"
            value={type}
            onChange={(v) => replaceFilters({ type: v })}
            options={TYPES.map((t) => ({
              value: t,
              label:
                t === "all"
                  ? "All types"
                  : t.charAt(0).toUpperCase() + t.slice(1),
            }))}
          />
          <FilterSelect
            label="Status"
            value={status}
            onChange={(v) => replaceFilters({ status: v })}
            options={STATUSES.map((s) => ({
              value: s,
              label: s.charAt(0).toUpperCase() + s.slice(1),
            }))}
          />
        </div>
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

          <DataTable
            empty={result.reports.length === 0}
            emptyTitle={
              status === "pending"
                ? "No pending reports"
                : "No reports match these filters"
            }
            emptyDescription={
              status === "pending"
                ? "The moderation queue is clear. Great work."
                : "Try another status or type filter."
            }
          >
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
                    : listingTitle(r.listing || {}) ||
                      r.listing?.id ||
                      "Listing report";

                return (
                  <tr key={key}>
                    <Td className="capitalize">{r.type}</Td>
                    <Td>
                      <p className="font-medium">{subject}</p>
                      {r.details ? (
                        <p className="mt-1 line-clamp-2 text-xs text-surface-muted">
                          {r.details}
                        </p>
                      ) : null}
                      {r.admin_notes ? (
                        <p className="mt-1 text-xs text-brand-300/80">
                          Note: {r.admin_notes}
                        </p>
                      ) : null}
                      {r.type === "listing" && r.listing?.id ? (
                        <div className="mt-1 flex flex-wrap gap-2">
                          <Link
                            href={`/listings/${r.listing.id}`}
                            className="text-xs text-brand-400 hover:underline"
                          >
                            Admin view →
                          </Link>
                          <a
                            href={listingPublicUrl(r.listing.id)}
                            target="_blank"
                            rel="noreferrer"
                            className="text-xs text-brand-400 hover:underline"
                          >
                            Public ↗
                          </a>
                        </div>
                      ) : null}
                      {r.type === "user" && r.reported_user?.id ? (
                        <Link
                          href={`/users/${r.reported_user.id}`}
                          className="mt-1 inline-block text-xs text-brand-400 hover:underline"
                        >
                          View user →
                        </Link>
                      ) : null}
                    </Td>
                    <Td className="text-surface-muted">{r.reason || "—"}</Td>
                    <Td>
                      <span className="inline-flex rounded-full bg-brand-900/30 px-2 py-0.5 text-xs text-brand-200">
                        {r.status}
                      </span>
                    </Td>
                    <Td className="text-surface-muted">
                      {formatDate(r.created_at)}
                    </Td>
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
                            onClick={() => handleStatus(r, "reviewed")}
                            className="rounded bg-sky-900/40 px-2 py-1 text-xs hover:bg-sky-900/60 disabled:opacity-50"
                          >
                            Mark reviewed
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
          <Pagination
            pagination={result.pagination}
            onPageChange={(p) =>
              replaceFilters({ page: p > 1 ? p : undefined }, false)
            }
          />
        </>
      )}
    </AsyncPageBody>
  );
}

export default function ReportsPage() {
  return (
    <Suspense fallback={<p className="text-surface-muted">Loading reports…</p>}>
      <ReportsPageInner />
    </Suspense>
  );
}
