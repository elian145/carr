import {
  LEGACY_AUTH_FLAG_COOKIE,
  LEGACY_TOKEN_STORAGE_KEY,
} from "./admin-session-constants";

/**
 * Browser calls go through the Next.js `/backend-api` rewrite (same-origin),
 * which proxies to the Flask API and avoids CORS failures.
 * Auth is an httpOnly cookie; middleware attaches Authorization for the proxy.
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

function scrubLegacyClientAuth(): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.removeItem(LEGACY_TOKEN_STORAGE_KEY);
  } catch {
    // ignore
  }
  try {
    document.cookie = `${LEGACY_AUTH_FLAG_COOKIE}=; Path=/; Max-Age=0; SameSite=Lax`;
  } catch {
    // ignore
  }
}

/** Create httpOnly admin session via Next route (JWT never stored in JS). */
export async function establishSession(
  username: string,
  password: string,
): Promise<unknown> {
  scrubLegacyClientAuth();
  const res = await fetch("/api/admin-session", {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    credentials: "same-origin",
    body: JSON.stringify({ username, password }),
  });
  const body = (await res.json().catch(() => ({}))) as {
    message?: string;
    user?: unknown;
  };
  if (!res.ok) {
    throw new ApiRequestError(body.message || `Login failed (${res.status})`, res.status);
  }
  return body.user;
}

/** Clear httpOnly admin session cookie. */
export async function clearSession(): Promise<void> {
  scrubLegacyClientAuth();
  try {
    await fetch("/api/admin-session", {
      method: "DELETE",
      credentials: "same-origin",
    });
  } catch {
    // Still clear local leftovers even if the route is unreachable.
  }
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
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string>),
  };

  const url = `${getApiBase()}${path.startsWith("/") ? path : `/${path}`}`;

  let res: Response;
  try {
    res = await fetch(url, {
      ...options,
      headers,
      credentials: "same-origin",
    });
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
  const headers: Record<string, string> = {};
  const url = `${getApiBase()}${path.startsWith("/") ? path : `/${path}`}`;
  const res = await fetch(url, { headers, credentials: "same-origin" });
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
