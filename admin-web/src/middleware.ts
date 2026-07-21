import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { ADMIN_JWT_COOKIE } from "@/lib/admin-session-constants";
import { verifyAdminAccessJwt } from "@/lib/verify-admin-jwt";

const PUBLIC = new Set(["/login"]);

function securityHeaders(res: NextResponse): NextResponse {
  res.headers.set("X-Frame-Options", "DENY");
  res.headers.set("X-Content-Type-Options", "nosniff");
  res.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  res.headers.set(
    "Permissions-Policy",
    "camera=(), microphone=(), geolocation=()",
  );
  // Baseline CSP: Next.js needs inline/eval for hydration in this app setup.
  res.headers.set(
    "Content-Security-Policy",
    [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob: https:",
      "font-src 'self' data:",
      "connect-src 'self' https: http://localhost:* http://127.0.0.1:*",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'",
    ].join("; "),
  );
  return res;
}

async function jwtFromRequest(request: NextRequest): Promise<string | null> {
  const raw = request.cookies.get(ADMIN_JWT_COOKIE)?.value || "";
  if (!raw) return null;
  const secret = (process.env.JWT_SECRET_KEY || "").trim();
  const isProd =
    (process.env.NODE_ENV || "").trim() === "production" ||
    (process.env.APP_ENV || "").trim().toLowerCase() === "production";
  // Production must verify signatures; unsigned decode-only is a local-dev fallback.
  if (isProd && !secret) return null;
  const check = await verifyAdminAccessJwt(raw, secret);
  return check.ok ? raw : null;
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (
    pathname.startsWith("/_next") ||
    pathname.startsWith("/favicon") ||
    pathname.startsWith("/api/admin-session") ||
    pathname.includes(".")
  ) {
    return NextResponse.next();
  }

  // Flask proxy is handled by app/backend-api/[...path] (injects Bearer from httpOnly cookie).
  if (pathname.startsWith("/backend-api")) {
    return NextResponse.next();
  }

  const token = await jwtFromRequest(request);
  const hasAuth = Boolean(token);
  const isPublic = PUBLIC.has(pathname);

  if (!hasAuth && !isPublic) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return securityHeaders(NextResponse.redirect(url));
  }

  if (hasAuth && pathname === "/login") {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    return securityHeaders(NextResponse.redirect(url));
  }

  return securityHeaders(NextResponse.next());
}

export const config = {
  matcher: ["/((?!_next/static|_next/image).*)"],
};
