"use client";

import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchMessages } from "@/lib/api";
import { formatDate } from "@/lib/format";

export default function MessagesPage() {
  const [page, setPage] = useState(1);

  const { data, error, loading, reload } = useAsyncData(
    () => fetchMessages({ page, per_page: 50 }),
    [page],
  );

  return (
    <AsyncPageBody
      title="Messages"
      description="Recent chat messages across the platform"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(result) => (
        <>
          <DataTable empty={result.messages.length === 0}>
            <thead>
              <tr>
                <Th>Content</Th>
                <Th>Listing</Th>
                <Th>Sent</Th>
              </tr>
            </thead>
            <tbody>
              {result.messages.map((m) => (
                <tr key={m.id}>
                  <Td className="max-w-md">
                    <p className="line-clamp-3">{(m.content || "").trim() || "—"}</p>
                  </Td>
                  <Td className="text-xs text-surface-muted">{m.car_id || "—"}</Td>
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
