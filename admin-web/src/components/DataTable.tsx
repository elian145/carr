import type { ReactNode } from "react";

export function EmptyState({
  title = "No records found",
  description,
  action,
}: {
  title?: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="rounded-xl border border-dashed border-surface-border bg-surface-card/50 px-6 py-14 text-center">
      <p className="text-sm font-medium text-white">{title}</p>
      {description ? (
        <p className="mx-auto mt-2 max-w-md text-sm text-surface-muted">
          {description}
        </p>
      ) : null}
      {action ? <div className="mt-4 flex justify-center">{action}</div> : null}
    </div>
  );
}

export function DataTable({
  children,
  empty,
  emptyTitle,
  emptyDescription,
  emptyAction,
}: {
  children: ReactNode;
  empty?: boolean;
  emptyTitle?: string;
  emptyDescription?: string;
  emptyAction?: ReactNode;
}) {
  if (empty) {
    return (
      <EmptyState
        title={emptyTitle}
        description={emptyDescription}
        action={emptyAction}
      />
    );
  }

  return (
    <div className="overflow-hidden rounded-xl border border-surface-border bg-surface-card">
      <div className="overflow-x-auto">
        <table className="min-w-full text-left text-sm">{children}</table>
      </div>
    </div>
  );
}

export function Th({
  children,
  className = "",
}: {
  children?: ReactNode;
  className?: string;
}) {
  return (
    <th
      className={`whitespace-nowrap border-b border-surface-border bg-black/20 px-4 py-3 text-xs font-medium uppercase tracking-wide text-surface-muted ${className}`}
    >
      {children}
    </th>
  );
}

export function Td({
  children,
  className = "",
  colSpan,
}: {
  children: ReactNode;
  className?: string;
  colSpan?: number;
}) {
  return (
    <td
      colSpan={colSpan}
      className={`border-b border-surface-border/60 px-4 py-3 align-top ${className}`}
    >
      {children}
    </td>
  );
}
