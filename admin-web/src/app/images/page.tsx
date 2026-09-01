"use client";

import Link from "next/link";
import { Suspense, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchImages, type ImageListParams } from "@/lib/api";
import { formatDate, listingTitle, mediaUrl } from "@/lib/format";
import type { AdminImage } from "@/lib/types";
import {
  buildUrlQuery,
  paramPage,
  paramString,
} from "@/lib/urlParams";

function ImageCard({ image }: { image: AdminImage }) {
  const src = mediaUrl(image.image_url);
  const car = image.car;
  const title = car ? listingTitle(car) : "Unknown listing";

  return (
    <article className="group overflow-hidden rounded-xl border border-surface-border bg-surface-card/50">
      <a
        href={src}
        target="_blank"
        rel="noreferrer"
        className="relative block aspect-[4/3] overflow-hidden bg-black/40"
      >
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={src}
          alt={title}
          loading="lazy"
          className="h-full w-full object-cover transition group-hover:scale-[1.02]"
        />
        {image.is_primary ? (
          <span className="absolute left-2 top-2 rounded bg-brand-700/90 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide">
            Primary
          </span>
        ) : null}
        {image.kind === "damage" ? (
          <span className="absolute right-2 top-2 rounded bg-amber-800/90 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide">
            Damage
          </span>
        ) : null}
      </a>
      <div className="space-y-1 p-3">
        {car ? (
          <Link
            href={`/listings/${car.id}`}
            className="line-clamp-2 text-sm font-medium text-brand-300 hover:underline"
          >
            {title}
          </Link>
        ) : (
          <p className="line-clamp-2 text-sm font-medium text-surface-muted">
            {title}
          </p>
        )}
        <p className="text-xs text-surface-muted">
          {image.image_width && image.image_height
            ? `${image.image_width}×${image.image_height}`
            : "—"}
          {image.created_at ? ` · ${formatDate(image.created_at)}` : ""}
        </p>
        {image.seller?.username ? (
          <p className="truncate text-xs text-surface-muted">
            @{image.seller.username}
          </p>
        ) : null}
      </div>
    </article>
  );
}

function ImagesPageInner() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const page = paramPage(searchParams);
  const query = paramString(searchParams, "q");
  const kind = paramString(searchParams, "kind", "all");
  const carId = paramString(searchParams, "car_id");
  const sort = paramString(searchParams, "sort", "created_desc");

  const [search, setSearch] = useState(query);
  const [carFilter, setCarFilter] = useState(carId);

  useEffect(() => {
    setSearch(query);
  }, [query]);

  useEffect(() => {
    setCarFilter(carId);
  }, [carId]);

  const listParams: ImageListParams = useMemo(
    () => ({
      search: query || undefined,
      kind: kind !== "all" ? kind : undefined,
      car_id: carId || undefined,
      sort,
    }),
    [query, kind, carId, sort],
  );

  function replaceFilters(
    patch: Record<string, string | number | boolean | undefined | null>,
    resetPage = true,
  ) {
    const next = {
      q: query || undefined,
      kind: kind !== "all" ? kind : undefined,
      car_id: carId || undefined,
      sort: sort !== "created_desc" ? sort : undefined,
      page: resetPage ? undefined : page > 1 ? page : undefined,
      ...patch,
    };
    if (resetPage && patch.page === undefined) {
      next.page = undefined;
    }
    router.replace(
      `${pathname}${buildUrlQuery(next, {
        kind: "all",
        sort: "created_desc",
        page: 1,
      })}`,
    );
  }

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchImages({
        page,
        per_page: 48,
        ...listParams,
      }),
    [page, listParams],
  );

  function applySearch() {
    replaceFilters({
      q: search.trim() || undefined,
      car_id: carFilter.trim() || undefined,
    });
  }

  return (
    <AsyncPageBody
      title="Images"
      description="All listing photos uploaded across the platform"
      count={data?.pagination.total}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(result) => (
        <>
          <div className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-surface-border bg-surface-card/50 p-4">
            <label className="flex flex-col gap-1 text-xs text-surface-muted">
              <span>Search</span>
              <input
                type="search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && applySearch()}
                placeholder="Listing title, brand, URL…"
                className="w-56 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
            <label className="flex flex-col gap-1 text-xs text-surface-muted">
              <span>Listing ID</span>
              <input
                type="text"
                value={carFilter}
                onChange={(e) => setCarFilter(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && applySearch()}
                placeholder="Filter by listing…"
                className="w-44 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
            <FilterSelect
              label="Type"
              value={kind}
              onChange={(v) =>
                replaceFilters({ kind: v === "all" ? undefined : v })
              }
              options={[
                { value: "all", label: "All types" },
                { value: "listing", label: "Listing photos" },
                { value: "damage", label: "Damage photos" },
              ]}
            />
            <FilterSelect
              label="Sort"
              value={sort}
              onChange={(v) =>
                replaceFilters({
                  sort: v === "created_desc" ? undefined : v,
                })
              }
              options={[
                { value: "created_desc", label: "Newest" },
                { value: "created_asc", label: "Oldest" },
              ]}
            />
            <button
              type="button"
              onClick={applySearch}
              className="rounded-lg bg-brand-600 px-4 py-2 text-sm"
            >
              Search
            </button>
          </div>

          {result.images.length === 0 ? (
            <div className="rounded-xl border border-surface-border bg-surface-card/30 px-6 py-16 text-center">
              <p className="text-lg font-medium">No images found</p>
              <p className="mt-1 text-sm text-surface-muted">
                Try clearing filters or searching a different listing.
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
              {result.images.map((img) => (
                <ImageCard key={img.id ?? img.image_url} image={img} />
              ))}
            </div>
          )}

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

export default function ImagesPage() {
  return (
    <Suspense fallback={<p className="text-surface-muted">Loading images…</p>}>
      <ImagesPageInner />
    </Suspense>
  );
}
