"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "@/context/AuthContext";
import { displayName } from "@/lib/format";
import { NavBadge, NavTotalBadge, useNavBadges } from "@/components/NavBadges";
import { GlobalSearchBar } from "@/components/GlobalSearchBar";
import type { NavBadges } from "@/lib/api";

type NavItem = {
  href: string;
  label: string;
  totalKey?: keyof NavBadges;
  alertKey?: "pendingReports" | "pendingDealers";
};

const NAV: NavItem[] = [
  { href: "/dashboard", label: "Dashboard" },
  { href: "/search", label: "Search" },
  { href: "/insights", label: "Insights" },
  { href: "/analytics", label: "Engagement" },
  { href: "/users", label: "Users", totalKey: "users" },
  { href: "/listings", label: "Listings", totalKey: "listings" },
  { href: "/reports", label: "Reports", alertKey: "pendingReports" },
  {
    href: "/dealers",
    label: "Dealers",
    totalKey: "dealers",
    alertKey: "pendingDealers",
  },
  { href: "/messages", label: "Messages", totalKey: "messages" },
  { href: "/notifications", label: "Notifications", totalKey: "notifications" },
  { href: "/saved-searches", label: "Saved searches", totalKey: "savedSearches" },
  { href: "/audit", label: "Audit log", totalKey: "auditLog" },
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
          <p className="text-lg font-bold text-brand-400">CarNet</p>
          <p className="text-xs text-surface-muted">Admin dashboard</p>
        </div>
        <nav className="flex-1 space-y-1 p-3">
          {NAV.map((item) => {
            const active =
              pathname === item.href || pathname.startsWith(`${item.href}/`);
            const alertCount = item.alertKey ? badges[item.alertKey] : 0;
            const totalCount = item.totalKey ? badges[item.totalKey] : 0;
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`flex items-center gap-2 rounded-lg px-3 py-2 text-sm transition ${
                  active
                    ? "bg-brand-600/20 font-medium text-brand-300"
                    : "text-surface-muted hover:bg-white/5 hover:text-white"
                }`}
              >
                <span className="min-w-0 flex-1 truncate">{item.label}</span>
                {item.alertKey ? <NavBadge count={alertCount} /> : null}
                {item.totalKey ? <NavTotalBadge count={totalCount} /> : null}
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
      <main className="flex-1 overflow-auto p-6 lg:p-8">
        {pathname !== "/login" ? <GlobalSearchBar /> : null}
        {children}
      </main>
    </div>
  );
}
