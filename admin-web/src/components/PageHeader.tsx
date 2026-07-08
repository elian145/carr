import type { ReactNode } from "react";
import { formatNumber } from "@/lib/format";

export function PageHeader({
  title,
  description,
  actions,
  count,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
  count?: number | null;
}) {
  return (
    <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <h1 className="flex flex-wrap items-center gap-2 text-2xl font-semibold tracking-tight">
          <span>{title}</span>
          {count != null ? (
            <span className="rounded-full border border-surface-border bg-white/5 px-2.5 py-0.5 text-sm font-medium text-surface-muted">
              {formatNumber(count)}
            </span>
          ) : null}
        </h1>
        {description ? (
          <p className="mt-1 text-sm text-surface-muted">{description}</p>
        ) : null}
      </div>
      {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
    </div>
  );
}
