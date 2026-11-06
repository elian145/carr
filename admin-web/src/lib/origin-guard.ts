/**
 * CSRF defence for the cookie-authenticated admin endpoints.
 *
 * The admin session lives in httpOnly cookies that the browser attaches
 * automatically, so a malicious page could otherwise make an admin's browser
 * send a state-changing request to `/backend-api/...` (a generic proxy that
 * adds the Bearer token) or to `/api/admin-session` (login/logout CSRF).
 * SameSite=Lax already withholds the cookie on cross-site POSTs; this check is
 * the second, independent layer (and also covers same-site-but-cross-origin
 * pages and browsers with SameSite quirks).
 *
 * Policy (state-changing methods only; GET/HEAD/OPTIONS are untouched):
 *   - The request must carry `Origin` (or, when absent, a `Referer`) that
 *     matches an allowed origin; `Origin: null`, unparsable values and requests
 *     with neither header are rejected (browsers always send `Origin` on
 *     same-origin POST/PUT/PATCH/DELETE fetches).
 *   - Allowed origins: `ADMIN_ALLOWED_ORIGINS` (comma-separated, exact
 *     scheme://host[:port]) when set; otherwise the request's own origin
 *     (public host from `X-Forwarded-Host`/`Host`, scheme from
 *     `X-Forwarded-Proto` or the URL). A cross-site attacker cannot forge
 *     those request headers from a browser, so deriving the default from them
 *     is safe.
 */

const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

export type OriginDecision = { ok: true } | { ok: false; reason: string };

function firstValue(v: string | null): string {
  return (v || "").split(",")[0].trim();
}

/** Canonical `scheme://host[:port]` (default ports dropped), or null. */
export function canonicalOrigin(value: string): string | null {
  const trimmed = (value || "").trim();
  if (!trimmed || trimmed.toLowerCase() === "null") return null;
  try {
    const u = new URL(trimmed);
    if (u.protocol !== "http:" && u.protocol !== "https:") return null;
    return u.origin.toLowerCase();
  } catch {
    return null;
  }
}

export function allowedOriginsFromEnv(
  env: Record<string, string | undefined>,
): string[] {
  return (env.ADMIN_ALLOWED_ORIGINS || "")
    .split(",")
    .map((s) => canonicalOrigin(s))
    .filter((s): s is string => Boolean(s));
}

/** The origin this request was addressed to (default allow-list entry). */
export function requestOrigin(request: Request): string | null {
  const proto =
    firstValue(request.headers.get("x-forwarded-proto")) ||
    (() => {
      try {
        return new URL(request.url).protocol.replace(":", "");
      } catch {
        return "";
      }
    })();
  const host =
    firstValue(request.headers.get("x-forwarded-host")) ||
    firstValue(request.headers.get("host")) ||
    (() => {
      try {
        return new URL(request.url).host;
      } catch {
        return "";
      }
    })();
  if (!proto || !host) return null;
  return canonicalOrigin(`${proto}://${host}`);
}

export function checkSameOrigin(
  request: Request,
  env: Record<string, string | undefined> = process.env,
): OriginDecision {
  const method = (request.method || "GET").toUpperCase();
  if (SAFE_METHODS.has(method)) return { ok: true };

  const originHeader = request.headers.get("origin");
  let claimed: string | null = null;
  if (originHeader !== null && originHeader.trim() !== "") {
    claimed = canonicalOrigin(originHeader);
    if (!claimed) return { ok: false, reason: "invalid_origin" };
  } else {
    const referer = request.headers.get("referer");
    if (!referer || referer.trim() === "") {
      return { ok: false, reason: "missing_origin" };
    }
    claimed = canonicalOrigin(referer);
    if (!claimed) return { ok: false, reason: "invalid_referer" };
  }

  const configured = allowedOriginsFromEnv(env);
  const allowed = configured.length > 0 ? configured : [requestOrigin(request)];
  if (allowed.some((o) => o !== null && o === claimed)) return { ok: true };
  return { ok: false, reason: "cross_origin" };
}

/** `null` when the request may proceed, otherwise a ready 403 response. */
export function rejectCrossSiteRequest(request: Request): Response | null {
  const decision = checkSameOrigin(request);
  if (decision.ok) return null;
  return Response.json(
    { message: "Cross-site request blocked" },
    {
      status: 403,
      headers: {
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
      },
    },
  );
}
