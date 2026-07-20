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
import { deleteListing, fetchListingDetail, purgeListing, updateListingStatus } from "@/lib/api";
import { listingPublicUrl } from "@/lib/export";
import { getFilterMeta } from "@/lib/filterMeta";
import {
  dash,
  displayName,
  formatDate,
  formatMileage,
  formatNumber,
  formatPrice,
  listingTitle,
  mediaUrl,
} from "@/lib/format";
import { hasPermission } from "@/lib/permissions";
import type { CarImage, CarListing, CarVideo } from "@/lib/types";

const FALLBACK_STATUSES = ["active", "sold", "pending", "draft", "hidden"];

function Spec({
  label,
  value,
}: {
  label: string;
  value?: string | number | null;
}) {
  return (
    <div>
      <dt className="text-xs text-surface-muted">{label}</dt>
      <dd className="mt-1 text-sm">{dash(value)}</dd>
    </div>
  );
}

function sortedImages(images: CarImage[] | undefined, kind?: string): CarImage[] {
  const list = (images || []).filter((img) =>
    kind ? (img.kind || "listing") === kind : true,
  );
  return [...list].sort((a, b) => {
    if (a.is_primary && !b.is_primary) return -1;
    if (!a.is_primary && b.is_primary) return 1;
    return (a.order ?? 0) - (b.order ?? 0);
  });
}

function sortedVideos(videos: CarVideo[] | undefined): CarVideo[] {
  return [...(videos || [])].sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
}

function ImageGallery({
  title,
  images,
}: {
  title: string;
  images: CarImage[];
}) {
  if (images.length === 0) return null;
  return (
    <div>
      <h4 className="mb-2 text-sm font-medium text-surface-muted">
        {title} ({images.length})
      </h4>
      <div className="flex flex-wrap gap-2">
        {images.map((img, i) => {
          const src = mediaUrl(img.image_url);
          return (
            <a
              key={img.id ?? `${img.image_url}-${i}`}
              href={src}
              target="_blank"
              rel="noreferrer"
              className="relative block overflow-hidden rounded-lg border border-surface-border"
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={src}
                alt=""
                className="h-24 w-36 object-cover"
              />
              {img.is_primary ? (
                <span className="absolute left-1 top-1 rounded bg-black/70 px-1.5 py-0.5 text-[10px] text-white">
                  Primary
                </span>
              ) : null}
            </a>
          );
        })}
      </div>
    </div>
  );
}

function vehicleSpecs(c: CarListing): { label: string; value?: string | number | null }[] {
  const cylinders = c.cylinder_count ?? c.cylinders;
  return [
    { label: "Brand", value: c.brand },
    { label: "Model", value: c.model },
    { label: "Trim", value: c.trim },
    { label: "Year", value: c.year },
    { label: "Mileage", value: c.mileage != null ? formatMileage(c.mileage) : null },
    { label: "Condition", value: c.condition },
    { label: "Body type", value: c.body_type },
    { label: "Color", value: c.color },
    { label: "Transmission", value: c.transmission },
    { label: "Drive type", value: c.drive_type },
    { label: "Fuel type", value: c.fuel_type },
    { label: "Engine type", value: c.engine_type },
    {
      label: "Engine size",
      value: c.engine_size != null ? `${c.engine_size} L` : null,
    },
    { label: "Cylinders", value: cylinders },
    { label: "Fuel economy", value: c.fuel_economy },
    { label: "Seating", value: c.seating },
    { label: "Title status", value: c.title_status },
    {
      label: "Damaged parts",
      value: c.damaged_parts != null ? formatNumber(c.damaged_parts) : null,
    },
    { label: "Region specs", value: c.region_specs },
    { label: "Plate type", value: c.plate_type },
    { label: "Plate city", value: c.plate_city },
    { label: "VIN", value: c.vin },
    { label: "Currency", value: c.currency },
  ];
}

