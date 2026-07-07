import { formatNumber } from "@/lib/format";

export function ActionBarChart({
  items,
}: {
  items: { action_type: string; count: number }[];
}) {
  const sorted = [...items].sort((a, b) => b.count - a.count).slice(0, 10);
  const max = sorted[0]?.count || 1;

  if (sorted.length === 0) {
    return (
      <p className="text-sm text-surface-muted">No action data yet.</p>
    );
  }

  return (
    <div className="space-y-3">
      {sorted.map((row) => (
        <div key={row.action_type}>
          <div className="mb-1 flex justify-between text-sm">
            <span className="text-surface-muted">{row.action_type}</span>
            <span className="font-medium">{formatNumber(row.count)}</span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-black/30">
            <div
              className="h-full rounded-full bg-brand-500 transition-all"
              style={{ width: `${Math.max(4, (row.count / max) * 100)}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
