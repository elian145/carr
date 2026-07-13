/** Read a string query param with a fallback. */
export function paramString(
  params: URLSearchParams,
  key: string,
  fallback = "",
): string {
  return params.get(key) ?? fallback;
}

/** Read a positive integer page param (min 1). */
export function paramPage(params: URLSearchParams, key = "page"): number {
  const n = Number(params.get(key));
  return Number.isFinite(n) && n >= 1 ? Math.floor(n) : 1;
}

/** Read a boolean query param (`1`/`true` = true). */
export function paramBool(params: URLSearchParams, key: string): boolean {
  const v = (params.get(key) || "").toLowerCase();
  return v === "1" || v === "true" || v === "yes";
}

/**
 * Build a query string from a record, omitting empty / default values.
 * `defaults` values are omitted when equal (keeps URLs clean).
 */
export function buildUrlQuery(
  values: Record<string, string | number | boolean | undefined | null>,
  defaults: Record<string, string | number | boolean> = {},
): string {
  const params = new URLSearchParams();
  for (const [key, raw] of Object.entries(values)) {
    if (raw === undefined || raw === null || raw === "") continue;
    const str = typeof raw === "boolean" ? (raw ? "1" : "0") : String(raw);
    const def = defaults[key];
    if (def !== undefined) {
      const defStr =
        typeof def === "boolean" ? (def ? "1" : "0") : String(def);
      if (str === defStr) continue;
    }
    params.set(key, str);
  }
  const qs = params.toString();
  return qs ? `?${qs}` : "";
}
