export function formatDate(value?: string | null): string {
  if (!value) return "—";
  try {
    return new Date(value).toLocaleString();
  } catch {
    return value;
  }
}

export function formatNumber(value?: number | null): string {
  if (value == null) return "—";
  return new Intl.NumberFormat().format(value);
}

export function formatPrice(
  value?: number | null,
  currency?: string | null,
): string {
  if (value == null) return "—";
  const code = (currency || "USD").trim().toUpperCase() || "USD";
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: code,
      maximumFractionDigits: 0,
    }).format(value);
  } catch {
    return `${formatNumber(value)} ${code}`;
  }
}

export function formatMileage(value?: number | null): string {
  if (value == null) return "—";
  return `${formatNumber(value)} km`;
}

export function mediaUrl(path?: string | null): string {
  if (!path) return "";
  if (/^https?:\/\//i.test(path)) return path;
  const base = (process.env.NEXT_PUBLIC_API_BASE || "").replace(/\/+$/, "");
  if (path.startsWith("/")) return `${base}${path}`;
  return `${base}/${path}`;
}

export function dash(value?: string | number | null): string {
  if (value == null) return "—";
  const s = String(value).trim();
  return s || "—";
}

export function displayName(user: {
  first_name?: string;
  last_name?: string;
  username?: string;
  email?: string;
  phone_number?: string;
}): string {
  const full = [user.first_name, user.last_name].filter(Boolean).join(" ");
  return full || user.username || user.email || user.phone_number || "—";
}

export function listingTitle(car: {
  title?: string;
  brand?: string;
  model?: string;
  year?: number;
}): string {
  if (car.title?.trim()) return car.title;
  const parts = [car.brand, car.model, car.year ? `(${car.year})` : ""]
    .filter(Boolean)
    .join(" ");
  return parts || "—";
}
