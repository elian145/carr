"use client";

import { useEffect, useState } from "react";
import { PageHeader } from "@/components/PageHeader";
import { RefreshButton } from "@/components/RefreshButton";

export function LoadingBlock({ label = "Loading…" }: { label?: string }) {
  return (
    <div
      className="space-y-4"
      role="status"
      aria-live="polite"
      aria-label={label}
    >
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            className="h-24 animate-pulse rounded-xl border border-surface-border bg-surface-card"
          />
        ))}
      </div>
      <div className="h-64 animate-pulse rounded-xl border border-surface-border bg-surface-card" />
      <p className="text-center text-sm text-surface-muted">{label}</p>
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
    <div
      className="rounded-xl border border-red-900/50 bg-red-950/30 px-6 py-8"
      role="alert"
    >
      <p className="font-medium text-red-300">Something went wrong</p>
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
  count,
  data,
  error,
  loading,
  reload,
  children,
}: {
  title: string;
  description?: string;
  actions?: React.ReactNode;
  count?: number | null;
  data: T | null;
  error: string | null;
  loading: boolean;
  reload: () => void;
  children: (data: T) => React.ReactNode;
}) {
  const showInitialSkeleton = loading && !data;
  const showError = !loading && error && !data;
  const showStaleError = Boolean(error && data);

  return (
    <>
      <PageHeader
        title={title}
        description={description}
        count={count}
        actions={
          <>
            <RefreshButton onClick={reload} />
            {actions}
          </>
        }
      />
      {showInitialSkeleton ? <LoadingBlock /> : null}
      {showError ? <ErrorBlock message={error!} onRetry={reload} /> : null}
      {showStaleError ? (
        <div className="mb-4 rounded-lg border border-amber-800/40 bg-amber-950/30 px-3 py-2 text-sm text-amber-100">
          Refresh failed: {error}. Showing last loaded data.{" "}
          <button
            type="button"
            onClick={reload}
            className="underline hover:text-white"
          >
            Retry
          </button>
        </div>
      ) : null}
      {data ? (
        <div className={loading ? "opacity-70 transition-opacity" : undefined}>
          {children(data)}
        </div>
      ) : null}
    </>
  );
}
