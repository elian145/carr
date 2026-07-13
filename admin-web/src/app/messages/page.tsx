"use client";

import Link from "next/link";
import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchMessages } from "@/lib/api";
import { formatDate } from "@/lib/format";

function partyLabel(name?: string, username?: string, id?: string) {
  const n = (name || "").trim();
  if (n) return n;
  if (username) return `@${username}`;
  return id || "—";
}

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
              <span>Search content</span>
              <input
                type="search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onKeyDown={(e) =>
                  e.key === "Enter" && (setPage(1), setQuery(search.trim()))
                }
                className="w-56 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
            <label className="flex flex-col gap-1 text-xs text-surface-muted">
              <span>Listing ID</span>
              <input
                type="text"
                value={carFilter}
                onChange={(e) => {
                  setCarFilter(e.target.value);
                  setPage(1);
                }}
                placeholder="Car public id"
                className="w-40 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
            <FilterSelect
              label="Read"
              value={readFilter}
              onChange={(v) => {
                setReadFilter(v);
                setPage(1);
              }}
              options={[
                { value: "all", label: "All" },
                { value: "read", label: "Read" },
                { value: "unread", label: "Unread" },
              ]}
            />
            <button
              type="button"
              onClick={() => {
                setPage(1);
                setQuery(search.trim());
              }}
              className="rounded-lg bg-brand-600 px-4 py-2 text-sm"
            >
              Search
            </button>
          </div>

          <DataTable empty={result.messages.length === 0}>
            <thead>
              <tr>
                <Th>Content</Th>
                <Th>From</Th>
                <Th>To</Th>
                <Th>Listing</Th>
                <Th>Read</Th>
                <Th>Sent</Th>
              </tr>
            </thead>
            <tbody>
              {result.messages.map((m) => (
                <tr key={m.id} className="hover:bg-white/[0.02]">
                  <Td className="max-w-md">
                    <p className="line-clamp-3">
                      {(m.content || "").trim() || "—"}
                    </p>
                    <p className="mt-1 text-xs text-surface-muted">
                      {m.message_type || "text"}
                    </p>
                  </Td>
                  <Td>
                    {m.sender_id ? (
                      <Link
                        href={`/users/${m.sender_id}`}
                        className="text-sm text-brand-300 hover:underline"
                      >
                        {partyLabel(
                          m.sender_name,
                          m.sender_username,
                          m.sender_id,
                        )}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </Td>
                  <Td>
                    {m.receiver_id ? (
                      <Link
                        href={`/users/${m.receiver_id}`}
                        className="text-sm text-brand-300 hover:underline"
                      >
                        {partyLabel(
                          m.receiver_name,
                          m.receiver_username,
                          m.receiver_id,
                        )}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </Td>
                  <Td>
                    {m.car_id ? (
                      <Link
                        href={`/listings/${m.car_id}`}
                        className="text-xs text-brand-400 hover:underline"
                        title={m.car_id}
                      >
                        View listing →
                      </Link>
                    ) : (
                      "—"
                    )}
                  </Td>
                  <Td>{m.is_read ? "Yes" : "No"}</Td>
                  <Td className="text-surface-muted">
                    {formatDate(m.created_at)}
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
