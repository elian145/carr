"use client";

import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/context/AuthContext";
import { fetchNavBadges, type NavBadges } from "@/lib/api";
import { getToken } from "@/lib/auth";
import { formatNumber } from "@/lib/format";

const EMPTY_BADGES: NavBadges = {
  pendingReports: 0,
  pendingDealers: 0,
  users: 0,
  listings: 0,
  dealers: 0,
  messages: 0,
  notifications: 0,
  savedSearches: 0,
  auditLog: 0,
};

const REFRESH_EVENT = "carnet-nav-badges-refresh";

/** Call after moderation actions so sidebar counts stay current. */
export function refreshNavBadges() {
  if (typeof window !== "undefined") {
    window.dispatchEvent(new Event(REFRESH_EVENT));
  }
}

export function useNavBadges() {
  const { user } = useAuth();
  const [badges, setBadges] = useState<NavBadges>(EMPTY_BADGES);
  const [tick, setTick] = useState(0);

  const load = useCallback(() => {
    if (!user || !getToken()) {
      setBadges(EMPTY_BADGES);
      return () => {};
    }

    let cancelled = false;
    fetchNavBadges()
      .then((b) => {
        if (!cancelled) setBadges(b);
      })
      .catch(() => {
        if (!cancelled) setBadges(EMPTY_BADGES);
      });
    return () => {
      cancelled = true;
    };
  }, [user]);

  useEffect(() => {
    return load();
  }, [load, tick]);

  useEffect(() => {
    const onRefresh = () => setTick((t) => t + 1);
    window.addEventListener(REFRESH_EVENT, onRefresh);
    return () => window.removeEventListener(REFRESH_EVENT, onRefresh);
  }, []);

  return badges;
}

/** Pending attention pill (reports / dealer applications). */
export function NavBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span className="ml-auto inline-flex min-w-5 items-center justify-center rounded-full bg-brand-600 px-1.5 py-0.5 text-xs font-medium text-white">
      {count > 99 ? "99+" : count}
    </span>
  );
}

/** Quieter total count for entity nav items. */
export function NavTotalBadge({ count }: { count: number }) {
  return (
    <span className="ml-auto inline-flex min-w-5 items-center justify-center rounded-full border border-surface-border bg-white/5 px-1.5 py-0.5 text-xs font-medium text-surface-muted">
      {count > 9999 ? "9999+" : formatNumber(count)}
    </span>
  );
}
