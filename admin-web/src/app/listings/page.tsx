"use client";

import { useMemo, useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchListings } from "@/lib/api";
import { downloadCsv, listingPublicUrl } from "@/lib/export";
import { formatDate, formatNumber, formatPrice, listingTitle } from "@/lib/format";

export default function ListingsPage() {
  const [page, setPage] = useState(1);
  const [activeOnly, setActiveOnly] = useState(false);
  const [search, setSearch] = useState("");

  const { data, error, loading, reload } = useAsyncData(
    () => fetchListings({ page, per_page: 20, active_only: activeOnly }),
    [page, activeOnly],
  );

  const filtered = useMemo(() => {
    if (!data) return [];
    const q = search.trim().toLowerCase();
    if (!q) return data.cars;
    return data.cars.filter((c) => {
      const hay = [
        c.title,
        c.brand,
        c.model,
        c.location,
        c.id,
        String(c.year ?? ""),
      ]
        .join(" ")
        .toLowerCase();
      return hay.includes(q);
    });
  }, [data, search]);

  return (
    <AsyncPageBody
      title="Listings"
      description="All car listings on the platform"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <>
          <button
            type="button"
            disabled={filtered.length === 0}
            onClick={() => {
              downloadCsv(
                `carnet-listings-page-${page}.csv`,
                ["ID", "Title", "Brand", "Model", "Year", "Price", "Location", "Status", "Views", "Created"],
                filtered.map((c) => [
                  c.id,
                  c.title || "",
                  c.brand || "",
                  c.model || "",
                  String(c.year ?? ""),
                  String(c.price ?? ""),
                  c.location || "",
                  c.status || (c.is_active ? "active" : "inactive"),
                  String(c.views_count ?? 0),
                  c.created_at || "",
                ]),
              );
            }}
            className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5 disabled:opacity-40"
          >
            Export CSV
          </button>
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Filter this page…"
            className="w-48 rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm"
          />
          <label className="flex items-center gap-2 text-sm text-surface-muted">
            <input
              type="checkbox"
              checked={activeOnly}
              onChange={(e) => {
                setActiveOnly(e.target.checked);
                setPage(1);
              }}
              className="rounded border-surface-border"
            />
            Active only
          </label>
        </>
      }
    >
      {(result) => (
        <>
          <DataTable empty={filtered.length === 0}>
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
              {filtered.map((c) => (
                <tr key={c.id} className="hover:bg-white/[0.02]">
                  <Td>
                    <p className="font-medium">{listingTitle(c)}</p>
                    <p className="text-xs text-surface-muted">{c.id}</p>
                  </Td>
                  <Td>{formatPrice(c.price)}</Td>
                  <Td className="text-surface-muted">{c.location || "—"}</Td>
                  <Td>
                    <span
                      className={`inline-flex rounded-full px-2 py-0.5 text-xs ${
                        c.is_active
                          ? "bg-emerald-900/40 text-emerald-300"
                          : "bg-surface-border text-surface-muted"
                      }`}
                    >
                      {c.status || (c.is_active ? "active" : "inactive")}
                    </span>
                  </Td>
                  <Td>{formatNumber(c.views_count)}</Td>
                  <Td className="text-surface-muted">{formatDate(c.created_at)}</Td>
                  <Td>
                    <a
                      href={listingPublicUrl(c.id)}
                      target="_blank"
                      rel="noreferrer"
                      className="text-xs text-brand-400 hover:underline"
                    >
                      Open ↗
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
