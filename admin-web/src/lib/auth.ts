const TOKEN_KEY = "carzo_admin_token";
const AUTH_COOKIE = "carzo_admin_auth";

/**
 * Browser calls go through the Next.js `/backend-api` rewrite (same-origin),
 * which proxies to the Flask API and avoids CORS failures.
 * Server-side / tooling can still use NEXT_PUBLIC_API_BASE directly.
 */
export function getApiBase(): string {
  if (typeof window !== "undefined") {
    return "/backend-api";
  }
  const base = (process.env.NEXT_PUBLIC_API_BASE || "http://localhost:5000").trim();
  return base.replace(/\/+$/, "");
}

/** Absolute Flask origin for public listing links (not the proxy). */
export function getPublicApiBase(): string {
  const base = (process.env.NEXT_PUBLIC_API_BASE || "http://localhost:5000").trim();
  return base.replace(/\/+$/, "");
}

function setAuthCookie(present: boolean): void {
  if (typeof document === "undefined") return;
  if (present) {
    // Flag cookie for Next middleware route protection (JWT stays in localStorage for API Bearer).
    const secure =
      typeof window !== "undefined" && window.location.protocol === "https:"
        ? "; Secure"
        : "";
    document.cookie = `${AUTH_COOKIE}=1; Path=/; SameSite=Lax; Max-Age=${60 * 60 * 24 * 14}${secure}`;
  } else {
    document.cookie = `${AUTH_COOKIE}=; Path=/; Max-Age=0; SameSite=Lax`;
  }
}

export function getToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token);
  setAuthCookie(true);
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY);
  setAuthCookie(false);
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

  let res: Response;
  try {
    res = await fetch(url, { ...options, headers });
  } catch {
    throw new ApiRequestError(
      `Cannot reach API via ${url}. Is the Flask server running, and is NEXT_PUBLIC_API_BASE / API_PROXY_TARGET correct?`,
      0,
    );
  }

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

export async function apiBlobRequest(path: string): Promise<Blob> {
  const token = getToken();
  const headers: Record<string, string> = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  const url = `${getApiBase()}${path.startsWith("/") ? path : `/${path}`}`;
  const res = await fetch(url, { headers });
  if (!res.ok) {
    let message = `Request failed (${res.status})`;
    try {
      const body = (await res.json()) as { message?: string };
      if (body.message) message = body.message;
    } catch {
      // Keep the status-based fallback for non-JSON responses.
    }
    throw new ApiRequestError(message, res.status);
  }
  return res.blob();
}
