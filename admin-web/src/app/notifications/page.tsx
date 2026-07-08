"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchFilterMeta, fetchNotifications } from "@/lib/api";
import { formatDate } from "@/lib/format";

export default function NotificationsPage() {
  const [page, setPage] = useState(1);
  const [typeFilter, setTypeFilter] = useState("all");
  const [readFilter, setReadFilter] = useState("all");
  const [types, setTypes] = useState<string[]>([]);

  useEffect(() => {
    fetchFilterMeta()
      .then((m) => setTypes(m.notification_types))
      .catch(() => {});
  }, []);

  const { data, error, loading, reload } = useAsyncData(
    () =>
      fetchNotifications({
        page,
        per_page: 50,
        type: typeFilter !== "all" ? typeFilter : undefined,
        is_read: readFilter === "all" ? undefined : readFilter === "read",
      }),
    [page, typeFilter, readFilter],
  );

  return (
    <AsyncPageBody
      title="Notifications"
      description="In-app notifications sent to users"
      count={data?.pagination.total}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <div className="flex flex-wrap gap-2">
          <FilterSelect
            label="Type"
            value={typeFilter}
            onChange={(v) => { setTypeFilter(v); setPage(1); }}
            options={[{ value: "all", label: "All types" }, ...types.map((t) => ({ value: t, label: t }))]}
          />
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
        </div>
      }
    >
      {(result) => (
        <>
          <DataTable empty={result.notifications.length === 0}>
            <thead>
              <tr>
                <Th>Title</Th>
                <Th>User</Th>
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
                  <Td>
                    {n.user_public_id ? (
                      <Link href={`/users/${n.user_public_id}`} className="text-brand-300 hover:underline">
                        {n.user_username || n.user_public_id}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </Td>
                  <Td className="text-surface-muted">{n.notification_type || "—"}</Td>
                  <Td className="max-w-md">
                    <p className="line-clamp-2 text-sm">{n.message || "—"}</p>
                  </Td>
                  <Td>{n.is_read ? "Read" : "Unread"}</Td>
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
