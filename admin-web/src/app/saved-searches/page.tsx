"use client";

import Link from "next/link";
import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchSavedSearches } from "@/lib/api";
import { formatDate } from "@/lib/format";

export default function SavedSearchesPage() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");

  const { data, error, loading, reload } = useAsyncData(
    () => fetchSavedSearches({ page, per_page: 30, search: query || undefined }),
    [page, query],
  );

  return (
    <AsyncPageBody
      title="Saved searches"
      description="What users are watching for"
      count={data?.pagination.total}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <form
          className="flex gap-2"
          onSubmit={(e) => {
            e.preventDefault();
            setPage(1);
            setQuery(search.trim());
          }}
        >
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Filter by name…"
            className="w-48 rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm"
          />
          <button type="submit" className="rounded-lg bg-brand-600 px-4 py-2 text-sm">
            Filter
          </button>
        </form>
      }
    >
      {(result) => (
        <>
          <DataTable empty={result.saved_searches.length === 0}>
            <thead>
              <tr>
                <Th>Name</Th>
                <Th>User</Th>
                <Th>Alerts</Th>
                <Th>Filters</Th>
                <Th>Created</Th>
              </tr>
            </thead>
            <tbody>
              {result.saved_searches.map((s) => (
                <tr key={s.id}>
                  <Td className="font-medium">{s.name || "—"}</Td>
                  <Td>
                    {s.user_public_id ? (
                      <Link href={`/users/${s.user_public_id}`} className="text-brand-300 hover:underline">
                        {s.user_username || s.user_public_id}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </Td>
                  <Td>{s.notify ? "On" : "Off"}</Td>
                  <Td className="max-w-xs truncate text-xs text-surface-muted">
                    {JSON.stringify(s.filters)}
                  </Td>
                  <Td className="text-surface-muted">{formatDate(s.created_at)}</Td>
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
