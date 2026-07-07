"use client";

import Link from "next/link";
import { FormEvent, useState } from "react";
import { useRouter } from "next/navigation";

export function GlobalSearchBar() {
  const router = useRouter();
  const [q, setQ] = useState("");

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    const term = q.trim();
    if (!term) return;
    router.push(`/search?q=${encodeURIComponent(term)}`);
  }

  return (
    <form onSubmit={onSubmit} className="mb-6 flex gap-2">
      <input
        type="search"
        value={q}
        onChange={(e) => setQ(e.target.value)}
        placeholder="Search users, listings, phone, brand…"
        className="flex-1 rounded-lg border border-surface-border bg-black/30 px-4 py-2 text-sm"
      />
      <button
        type="submit"
        className="rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium hover:bg-brand-500"
      >
        Search
      </button>
      <Link
        href="/search"
        className="rounded-lg border border-surface-border px-3 py-2 text-sm text-surface-muted hover:bg-white/5"
      >
        Advanced
      </Link>
    </form>
  );
}
