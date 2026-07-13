"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { refreshNavBadges } from "@/components/NavBadges";
import { useConfirm } from "@/context/ConfirmContext";
import { useToast } from "@/context/ToastContext";
import { broadcastNotification, fetchNotifications } from "@/lib/api";
import { getFilterMeta } from "@/lib/filterMeta";
import { formatDate } from "@/lib/format";

type Audience = "all" | "dealers" | "users" | "user";

export default function NotificationsPage() {
  const toast = useToast();
  const { confirm } = useConfirm();
  const [page, setPage] = useState(1);
  const [typeFilter, setTypeFilter] = useState("all");
  const [readFilter, setReadFilter] = useState("all");
  const [types, setTypes] = useState<string[]>([]);

  const [title, setTitle] = useState("");
  const [message, setMessage] = useState("");
  const [audience, setAudience] = useState<Audience>("all");
  const [targetUserId, setTargetUserId] = useState("");
  const [sendPush, setSendPush] = useState(true);
  const [sending, setSending] = useState(false);

  useEffect(() => {
    getFilterMeta()
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

  async function handleBroadcast() {
    const t = title.trim();
    const m = message.trim();
    if (!t || !m) {
      toast.error("Title and message are required");
      return;
    }
    if (audience === "user" && !targetUserId.trim()) {
      toast.error("Enter a target user public id");
      return;
    }

    const audienceLabel =
      audience === "all"
        ? "all active users"
        : audience === "dealers"
          ? "active dealers"
          : audience === "users"
            ? "active non-dealer users"
            : `user ${targetUserId.trim()}`;

    const ok = await confirm({
      title: "Send notification?",
      description: `This will create in-app notifications for ${audienceLabel}${
        sendPush ? " and attempt FCM push where tokens exist" : ""
      }.`,
      confirmLabel: "Send",
      tone: "brand",
    });
    if (!ok) return;

    setSending(true);
    try {
      const result = await broadcastNotification({
        title: t,
        message: m,
        audience,
        target_user_id: audience === "user" ? targetUserId.trim() : undefined,
        notification_type: "admin",
        send_push: sendPush,
      });
      toast.success(
        `${result.message}${
          result.push_configured
            ? ` · ${result.pushed} push delivered`
            : " · push not configured on server"
        }`,
      );
      setTitle("");
      setMessage("");
      setTargetUserId("");
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Broadcast failed");
    } finally {
      setSending(false);
    }
  }

  return (
    <AsyncPageBody
      title="Notifications"
      description="Broadcast and review in-app notifications"
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
            onChange={(v) => {
              setTypeFilter(v);
              setPage(1);
            }}
            options={[
              { value: "all", label: "All types" },
              ...types.map((t) => ({ value: t, label: t })),
            ]}
          />
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
        </div>
      }
    >
      {(result) => (
        <>
          <section className="mb-6 rounded-xl border border-surface-border bg-surface-card p-4">
            <h2 className="text-sm font-medium">Broadcast notification</h2>
            <p className="mt-1 text-xs text-surface-muted">
              Creates in-app notifications. Push is best-effort when FCM is configured.
            </p>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              <label className="flex flex-col gap-1 text-xs text-surface-muted sm:col-span-2">
                <span>Title</span>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  maxLength={200}
                  className="rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm text-white"
                  placeholder="Announcement title"
                />
              </label>
              <label className="flex flex-col gap-1 text-xs text-surface-muted sm:col-span-2">
                <span>Message</span>
                <textarea
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  rows={3}
                  className="rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm text-white"
                  placeholder="Message body shown in the app"
                />
              </label>
              <FilterSelect
                label="Audience"
                value={audience}
                onChange={(v) => setAudience(v as Audience)}
                options={[
                  { value: "all", label: "All active users" },
                  { value: "dealers", label: "Dealers only" },
                  { value: "users", label: "Non-dealers only" },
                  { value: "user", label: "Single user" },
                ]}
              />
              {audience === "user" ? (
                <label className="flex flex-col gap-1 text-xs text-surface-muted">
                  <span>User public id</span>
                  <input
                    type="text"
                    value={targetUserId}
                    onChange={(e) => setTargetUserId(e.target.value)}
                    className="rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm text-white"
                    placeholder="User public id"
                  />
                </label>
              ) : (
                <label className="flex items-end gap-2 pb-2 text-sm text-surface-muted">
                  <input
                    type="checkbox"
                    checked={sendPush}
                    onChange={(e) => setSendPush(e.target.checked)}
                  />
                  Also send FCM push
                </label>
              )}
            </div>
            {audience === "user" ? (
              <label className="mt-3 flex items-center gap-2 text-sm text-surface-muted">
                <input
                  type="checkbox"
                  checked={sendPush}
                  onChange={(e) => setSendPush(e.target.checked)}
                />
                Also send FCM push
              </label>
            ) : null}
            <button
              type="button"
              disabled={sending}
              onClick={handleBroadcast}
              className="mt-4 rounded-lg bg-brand-600 px-4 py-2 text-sm hover:bg-brand-500 disabled:opacity-50"
            >
              {sending ? "Sending…" : "Send notification"}
            </button>
          </section>

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
                      <Link
                        href={`/users/${n.user_public_id}`}
                        className="text-brand-300 hover:underline"
                      >
                        {n.user_username || n.user_public_id}
                      </Link>
                    ) : (
                      "—"
                    )}
                  </Td>
                  <Td className="text-surface-muted">
                    {n.notification_type || "—"}
                  </Td>
                  <Td className="max-w-md">
                    <p className="line-clamp-2 text-sm">{n.message || "—"}</p>
                  </Td>
                  <Td>{n.is_read ? "Read" : "Unread"}</Td>
                  <Td className="text-surface-muted">
                    {formatDate(n.created_at)}
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
