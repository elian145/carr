"use client";

import Link from "next/link";
import { Suspense } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { DataTable, Td, Th } from "@/components/DataTable";
import { Pagination } from "@/components/Pagination";
import { FilterSelect } from "@/components/FilterSelect";
import { AsyncPageBody, useAsyncData } from "@/components/AsyncPage";
import { fetchListingRevisions } from "@/lib/api";
import { formatDate, formatPrice } from "@/lib/format";
import { buildUrlQuery, paramPage, paramString } from "@/lib/urlParams";

function ListingEditsInner() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const page = paramPage(searchParams);
  const status = paramString(searchParams, "status", "pending") as
    | "pending"
    | "rejected"
    | "all";

  const { data, error, loading, reload } = useAsyncData(
    () => fetchListingRevisions({ page, per_page: 20, status }),
    [page, status],
  );

  function replace(patch: Record<string, string | number | undefined>) {
    router.replace(
      `${pathname}${buildUrlQuery(
        { status: status !== "pending" ? status : undefined, ...patch },
        { page: 1 },
      )}`,
    );
  }

  return (
    <AsyncPageBody
      title="Listing edits"
      description="Seller edits to already-published listings. The public keeps seeing the approved version until you approve."
      count={data?.pagination.total}
      data={data}
      error={error}
      loading={loading}
      reload={reload}
    >
      {(result) => (
        <>
          <div className="mb-4 flex flex-wrap items-end gap-3 rounded-xl border border-surface-border bg-surface-card/50 p-4">
            <FilterSelect
              label="Status"
              value={status}
              onChange={(v) =>
                replace({ status: v === "pending" ? undefined : v, page: undefined })
              }
              options={[
                { value: "pending", label: "Awaiting review" },
                { value: "rejected", label: "Rejected" },
                { value: "all", label: "All" },
              ]}
            />
          </div>
          <DataTable
            empty={result.revisions.length === 0}
            emptyTitle="No pending edits"
            emptyDescription="Edits submitted by sellers for published listings appear here."
          >
            <thead>
              <tr>
                <Th>Listing</Th>
                <Th>Seller</Th>
                <Th>Current price</Th>
                <Th>Changed</Th>
                <Th>Status</Th>
                <Th>Submitted</Th>
                <Th></Th>
              </tr>
            </thead>
            <tbody>
              {result.revisions.map((r) => (
                <tr key={r.id} className="hover:bg-white/[0.02]">
                  <Td>
                    <p className="font-medium">
                      {r.listing?.title ||
                        [r.listing?.brand, r.listing?.model, r.listing?.year]
                          .filter(Boolean)
                          .join(" ")}
                    </p>
                    <p className="text-xs text-surface-muted">{r.listing?.id}</p>
                  </Td>
                  <Td className="text-surface-muted">
                    {r.listing?.seller?.username || "—"}
                  </Td>
                  <Td>
                    {formatPrice(r.listing?.price ?? null, r.listing?.currency)}
                  </Td>
                  <Td className="max-w-xs text-sm text-surface-muted">
                    {r.changed_fields.join(", ") || "—"}
                    {r.media && !r.media.ready ? (
                      <span className="ml-2 text-xs text-amber-400">
                        media processing ({r.media.in_flight})
                      </span>
                    ) : null}
                    {r.media && r.media.failed > 0 ? (
                      <span className="ml-2 text-xs text-red-400">
                        {r.media.failed} photo(s) failed
                      </span>
                    ) : null}
                  </Td>
                  <Td>{r.status}</Td>
                  <Td className="text-surface-muted">
                    {formatDate(r.submitted_at)}
                  </Td>
                  <Td>
                    <Link
                      href={`/listing-edits/${r.id}`}
                      className="text-brand-300 hover:underline"
                    >
                      Review
                    </Link>
                  </Td>
                </tr>
              ))}
            </tbody>
          </DataTable>
          <Pagination
            pagination={result.pagination}
            onPageChange={(p) => replace({ page: p > 1 ? p : undefined })}
          />
        </>
      )}
    </AsyncPageBody>
  );
}

export default function ListingEditsPage() {
  return (
    <Suspense fallback={<p className="text-surface-muted">Loading edits…</p>}>
      <ListingEditsInner />
    </Suspense>
  );
}
