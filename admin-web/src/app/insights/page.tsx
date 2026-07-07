"use client";

import { useState } from "react";
import Link from "next/link";
import { TrendChart } from "@/components/TrendChart";
import { DataTable, Td, Th } from "@/components/DataTable";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchInsights } from "@/lib/api";
import { formatNumber } from "@/lib/format";

export default function InsightsPage() {
  const [days, setDays] = useState(14);
  const { data, error, loading, reload } = useAsyncData(
    () => fetchInsights(days),
    [days],
  );

  return (
    <AsyncPageBody
      title="Insights"
      description="Trends and marketplace demand signals"
      data={data}
      error={error}
      loading={loading}
      reload={reload}
      actions={
        <select
          value={days}
          onChange={(e) => setDays(Number(e.target.value))}
          className="rounded-lg border border-surface-border bg-black/30 px-3 py-2 text-sm"
        >
          <option value={7}>Last 7 days</option>
          <option value={14}>Last 14 days</option>
          <option value={30}>Last 30 days</option>
          <option value={90}>Last 90 days</option>
        </select>
      }
    >
      {(insights) => (
        <div className="space-y-8">
          <div className="grid gap-4 lg:grid-cols-3">
            <TrendChart title="New signups" series={insights.signups_by_day} />
            <TrendChart title="New listings" series={insights.listings_by_day} />
            <TrendChart title="Messages sent" series={insights.messages_by_day} />
          </div>

          <div className="grid gap-6 lg:grid-cols-2">
            <section>
              <h2 className="mb-3 text-lg font-medium">Top brands</h2>
              <DataTable empty={insights.top_brands.length === 0}>
                <thead>
                  <tr>
                    <Th>Brand</Th>
                    <Th>Listings</Th>
                  </tr>
                </thead>
                <tbody>
                  {insights.top_brands.map((row) => (
                    <tr key={row.brand}>
                      <Td>
                        <Link
                          href={`/listings?brand=${encodeURIComponent(row.brand)}`}
                          className="text-brand-300 hover:underline"
                        >
                          {row.brand}
                        </Link>
                      </Td>
                      <Td>{formatNumber(row.count)}</Td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>
            </section>

            <section>
              <h2 className="mb-3 text-lg font-medium">Top locations</h2>
              <DataTable empty={insights.top_locations.length === 0}>
                <thead>
                  <tr>
                    <Th>Location</Th>
                    <Th>Listings</Th>
                  </tr>
                </thead>
                <tbody>
                  {insights.top_locations.map((row) => (
                    <tr key={row.location}>
                      <Td>{row.location}</Td>
                      <Td>{formatNumber(row.count)}</Td>
                    </tr>
                  ))}
                </tbody>
              </DataTable>
            </section>
          </div>
        </div>
      )}
    </AsyncPageBody>
  );
}
