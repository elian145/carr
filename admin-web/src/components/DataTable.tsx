import type { ReactNode } from "react";

export function DataTable({
  children,
  empty,
}: {
  children: ReactNode;
  empty?: boolean;
}) {
  if (empty) {
    return (
      <div className="rounded-xl border border-dashed border-surface-border bg-surface-card/50 px-6 py-16 text-center text-surface-muted">
        No records found
      </div>
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

export function Th({ children, className = "" }: { children?: ReactNode; className?: string }) {
  return (
    <th
      className={`whitespace-nowrap border-b border-surface-border bg-black/20 px-4 py-3 text-xs font-medium uppercase tracking-wide text-surface-muted ${className}`}
    >
      {children}
    </th>
  );
}

export function Td({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <td className={`border-b border-surface-border/60 px-4 py-3 align-top ${className}`}>
      {children}
    </td>
  );
}
