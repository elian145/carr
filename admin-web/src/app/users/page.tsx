"use client";

import Link from "next/link";
import { Suspense, useEffect, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchUsers, type UserListParams } from "@/lib/api";
import { exportAllPagesCsv } from "@/lib/export";
import { displayName, formatDate } from "@/lib/format";
import { roleLabel } from "@/lib/permissions";
import type { User } from "@/lib/types";
import { useToast } from "@/context/ToastContext";
import {
  buildUrlQuery,
  paramPage,
  paramString,
} from "@/lib/urlParams";

function UsersPageInner() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const toast = useToast();

  const page = paramPage(searchParams);
  const query = paramString(searchParams, "q");
  const accountType = paramString(searchParams, "account_type", "all");
  const dealerStatus = paramString(searchParams, "dealer_status", "all");
  const activeFilter = paramString(searchParams, "active", "all");
  const adminFilter = paramString(searchParams, "admin", "all");

  const [search, setSearch] = useState(query);
  const [exporting, setExporting] = useState(false);

  useEffect(() => {
    setSearch(query);
  }, [query]);

  function replaceFilters(
    patch: Record<string, string | number | boolean | undefined | null>,
    resetPage = true,
  ) {
    const next = {
      q: query || undefined,
      account_type: accountType !== "all" ? accountType : undefined,
      dealer_status: dealerStatus !== "all" ? dealerStatus : undefined,
      active: activeFilter !== "all" ? activeFilter : undefined,
      admin: adminFilter !== "all" ? adminFilter : undefined,
      page: resetPage ? undefined : page > 1 ? page : undefined,
      ...patch,
    };
    router.replace(
      `${pathname}${buildUrlQuery(next, {
        account_type: "all",
        dealer_status: "all",
        active: "all",
        admin: "all",
        page: 1,
      })}`,
    );
  }

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

  const listParams: UserListParams = {
    search: query || undefined,
    account_type: accountType !== "all" ? accountType : undefined,
    dealer_status: dealerStatus !== "all" ? dealerStatus : undefined,
    is_active: activeFilter === "all" ? undefined : activeFilter === "active",
    is_admin: adminFilter === "all" ? undefined : adminFilter === "yes",
  };

  async function handleExportAll() {
    setExporting(true);
    try {
      const count = await exportAllPagesCsv<User>({
        filename: `carnet-users-${new Date().toISOString().slice(0, 10)}.csv`,
        headers: [
          "Name",
          "Username",
          "Email",
          "Phone",
          "Type",
          "Active",
          "Admin",
          "Joined",
        ],
        mapRow: (u) => [
          displayName(u),
          u.username || "",
          u.email || "",
          u.phone_number || "",
          u.account_type || "user",
          u.is_active ? "yes" : "no",
          u.is_admin ? "yes" : "no",
          u.created_at || "",
        ],
        fetchPage: async (p, perPage) => {
          const res = await fetchUsers({
            page: p,
            per_page: perPage,
            ...listParams,
          });
          return { items: res.users, pagination: res.pagination };
        },
      });
      toast.success(`Exported ${count} user(s)`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Export failed");
    } finally {
      setExporting(false);
    }
  }

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
          disabled={exporting || !data?.users.length}
          onClick={handleExportAll}
          className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5 disabled:opacity-40"
        >
          {exporting ? "Exporting…" : "Export CSV"}
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
                    replaceFilters({ q: search.trim() || undefined });
                  }
                }}
                placeholder="Name, email, phone, username…"
                className="w-56 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
            <FilterSelect
              label="Account"
              value={accountType}
              onChange={(v) =>
                replaceFilters({ account_type: v === "all" ? undefined : v })
              }
              options={[
                { value: "all", label: "All" },
                { value: "user", label: "User" },
                { value: "dealer", label: "Dealer" },
              ]}
            />
            <FilterSelect
              label="Dealer status"
              value={dealerStatus}
              onChange={(v) =>
                replaceFilters({ dealer_status: v === "all" ? undefined : v })
              }
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
              onChange={(v) =>
                replaceFilters({ active: v === "all" ? undefined : v })
              }
              options={[
                { value: "all", label: "All" },
                { value: "active", label: "Active" },
                { value: "inactive", label: "Inactive" },
              ]}
            />
            <FilterSelect
              label="Admin"
              value={adminFilter}
              onChange={(v) =>
                replaceFilters({ admin: v === "all" ? undefined : v })
              }
              options={[
                { value: "all", label: "All" },
                { value: "yes", label: "Admins" },
                { value: "no", label: "Non-admins" },
              ]}
            />
            <button
              type="button"
              onClick={() => replaceFilters({ q: search.trim() || undefined })}
              className="rounded-lg bg-brand-600 px-4 py-2 text-sm"
            >
              Search
            </button>
          </div>

          <DataTable
            empty={result.users.length === 0}
            emptyTitle="No users found"
            emptyDescription="Adjust search or account filters and try again."
          >
            <thead>
              <tr>
                <Th>Name</Th>
                <Th>Contact</Th>
                <Th>Type</Th>
                <Th>Status</Th>
                <Th>Role</Th>
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
                    {u.dealer_status && u.dealer_status !== "none"
                      ? ` (${u.dealer_status})`
                      : ""}
                  </Td>
                  <Td>{u.is_active ? "Active" : "Inactive"}</Td>
                  <Td>
                    {u.is_admin ? roleLabel(u.admin_role) : "—"}
                  </Td>
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

export default function UsersPage() {
  return (
    <Suspense fallback={<p className="text-surface-muted">Loading users…</p>}>
      <UsersPageInner />
    </Suspense>
  );
}
