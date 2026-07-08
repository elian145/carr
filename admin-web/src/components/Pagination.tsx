import type { Pagination as PaginationType } from "@/lib/types";
import { formatNumber } from "@/lib/format";

export function Pagination({
  pagination,
  onPageChange,
}: {
  pagination: PaginationType;
  onPageChange: (page: number) => void;
}) {
  if (pagination.pages <= 1) {
    return (
      <div className="mt-4 text-sm text-surface-muted">
        {formatNumber(pagination.total)} total
      </div>
    );
  }

  return (
    <div className="mt-4 flex items-center justify-between text-sm text-surface-muted">
      <span>
        Page {pagination.page} of {pagination.pages} ({formatNumber(pagination.total)} total)
      </span>
      <div className="flex gap-2">
        <button
          type="button"
          disabled={!pagination.has_prev}
          onClick={() => onPageChange(pagination.page - 1)}
          className="rounded-lg border border-surface-border px-3 py-1.5 disabled:opacity-40 hover:bg-white/5"
        >
          Previous
        </button>
        <button
          type="button"
          disabled={!pagination.has_next}
          onClick={() => onPageChange(pagination.page + 1)}
          className="rounded-lg border border-surface-border px-3 py-1.5 disabled:opacity-40 hover:bg-white/5"
        >
          Next
        </button>
      </div>
    </div>
  );
}
