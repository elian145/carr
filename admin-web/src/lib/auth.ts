const TOKEN_KEY = "carzo_admin_token";

export function getApiBase(): string {
  const base = (process.env.NEXT_PUBLIC_API_BASE || "http://localhost:5000").trim();
  return base.replace(/\/+$/, "");
}

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY);
}

export class ApiRequestError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "ApiRequestError";
    this.status = status;
  }
}

export async function apiRequest<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const token = getToken();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string>),
  };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const url = `${getApiBase()}${path.startsWith("/") ? path : `/${path}`}`;
  const res = await fetch(url, { ...options, headers });

  let body: unknown = null;
  const text = await res.text();
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = { message: text };
    }
  }

  if (!res.ok) {
    const msg =
      (body as { message?: string })?.message ||
      `Request failed (${res.status})`;
    throw new ApiRequestError(msg, res.status);
  }

  return body as T;
}
