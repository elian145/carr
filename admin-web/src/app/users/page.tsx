"use client";

import Link from "next/link";
import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchUsers } from "@/lib/api";
import { downloadCsv } from "@/lib/export";
import { displayName, formatDate } from "@/lib/format";

export default function UsersPage() {
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [accountType, setAccountType] = useState("all");
  const [dealerStatus, setDealerStatus] = useState("all");
  const [activeFilter, setActiveFilter] = useState("all");
  const [adminFilter, setAdminFilter] = useState("all");

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchUsers({
        page,
        per_page: 20,
        search: query || undefined,
        account_type: accountType !== "all" ? accountType : undefined,
        dealer_status: dealerStatus !== "all" ? dealerStatus : undefined,
        is_active: activeFilter === "all" ? undefined : activeFilter === "active",
        is_admin: adminFilter === "all" ? undefined : adminFilter === "yes",
      }),
    [page, query, accountType, dealerStatus, activeFilter, adminFilter],
  );

  return (
    <AsyncPageBody
      title="Users"
      description="Search and filter all accounts"
      count={data?.pagination.total}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <button
          type="button"
          disabled={!data?.users.length}
          onClick={() => {
            if (!data) return;
            downloadCsv(
              `carnet-users-page-${page}.csv`,
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
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    setPage(1);
                    setQuery(search.trim());
                  }
                }}
                placeholder="Name, email, phone, username…"
                className="w-56 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
            <FilterSelect
              label="Account"
              value={accountType}
              onChange={(v) => { setAccountType(v); setPage(1); }}
              options={[
                { value: "all", label: "All" },
                { value: "user", label: "User" },
                { value: "dealer", label: "Dealer" },
              ]}
            />
            <FilterSelect
              label="Dealer status"
              value={dealerStatus}
              onChange={(v) => { setDealerStatus(v); setPage(1); }}
              options={[
                { value: "all", label: "All" },
                { value: "none", label: "None" },
                { value: "pending", label: "Pending" },
                { value: "approved", label: "Approved" },
                { value: "rejected", label: "Rejected" },
              ]}
            />
            <FilterSelect
              label="Active"
              value={activeFilter}
              onChange={(v) => { setActiveFilter(v); setPage(1); }}
              options={[
                { value: "all", label: "All" },
                { value: "active", label: "Active" },
                { value: "inactive", label: "Inactive" },
              ]}
            />
            <FilterSelect
              label="Admin"
              value={adminFilter}
              onChange={(v) => { setAdminFilter(v); setPage(1); }}
              options={[
                { value: "all", label: "All" },
                { value: "yes", label: "Admins" },
                { value: "no", label: "Non-admins" },
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
                    <Link href={`/users/${u.id}`} className="font-medium text-brand-300 hover:underline">
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
                    {u.dealer_status && u.dealer_status !== "none" ? ` (${u.dealer_status})` : ""}
                  </Td>
                  <Td>{u.is_active ? "Active" : "Inactive"}</Td>
                  <Td>{u.is_admin ? "Yes" : "—"}</Td>
                  <Td className="text-surface-muted">{formatDate(u.created_at)}</Td>
                  <Td>
                    <Link href={`/users/${u.id}`} className="text-xs text-brand-400 hover:underline">
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
