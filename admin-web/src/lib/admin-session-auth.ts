import type { NextResponse } from "next/server";
import {
  ADMIN_JWT_COOKIE,
  ADMIN_REFRESH_COOKIE,
  ADMIN_SESSION_MAX_AGE_SEC,
  LEGACY_AUTH_FLAG_COOKIE,
} from "@/lib/admin-session-constants";
import { verifyAdminAccessJwt } from "@/lib/verify-admin-jwt";

export function apiUpstreamBase(): string {
  return (
    process.env.API_PROXY_TARGET ||
    process.env.NEXT_PUBLIC_API_BASE ||
    "http://localhost:5000"
  ).replace(/\/+$/, "");
}

export function cookieSecureFromRequest(request: Request): boolean {
  const proto = request.headers.get("x-forwarded-proto");
  if (proto) return proto.split(",")[0].trim() === "https";
  try {
    return new URL(request.url).protocol === "https:";
  } catch {
    return false;
  }
}

function jwtSecret(): string {
  return (process.env.JWT_SECRET_KEY || "").trim();
}

function requireSecretInProd(): boolean {
  const isProd =
    (process.env.NODE_ENV || "").trim() === "production" ||
    (process.env.APP_ENV || "").trim().toLowerCase() === "production";
  return isProd && !jwtSecret();
}

type CookieJar = {
  get: (name: string) => { value: string } | undefined;
};

export function clearLegacyCookiesOn(res: {
  cookies: { set: (name: string, value: string, opts: Record<string, unknown>) => void };
}): void {
  res.cookies.set(LEGACY_AUTH_FLAG_COOKIE, "", {
    httpOnly: false,
    path: "/",
    maxAge: 0,
    sameSite: "lax",
  });
}

export function setAdminSessionCookies(
  res: {
    cookies: { set: (name: string, value: string, opts: Record<string, unknown>) => void };
  },
  accessToken: string,
  refreshToken: string,
  secure: boolean,
): void {
  const common = {
    httpOnly: true,
    secure,
    sameSite: "lax" as const,
    path: "/",
    maxAge: ADMIN_SESSION_MAX_AGE_SEC,
  };
  res.cookies.set(ADMIN_JWT_COOKIE, accessToken, common);
  res.cookies.set(ADMIN_REFRESH_COOKIE, refreshToken, common);
  clearLegacyCookiesOn(res);
}

export function clearAdminSessionCookies(
  res: {
    cookies: { set: (name: string, value: string, opts: Record<string, unknown>) => void };
  },
  secure: boolean,
): void {
  const common = {
    httpOnly: true,
    secure,
    sameSite: "lax" as const,
    path: "/",
    maxAge: 0,
  };
  res.cookies.set(ADMIN_JWT_COOKIE, "", common);
  res.cookies.set(ADMIN_REFRESH_COOKIE, "", common);
  clearLegacyCookiesOn(res);
}

export async function refreshAccessWithRefreshToken(
  refreshToken: string,
): Promise<{ access: string; refresh: string } | null> {
  const rt = (refreshToken || "").trim();
  if (!rt) return null;
  let res: Response;
  try {
    res = await fetch(`${apiUpstreamBase()}/api/auth/refresh`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${rt}`,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    });
  } catch {
    return null;
  }
  if (!res.ok) return null;
  const body = (await res.json().catch(() => ({}))) as {
    access_token?: string;
    refresh_token?: string;
  };
  const access = (body.access_token || "").trim();
  const refresh = (body.refresh_token || "").trim() || rt;
  if (!access) return null;
  return { access, refresh };
}

/**
 * Resolve a valid access JWT from cookies, refreshing via refresh cookie when needed.
 * When tokens are rotated, ``onRotated`` receives the new pair so callers can Set-Cookie.
 */
export async function resolveAdminAccessToken(
  jar: CookieJar,
  onRotated?: (access: string, refresh: string) => void,
): Promise<string | null> {
  if (requireSecretInProd()) return null;
  const secret = jwtSecret();
  const accessRaw = jar.get(ADMIN_JWT_COOKIE)?.value || "";
  if (accessRaw) {
    const check = await verifyAdminAccessJwt(accessRaw, secret);
    if (check.ok) return accessRaw;
  }

  const refreshRaw = jar.get(ADMIN_REFRESH_COOKIE)?.value || "";
  if (!refreshRaw) return null;
  const rotated = await refreshAccessWithRefreshToken(refreshRaw);
  if (!rotated) return null;
  onRotated?.(rotated.access, rotated.refresh);
  return rotated.access;
}

/** Attach rotated cookies onto a NextResponse (middleware). */
export function attachRotatedCookies(
  res: NextResponse,
  access: string,
  refresh: string,
  secure: boolean,
): void {
  setAdminSessionCookies(res, access, refresh, secure);
}
