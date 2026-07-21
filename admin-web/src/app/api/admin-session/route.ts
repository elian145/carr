import { NextResponse } from "next/server";
import {
  ADMIN_JWT_COOKIE,
  ADMIN_SESSION_MAX_AGE_SEC,
  LEGACY_AUTH_FLAG_COOKIE,
} from "@/lib/admin-session-constants";

function apiBase(): string {
  return (
    process.env.API_PROXY_TARGET ||
    process.env.NEXT_PUBLIC_API_BASE ||
    "http://localhost:5000"
  ).replace(/\/+$/, "");
}

function cookieSecure(request: Request): boolean {
  const proto = request.headers.get("x-forwarded-proto");
  if (proto) return proto.split(",")[0].trim() === "https";
  try {
    return new URL(request.url).protocol === "https:";
  } catch {
    return false;
  }
}

function clearLegacyCookies(res: NextResponse): void {
  res.cookies.set(LEGACY_AUTH_FLAG_COOKIE, "", {
    httpOnly: false,
    path: "/",
    maxAge: 0,
    sameSite: "lax",
  });
}

function setJwtCookie(res: NextResponse, token: string, secure: boolean): void {
  res.cookies.set(ADMIN_JWT_COOKIE, token, {
    httpOnly: true,
    secure,
    sameSite: "lax",
    path: "/",
    maxAge: ADMIN_SESSION_MAX_AGE_SEC,
  });
  clearLegacyCookies(res);
}

function clearJwtCookie(res: NextResponse, secure: boolean): void {
  res.cookies.set(ADMIN_JWT_COOKIE, "", {
    httpOnly: true,
    secure,
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });
  clearLegacyCookies(res);
}

/**
 * Establish an httpOnly admin session from username/password.
 * The JWT never needs to live in localStorage or a readable cookie.
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
  if (!token) {
    return NextResponse.json({ message: "No token in login response" }, { status: 502 });
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
  setJwtCookie(res, token, cookieSecure(request));
  return res;
}

/** Clear the httpOnly admin JWT cookie. */
export async function DELETE(request: Request) {
  const res = NextResponse.json({ ok: true });
  clearJwtCookie(res, cookieSecure(request));
  return res;
}
