"use client";

import Link from "next/link";
import { Fragment, useEffect, useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { refreshNavBadges } from "@/components/NavBadges";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import {
  approveDealer,
  fetchDealerVerificationPhoto,
  fetchDealers,
  rejectDealer,
  reviewDealer,
  setDealerFeatured,
} from "@/lib/api";
import { displayName, formatDate, formatNumber } from "@/lib/format";
import type { User } from "@/lib/types";

type DealerTab =
  | "submitted"
  | "under_review"
  | "needs_changes"
  | "all"
  | "approved"
  | "rejected";

const EMPTY_COUNTS: Record<DealerTab, number> = {
  submitted: 0,
  under_review: 0,
  needs_changes: 0,
  all: 0,
  approved: 0,
  rejected: 0,
};

export default function DealersPage() {
  const toast = useToast();
  const { confirm, prompt } = useConfirm();
  const [tab, setTab] = useState<DealerTab>("submitted");
  const [page, setPage] = useState(1);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [verificationPhotoUrl, setVerificationPhotoUrl] = useState<string | null>(null);

  useEffect(
    () => () => {
      if (verificationPhotoUrl) URL.revokeObjectURL(verificationPhotoUrl);
    },
    [verificationPhotoUrl],
  );

  const { data, error, loading, reload } = useAsyncData(
    () => fetchDealers(tab === "all" ? "all" : tab, { page, per_page: 20 }),
    [tab, page],
  );

  const tabCounts = data?.counts
    ? {
        submitted: data.counts.submitted,
        under_review: data.counts.under_review,
        needs_changes: data.counts.needs_changes,
        all: data.counts.all,
        approved: data.counts.approved,
        rejected: data.counts.rejected,
      }
    : EMPTY_COUNTS;

  async function viewVerificationPhoto(dealer: User) {
    setBusyId(dealer.id);
    try {
      const blob = await fetchDealerVerificationPhoto(dealer.id);
      if (verificationPhotoUrl) URL.revokeObjectURL(verificationPhotoUrl);
      setVerificationPhotoUrl(URL.createObjectURL(blob));
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Unable to load verification photo");
    } finally {
      setBusyId(null);
    }
  }

  async function handleApprove(dealer: User) {
    const ok = await confirm({
      title: "Approve dealer?",
      description: `${displayName(dealer)} will become an approved dealer account.`,
      confirmLabel: "Approve",
      tone: "brand",
    });
    if (!ok) return;

    setBusyId(dealer.id);
    try {
      await approveDealer(dealer.id);
      toast.success("Dealer approved");
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Approve failed");
    } finally {
      setBusyId(null);
    }
  }

  async function handleReject(dealer: User) {
    const reason = await prompt({
      title: "Reject dealer application?",
      description: `Reject ${displayName(dealer)}. A reason will be shown to the applicant.`,
      confirmLabel: "Reject",
      tone: "danger",
      inputLabel: "Reason",
      placeholder: "e.g. incomplete documents",
    });
    if (reason === null || !reason.trim()) return;

    setBusyId(dealer.id);
    try {
      await rejectDealer(dealer.id, reason.trim());
      toast.success("Dealer rejected");
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Reject failed");
    } finally {
      setBusyId(null);
    }
  }

  async function handleStartReview(dealer: User) {
    setBusyId(dealer.id);
    try {
      await reviewDealer(dealer.id, "under_review");
      toast.success("Review started");
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Update failed");
    } finally {
      setBusyId(null);
    }
  }

  async function handleNeedsChanges(dealer: User) {
    const reason = await prompt({
      title: "Request application changes",
      description: `Tell ${displayName(dealer)} exactly what must be corrected.`,
      confirmLabel: "Request changes",
      tone: "brand",
      inputLabel: "Required changes",
      placeholder: "e.g. upload a valid business registration document",
    });
    if (reason === null || !reason.trim()) return;
    setBusyId(dealer.id);
    try {
      await reviewDealer(dealer.id, "needs_changes", reason.trim());
      toast.success("Changes requested");
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Update failed");
    } finally {
      setBusyId(null);
    }
  }

  async function handleFeature(dealer: User) {
    const next = !dealer.is_featured_dealer;
    const ok = await confirm({
      title: next ? "Feature this dealer?" : "Remove featured?",
      description: next
        ? `${displayName(dealer)} will be marked as a featured dealer.`
        : `${displayName(dealer)} will no longer be featured.`,
      confirmLabel: next ? "Feature" : "Unfeature",
      tone: "brand",
    });
    if (!ok) return;
    setBusyId(dealer.id);
    try {
      await setDealerFeatured(dealer.id, next);
      toast.success(next ? "Dealer featured" : "Feature removed");
      reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Update failed");
    } finally {
      setBusyId(null);
    }
  }

  const tabs: { id: DealerTab; label: string }[] = [
    { id: "submitted", label: "Submitted" },
    { id: "under_review", label: "Under review" },
    { id: "needs_changes", label: "Needs changes" },
    { id: "all", label: "All dealers" },
    { id: "approved", label: "Approved" },
    { id: "rejected", label: "Rejected" },
  ];

  return (
    <>
      <AsyncPageBody
      title="Dealers"
      description="Dealer applications and accounts"
      count={data?.pagination?.total ?? data?.dealers?.length}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <div className="flex max-w-full flex-wrap gap-1 rounded-lg border border-surface-border p-1">
          {tabs.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => {
                setTab(t.id);
                setPage(1);
              }}
              className={`rounded-md px-3 py-1.5 text-sm ${
                tab === t.id
                  ? "bg-brand-600 text-white"
                  : "text-surface-muted hover:bg-white/5"
              }`}
            >
              {t.label} ({formatNumber(tabCounts[t.id])})
            </button>
          ))}
        </div>
      }
    >
      {(result) => (
        <>
          <DataTable
            empty={result.dealers.length === 0}
            emptyTitle={
              tab === "submitted"
                ? "No submitted dealer applications"
                : "No dealers in this view"
            }
            emptyDescription={
              tab === "submitted"
                ? "New dealer applications will show up here for review."
                : "Try another tab or check back later."
            }
          >
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
              {result.dealers.map((d) => {
                const open = expandedId === d.id;
                return (
                  <Fragment key={d.id}>
                    <tr className="hover:bg-white/[0.02]">
                      <Td>
                        <Link
                          href={`/users/${d.id}`}
                          className="font-medium text-brand-300 hover:underline"
                        >
                          {displayName(d)}
                        </Link>
                        <p className="text-xs text-surface-muted">{d.username}</p>
                      </Td>
                      <Td>
                        <p>{d.dealership_name || "—"}</p>
                        {d.dealership_location ? (
                          <p className="text-xs text-surface-muted">
                            {d.dealership_location}
                          </p>
                        ) : null}
                        <button
                          type="button"
                          onClick={() =>
                            setExpandedId(open ? null : d.id)
                          }
                          className="mt-1 text-xs text-brand-400 hover:underline"
                        >
                          {open ? "Hide details" : "Show details"}
                        </button>
                      </Td>
                      <Td className="text-surface-muted">
                        <p>{d.email || "—"}</p>
                        <p className="text-xs">
                          {d.dealership_phone || d.phone_number || ""}
                        </p>
                      </Td>
                      <Td>{d.dealer_status || "—"}</Td>
                      <Td className="text-surface-muted">
                        {formatDate(
                          d.dealer_application?.submitted_at ?? d.created_at,
                        )}
                      </Td>
                      <Td>
                        {d.dealer_status === "submitted" ||
                        d.dealer_status === "under_review" ? (
                          <div className="flex flex-wrap gap-2">
                            {d.dealer_status === "submitted" ? (
                              <button
                                type="button"
                                disabled={busyId === d.id}
                                onClick={() => handleStartReview(d)}
                                className="rounded-lg border border-brand-500 px-3 py-1.5 text-xs text-brand-300 disabled:opacity-50"
                              >
                                Start review
                              </button>
                            ) : null}
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
                              onClick={() => handleNeedsChanges(d)}
                              className="rounded-lg border border-amber-600 px-3 py-1.5 text-xs text-amber-300 disabled:opacity-50"
                            >
                              Request changes
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
                          <div className="flex flex-wrap items-center gap-2">
                            {d.dealer_status === "approved" ? (
                              <button
                                type="button"
                                disabled={busyId === d.id}
                                onClick={() => handleFeature(d)}
                                className="rounded-lg border border-surface-border px-3 py-1.5 text-xs disabled:opacity-50"
                              >
                                {d.is_featured_dealer ? "Unfeature" : "Feature"}
                              </button>
                            ) : null}
                            {d.is_featured_dealer ? (
                              <span className="text-xs text-brand-300">Featured</span>
                            ) : null}
                            <Link
                              href={`/users/${d.id}`}
                              className="text-xs text-brand-400 hover:underline"
                            >
                              Profile →
                            </Link>
                          </div>
                        )}
                      </Td>
                    </tr>
                    {open ? (
                      <tr>
                        <Td colSpan={6} className="bg-black/20">
                          <div className="grid gap-3 text-sm sm:grid-cols-2">
                            <div>
                              <p className="text-xs text-surface-muted">Description</p>
                              <p className="mt-1 whitespace-pre-wrap text-surface-muted">
                                {d.dealer_application?.dealership_description ||
                                  d.dealership_description ||
                                  "No description provided."}
                              </p>
                              {d.dealer_application?.review_reason ? (
                                <>
                                  <p className="mt-3 text-xs text-surface-muted">
                                    Latest review reason
                                  </p>
                                  <p className="mt-1 whitespace-pre-wrap text-amber-300">
                                    {d.dealer_application.review_reason}
                                  </p>
                                </>
                              ) : null}
                            </div>
                            <div>
                              <p className="text-xs text-surface-muted">Phones</p>
                              <p className="mt-1">
                                {(d.dealership_phones && d.dealership_phones.length
                                  ? d.dealership_phones.join(", ")
                                  : d.dealership_phone) || "—"}
                              </p>
                              <p className="mt-3 text-xs text-surface-muted">Opening hours</p>
                              <p className="mt-1 text-surface-muted">
                                {typeof d.dealership_opening_hours === "string"
                                  ? d.dealership_opening_hours
                                  : d.dealership_opening_hours
                                    ? JSON.stringify(d.dealership_opening_hours)
                                    : "—"}
                              </p>
                              <p className="mt-3 text-xs text-surface-muted">
                                Private dealership verification
                              </p>
                              {d.dealer_application?.has_verification_photo ? (
                                <button
                                  type="button"
                                  disabled={busyId === d.id}
                                  onClick={() => viewVerificationPhoto(d)}
                                  className="mt-2 rounded-lg border border-brand-500/60 px-3 py-2 text-xs font-medium text-brand-300 hover:bg-brand-500/10 disabled:opacity-50"
                                >
                                  {busyId === d.id
                                    ? "Loading photo…"
                                    : "View dealership photo"}
                                </button>
                              ) : (
                                <p className="mt-1 text-amber-300">Not provided</p>
                              )}
                            </div>
                            {d.dealer_application?.decisions?.length ? (
                              <div className="sm:col-span-2">
                                <p className="text-xs text-surface-muted">Review history</p>
                                <div className="mt-2 space-y-2">
                                  {d.dealer_application.decisions.map((decision) => (
                                    <div
                                      key={decision.id}
                                      className="rounded-lg border border-surface-border p-2"
                                    >
                                      <span className="font-medium">
                                        {decision.decision.replaceAll("_", " ")}
                                      </span>
                                      {decision.reviewer?.username
                                        ? ` by ${decision.reviewer.username}`
                                        : ""}
                                      {decision.reason ? ` — ${decision.reason}` : ""}
                                      <span className="ml-2 text-xs text-surface-muted">
                                        {formatDate(decision.created_at)}
                                      </span>
                                    </div>
                                  ))}
                                </div>
                              </div>
                            ) : null}
                          </div>
                        </Td>
                      </tr>
                    ) : null}
                  </Fragment>
                );
              })}
            </tbody>
          </DataTable>
          {result.pagination ? (
            <Pagination
              pagination={result.pagination}
              onPageChange={setPage}
            />
          ) : null}
        </>
      )}
      </AsyncPageBody>
      {verificationPhotoUrl ? (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Private dealership verification photo"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
          onClick={() => setVerificationPhotoUrl(null)}
        >
          <div
            className="max-h-[90vh] max-w-4xl overflow-hidden rounded-2xl border border-surface-border bg-surface-card p-3 shadow-2xl"
            onClick={(event) => event.stopPropagation()}
          >
            <div className="mb-3 flex items-center justify-between gap-4">
              <div>
                <p className="font-semibold">Private dealership verification</p>
                <p className="text-xs text-surface-muted">
                  For authorized dealer review only. Never displayed publicly.
                </p>
              </div>
              <button
                type="button"
                onClick={() => setVerificationPhotoUrl(null)}
                className="rounded-lg border border-surface-border px-3 py-1.5 text-sm"
              >
                Close
              </button>
            </div>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={verificationPhotoUrl}
              alt="Dealership verification"
              className="max-h-[75vh] w-full rounded-xl object-contain"
            />
          </div>
        </div>
      ) : null}
    </>
  );
}
