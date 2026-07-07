"use client";

import Link from "next/link";
import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchUsers } from "@/lib/api";
import { downloadCsv } from "@/lib/export";
import { displayName, formatDate } from "@/lib/format";

export default function UsersPage() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");

  const { data, error, loading, reload } = useAsyncData(
    () => fetchUsers({ page, per_page: 20, search: query || undefined }),
    [page, query],
  );

  return (
    <AsyncPageBody
      title="Users"
      description="Search and browse registered accounts"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <>
          <button
            type="button"
            disabled={!data?.users.length}
            onClick={() => {
              if (!data) return;
              downloadCsv(
                `carzo-users-page-${page}.csv`,
                ["Name", "Username", "Email", "Phone", "Type", "Active", "Admin", "Joined"],
                data.users.map((u) => [
                  displayName(u),
                  u.username || "",
                  u.email || "",
                  u.phone_number || "",
                  u.account_type || "user",
                  u.is_active ? "yes" : "no",
                  u.is_admin ? "yes" : "no",
                  u.created_at || "",
                ]),
              );
            }}
            className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5 disabled:opacity-40"
          >
            Export CSV
          </button>
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
              placeholder="Search name, email, username…"
              className="w-64 rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm"
            />
            <button
              type="submit"
              className="rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium hover:bg-brand-500"
            >
              Search
            </button>
          </form>
        </>
      }
    >
      {(result) => (
        <>
          <DataTable empty={result.users.length === 0}>
            <thead>
              <tr>
                <Th>Name</Th>
                <Th>Contact</Th>
                <Th>Type</Th>
                <Th>Status</Th>
                <Th>Admin</Th>
                <Th>Joined</Th>
                <Th></Th>
              </tr>
            </thead>
            <tbody>
              {result.users.map((u) => (
                <tr key={u.id} className="hover:bg-white/[0.02]">
                  <Td>
                    <Link
                      href={`/users/${u.id}`}
                      className="font-medium text-brand-300 hover:underline"
                    >
                      {displayName(u)}
                    </Link>
                    <p className="text-xs text-surface-muted">{u.username}</p>
                  </Td>
                  <Td className="text-surface-muted">
                    <p>{u.email || "—"}</p>
                    <p className="text-xs">{u.phone_number || ""}</p>
                  </Td>
                  <Td>
                    {u.account_type || "user"}
                    {u.dealer_status && u.dealer_status !== "none" ? (
                      <span className="ml-1 text-xs text-surface-muted">
                        ({u.dealer_status})
                      </span>
                    ) : null}
                  </Td>
                  <Td>
                    <span
                      className={`inline-flex rounded-full px-2 py-0.5 text-xs ${
                        u.is_active
                          ? "bg-emerald-900/40 text-emerald-300"
                          : "bg-red-900/40 text-red-300"
                      }`}
                    >
                      {u.is_active ? "Active" : "Inactive"}
                    </span>
                  </Td>
                  <Td>{u.is_admin ? "Yes" : "—"}</Td>
                  <Td className="text-surface-muted">{formatDate(u.created_at)}</Td>
                  <Td>
                    <Link
                      href={`/users/${u.id}`}
                      className="text-xs text-brand-400 hover:underline"
                    >
                      Details →
                    </Link>
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
