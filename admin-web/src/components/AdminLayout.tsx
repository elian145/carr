"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "@/context/AuthContext";
import { displayName } from "@/lib/format";
import { NavBadge, useNavBadges } from "@/components/NavBadges";

const NAV = [
  { href: "/dashboard", label: "Dashboard", badgeKey: null },
  { href: "/users", label: "Users", badgeKey: null },
  { href: "/listings", label: "Listings", badgeKey: null },
  { href: "/reports", label: "Reports", badgeKey: "pendingReports" as const },
  { href: "/dealers", label: "Dealers", badgeKey: "pendingDealers" as const },
  { href: "/messages", label: "Messages", badgeKey: null },
  { href: "/notifications", label: "Notifications", badgeKey: null },
  { href: "/audit", label: "Audit log", badgeKey: null },
];

export function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { user, loading, logout } = useAuth();
  const badges = useNavBadges();

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center">
        <p className="text-surface-muted">Loading…</p>
      </div>
    );
  }

  if (!user) {
    return <>{children}</>;
  }

  return (
    <div className="flex min-h-screen">
      <aside className="flex w-60 shrink-0 flex-col border-r border-surface-border bg-black/30">
        <div className="border-b border-surface-border px-5 py-5">
          <p className="text-lg font-bold text-brand-400">CARZO</p>
          <p className="text-xs text-surface-muted">Admin dashboard</p>
        </div>
        <nav className="flex-1 space-y-1 p-3">
          {NAV.map((item) => {
            const active =
              pathname === item.href || pathname.startsWith(`${item.href}/`);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`flex items-center rounded-lg px-3 py-2 text-sm transition ${
                  active
                    ? "bg-brand-600/20 font-medium text-brand-300"
                    : "text-surface-muted hover:bg-white/5 hover:text-white"
                }`}
              >
                <span>{item.label}</span>
                {item.badgeKey ? (
                  <NavBadge count={badges[item.badgeKey]} />
                ) : null}
              </Link>
            );
          })}
        </nav>
        <div className="border-t border-surface-border p-4">
          <p className="truncate text-sm font-medium">{displayName(user)}</p>
          <p className="truncate text-xs text-surface-muted">
            {user.email || user.phone_number || user.username}
          </p>
          <button
            type="button"
            onClick={logout}
            className="mt-3 w-full rounded-lg border border-surface-border px-3 py-2 text-sm text-surface-muted hover:bg-white/5 hover:text-white"
          >
            Sign out
          </button>
        </div>
      </aside>
      <main className="flex-1 overflow-auto p-6 lg:p-8">{children}</main>
    </div>
  );
}
