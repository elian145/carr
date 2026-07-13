import { getPublicApiBase } from "./auth";

export function downloadCsv(filename: string, headers: string[], rows: string[][]): void {
  const escape = (cell: string) => {
    const s = String(cell ?? "");
    if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
    return s;
  };
  const lines = [
    headers.map(escape).join(","),
    ...rows.map((row) => row.map(escape).join(",")),
    "",
  ];
  const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/**
 * Fetch all pages for a filtered list and download as CSV.
 * Caps at `maxRows` to avoid locking the browser on huge datasets.
 */
export async function exportAllPagesCsv<T>(options: {
  filename: string;
  headers: string[];
  mapRow: (item: T) => string[];
  fetchPage: (
    page: number,
    perPage: number,
  ) => Promise<{ items: T[]; pagination: { page: number; pages: number; total: number } }>;
  maxRows?: number;
  perPage?: number;
  onProgress?: (loaded: number, total: number) => void;
}): Promise<number> {
  const perPage = options.perPage ?? 100;
  const maxRows = options.maxRows ?? 5000;
  const rows: string[][] = [];
  let page = 1;
  let total = 0;
  let pages = 1;

  while (page <= pages && rows.length < maxRows) {
    const result = await options.fetchPage(page, perPage);
    total = result.pagination.total;
    pages = Math.max(1, result.pagination.pages);
    for (const item of result.items) {
      rows.push(options.mapRow(item));
      if (rows.length >= maxRows) break;
    }
    options.onProgress?.(rows.length, Math.min(total, maxRows));
    if (result.items.length === 0) break;
    page += 1;
  }

  downloadCsv(options.filename, options.headers, rows);
  return rows.length;
}

export function listingPublicUrl(listingId: string): string {
  return `${getPublicApiBase()}/listing/${encodeURIComponent(listingId)}`;
}
