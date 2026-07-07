import type { ReactNode } from "react";

export function StatCard({
  label,
  value,
  sub,
}: {
  label: string;
  value: string | number;
  sub?: string;
}) {
  return (
    <div className="rounded-xl border border-surface-border bg-surface-card p-5 shadow-sm">
      <p className="text-sm text-surface-muted">{label}</p>
      <p className="mt-2 text-3xl font-semibold tracking-tight">{value}</p>
      {sub ? <p className="mt-1 text-xs text-surface-muted">{sub}</p> : null}
    </div>
  );
}
