"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { getFilterMeta } from "@/lib/filterMeta";
import { fetchUserActions } from "@/lib/api";
import { formatDate } from "@/lib/format";

export default function AuditPage() {
  const [page, setPage] = useState(1);
  const [actionType, setActionType] = useState("");
  const [query, setQuery] = useState("");
  const [targetType, setTargetType] = useState("all");
  const [scope, setScope] = useState<"all" | "admin" | "user">("all");
  const [userId, setUserId] = useState("");
  const [actionTypes, setActionTypes] = useState<string[]>([]);

  useEffect(() => {
    getFilterMeta()
      .then((m) => setActionTypes(m.action_types))
      .catch(() => {});
  }, []);

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchUserActions({
        page,
        per_page: 50,
        action_type: query || undefined,
        target_type: targetType !== "all" ? targetType : undefined,
        user_id: userId.trim() || undefined,
        scope,
      }),
    [page, query, targetType, userId, scope],
  );

  return (
    <AsyncPageBody
      title="Audit log"
      description="Platform action history — filter admin moderation events separately"
      count={data?.pagination.total}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(result) => (
        <>
          <div className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-surface-border bg-surface-card/50 p-4">
            <FilterSelect
              label="Scope"
              value={scope}
              onChange={(v) => {
                setScope(v as "all" | "admin" | "user");
                setPage(1);
              }}
              options={[
                { value: "all", label: "All actions" },
                { value: "admin", label: "Admin / dealer ops" },
                { value: "user", label: "End-user only" },
              ]}
            />
            <FilterSelect
              label="Action type"
              value={actionType || "all"}
              onChange={(v) => {
                setActionType(v);
                setPage(1);
                setQuery(v === "all" ? "" : v);
              }}
              options={[
                { value: "all", label: "All types" },
                ...actionTypes.map((t) => ({ value: t, label: t })),
              ]}
            />
            <FilterSelect
              label="Target type"
              value={targetType}
              onChange={(v) => {
                setTargetType(v);
                setPage(1);
              }}
              options={[
                { value: "all", label: "All targets" },
                { value: "car", label: "car" },
                { value: "user", label: "user" },
                { value: "message", label: "message" },
                { value: "notification", label: "notification" },
              ]}
            />
            <label className="flex flex-col gap-1 text-xs text-surface-muted">
              <span>User ID</span>
              <input
                type="text"
                value={userId}
                onChange={(e) => {
                  setUserId(e.target.value);
                  setPage(1);
                }}
                placeholder="User public id"
                className="w-44 rounded-lg border border-surface-border bg-black/30 px-3 py-1.5 text-sm"
              />
            </label>
          </div>

          <DataTable empty={result.actions.length === 0}>
            <thead>
              <tr>
                <Th>Action</Th>
                <Th>User</Th>
                <Th>Target</Th>
                <Th>When</Th>
              </tr>
            </thead>
            <tbody>
              {result.actions.map((a) => (
                <tr key={a.id}>
                  <Td className="font-medium">{a.action_type}</Td>
                  <Td>
                    {a.user_public_id ? (
                      <Link
                        href={`/users/${a.user_public_id}`}
                        className="text-brand-300 hover:underline"
                      >
                        {a.user_username || a.user_public_id}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </Td>
                  <Td className="text-surface-muted">
                    {a.target_type ? `${a.target_type}: ` : ""}
                    {a.target_id || "—"}
                  </Td>
                  <Td className="text-surface-muted">
                    {formatDate(a.created_at)}
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
