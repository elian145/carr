import { NextResponse } from "next/server";
import {
  clearAdminSessionCookies,
  cookieSecureFromRequest,
  setAdminSessionCookies,
} from "@/lib/admin-session-auth";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
/** Render free-tier cold starts can exceed the default serverless budget. */
export const maxDuration = 60;

function apiBase(): string {
  return (
    process.env.API_PROXY_TARGET ||
    process.env.NEXT_PUBLIC_API_BASE ||
    "http://localhost:5000"
  ).replace(/\/+$/, "");
}

type JsonBody = Record<string, unknown>;

async function readJson(res: Response): Promise<JsonBody> {
  return (await res.json().catch(() => ({}))) as JsonBody;
}

function upstreamMessage(body: JsonBody, fallback: string): string {
  const msg = typeof body.message === "string" ? body.message.trim() : "";
  return msg || fallback;
}

/** Retry transient gateway / connection failures (common while Render wakes up). */
async function fetchUpstream(
  url: string,
  init: RequestInit,
  attempts = 3,
): Promise<Response> {
  let lastError: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url, init);
      if ([502, 503, 504].includes(res.status) && i < attempts - 1) {
        await new Promise((r) => setTimeout(r, 1500 * (i + 1)));
        continue;
      }
      return res;
    } catch (err) {
      lastError = err;
      if (i < attempts - 1) {
        await new Promise((r) => setTimeout(r, 1500 * (i + 1)));
        continue;
      }
    }
  }
  throw lastError instanceof Error ? lastError : new Error("Upstream fetch failed");
}

/**
 * Establish an httpOnly admin session from username/password.
 * Stores access + refresh JWTs (access is short-lived; refresh rotates it).
 */
export async function POST(request: Request) {
  let body: { username?: string; password?: string };
  try {
    body = (await request.json()) as { username?: string; password?: string };
  } catch {
    return NextResponse.json({ message: "Invalid JSON" }, { status: 400 });
  }

  const username = (body.username || "").trim();
  const password = body.password || "";
  if (!username || !password) {
    return NextResponse.json(
      { message: "Username and password required" },
      { status: 400 },
    );
  }

  const base = apiBase();
  let loginRes: Response;
  try {
    loginRes = await fetchUpstream(`${base}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        username,
        password,
        account_scope: "admin",
      }),
    });
  } catch {
    return NextResponse.json(
      {
        message: `Cannot reach API at ${base}. If this is Render, wait for the service to wake and try again.`,
      },
      { status: 502 },
    );
  }

  const loginBody = await readJson(loginRes);
  if (!loginRes.ok) {
    return NextResponse.json(
      {
        message: upstreamMessage(
          loginBody,
          `API login failed (${loginRes.status}) at ${base}`,
        ),
      },
      { status: loginRes.status },
    );
  }

  const token = String(loginBody.access_token || loginBody.token || "").trim();
  const refresh = String(loginBody.refresh_token || "").trim();
  if (!token) {
    return NextResponse.json({ message: "No token in login response" }, { status: 502 });
  }
  if (!refresh) {
    return NextResponse.json(
      { message: "No refresh_token in login response" },
      { status: 502 },
    );
  }

  let meRes: Response;
  try {
    meRes = await fetchUpstream(`${base}/api/auth/me`, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    });
  } catch {
    return NextResponse.json({ message: "Cannot verify admin session" }, { status: 502 });
  }

  const me = await readJson(meRes);
  if (!meRes.ok) {
    return NextResponse.json(
      {
        message: upstreamMessage(
          me,
          `Session verification failed (${meRes.status})`,
        ),
      },
      { status: meRes.status },
    );
  }
  if (!me.is_admin) {
    return NextResponse.json(
      { message: "This account does not have admin access" },
      { status: 403 },
    );
  }

  const res = NextResponse.json({ user: me });
  setAdminSessionCookies(
    res,
    token,
    refresh,
    cookieSecureFromRequest(request),
  );
  return res;
}

/** Clear httpOnly admin access + refresh cookies. */
export async function DELETE(request: Request) {
  const res = NextResponse.json({ ok: true });
  clearAdminSessionCookies(res, cookieSecureFromRequest(request));
  return res;
}
