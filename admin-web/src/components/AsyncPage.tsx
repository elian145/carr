"use client";

import { useEffect, useState } from "react";
import { PageHeader } from "@/components/PageHeader";
import { RefreshButton } from "@/components/RefreshButton";

export function LoadingBlock({ label = "Loading…" }: { label?: string }) {
  return (
    <div className="rounded-xl border border-surface-border bg-surface-card px-6 py-16 text-center text-surface-muted">
      {label}
    </div>
  );
}

export function ErrorBlock({
  message,
  onRetry,
}: {
  message: string;
  onRetry?: () => void;
}) {
  return (
    <div className="rounded-xl border border-red-900/50 bg-red-950/30 px-6 py-8">
      <p className="font-medium text-red-300">Error</p>
      <p className="mt-2 text-sm text-red-200/80">{message}</p>
      {onRetry ? (
        <button
          type="button"
          onClick={onRetry}
          className="mt-4 rounded-lg bg-red-900/40 px-4 py-2 text-sm hover:bg-red-900/60"
        >
          Retry
        </button>
      ) : null}
    </div>
  );
}

export function useAsyncData<T>(
  loader: () => Promise<T>,
  deps: unknown[] = [],
) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    loader()
      .then((result) => {
        if (!cancelled) setData(result);
      })
      .catch((e: unknown) => {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : "Failed to load");
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tick, ...deps]);

  return {
    data,
    error,
    loading,
    reload: () => setTick((t) => t + 1),
  };
}

export function AsyncPageBody<T>({
  title,
  description,
  actions,
  data,
  error,
  loading,
  reload,
  children,
}: {
  title: string;
  description?: string;
  actions?: React.ReactNode;
  data: T | null;
  error: string | null;
  loading: boolean;
  reload: () => void;
  children: (data: T) => React.ReactNode;
}) {
  return (
    <>
      <PageHeader
        title={title}
        description={description}
        actions={
          <>
            <RefreshButton onClick={reload} />
            {actions}
          </>
        }
      />
      {loading ? <LoadingBlock /> : null}
      {!loading && error ? <ErrorBlock message={error} onRetry={reload} /> : null}
      {!loading && !error && data ? children(data) : null}
    </>
  );
}
