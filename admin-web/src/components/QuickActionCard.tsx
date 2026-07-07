import Link from "next/link";

export function QuickActionCard({
  title,
  count,
  description,
  href,
  tone = "brand",
}: {
  title: string;
  count: number;
  description: string;
  href: string;
  tone?: "brand" | "warning" | "danger";
}) {
  const tones = {
    brand: "border-brand-700/40 bg-brand-950/30 hover:bg-brand-950/50",
    warning: "border-amber-700/40 bg-amber-950/20 hover:bg-amber-950/40",
    danger: "border-red-800/40 bg-red-950/20 hover:bg-red-950/40",
  };

  return (
    <Link
      href={href}
      className={`block rounded-xl border p-5 transition ${tones[tone]}`}
    >
      <p className="text-sm text-surface-muted">{title}</p>
      <p className="mt-2 text-3xl font-semibold">{count}</p>
      <p className="mt-1 text-xs text-surface-muted">{description}</p>
    </Link>
  );
}
