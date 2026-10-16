"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useState } from "react";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { refreshNavBadges } from "@/components/NavBadges";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import { useAuth } from "@/context/AuthContext";
import {
  approveListingRevision,
  fetchListingRevisionDetail,
  rejectListingRevision,
} from "@/lib/api";
import { dash, formatDate, listingTitle, mediaUrl } from "@/lib/format";
import { hasPermission } from "@/lib/permissions";
import type { CarImage, CarListing } from "@/lib/types";

function sortedListingImages(car: CarListing | undefined): CarImage[] {
  const list = (car?.images || []).filter(
    (img) => (img.kind || "listing") === "listing",
  );
  return [...list].sort((a, b) => {
    if (a.is_primary && !b.is_primary) return -1;
    if (!a.is_primary && b.is_primary) return 1;
    return (a.order ?? 0) - (b.order ?? 0);
  });
}

function Gallery({ title, images }: { title: string; images: CarImage[] }) {
  return (
    <div>
      <h4 className="mb-2 text-sm font-medium text-surface-muted">
        {title} ({images.length})
      </h4>
      <div className="flex flex-wrap gap-2">
        {images.map((img, i) => (
          <a
            key={img.id ?? `${img.image_url}-${i}`}
            href={mediaUrl(img.image_url)}
            target="_blank"
            rel="noreferrer"
            className="relative block overflow-hidden rounded-lg border border-surface-border"
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={mediaUrl(img.image_url)}
              alt=""
              className="h-24 w-36 object-cover"
            />
            {img.is_primary ? (
              <span className="absolute left-1 top-1 rounded bg-black/70 px-1.5 py-0.5 text-[10px] text-white">
                Cover
              </span>
            ) : null}
          </a>
        ))}
        {images.length === 0 ? (
          <p className="text-sm text-surface-muted">No photos</p>
        ) : null}
      </div>
    </div>
  );
}

function fieldValue(car: CarListing | undefined, field: string): string {
  const v = (car as unknown as Record<string, unknown> | undefined)?.[field];
  if (v == null) return "—";
  if (Array.isArray(v)) return v.join(", ") || "—";
  return String(v);
}

