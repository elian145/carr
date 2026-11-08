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

function isProductionRuntime(): boolean {
  return (
    (process.env.NODE_ENV || "").trim() === "production" ||
    (process.env.APP_ENV || "").trim().toLowerCase() === "production"
  );
}

/**
 * F-32: in production the session cookies are ALWAYS `Secure`; the flag no
 * longer depends on a client/proxy-supplied `x-forwarded-proto`. Plain-HTTP
 * production-mode runs (e.g. `next start` on localhost) must opt out
 * explicitly with ADMIN_COOKIE_ALLOW_HTTP=1. Outside production the scheme is
 * derived from the request as before.
 */
export function cookieSecureFromRequest(request: Request): boolean {
  if (
    isProductionRuntime() &&
    (process.env.ADMIN_COOKIE_ALLOW_HTTP || "").trim() !== "1"
  ) {
    return true;
  }
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

/**
 * F-19: PUBLIC key (PEM) of the API's admin-token signing key. This is all the
 * admin service needs to verify its session cookie; it cannot sign anything.
 */
function adminPublicKey(): string {
  return (process.env.ADMIN_JWT_PUBLIC_KEY || "").trim();
}

/** Production fails closed unless the edge can actually verify signatures. */
function requireSecretInProd(): boolean {
  return isProductionRuntime() && !jwtSecret() && !adminPublicKey();
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

type RotatedPair = { access: string; refresh: string };

// Refresh tokens are single-use (the API rotates them). When the access token
// expires, a burst of parallel requests (page load + link prefetches + proxy
// calls) all present the SAME refresh token; only the first rotation can win
// and the rest would get 401 and redirect to /login. Coalesce them: callers
// presenting the same refresh token share one upstream call, and a result is
// reused for a few seconds by late siblings that still carry the old cookie.
// (Per server process / runtime; every sibling then sets the same new pair.)
const REFRESH_REUSE_MS = 15_000;
const refreshInflight = new Map<string, Promise<RotatedPair | null>>();
const refreshRecent = new Map<string, { at: number; pair: RotatedPair }>();

export async function refreshAccessWithRefreshToken(
  refreshToken: string,
): Promise<RotatedPair | null> {
  const rt = (refreshToken || "").trim();
  if (!rt) return null;

  const now = Date.now();
  for (const [k, v] of refreshRecent) {
    if (now - v.at >= REFRESH_REUSE_MS) refreshRecent.delete(k);
  }
  const recent = refreshRecent.get(rt);
  if (recent) return recent.pair;
  const pending = refreshInflight.get(rt);
  if (pending) return pending;

  const p = refreshUpstream(rt)
    .then((pair) => {
      if (pair) refreshRecent.set(rt, { at: Date.now(), pair });
      return pair;
    })
    .finally(() => {
      refreshInflight.delete(rt);
    });
  refreshInflight.set(rt, p);
  return p;
}

async function refreshUpstream(rt: string): Promise<RotatedPair | null> {
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
  const publicKey = adminPublicKey();
  const verifyOptions = {
    // F-32: unsigned claims only with an explicit, non-production opt-in.
    allowUnsignedDev:
      !isProductionRuntime() &&
      (process.env.ADMIN_ALLOW_UNSIGNED_DEV || "").trim() === "1",
    // Optional overrides; must equal the API's ADMIN_JWT_ISSUER/AUDIENCE.
    issuer: (process.env.ADMIN_JWT_ISSUER || "").trim(),
    audience: (process.env.ADMIN_JWT_AUDIENCE || "").trim(),
  };
  const accessRaw = jar.get(ADMIN_JWT_COOKIE)?.value || "";
  if (accessRaw) {
    const check = await verifyAdminAccessJwt(
      accessRaw,
      secret,
      publicKey,
      verifyOptions,
    );
    if (check.ok) return accessRaw;
  }

  const refreshRaw = jar.get(ADMIN_REFRESH_COOKIE)?.value || "";
  if (!refreshRaw) return null;
  const rotated = await refreshAccessWithRefreshToken(refreshRaw);
  if (!rotated) return null;
  // A freshly rotated access token goes through the same checks (signature,
  // iss/aud, admin scope, exp) instead of being trusted because it came from
  // the upstream refresh endpoint.
  const rotatedCheck = await verifyAdminAccessJwt(
    rotated.access,
    secret,
    publicKey,
    verifyOptions,
  );
  if (!rotatedCheck.ok) return null;
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
