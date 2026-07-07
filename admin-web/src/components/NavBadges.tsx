"use client";

import { useEffect, useState } from "react";
import { fetchNavBadges } from "@/lib/api";

export function useNavBadges() {
  const [badges, setBadges] = useState({ pendingReports: 0, pendingDealers: 0 });

  useEffect(() => {
    let cancelled = false;
    fetchNavBadges()
      .then((b) => {
        if (!cancelled) setBadges(b);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  return badges;
}

export function NavBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span className="ml-auto inline-flex min-w-5 items-center justify-center rounded-full bg-brand-600 px-1.5 py-0.5 text-xs font-medium text-white">
      {count > 99 ? "99+" : count}
    </span>
  );
}
