"use client";

import { useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchNotifications } from "@/lib/api";
import { formatDate } from "@/lib/format";

export default function NotificationsPage() {
  const [page, setPage] = useState(1);

  const { data, error, loading, reload } = useAsyncData(
    () => fetchNotifications({ page, per_page: 50 }),
    [page],
  );

  return (
    <AsyncPageBody
      title="Notifications"
      description="In-app notifications sent to users"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(result) => (
        <>
          <DataTable empty={result.notifications.length === 0}>
            <thead>
              <tr>
                <Th>Title</Th>
                <Th>Type</Th>
                <Th>Message</Th>
                <Th>Read</Th>
                <Th>Sent</Th>
              </tr>
            </thead>
            <tbody>
              {result.notifications.map((n) => (
                <tr key={n.id}>
                  <Td className="font-medium">{n.title || "—"}</Td>
                  <Td className="text-surface-muted">{n.notification_type || "—"}</Td>
                  <Td className="max-w-md">
                    <p className="line-clamp-2 text-sm">{n.message || "—"}</p>
                  </Td>
                  <Td>
                    <span
                      className={`inline-flex rounded-full px-2 py-0.5 text-xs ${
                        n.is_read
                          ? "bg-surface-border text-surface-muted"
                          : "bg-brand-900/40 text-brand-200"
                      }`}
                    >
                      {n.is_read ? "Read" : "Unread"}
                    </span>
                  </Td>
                  <Td className="text-surface-muted">{formatDate(n.created_at)}</Td>
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
