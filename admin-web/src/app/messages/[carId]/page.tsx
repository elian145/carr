"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchMessageThread } from "@/lib/api";
import { formatDate, listingTitle } from "@/lib/format";

export default function MessageThreadPage() {
  const params = useParams();
  const carId = String(params.carId || "");

  const { data, error, loading, reload } = useAsyncData(
    () => fetchMessageThread(carId),
    [carId],
  );

  return (
    <AsyncPageBody
      title="Message thread"
      description={carId}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <Link
          href="/messages"
          className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5"
        >
          ← Messages
        </Link>
      }
    >
      {(thread) => (
        <div className="space-y-6">
          <section className="rounded-xl border border-surface-border bg-surface-card p-4">
            <p className="text-xs text-surface-muted">Listing</p>
            <Link
              href={`/listings/${thread.car.id}`}
              className="text-lg font-medium text-brand-300 hover:underline"
            >
              {listingTitle(thread.car)}
            </Link>
            <p className="mt-1 text-sm text-surface-muted">
              {thread.count} message(s)
            </p>
          </section>
          <div className="space-y-3">
            {thread.messages.length === 0 ? (
              <p className="text-sm text-surface-muted">No messages</p>
            ) : (
              thread.messages.map((m) => (
                <div
                  key={m.id}
                  className="rounded-xl border border-surface-border bg-surface-card p-4"
                >
                  <div className="flex flex-wrap items-baseline justify-between gap-2">
                    <p className="text-sm">
                      <Link
                        href={`/users/${m.sender_id}`}
                        className="font-medium text-brand-300 hover:underline"
                      >
                        {m.sender_username || m.sender_id || "—"}
                      </Link>
                      <span className="text-surface-muted"> → </span>
                      <Link
                        href={`/users/${m.receiver_id}`}
                        className="text-brand-300 hover:underline"
                      >
                        {m.receiver_username || m.receiver_id || "—"}
                      </Link>
                    </p>
                    <p className="text-xs text-surface-muted">
                      {formatDate(m.created_at)}
                      {m.is_read ? " · read" : " · unread"}
                    </p>
                  </div>
                  <p className="mt-2 whitespace-pre-wrap text-sm">{m.content}</p>
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </AsyncPageBody>
  );
}
