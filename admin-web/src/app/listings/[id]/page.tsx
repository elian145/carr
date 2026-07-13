"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { FilterSelect } from "@/components/FilterSelect";
import { refreshNavBadges } from "@/components/NavBadges";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import { useAuth } from "@/context/AuthContext";
import { deleteListing, fetchListingDetail, updateListingStatus } from "@/lib/api";
import { listingPublicUrl } from "@/lib/export";
import { getFilterMeta } from "@/lib/filterMeta";
import {
  formatDate,
  formatNumber,
  formatPrice,
  listingTitle,
} from "@/lib/format";
import { hasPermission } from "@/lib/permissions";

const FALLBACK_STATUSES = ["active", "sold", "pending", "draft", "hidden"];

export default function ListingDetailPage() {
  const params = useParams();
  const router = useRouter();
  const carId = String(params.id || "");
  const toast = useToast();
  const { confirm } = useConfirm();
  const { user } = useAuth();
  const canWrite = hasPermission(user, "listings.write");
  const canDelete = hasPermission(user, "listings.delete");
  const [busy, setBusy] = useState(false);
  const [statuses, setStatuses] = useState<string[]>(FALLBACK_STATUSES);

  const { data, error, loading, reload } = useAsyncData(
    () => fetchListingDetail(carId),
    [carId],
  );

  useEffect(() => {
    getFilterMeta()
      .then((m) => {
        const fromApi = m.listing_statuses || [];
        const merged = Array.from(
          new Set([...FALLBACK_STATUSES, ...fromApi].filter(Boolean)),
        );
        setStatuses(merged);
      })
      .catch(() => {});
  }, []);

  async function patch(patch: {
    is_active?: boolean;
    is_featured?: boolean;
    status?: string;
  }) {
    if (patch.is_active === false) {
      const ok = await confirm({
        title: "Deactivate listing?",
        description: "The listing will be hidden from public browse results.",
        confirmLabel: "Deactivate",
        tone: "danger",
      });
      if (!ok) return;
    }

    setBusy(true);
    try {
      await updateListingStatus(carId, patch);
      toast.success("Listing updated");
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Update failed");
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete() {
    const ok = await confirm({
      title: "Soft-delete listing?",
      description:
        "The listing will be hidden from browse, removed from favorites/history, and marked hidden. The record is kept for audit.",
      confirmLabel: "Delete listing",
      tone: "danger",
    });
    if (!ok) return;

    setBusy(true);
    try {
      await deleteListing(carId);
      toast.success("Listing soft-deleted");
      refreshNavBadges();
      router.push("/listings");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Delete failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <AsyncPageBody
      title="Listing details"
      description={carId}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <Link
          href="/listings"
          className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5"
        >
          ← Back
        </Link>
      }
    >
      {(detail) => {
        const c = detail.car;
        const a = detail.analytics;
        const statusValue = c.status || "active";
        const statusOptions = Array.from(
          new Set([statusValue, ...statuses]),
        ).map((s) => ({ value: s, label: s }));

        return (
          <div className="space-y-8">
            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <h2 className="text-xl font-semibold">{listingTitle(c)}</h2>
                  <p className="mt-1 text-sm text-surface-muted">{c.location}</p>
                  <p className="mt-2 text-2xl font-bold text-brand-300">
                    {formatPrice(c.price)}
                  </p>
                </div>
                <div className="flex flex-wrap items-end gap-2">
                  <a
                    href={listingPublicUrl(c.id)}
                    target="_blank"
                    rel="noreferrer"
                    className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5"
                  >
                    Open public ↗
                  </a>
                  {canWrite ? (
                    <>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => patch({ is_active: !c.is_active })}
                        className="rounded-lg bg-brand-700 px-3 py-2 text-sm hover:bg-brand-600 disabled:opacity-50"
                      >
                        {c.is_active ? "Deactivate" : "Activate"}
                      </button>
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() => patch({ is_featured: !c.is_featured })}
                        className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5 disabled:opacity-50"
                      >
                        {c.is_featured ? "Unfeature" : "Feature"}
                      </button>
                      <FilterSelect
                        label="Listing status"
                        value={statusValue}
                        onChange={(v) => {
                          if (v !== statusValue) patch({ status: v });
                        }}
                        options={statusOptions}
                      />
                    </>
                  ) : null}
                  {canDelete ? (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={handleDelete}
                      className="rounded-lg border border-red-800/60 bg-red-950/40 px-3 py-2 text-sm text-red-200 hover:bg-red-900/40 disabled:opacity-50"
                    >
                      Delete
                    </button>
                  ) : null}
                </div>
              </div>

              <dl className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <div>
                  <dt className="text-xs text-surface-muted">Status</dt>
                  <dd className="mt-1">
                    {c.status} · {c.is_active ? "active" : "inactive"}
                    {c.is_featured ? " · featured" : ""}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Views (car)</dt>
                  <dd className="mt-1">{formatNumber(c.views_count)}</dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Created</dt>
                  <dd className="mt-1">{formatDate(c.created_at)}</dd>
                </div>
                <div>
                  <dt className="text-xs text-surface-muted">Seller</dt>
                  <dd className="mt-1">
                    {c.seller?.id ? (
                      <Link
                        href={`/users/${c.seller.id}`}
                        className="text-brand-300 hover:underline"
                      >
                        {c.seller.username || c.seller.id}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </dd>
                </div>
              </dl>

              {c.description ? (
                <p className="mt-4 whitespace-pre-wrap text-sm text-surface-muted">
                  {c.description}
                </p>
              ) : null}

              {c.images && c.images.length > 0 ? (
                <div className="mt-4 flex flex-wrap gap-2">
                  {c.images.slice(0, 6).map((img, i) => (
                    <img
                      key={i}
                      src={
                        img.image_url.startsWith("http")
                          ? img.image_url
                          : `${process.env.NEXT_PUBLIC_API_BASE}${img.image_url}`
                      }
                      alt=""
                      className="h-20 w-28 rounded-lg border border-surface-border object-cover"
                    />
                  ))}
                </div>
              ) : null}
            </section>

            {a ? (
              <section className="grid gap-4 sm:grid-cols-5">
                {[
                  ["Views", a.views],
                  ["Messages", a.messages],
                  ["Calls", a.calls],
                  ["Shares", a.shares],
                  ["Favorites", a.favorites],
                ].map(([label, val]) => (
                  <div
                    key={label as string}
                    className="rounded-xl border border-surface-border bg-surface-card p-4"
                  >
                    <p className="text-xs text-surface-muted">{label}</p>
                    <p className="mt-1 text-2xl font-semibold">
                      {formatNumber(val as number)}
                    </p>
                  </div>
                ))}
              </section>
            ) : null}

            <section>
              <h3 className="mb-3 text-lg font-medium">
                Reports ({detail.reports.length})
              </h3>
              <DataTable empty={detail.reports.length === 0}>
                <thead>
                  <tr>
                    <Th>Reason</Th>
                    <Th>Status</Th>
                    <Th>Created</Th>
                  </tr>
                </thead>
                <tbody>
                  {detail.reports.map((r) => (
                    <tr key={r.id}>
                      <Td>{r.reason || "—"}</Td>
                      <Td>{r.status}</Td>
                      <Td>{formatDate(r.created_at)}</Td>
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
