"use client";

import Link from "next/link";
import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchMessages } from "@/lib/api";
import { formatDate } from "@/lib/format";

export default function MessagesPage() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [readFilter, setReadFilter] = useState("all");
  const [carFilter, setCarFilter] = useState("");

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchMessages({
        page,
        per_page: 50,
        search: query || undefined,
        car_id: carFilter.trim() || undefined,
        is_read: readFilter === "all" ? undefined : readFilter === "read",
      }),
    [page, query, readFilter, carFilter],
  );

  return (
    <AsyncPageBody
      title="Messages"
      description="Chat messages across the platform"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(result) => (
        <>
          <div className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-surface-border bg-surface-card/50 p-4">
            <label className="flex flex-col gap-1 text-xs text-surface-muted">
              <span>Search content</span>
              <input
                type="search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && (setPage(1), setQuery(search.trim()))}
                className="w-56 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
            <label className="flex flex-col gap-1 text-xs text-surface-muted">
              <span>Listing ID</span>
              <input
                type="text"
                value={carFilter}
                onChange={(e) => { setCarFilter(e.target.value); setPage(1); }}
                placeholder="Car public id"
                className="w-40 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
            <FilterSelect
              label="Read"
              value={readFilter}
              onChange={(v) => { setReadFilter(v); setPage(1); }}
              options={[
                { value: "all", label: "All" },
                { value: "read", label: "Read" },
                { value: "unread", label: "Unread" },
              ]}
            />
            <button
              type="button"
              onClick={() => { setPage(1); setQuery(search.trim()); }}
              className="rounded-lg bg-brand-600 px-4 py-2 text-sm"
            >
              Search
            </button>
          </div>

          <DataTable empty={result.messages.length === 0}>
            <thead>
              <tr>
                <Th>Content</Th>
                <Th>Type</Th>
                <Th>Listing</Th>
                <Th>Read</Th>
                <Th>Sent</Th>
              </tr>
            </thead>
            <tbody>
              {result.messages.map((m) => (
                <tr key={m.id}>
                  <Td className="max-w-md">
                    <p className="line-clamp-3">{(m.content || "").trim() || "—"}</p>
                  </Td>
                  <Td className="text-surface-muted">{m.message_type || "text"}</Td>
                  <Td>
                    {m.car_id ? (
                      <Link href={`/listings/${m.car_id}`} className="text-xs text-brand-400 hover:underline">
                        {m.car_id}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </Td>
                  <Td>{m.is_read ? "Yes" : "No"}</Td>
                  <Td className="text-surface-muted">{formatDate(m.created_at)}</Td>
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
