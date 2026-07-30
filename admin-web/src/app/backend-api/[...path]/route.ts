import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import {
  cookieSecureFromRequest,
  resolveAdminAccessToken,
  setAdminSessionCookies,
} from "@/lib/admin-session-auth";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function apiBase(): string {
  return (
    process.env.API_PROXY_TARGET ||
    process.env.NEXT_PUBLIC_API_BASE ||
    "http://localhost:5000"
  ).replace(/\/+$/, "");
}

type Ctx = { params: Promise<{ path: string[] }> };

async function proxy(request: Request, context: Ctx): Promise<Response> {
  const { path } = await context.params;
  const joined = (path || []).map(encodeURIComponent).join("/");
  const incoming = new URL(request.url);
  const dest = `${apiBase()}/${joined}${incoming.search}`;

  const headers = new Headers();
  const pass = [
    "accept",
    "accept-language",
    "content-type",
    "if-none-match",
    "if-modified-since",
  ];
  for (const name of pass) {
    const v = request.headers.get(name);
    if (v) headers.set(name, v);
  }

  const jar = await cookies();
  let rotatedAccess: string | null = null;
  let rotatedRefresh: string | null = null;
  const token = await resolveAdminAccessToken(jar, (access, refresh) => {
    rotatedAccess = access;
    rotatedRefresh = refresh;
  });
  // Never proxy unauthenticated requests upstream. The admin panel always holds
  // a session for /backend-api calls (login goes through /api/admin-session),
  // so a missing token means an unauthenticated caller — reject instead of
  // acting as an open relay to the API host.
  if (!token) {
    return Response.json({ message: "Authentication required" }, { status: 401 });
  }
  headers.set("Authorization", `Bearer ${token}`);

  const init: RequestInit = {
    method: request.method,
    headers,
    redirect: "manual",
  };
  if (request.method !== "GET" && request.method !== "HEAD") {
    init.body = request.body;
    (init as { duplex?: string }).duplex = "half";
  }

  let upstream: Response;
  try {
    upstream = await fetch(dest, init);
  } catch {
    return Response.json(
      { message: `Cannot reach API at ${apiBase()}` },
      { status: 502 },
    );
  }

  const outHeaders = new Headers();
  const outPass = ["content-type", "cache-control", "etag", "last-modified"];
  for (const name of outPass) {
    const v = upstream.headers.get(name);
    if (v) outHeaders.set(name, v);
  }

  // Prefer NextResponse so we can rotate httpOnly cookies after refresh.
  const res = new NextResponse(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: outHeaders,
  });
  if (rotatedAccess && rotatedRefresh) {
    setAdminSessionCookies(
      res,
      rotatedAccess,
      rotatedRefresh,
      cookieSecureFromRequest(request),
    );
  }
  return res;
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
export const HEAD = proxy;
export const OPTIONS = proxy;
