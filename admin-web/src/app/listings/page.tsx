"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchFilterMeta, fetchListings } from "@/lib/api";
import { downloadCsv, listingPublicUrl } from "@/lib/export";
import { formatDate, formatNumber, formatPrice, listingTitle } from "@/lib/format";

export default function ListingsPage() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [brand, setBrand] = useState("all");
  const [status, setStatus] = useState("all");
  const [sort, setSort] = useState("created_desc");
  const [activeOnly, setActiveOnly] = useState(false);
  const [featuredOnly, setFeaturedOnly] = useState(false);
  const [minPrice, setMinPrice] = useState("");
  const [maxPrice, setMaxPrice] = useState("");
  const [brands, setBrands] = useState<string[]>([]);
  const [statuses, setStatuses] = useState<string[]>([]);

  useEffect(() => {
    fetchFilterMeta()
      .then((m) => {
        setBrands(m.brands);
        setStatuses(m.listing_statuses);
      })
      .catch(() => {});
  }, []);

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchListings({
        page,
        per_page: 20,
        search: query || undefined,
        brand: brand !== "all" ? brand : undefined,
        status: status !== "all" ? status : undefined,
        active_only: activeOnly,
        is_featured: featuredOnly ? true : undefined,
        min_price: minPrice ? Number(minPrice) : undefined,
        max_price: maxPrice ? Number(maxPrice) : undefined,
        sort,
      }),
    [page, query, brand, status, activeOnly, featuredOnly, minPrice, maxPrice, sort],
  );

  function applyFilters() {
    setPage(1);
    setQuery(search.trim());
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
          disabled={!data?.cars.length}
          onClick={() => {
            if (!data) return;
            downloadCsv(
              `carnet-listings-page-${page}.csv`,
              ["ID", "Title", "Brand", "Price", "Location", "Status", "Views", "Created"],
              data.cars.map((c) => [
                c.id,
                listingTitle(c),
                c.brand || "",
                String(c.price ?? ""),
                c.location || "",
                c.status || "",
                String(c.views_count ?? 0),
                c.created_at || "",
              ]),
            );
          }}
          className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5 disabled:opacity-40"
        >
          Export CSV
        </button>
      }
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
                onKeyDown={(e) => e.key === "Enter" && applyFilters()}
                placeholder="Title, brand, ID, location…"
                className="w-56 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
            <FilterSelect
              label="Brand"
              value={brand}
              onChange={(v) => { setBrand(v); setPage(1); }}
              options={[{ value: "all", label: "All brands" }, ...brands.map((b) => ({ value: b, label: b }))]}
            />
            <FilterSelect
              label="Status"
              value={status}
              onChange={(v) => { setStatus(v); setPage(1); }}
              options={[{ value: "all", label: "All" }, ...statuses.map((s) => ({ value: s, label: s }))]}
            />
            <FilterSelect
              label="Sort"
              value={sort}
              onChange={(v) => { setSort(v); setPage(1); }}
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
                onChange={(e) => setMinPrice(e.target.value)}
                className="w-24 rounded-lg border border-surface-border bg-black/30 px-2 py-1.5 text-sm"
              />
            </label>
            <label className="flex flex-col gap-1 text-xs text-surface-muted">
              <span>Max price</span>
              <input
                type="number"
                value={maxPrice}
                onChange={(e) => setMaxPrice(e.target.value)}
                className="w-24 rounded-lg border border-surface-border bg-black/30 px-2 py-1.5 text-sm"
              />
            </label>
            <label className="flex items-center gap-2 text-sm text-surface-muted">
              <input type="checkbox" checked={activeOnly} onChange={(e) => { setActiveOnly(e.target.checked); setPage(1); }} />
              Active only
            </label>
            <label className="flex items-center gap-2 text-sm text-surface-muted">
              <input type="checkbox" checked={featuredOnly} onChange={(e) => { setFeaturedOnly(e.target.checked); setPage(1); }} />
              Featured
            </label>
            <button type="button" onClick={applyFilters} className="rounded-lg bg-brand-600 px-4 py-2 text-sm">
              Search
            </button>
          </div>

          <DataTable empty={result.cars.length === 0}>
            <thead>
              <tr>
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
                    <Link href={`/listings/${c.id}`} className="font-medium text-brand-300 hover:underline">
                      {listingTitle(c)}
                    </Link>
                    {c.is_featured ? (
                      <span className="ml-2 text-xs text-amber-400">★</span>
                    ) : null}
                    <p className="text-xs text-surface-muted">{c.id}</p>
                  </Td>
                  <Td>{formatPrice(c.price)}</Td>
                  <Td className="text-surface-muted">{c.location || "—"}</Td>
                  <Td>{c.is_active ? c.status || "active" : "inactive"}</Td>
                  <Td>{formatNumber(c.views_count)}</Td>
                  <Td className="text-surface-muted">{formatDate(c.created_at)}</Td>
                  <Td>
                    <a href={listingPublicUrl(c.id)} target="_blank" rel="noreferrer" className="text-xs text-brand-400 hover:underline">
                      Public ↗
                    </a>
                  </Td>
                </tr>
              ))}
            </tbody>
          </DataTable>
          <Pagination pagination={result.pagination} onPageChange={setPage} />
        </>
      )}
    </AsyncPageBody>
  );
}