export default function ListingEditReviewPage() {
  const params = useParams();
  const router = useRouter();
  const revisionId = String(params.id || "");
  const toast = useToast();
  const { confirm } = useConfirm();
  const { user } = useAuth();
  const canWrite = hasPermission(user, "listings.write");
  const [busy, setBusy] = useState(false);
  const [reason, setReason] = useState("");

  const { data, error, loading, reload } = useAsyncData(
    () => fetchListingRevisionDetail(revisionId),
    [revisionId],
  );

  async function approve(token: string) {
    const ok = await confirm({
      title: "Approve and publish these changes?",
      description:
        "The listing keeps its ID. The proposed details, photos and cover replace the approved version immediately.",
      confirmLabel: "Approve & publish",
      tone: "brand",
    });
    if (!ok) return;
    setBusy(true);
    try {
      await approveListingRevision(revisionId, token);
      toast.success("Changes published");
      refreshNavBadges();
      router.push("/listing-edits");
    } catch (e) {
      // 409 stale_revision: the seller changed the edit after it was loaded.
      toast.error(e instanceof Error ? e.message : "Approval failed");
      reload();
    } finally {
      setBusy(false);
    }
  }

  async function reject(token: string) {
    if (!reason.trim()) {
      toast.error("Enter a reason - the seller will see it");
      return;
    }
    const ok = await confirm({
      title: "Reject these changes?",
      description:
        "The approved listing stays live and unchanged. The seller is told why and can resubmit.",
      confirmLabel: "Reject changes",
      tone: "danger",
    });
    if (!ok) return;
    setBusy(true);
    try {
      await rejectListingRevision(revisionId, token, reason.trim());
      toast.success("Changes rejected");
      router.push("/listing-edits");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Rejection failed");
      reload();
    } finally {
      setBusy(false);
    }
  }

  return (
    <AsyncPageBody
      title="Review listing edit"
      description={revisionId}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <Link
          href="/listing-edits"
          className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5"
        >
          ← Back
        </Link>
      }
    >
      {({ revision, current }) => {
        const proposed = revision.car;
        const textFields = revision.changed_fields.filter(
          (f) => f !== "images" && f !== "videos",
        );
        const mediaBlocked = revision.media ? !revision.media.ready : false;
        const mediaFailed = (revision.media?.failed ?? 0) > 0;
        // Approval needs every declared photo/video to have arrived.
        const approveBlocked = mediaBlocked || mediaFailed;
        return (
          <div className="space-y-8">
            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <h2 className="text-xl font-semibold">{listingTitle(current)}</h2>
              <p className="mt-1 text-sm text-surface-muted">
                Listing {current.id} ·{" "}
                <Link
                  href={`/listings/${current.id}`}
                  className="text-brand-300 hover:underline"
                >
                  open listing
                </Link>{" "}
                · status {revision.status} · submitted{" "}
                {formatDate(revision.submitted_at)}
              </p>
              {revision.status === "rejected" ? (
                <p className="mt-2 text-sm text-red-300">
                  Rejected: {dash(revision.rejection_reason)}
                </p>
              ) : null}
              {mediaBlocked ? (
                <p className="mt-2 text-sm text-amber-300">
                  New media is still uploading/processing (
                  {revision.media?.in_flight}). Approval is blocked until it is
                  ready.
                </p>
              ) : null}
              {mediaFailed ? (
                <p className="mt-2 text-sm text-red-300">
                  {revision.media?.failed} new photo/video(s) failed processing
                  {revision.media?.failed_cover
                    ? " (including the new cover photo)"
                    : ""}
                  . These changes cannot be approved as submitted. Reject them —
                  the live listing stays unchanged and the seller can resubmit.
                </p>
              ) : null}
            </section>

            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <h3 className="text-lg font-medium">Proposed changes</h3>
              {textFields.length === 0 ? (
                <p className="mt-3 text-sm text-surface-muted">
                  No field changes (media only).
                </p>
              ) : (
                <table className="mt-4 w-full text-sm">
                  <thead>
                    <tr className="text-left text-xs text-surface-muted">
                      <th className="py-1 pr-4">Field</th>
                      <th className="py-1 pr-4">Approved (live)</th>
                      <th className="py-1">Proposed</th>
                    </tr>
                  </thead>
                  <tbody>
                    {textFields.map((f) => (
                      <tr key={f} className="border-t border-surface-border">
                        <td className="py-2 pr-4 text-surface-muted">
                          {f.replace(/_/g, " ")}
                        </td>
                        <td className="py-2 pr-4 line-through opacity-70">
                          {fieldValue(current, f)}
                        </td>
                        <td className="py-2 font-medium">
                          {fieldValue(proposed, f)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </section>

            {revision.changed_fields.includes("images") ||
            revision.changed_fields.includes("videos") ? (
              <section className="space-y-6 rounded-xl border border-surface-border bg-surface-card p-6">
                <h3 className="text-lg font-medium">Photos</h3>
                <Gallery
                  title="Approved (live)"
                  images={sortedListingImages(current)}
                />
                <Gallery
                  title="Proposed (cover first)"
                  images={sortedListingImages(proposed)}
                />
              </section>
            ) : null}

            {canWrite ? (
              <section className="rounded-xl border border-surface-border bg-surface-card p-6">
                <h3 className="text-lg font-medium">Decision</h3>
                <div className="mt-4 flex flex-wrap items-start gap-4">
                  <button
                    type="button"
                    disabled={busy || approveBlocked}
                    onClick={() => void approve(revision.revision_token)}
                    className="rounded-lg bg-emerald-800 px-4 py-2 text-sm hover:bg-emerald-700 disabled:opacity-50"
                  >
                    Approve &amp; publish
                  </button>
                  <div className="flex min-w-[18rem] flex-1 flex-col gap-2">
                    <textarea
                      value={reason}
                      onChange={(e) => setReason(e.target.value)}
                      placeholder="Reason shown to the seller (required to reject)"
                      rows={3}
                      className="rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm"
                    />
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void reject(revision.revision_token)}
                      className="self-start rounded-lg border border-red-800/60 bg-red-950/40 px-4 py-2 text-sm text-red-200 hover:bg-red-900/40 disabled:opacity-50"
                    >
                      Reject changes
                    </button>
                  </div>
                </div>
              </section>
            ) : null}
          </div>
        );
      }}
    </AsyncPageBody>
  );
}
