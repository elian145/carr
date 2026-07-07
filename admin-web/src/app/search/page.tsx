"use client";

import Link from "next/link";
import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { globalSearch } from "@/lib/api";
import { displayName, formatPrice, listingTitle } from "@/lib/format";

function SearchPageInner() {
  const searchParams = useSearchParams();
  const q = (searchParams.get("q") || "").trim();

  const { data, error, loading, reload } = useAsyncData(
    () => (q ? globalSearch(q, 30) : Promise.resolve({ users: [], cars: [] })),
    [q],
  );

  return (
    <AsyncPageBody
      title="Search"
      description={q ? `Results for “${q}”` : "Use the search bar above"}
      data={data}
      error={error}
      loading={loading && !!q}
      reload={reload}
    >
      {(result) => (
        <div className="space-y-8">
          {!q ? (
            <p className="text-surface-muted">Type a name, phone, brand, listing ID, or location.</p>
          ) : null}

          <section>
            <h2 className="mb-3 text-lg font-medium">Users ({result.users.length})</h2>
            <DataTable empty={result.users.length === 0}>
              <thead>
                <tr>
                  <Th>Name</Th>
                  <Th>Phone</Th>
                  <Th>Email</Th>
                  <Th></Th>
                </tr>
              </thead>
              <tbody>
                {result.users.map((u) => (
                  <tr key={u.id}>
                    <Td>
                      <p className="font-medium">{displayName(u)}</p>
                      <p className="text-xs text-surface-muted">{u.username}</p>
                    </Td>
                    <Td>{u.phone_number || "—"}</Td>
                    <Td>{u.email || "—"}</Td>
                    <Td>
                      <Link href={`/users/${u.id}`} className="text-xs text-brand-400 hover:underline">
                        Open →
                      </Link>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </DataTable>
          </section>

          <section>
            <h2 className="mb-3 text-lg font-medium">Listings ({result.cars.length})</h2>
            <DataTable empty={result.cars.length === 0}>
              <thead>
                <tr>
                  <Th>Listing</Th>
                  <Th>Price</Th>
                  <Th>Location</Th>
                  <Th></Th>
                </tr>
              </thead>
              <tbody>
                {result.cars.map((c) => (
                  <tr key={c.id}>
                    <Td>
                      <p className="font-medium">{listingTitle(c)}</p>
                      <p className="text-xs text-surface-muted">{c.id}</p>
                    </Td>
                    <Td>{formatPrice(c.price)}</Td>
                    <Td>{c.location || "—"}</Td>
                    <Td>
                      <Link href={`/listings/${c.id}`} className="text-xs text-brand-400 hover:underline">
                        Open →
                      </Link>
                    </Td>
                  </tr>
                ))}
              </tbody>
            </DataTable>
          </section>
        </div>
      )}
    </AsyncPageBody>
  );
}

export default function SearchPage() {
  return (
    <Suspense fallback={<p className="text-surface-muted">Loading search…</p>}>
      <SearchPageInner />
    </Suspense>
  );
}
