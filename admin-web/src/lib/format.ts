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

export function formatPrice(value?: number | null): string {
  if (value == null) return "—";
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 0,
  }).format(value);
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
