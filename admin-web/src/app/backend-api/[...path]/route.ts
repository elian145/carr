import { cookies } from "next/headers";
import { ADMIN_JWT_COOKIE } from "@/lib/admin-session-constants";
import { verifyAdminAccessJwt } from "@/lib/verify-admin-jwt";

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

async function resolveBearer(): Promise<string | null> {
  const jar = await cookies();
  const raw = jar.get(ADMIN_JWT_COOKIE)?.value || "";
  if (!raw) return null;
  const secret = (process.env.JWT_SECRET_KEY || "").trim();
  const isProd =
    (process.env.NODE_ENV || "").trim() === "production" ||
    (process.env.APP_ENV || "").trim().toLowerCase() === "production";
  if (isProd && !secret) return null;
  const check = await verifyAdminAccessJwt(raw, secret);
  return check.ok ? raw : null;
}

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

  const token = await resolveBearer();
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const init: RequestInit = {
    method: request.method,
    headers,
    redirect: "manual",
  };
  if (request.method !== "GET" && request.method !== "HEAD") {
    init.body = request.body;
    // Required by Node fetch when streaming a request body.
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

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: outHeaders,
  });
}

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
export const HEAD = proxy;
export const OPTIONS = proxy;
