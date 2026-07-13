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
import { useAuth } from "@/context/AuthContext";
import {
  broadcastNotification,
  cancelScheduledNotification,
  fetchNotifications,
  fetchScheduledNotifications,
  processScheduledNotifications,
} from "@/lib/api";
import { getFilterMeta } from "@/lib/filterMeta";
import { formatDate } from "@/lib/format";
import { hasPermission } from "@/lib/permissions";

type Audience = "all" | "dealers" | "users" | "user";

function toLocalInputValue(d: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function localInputToIso(local: string): string {
  const d = new Date(local);
  return d.toISOString();
}

export default function NotificationsPage() {
  const toast = useToast();
  const { confirm } = useConfirm();
  const { user } = useAuth();
  const canBroadcast = hasPermission(user, "notifications.broadcast");
  const [page, setPage] = useState(1);
  const [typeFilter, setTypeFilter] = useState("all");
  const [readFilter, setReadFilter] = useState("all");
  const [types, setTypes] = useState<string[]>([]);

  const [title, setTitle] = useState("");
  const [message, setMessage] = useState("");
  const [audience, setAudience] = useState<Audience>("all");
  const [targetUserId, setTargetUserId] = useState("");
  const [sendPush, setSendPush] = useState(true);
  const [scheduleMode, setScheduleMode] = useState(false);
  const [scheduledAtLocal, setScheduledAtLocal] = useState(() => {
    const d = new Date();
    d.setHours(d.getHours() + 1, 0, 0, 0);
    return toLocalInputValue(d);
  });
  const [sending, setSending] = useState(false);
  const [schedBusy, setSchedBusy] = useState(false);

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

  const scheduled = useAsyncData(
    () => fetchScheduledNotifications({ per_page: 20, status: "all" }),
    [],
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

    let scheduledIso: string | undefined;
    if (scheduleMode) {
      if (!scheduledAtLocal) {
        toast.error("Pick a schedule time");
        return;
      }
      scheduledIso = localInputToIso(scheduledAtLocal);
      if (Number.isNaN(Date.parse(scheduledIso)) || Date.parse(scheduledIso) <= Date.now()) {
        toast.error("Schedule time must be in the future");
        return;
      }
    }

    const ok = await confirm({
      title: scheduleMode ? "Schedule notification?" : "Send notification?",
      description: scheduleMode
        ? `Will send to ${audienceLabel} at ${new Date(scheduledIso!).toLocaleString()}.`
        : `This will create in-app notifications for ${audienceLabel}${
            sendPush ? " and attempt FCM push where tokens exist" : ""
          }.`,
      confirmLabel: scheduleMode ? "Schedule" : "Send",
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
        scheduled_at: scheduledIso,
      });
      if (result.scheduled) {
        toast.success(result.message || "Notification scheduled");
        scheduled.reload();
      } else {
        toast.success(
          `${result.message}${
            result.push_configured
              ? ` · ${result.pushed} push delivered`
              : " · push not configured on server"
          }`,
        );
        reload();
        refreshNavBadges();
      }
      setTitle("");
      setMessage("");
      setTargetUserId("");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Broadcast failed");
    } finally {
      setSending(false);
    }
  }

  async function handleCancel(id: number) {
    const ok = await confirm({
      title: "Cancel scheduled notification?",
      description: "It will not be sent.",
      confirmLabel: "Cancel send",
      tone: "danger",
    });
    if (!ok) return;
    setSchedBusy(true);
    try {
      await cancelScheduledNotification(id);
      toast.success("Cancelled");
      scheduled.reload();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Cancel failed");
    } finally {
      setSchedBusy(false);
    }
  }

  async function handleProcessDue() {
    setSchedBusy(true);
    try {
      const r = await processScheduledNotifications();
      toast.success(`Processed ${r.processed} · sent ${r.sent} · failed ${r.failed}`);
      scheduled.reload();
      reload();
      refreshNavBadges();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Process failed");
    } finally {
      setSchedBusy(false);
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
          {canBroadcast ? (
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
            <div className="mt-4 flex flex-wrap items-end gap-3">
              <label className="flex items-center gap-2 text-sm text-surface-muted">
                <input
                  type="checkbox"
                  checked={scheduleMode}
                  onChange={(e) => setScheduleMode(e.target.checked)}
                />
                Schedule for later
              </label>
              {scheduleMode ? (
                <label className="flex flex-col gap-1 text-xs text-surface-muted">
                  <span>Send at (local time)</span>
                  <input
                    type="datetime-local"
                    value={scheduledAtLocal}
                    onChange={(e) => setScheduledAtLocal(e.target.value)}
                    className="rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm text-white"
                  />
                </label>
              ) : null}
            </div>
            <button
              type="button"
              disabled={sending}
              onClick={handleBroadcast}
              className="mt-4 rounded-lg bg-brand-600 px-4 py-2 text-sm hover:bg-brand-500 disabled:opacity-50"
            >
              {sending
                ? scheduleMode
                  ? "Scheduling…"
                  : "Sending…"
                : scheduleMode
                  ? "Schedule notification"
                  : "Send notification"}
            </button>
          </section>
          ) : null}

          {scheduled.data ? (
            <section className="mb-6 rounded-xl border border-surface-border bg-surface-card p-4">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div>
                  <h2 className="text-sm font-medium">Scheduled</h2>
                  <p className="mt-1 text-xs text-surface-muted">
                    Due items send via Celery beat, or when this list refreshes / Process due.
                  </p>
                </div>
                {canBroadcast ? (
                  <button
                    type="button"
                    disabled={schedBusy}
                    onClick={() => void handleProcessDue()}
                    className="rounded-lg border border-surface-border px-3 py-1.5 text-xs hover:bg-white/5 disabled:opacity-50"
                  >
                    Process due now
                  </button>
                ) : null}
              </div>
              {scheduled.data.scheduled.length === 0 ? (
                <p className="mt-3 text-sm text-surface-muted">No scheduled notifications</p>
              ) : (
                <div className="mt-3 overflow-x-auto">
                  <table className="w-full text-left text-sm">
                    <thead>
                      <tr className="text-xs text-surface-muted">
                        <th className="py-1 pr-2">When</th>
                        <th className="py-1 pr-2">Title</th>
                        <th className="py-1 pr-2">Audience</th>
                        <th className="py-1 pr-2">Status</th>
                        <th className="py-1"> </th>
                      </tr>
                    </thead>
                    <tbody>
                      {scheduled.data.scheduled.map((s) => (
                        <tr key={s.id} className="border-t border-surface-border/60">
                          <td className="py-2 pr-2 whitespace-nowrap">
                            {formatDate(s.scheduled_at)}
                          </td>
                          <td className="py-2 pr-2">{s.title}</td>
                          <td className="py-2 pr-2 text-surface-muted">{s.audience}</td>
                          <td className="py-2 pr-2 capitalize">{s.status}</td>
                          <td className="py-2">
                            {canBroadcast && s.status === "pending" ? (
                              <button
                                type="button"
                                disabled={schedBusy}
                                onClick={() => void handleCancel(s.id)}
                                className="text-xs text-red-300 hover:underline disabled:opacity-50"
                              >
                                Cancel
                              </button>
                            ) : null}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
          ) : null}

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
