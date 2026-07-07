"use client";

import Link from "next/link";
import { StatCard } from "@/components/StatCard";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchAnalyticsOverview } from "@/lib/api";
import { formatNumber, listingTitle } from "@/lib/format";

export default function AnalyticsPage() {
  const { data, error, loading, reload } = useAsyncData(fetchAnalyticsOverview, []);

  return (
    <AsyncPageBody
      title="Engagement"
      description="Platform-wide listing analytics"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(overview) => (
        <div className="space-y-8">
          <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <StatCard label="Total views" value={formatNumber(overview.totals.views)} />
            <StatCard label="Messages" value={formatNumber(overview.totals.messages)} />
            <StatCard label="Calls" value={formatNumber(overview.totals.calls)} />
            <StatCard label="Shares" value={formatNumber(overview.totals.shares)} />
            <StatCard label="Favorites" value={formatNumber(overview.totals.favorites)} />
            <StatCard
              label="Tracked listings"
              value={formatNumber(overview.totals.tracked_listings)}
            />
          </div>

          <section>
            <h2 className="mb-3 text-lg font-medium">Top listings by views</h2>
            <DataTable empty={overview.top_listings.length === 0}>
              <thead>
                <tr>
                  <Th>Listing</Th>
                  <Th>Views</Th>
                  <Th>Messages</Th>
                  <Th>Calls</Th>
                  <Th>Favorites</Th>
                  <Th></Th>
                </tr>
              </thead>
              <tbody>
                {overview.top_listings.map((row) => (
                  <tr key={row.listing_id || `${row.brand}-${row.model}`}>
                    <Td className="font-medium">{listingTitle(row)}</Td>
                    <Td>{formatNumber(row.views)}</Td>
                    <Td>{formatNumber(row.messages)}</Td>
                    <Td>{formatNumber(row.calls)}</Td>
                    <Td>{formatNumber(row.favorites)}</Td>
                    <Td>
                      {row.listing_id ? (
                        <Link
                          href={`/listings/${row.listing_id}`}
                          className="text-xs text-brand-400 hover:underline"
                        >
                          Open →
                        </Link>
                      ) : null}
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
