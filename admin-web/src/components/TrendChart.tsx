import { formatNumber } from "@/lib/format";

export function TrendChart({
  title,
  series,
}: {
  title: string;
  series: { day: string; count: number }[];
}) {
  const max = Math.max(...series.map((s) => s.count), 1);

  return (
    <div className="rounded-xl border border-surface-border bg-surface-card p-4">
      <h3 className="mb-3 text-sm font-medium text-surface-muted">{title}</h3>
      {series.length === 0 ? (
        <p className="text-sm text-surface-muted">No data</p>
      ) : (
        <div className="flex h-32 items-end gap-1">
          {series.map((point) => (
            <div
              key={point.day}
              className="group relative flex flex-1 flex-col items-center justify-end"
              title={`${point.day}: ${point.count}`}
            >
              <div
                className="w-full min-w-[4px] rounded-t bg-brand-500/80 group-hover:bg-brand-400"
                style={{
                  height: `${Math.max(4, (point.count / max) * 100)}%`,
                }}
              />
              <span className="mt-1 hidden text-[10px] text-surface-muted lg:block">
                {point.day.slice(5)}
              </span>
            </div>
          ))}
        </div>
      )}
      <p className="mt-2 text-xs text-surface-muted">
        Total: {formatNumber(series.reduce((s, p) => s + p.count, 0))}
      </p>
    </div>
  );
}
