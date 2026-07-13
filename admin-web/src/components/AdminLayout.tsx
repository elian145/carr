"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
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
  { href: "/system", label: "System" },
];

function SidebarNav({
  pathname,
  badges,
  onNavigate,
}: {
  pathname: string;
  badges: NavBadges;
  onNavigate?: () => void;
}) {
  return (
    <nav className="flex-1 space-y-1 overflow-y-auto p-3">
      {NAV.map((item) => {
        const active =
          pathname === item.href || pathname.startsWith(`${item.href}/`);
        const alertCount = item.alertKey ? badges[item.alertKey] : 0;
        const totalCount = item.totalKey ? badges[item.totalKey] : 0;
        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={onNavigate}
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
  );
}

export function AdminLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { user, loading, logout } = useAuth();
  const badges = useNavBadges();
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    setMobileOpen(false);
  }, [pathname]);

  useEffect(() => {
    if (!mobileOpen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setMobileOpen(false);
    };
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [mobileOpen]);

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

  const sidebarBody = (
    <>
      <div className="border-b border-surface-border px-5 py-5">
        <p className="text-lg font-bold text-brand-400">CarNet</p>
        <p className="text-xs text-surface-muted">Admin dashboard</p>
      </div>
      <SidebarNav
        pathname={pathname}
        badges={badges}
        onNavigate={() => setMobileOpen(false)}
      />
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
    </>
  );

  return (
    <div className="flex min-h-screen">
      {/* Desktop sidebar */}
      <aside className="hidden w-60 shrink-0 flex-col border-r border-surface-border bg-black/30 lg:flex">
        {sidebarBody}
      </aside>

      {/* Mobile drawer */}
      {mobileOpen ? (
        <div className="fixed inset-0 z-50 lg:hidden" role="presentation">
          <button
            type="button"
            aria-label="Close menu"
            className="absolute inset-0 bg-black/60"
            onClick={() => setMobileOpen(false)}
          />
          <aside
            className="absolute inset-y-0 left-0 flex w-[min(100%,16rem)] flex-col border-r border-surface-border bg-surface shadow-xl"
            role="dialog"
            aria-modal="true"
            aria-label="Navigation"
          >
            <div className="flex items-center justify-between border-b border-surface-border px-4 py-3">
              <p className="font-semibold text-brand-400">Menu</p>
              <button
                type="button"
                onClick={() => setMobileOpen(false)}
                className="rounded-lg border border-surface-border px-2.5 py-1.5 text-sm text-surface-muted hover:bg-white/5"
              >
                Close
              </button>
            </div>
            <SidebarNav
              pathname={pathname}
              badges={badges}
              onNavigate={() => setMobileOpen(false)}
            />
            <div className="mt-auto border-t border-surface-border p-4">
              <p className="truncate text-sm font-medium">{displayName(user)}</p>
              <button
                type="button"
                onClick={logout}
                className="mt-3 w-full rounded-lg border border-surface-border px-3 py-2 text-sm text-surface-muted hover:bg-white/5 hover:text-white"
              >
                Sign out
              </button>
            </div>
          </aside>
        </div>
      ) : null}

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex items-center gap-3 border-b border-surface-border bg-surface/95 px-4 py-3 backdrop-blur lg:hidden">
          <button
            type="button"
            aria-label="Open menu"
            aria-expanded={mobileOpen}
            onClick={() => setMobileOpen(true)}
            className="rounded-lg border border-surface-border px-3 py-2 text-sm hover:bg-white/5"
          >
            Menu
          </button>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold text-brand-400">CarNet Admin</p>
          </div>
        </header>
        <main className="flex-1 overflow-auto p-4 sm:p-6 lg:p-8">
          {pathname !== "/login" ? <GlobalSearchBar /> : null}
          {children}
        </main>
      </div>
    </div>
  );
}
