"use client";

import Link from "next/link";
import { Suspense, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { refreshNavBadges } from "@/components/NavBadges";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import {
  bulkUpdateListingStatus,
  fetchListings,
  type ListingListParams,
} from "@/lib/api";
import { exportAllPagesCsv, listingPublicUrl } from "@/lib/export";
import { getFilterMeta } from "@/lib/filterMeta";
import { formatDate, formatNumber, formatPrice, listingTitle } from "@/lib/format";
import type { CarListing } from "@/lib/types";
import {
  buildUrlQuery,
  paramBool,
  paramPage,
  paramString,
} from "@/lib/urlParams";

function ListingsPageInner() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const toast = useToast();
  const { confirm } = useConfirm();

  const page = paramPage(searchParams);
  const query = paramString(searchParams, "q");
  const brand = paramString(searchParams, "brand", "all");
  const status = paramString(searchParams, "status", "all");
  const sort = paramString(searchParams, "sort", "created_desc");
  const activeOnly = paramBool(searchParams, "active");
  const featuredOnly = paramBool(searchParams, "featured");
  const minPrice = paramString(searchParams, "min_price");
  const maxPrice = paramString(searchParams, "max_price");

  const [search, setSearch] = useState(query);
  const [brands, setBrands] = useState<string[]>([]);
  const [statuses, setStatuses] = useState<string[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [exporting, setExporting] = useState(false);

  useEffect(() => {
    setSearch(query);
  }, [query]);

  useEffect(() => {
    getFilterMeta()
      .then((m) => {
        setBrands(m.brands);
        setStatuses(m.listing_statuses);
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    setSelected(new Set());
  }, [page, query, brand, status, activeOnly, featuredOnly, minPrice, maxPrice, sort]);

  const listParams: ListingListParams = useMemo(
    () => ({
      search: query || undefined,
      brand: brand !== "all" ? brand : undefined,
      status: status !== "all" ? status : undefined,
      active_only: activeOnly,
      is_featured: featuredOnly ? true : undefined,
      min_price: minPrice ? Number(minPrice) : undefined,
      max_price: maxPrice ? Number(maxPrice) : undefined,
      sort,
    }),
    [query, brand, status, activeOnly, featuredOnly, minPrice, maxPrice, sort],
  );

  function replaceFilters(
    patch: Record<string, string | number | boolean | undefined | null>,
    resetPage = true,
  ) {
    const next = {
      q: query || undefined,
      brand: brand !== "all" ? brand : undefined,
      status: status !== "all" ? status : undefined,
      sort: sort !== "created_desc" ? sort : undefined,
      active: activeOnly || undefined,
      featured: featuredOnly || undefined,
      min_price: minPrice || undefined,
      max_price: maxPrice || undefined,
      page: resetPage ? undefined : page > 1 ? page : undefined,
      ...patch,
    };
    if (resetPage && patch.page === undefined) {
      next.page = undefined;
    }
    router.replace(
      `${pathname}${buildUrlQuery(next, {
        brand: "all",
        status: "all",
        sort: "created_desc",
        active: false,
        featured: false,
        page: 1,
      })}`,
    );
  }

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchListings({
        page,
        per_page: 20,
        ...listParams,
      }),
    [page, listParams],
  );

  function applySearch() {
    replaceFilters({ q: search.trim() || undefined });
  }

  function toggleOne(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleAll(ids: string[]) {
    setSelected((prev) => {
      const allSelected = ids.length > 0 && ids.every((id) => prev.has(id));
      if (allSelected) return new Set();
      return new Set(ids);
    });
  }

  async function runBulk(
    label: string,
    patch: { is_active?: boolean; is_featured?: boolean; status?: string },
  ) {
    const ids = Array.from(selected);
    if (!ids.length) return;
    const ok = await confirm({
      title: `${label}?`,
      description: `Apply to ${ids.length} selected listing(s).`,
      confirmLabel: label,
      tone: patch.is_active === false ? "danger" : "brand",
    });
    if (!ok) return;

    setBusy(true);
    try {
      const result = await bulkUpdateListingStatus(ids, patch);
      toast.success(result.message);
      setSelected(new Set());
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Bulk update failed");
    } finally {
      setBusy(false);
    }
  }

  async function handleExportAll() {
    setExporting(true);
    try {
      const count = await exportAllPagesCsv<CarListing>({
        filename: `carnet-listings-${new Date().toISOString().slice(0, 10)}.csv`,
        headers: [
          "ID",
          "Title",
          "Brand",
          "Price",
          "Location",
          "Status",
          "Views",
          "Created",
        ],
        mapRow: (c) => [
          c.id,
          listingTitle(c),
          c.brand || "",
          String(c.price ?? ""),
          c.location || "",
          c.status || "",
          String(c.views_count ?? 0),
          c.created_at || "",
        ],
        fetchPage: async (p, perPage) => {
          const res = await fetchListings({
            page: p,
            per_page: perPage,
            ...listParams,
          });
          return { items: res.cars, pagination: res.pagination };
        },
      });
      toast.success(`Exported ${count} listing(s)`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Export failed");
    } finally {
      setExporting(false);
    }
  }

  return (
    <AsyncPageBody
      title="Listings"
      description="Search and filter all car listings"
      count={data?.pagination.total}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <button
          type="button"
          disabled={exporting || !data?.cars.length}
          onClick={handleExportAll}
          className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5 disabled:opacity-40"
        >
          {exporting ? "Exporting…" : "Export CSV"}
        </button>
      }
    >
      {(result) => {
        const ids = result.cars.map((c) => c.id);
        const allSelected =
          ids.length > 0 && ids.every((id) => selected.has(id));

        return (
          <>
            <div className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-surface-border bg-surface-card/50 p-4">
              <label className="flex flex-col gap-1 text-xs text-surface-muted">
                <span>Search</span>
                <input
                  type="search"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && applySearch()}
                  placeholder="Title, brand, ID, location…"
                  className="w-56 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
                />
              </label>
              <FilterSelect
                label="Brand"
                value={brand}
                onChange={(v) =>
                  replaceFilters({ brand: v === "all" ? undefined : v })
                }
                options={[
                  { value: "all", label: "All brands" },
                  ...brands.map((b) => ({ value: b, label: b })),
                ]}
              />
              <FilterSelect
                label="Status"
                value={status}
                onChange={(v) =>
                  replaceFilters({ status: v === "all" ? undefined : v })
                }
                options={[
                  { value: "all", label: "All" },
                  ...statuses.map((s) => ({ value: s, label: s })),
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
                  { value: "price_desc", label: "Price high" },
                  { value: "price_asc", label: "Price low" },
                  { value: "views_desc", label: "Most views" },
                ]}
              />
              <label className="flex flex-col gap-1 text-xs text-surface-muted">
                <span>Min price</span>
                <input
                  type="number"
                  value={minPrice}
                  onChange={(e) =>
                    replaceFilters({ min_price: e.target.value || undefined })
                  }
                  className="w-24 rounded-lg border border-surface-border bg-black/30 px-2 py-1.5 text-sm"
                />
              </label>
              <label className="flex flex-col gap-1 text-xs text-surface-muted">
                <span>Max price</span>
                <input
                  type="number"
                  value={maxPrice}
                  onChange={(e) =>
                    replaceFilters({ max_price: e.target.value || undefined })
                  }
                  className="w-24 rounded-lg border border-surface-border bg-black/30 px-2 py-1.5 text-sm"
                />
              </label>
              <label className="flex items-center gap-2 text-sm text-surface-muted">
                <input
                  type="checkbox"
                  checked={activeOnly}
                  onChange={(e) =>
                    replaceFilters({ active: e.target.checked || undefined })
                  }
                />
                Active only
              </label>
              <label className="flex items-center gap-2 text-sm text-surface-muted">
                <input
                  type="checkbox"
                  checked={featuredOnly}
                  onChange={(e) =>
                    replaceFilters({ featured: e.target.checked || undefined })
                  }
                />
                Featured
              </label>
              <button
                type="button"
                onClick={applySearch}
                className="rounded-lg bg-brand-600 px-4 py-2 text-sm"
              >
                Search
              </button>
            </div>

            {selected.size > 0 ? (
              <div className="mb-4 flex flex-wrap items-center gap-2 rounded-xl border border-brand-700/40 bg-brand-900/20 px-4 py-3 text-sm">
                <span className="text-surface-muted">
                  {selected.size} selected
                </span>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => runBulk("Activate", { is_active: true })}
                  className="rounded-lg bg-emerald-800 px-3 py-1.5 text-xs disabled:opacity-50"
                >
                  Activate
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => runBulk("Deactivate", { is_active: false })}
                  className="rounded-lg bg-red-900/70 px-3 py-1.5 text-xs disabled:opacity-50"
                >
                  Deactivate
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => runBulk("Feature", { is_featured: true })}
                  className="rounded-lg border border-surface-border px-3 py-1.5 text-xs disabled:opacity-50"
                >
                  Feature
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => runBulk("Unfeature", { is_featured: false })}
                  className="rounded-lg border border-surface-border px-3 py-1.5 text-xs disabled:opacity-50"
                >
                  Unfeature
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => runBulk("Mark sold", { status: "sold" })}
                  className="rounded-lg border border-surface-border px-3 py-1.5 text-xs disabled:opacity-50"
                >
                  Mark sold
                </button>
                <button
                  type="button"
                  onClick={() => setSelected(new Set())}
                  className="ml-auto text-xs text-surface-muted hover:text-white"
                >
                  Clear
                </button>
              </div>
            ) : null}

            <DataTable
              empty={result.cars.length === 0}
              emptyTitle="No listings found"
              emptyDescription="Try clearing filters or searching a different brand."
            >
              <thead>
                <tr>
                  <Th>
                    <input
                      type="checkbox"
                      checked={allSelected}
                      onChange={() => toggleAll(ids)}
                      aria-label="Select all on page"
                    />
                  </Th>
                  <Th>Listing</Th>
                  <Th>Price</Th>
                  <Th>Location</Th>
                  <Th>Status</Th>
                  <Th>Views</Th>
                  <Th>Created</Th>
                  <Th></Th>
                </tr>
              </thead>
              <tbody>
                {result.cars.map((c) => (
                  <tr key={c.id} className="hover:bg-white/[0.02]">
                    <Td>
                      <input
                        type="checkbox"
                        checked={selected.has(c.id)}
                        onChange={() => toggleOne(c.id)}
                        aria-label={`Select ${listingTitle(c)}`}
                      />
                    </Td>
                    <Td>
                      <Link
                        href={`/listings/${c.id}`}
                        className="font-medium text-brand-300 hover:underline"
                      >
                        {listingTitle(c)}
                      </Link>
                      {c.is_featured ? (
                        <span className="ml-2 text-xs text-amber-400">★</span>
                      ) : null}
                      <p className="text-xs text-surface-muted">{c.id}</p>
                    </Td>
                    <Td>{formatPrice(c.price)}</Td>
                    <Td className="text-surface-muted">
                      {c.location || "—"}
                    </Td>
                    <Td>
                      {c.is_active ? c.status || "active" : "inactive"}
                    </Td>
                    <Td>{formatNumber(c.views_count)}</Td>
                    <Td className="text-surface-muted">
                      {formatDate(c.created_at)}
                    </Td>
                    <Td>
                      <a
                        href={listingPublicUrl(c.id)}
                        target="_blank"
                        rel="noreferrer"
                        className="text-xs text-brand-400 hover:underline"
                      >
                        Public ↗
                      </a>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </DataTable>
            <Pagination
              pagination={result.pagination}
              onPageChange={(p) =>
                replaceFilters({ page: p > 1 ? p : undefined }, false)
              }
            />
          </>
        );
      }}
    </AsyncPageBody>
  );
}

export default function ListingsPage() {
  return (
    <Suspense fallback={<p className="text-surface-muted">Loading listings…</p>}>
      <ListingsPageInner />
    </Suspense>
  );
}
