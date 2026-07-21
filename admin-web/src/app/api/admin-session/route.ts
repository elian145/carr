import { NextResponse } from "next/server";
import {
  clearAdminSessionCookies,
  cookieSecureFromRequest,
  setAdminSessionCookies,
} from "@/lib/admin-session-auth";

function apiBase(): string {
  return (
    process.env.API_PROXY_TARGET ||
    process.env.NEXT_PUBLIC_API_BASE ||
    "http://localhost:5000"
  ).replace(/\/+$/, "");
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
    loginRes = await fetch(`${base}/api/auth/login`, {
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
      { message: `Cannot reach API at ${base}` },
      { status: 502 },
    );
  }

  const loginBody = (await loginRes.json().catch(() => ({}))) as {
    access_token?: string;
    token?: string;
    refresh_token?: string;
    message?: string;
    user?: unknown;
  };
  if (!loginRes.ok) {
    return NextResponse.json(
      { message: loginBody.message || "Login failed" },
      { status: loginRes.status },
    );
  }

  const token = (loginBody.access_token || loginBody.token || "").trim();
  const refresh = (loginBody.refresh_token || "").trim();
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
    meRes = await fetch(`${base}/api/auth/me`, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    });
  } catch {
    return NextResponse.json({ message: "Cannot verify admin session" }, { status: 502 });
  }

  const me = (await meRes.json().catch(() => ({}))) as {
    is_admin?: boolean;
    message?: string;
  };
  if (!meRes.ok) {
    return NextResponse.json(
      { message: me.message || "Session verification failed" },
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
  setAdminSessionCookies(res, token, refresh, cookieSecureFromRequest(request));
  return res;
}

/** Clear httpOnly admin access + refresh cookies. */
export async function DELETE(request: Request) {
  const res = NextResponse.json({ ok: true });
  clearAdminSessionCookies(res, cookieSecureFromRequest(request));
  return res;
}
