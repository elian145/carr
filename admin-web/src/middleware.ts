import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  attachRotatedCookies,
  cookieSecureFromRequest,
  resolveAdminAccessToken,
} from "@/lib/admin-session-auth";

const PUBLIC = new Set(["/login"]);

function securityHeaders(res: NextResponse): NextResponse {
  res.headers.set("X-Frame-Options", "DENY");
  res.headers.set("X-Content-Type-Options", "nosniff");
  res.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  res.headers.set(
    "Permissions-Policy",
    "camera=(), microphone=(), geolocation=()",
  );
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

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Only skip auth for genuine static assets (a file extension at the END of the
  // path), not for any route that merely contains a dot somewhere in it.
  const isStaticAsset = /\.[a-zA-Z0-9]+$/.test(pathname);
  if (
    pathname.startsWith("/_next") ||
    pathname.startsWith("/favicon") ||
    pathname.startsWith("/api/admin-session") ||
    isStaticAsset
  ) {
    return NextResponse.next();
  }

  if (pathname.startsWith("/backend-api")) {
    return NextResponse.next();
  }

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
    return securityHeaders(NextResponse.redirect(url));
  }

  if (hasAuth && pathname === "/login") {
    const url = request.nextUrl.clone();
    url.pathname = "/dashboard";
    const res = securityHeaders(NextResponse.redirect(url));
    if (rotatedAccess && rotatedRefresh) {
      attachRotatedCookies(res, rotatedAccess, rotatedRefresh, secure);
    }
    return res;
  }

  const res = securityHeaders(NextResponse.next());
  if (rotatedAccess && rotatedRefresh) {
    attachRotatedCookies(res, rotatedAccess, rotatedRefresh, secure);
  }
  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image).*)"],
};
