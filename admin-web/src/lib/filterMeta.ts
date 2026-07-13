/** In-memory cache for admin filter metadata (brands, statuses, etc.). */

import { fetchFilterMeta as fetchFilterMetaApi } from "./api";
import type { FilterMeta } from "./types";

const TTL_MS = 5 * 60 * 1000;

let cached: FilterMeta | null = null;
let cachedAt = 0;
let inflight: Promise<FilterMeta> | null = null;

export async function getFilterMeta(force = false): Promise<FilterMeta> {
  const fresh = cached && Date.now() - cachedAt < TTL_MS;
  if (!force && fresh && cached) return cached;
  if (!force && inflight) return inflight;

  inflight = fetchFilterMetaApi()
    .then((meta) => {
      cached = meta;
      cachedAt = Date.now();
      return meta;
    })
    .finally(() => {
      inflight = null;
    });

  return inflight;
}

export function clearFilterMetaCache() {
  cached = null;
  cachedAt = 0;
}
