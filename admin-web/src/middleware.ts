import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  attachRotatedCookies,
  cookieSecureFromRequest,
  resolveAdminAccessToken,
} from "@/lib/admin-session-auth";
import {
  applyApiSecurityHeaders,
  applyBaseSecurityHeaders,
  applyPageSecurityHeaders,
  buildCsp,
  isProduction,
} from "@/lib/security-headers";

const PUBLIC = new Set(["/login"]);

/**
 * F-19: every response (pages, API routes, the /backend-api proxy, static
 * files served via public/) now gets the security headers. Previously the
 * early `NextResponse.next()` returns below skipped them entirely, so proxied
 * and API responses had no `X-Content-Type-Options: nosniff`.
 */
function withHeaders(
  res: NextResponse,
  kind: "page" | "api" | "asset",
  nonce?: string,
): NextResponse {
  if (kind === "page") applyPageSecurityHeaders(res.headers, process.env, nonce);
  else if (kind === "api") applyApiSecurityHeaders(res.headers, process.env);
  else applyBaseSecurityHeaders(res.headers, process.env);
  return res;
}

/** Per-request CSP nonce (128 bits, base64). */
function newNonce(): string {
  return btoa(crypto.randomUUID());
}

/**
 * Pass the nonce-bearing CSP on the *request* so Next.js stamps its own
 * bootstrap/chunk <script> tags with the nonce, and `x-nonce` for components.
 */
function nextWithNonce(nonce: string): NextResponse {
  const requestHeaders = new Headers();
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("content-security-policy", buildCsp(process.env, nonce));
  return NextResponse.next({ request: { headers: requestHeaders } });
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Only skip auth for genuine static assets (a file extension at the END of the
  // path), not for any route that merely contains a dot somewhere in it.
  const isStaticAsset = /\.[a-zA-Z0-9]+$/.test(pathname);

  // API-ish routes (own handlers authenticate / guard themselves). A
  // /backend-api path that happens to end in ".ext" is still API, not a file.
  if (
    pathname.startsWith("/api/admin-session") ||
    pathname.startsWith("/api/health") ||
    pathname.startsWith("/backend-api")
  ) {
    return withHeaders(NextResponse.next(), "api");
  }
  if (
    pathname.startsWith("/_next") ||
    pathname.startsWith("/favicon") ||
    isStaticAsset
  ) {
    return withHeaders(NextResponse.next(), "asset");
  }

  const nonce = newNonce();
  let rotatedAccess: string | null = null;
  let rotatedRefresh: string | null = null;
  const token = await resolveAdminAccessToken(request.cookies, (access, refresh) => {
    rotatedAccess = access;
    rotatedRefresh = refresh;
  });
  const hasAuth = Boolean(token);
  const isPublic = PUBLIC.has(pathname);
  const secure = cookieSecureFromRequest(request);

  if (!hasAuth && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return withHeaders(NextResponse.redirect(url), "page", nonce);
  }

  if (hasAuth && pathname === "/login") {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    const res = withHeaders(NextResponse.redirect(url), "page", nonce);
    if (rotatedAccess && rotatedRefresh) {
      attachRotatedCookies(res, rotatedAccess, rotatedRefresh, secure);
    }
    return res;
  }

  const res = withHeaders(
    isProduction(process.env) ? nextWithNonce(nonce) : NextResponse.next(),
    "page",
    nonce,
  );
  if (rotatedAccess && rotatedRefresh) {
    attachRotatedCookies(res, rotatedAccess, rotatedRefresh, secure);
  }
  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image).*)"],
};