export default function ListingDetailPage() {
  const params = useParams();
  const router = useRouter();
  const carId = String(params.id || "");
  const toast = useToast();
  const { confirm } = useConfirm();
  const { user } = useAuth();
  const canWrite = hasPermission(user, "listings.write");
  const canDelete = hasPermission(user, "listings.delete");
  const canPurge = hasPermission(user, "purge");
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

  async function handlePurge() {
    const ok = await confirm({
      title: "Permanently purge listing?",
      description:
        "Deletes the listing and related messages, reports, and analytics. This cannot be undone.",
      confirmLabel: "Purge forever",
      tone: "danger",
    });
    if (!ok) return;
    setBusy(true);
    try {
      await purgeListing(carId);
      toast.success("Listing purged");
      refreshNavBadges();
      router.push("/listings");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Purge failed");
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
        const seller = c.seller;
        const statusValue = c.status || "active";
        const statusOptions = Array.from(
          new Set([statusValue, ...statuses]),
        ).map((s) => ({ value: s, label: s }));
        const listingImages = sortedImages(c.images, "listing");
        const damageImages = sortedImages(c.images, "damage");
        const otherImages = (c.images || []).filter((img) => {
          const kind = img.kind || "listing";
          return kind !== "listing" && kind !== "damage";
        });
        const videos = sortedVideos(c.videos);
        const specs = vehicleSpecs(c);

        return (
          <div className="space-y-8">
            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <h2 className="text-xl font-semibold">{listingTitle(c)}</h2>
                  <p className="mt-1 text-sm text-surface-muted">{c.location}</p>
                  <p className="mt-2 text-2xl font-bold text-brand-300">
                    {formatPrice(c.price, c.currency)}
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
                  {canPurge ? (
                    <button
                      type="button"
                      disabled={busy}
                      onClick={() => void handlePurge()}
                      className="rounded-lg border border-red-900 bg-red-950/70 px-3 py-2 text-sm text-red-100 hover:bg-red-900/50 disabled:opacity-50"
                    >
                      Purge
                    </button>
                  ) : null}
                </div>
              </div>

              <dl className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <Spec
                  label="Status"
                  value={`${c.status || "—"} · ${c.is_active ? "active" : "inactive"}${
                    c.is_featured ? " · featured" : ""
                  }`}
                />
                <Spec label="Views (car)" value={formatNumber(c.views_count)} />
                <Spec label="Created" value={formatDate(c.created_at)} />
                <Spec label="Updated" value={formatDate(c.updated_at)} />
              </dl>
            </section>

            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <h3 className="text-lg font-medium">Vehicle details</h3>
              <dl className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {specs.map((s) => (
                  <Spec key={s.label} label={s.label} value={s.value} />
                ))}
              </dl>
              {(c.latitude != null || c.longitude != null) && (
                <dl className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                  <Spec label="Latitude" value={c.latitude} />
                  <Spec label="Longitude" value={c.longitude} />
                </dl>
              )}
            </section>

            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <h3 className="text-lg font-medium">Description</h3>
              {c.description?.trim() ? (
                <p className="mt-3 whitespace-pre-wrap text-sm text-surface-muted">
                  {c.description}
                </p>
              ) : (
                <p className="mt-3 text-sm text-surface-muted">No description.</p>
              )}
            </section>

            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <h3 className="mb-4 text-lg font-medium">
                Media (
                {(c.images?.length || 0) + (c.videos?.length || 0)})
              </h3>
              {(c.images?.length || 0) + (c.videos?.length || 0) === 0 ? (
                <p className="text-sm text-surface-muted">No photos or videos.</p>
              ) : (
                <div className="space-y-6">
                  <ImageGallery title="Listing photos" images={listingImages} />
                  <ImageGallery title="Damage photos" images={damageImages} />
                  {otherImages.length > 0 ? (
                    <ImageGallery title="Other photos" images={otherImages} />
                  ) : null}
                  {videos.length > 0 ? (
                    <div>
                      <h4 className="mb-2 text-sm font-medium text-surface-muted">
                        Videos ({videos.length})
                      </h4>
                      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                        {videos.map((v, i) => {
                          const src = mediaUrl(v.video_url);
                          const thumb = mediaUrl(v.thumbnail_url);
                          return (
                            <a
                              key={v.id ?? `${v.video_url}-${i}`}
                              href={src}
                              target="_blank"
                              rel="noreferrer"
                              className="overflow-hidden rounded-lg border border-surface-border hover:bg-white/5"
                            >
                              {thumb ? (
                                // eslint-disable-next-line @next/next/no-img-element
                                <img
                                  src={thumb}
                                  alt=""
                                  className="h-36 w-full object-cover"
                                />
                              ) : (
                                <div className="flex h-36 items-center justify-center bg-black/30 text-sm text-surface-muted">
                                  Video
                                </div>
                              )}
                              <div className="px-3 py-2 text-xs text-surface-muted">
                                {v.duration != null
                                  ? `${formatNumber(v.duration)}s · `
                                  : ""}
                                Open video ↗
                              </div>
                            </a>
                          );
                        })}
                      </div>
                    </div>
                  ) : null}
                </div>
              )}
            </section>

            <section className="rounded-xl border border-surface-border bg-surface-card p-6">
              <h3 className="text-lg font-medium">Seller</h3>
              {seller ? (
                <dl className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  <div>
                    <dt className="text-xs text-surface-muted">Name</dt>
                    <dd className="mt-1 text-sm">
                      {seller.id ? (
                        <Link
                          href={`/users/${seller.id}`}
                          className="text-brand-300 hover:underline"
                        >
                          {displayName(seller)}
                        </Link>
                      ) : (
                        displayName(seller)
                      )}
                    </dd>
                  </div>
                  <Spec label="Username" value={seller.username} />
                  <Spec label="Phone" value={seller.phone_number} />
                  <Spec label="Email" value={seller.email} />
                  <Spec
                    label="Account"
                    value={`${seller.account_type || "user"}${
                      seller.dealer_status && seller.dealer_status !== "none"
                        ? ` · ${seller.dealer_status}`
                        : ""
                    }`}
                  />
                  <Spec
                    label="Dealership"
                    value={seller.dealership_name}
                  />
                  <Spec
                    label="Dealership phone"
                    value={seller.dealership_phone}
                  />
                  <Spec
                    label="Dealership location"
                    value={seller.dealership_location}
                  />
                </dl>
              ) : (
                <p className="mt-3 text-sm text-surface-muted">No seller linked.</p>
              )}
            </section>

            {c.ai_analyzed ? (
              <section className="rounded-xl border border-surface-border bg-surface-card p-6">
                <h3 className="text-lg font-medium">AI analysis</h3>
                <dl className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  <Spec label="Detected brand" value={c.ai_detected_brand} />
                  <Spec label="Detected model" value={c.ai_detected_model} />
                  <Spec label="Detected color" value={c.ai_detected_color} />
                  <Spec
                    label="Detected body type"
                    value={c.ai_detected_body_type}
                  />
                  <Spec
                    label="Detected condition"
                    value={c.ai_detected_condition}
                  />
                  <Spec
                    label="Confidence"
                    value={
                      c.ai_confidence_score != null
                        ? `${Math.round(c.ai_confidence_score * 100)}%`
                        : null
                    }
                  />
                  <Spec
                    label="Analyzed at"
                    value={formatDate(c.ai_analysis_timestamp)}
                  />
                </dl>
              </section>
            ) : null}

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
                    <Th>Details</Th>
                    <Th>Reporter</Th>
                    <Th>Status</Th>
                    <Th>Created</Th>
                  </tr>
                </thead>
                <tbody>
                  {detail.reports.map((r) => (
                    <tr key={r.id}>
                      <Td>{r.reason || "—"}</Td>
                      <Td className="max-w-xs whitespace-pre-wrap text-sm">
                        {r.details || r.admin_notes || "—"}
                      </Td>
                      <Td>
                        {r.reporter?.id ? (
                          <Link
                            href={`/users/${r.reporter.id}`}
                            className="text-brand-300 hover:underline"
                          >
                            {r.reporter.username || r.reporter.id}
                          </Link>
                        ) : (
                          "—"
                        )}
                      </Td>
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
