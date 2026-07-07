export function RefreshButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-lg border border-surface-border px-3 py-2 text-sm text-surface-muted hover:bg-white/5 hover:text-white"
    >
      Refresh
    </button>
  );
}
