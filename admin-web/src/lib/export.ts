export function downloadCsv(filename: string, headers: string[], rows: string[][]): void {
  const escape = (cell: string) => {
    const s = String(cell ?? "");
    if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
    return s;
  };
  const lines = [
    headers.map(escape).join(","),
    ...rows.map((row) => row.map(escape).join(",")),
  ];
  const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export function listingPublicUrl(listingId: string): string {
  const base = (
    process.env.NEXT_PUBLIC_API_BASE || "http://localhost:5000"
  ).replace(/\/+$/, "");
  return `${base}/listing/${encodeURIComponent(listingId)}`;
}
