"use client";

import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchUserActions } from "@/lib/api";
import { formatDate } from "@/lib/format";

export default function AuditPage() {
  const [page, setPage] = useState(1);
  const [actionType, setActionType] = useState("");
  const [query, setQuery] = useState("");

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchUserActions({
        page,
        per_page: 50,
        action_type: query || undefined,
      }),
    [page, query],
  );

  return (
    <AsyncPageBody
      title="Audit log"
      description="User action history across the platform"
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
            setQuery(actionType.trim());
          }}
        >
          <input
            type="search"
            value={actionType}
            onChange={(e) => setActionType(e.target.value)}
            placeholder="Filter by action type…"
            className="w-56 rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm"
          />
          <button
            type="submit"
            className="rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium hover:bg-brand-500"
          >
            Filter
          </button>
          {query ? (
            <button
              type="button"
              onClick={() => {
                setActionType("");
                setQuery("");
                setPage(1);
              }}
              className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5"
            >
              Clear
            </button>
          ) : null}
        </form>
      }
    >
      {(result) => (
        <>
          {query ? (
            <p className="mb-4 text-sm text-surface-muted">
              Showing actions matching <code className="text-brand-300">{query}</code>
            </p>
          ) : null}
          <DataTable empty={result.actions.length === 0}>
            <thead>
              <tr>
                <Th>Action</Th>
                <Th>Target</Th>
                <Th>When</Th>
              </tr>
            </thead>
            <tbody>
              {result.actions.map((a) => (
                <tr key={a.id}>
                  <Td className="font-medium">{a.action_type}</Td>
                  <Td className="text-surface-muted">
                    {a.target_type ? `${a.target_type}: ` : ""}
                    {a.target_id || "—"}
                  </Td>
                  <Td className="text-surface-muted">{formatDate(a.created_at)}</Td>
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
