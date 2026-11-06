/**
 * Single source of truth for the admin-web response security headers
 * (used by middleware.ts, the proxy route handlers and next.config.ts).
 */

type Env = Record<string, string | undefined>;

export function isProduction(env: Env): boolean {
  return (
    (env.NODE_ENV || "").trim() === "production" ||
    (env.APP_ENV || "").trim().toLowerCase() === "production"
  );
}

/**
 * Page CSP.
 *
 * F-19: `script-src` no longer allows `'unsafe-inline'` in production: scripts
 * are authorised by a per-request nonce (Next.js stamps its own bootstrap
 * scripts with the nonce found in the request's CSP header) plus
 * `'strict-dynamic'` for the chunks they load. 'unsafe-eval' stays dev-only
 * (Fast Refresh/HMR). Development keeps `'unsafe-inline'` (HMR/overlay).
 */
export function buildCsp(env: Env, nonce?: string): string {
  const prod = isProduction(env);
  let scriptSrc: string;
  if (prod && nonce) {
    scriptSrc = `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'`;
  } else if (prod) {
    // No nonce available (should not happen for pages): fail closed.
    scriptSrc = "script-src 'self'";
  } else {
    scriptSrc = "script-src 'self' 'unsafe-inline' 'unsafe-eval'";
  }
  return [
    "default-src 'self'",
    scriptSrc,
    // L-02: no inline <style>/CSS-in-JS is used; React's style={{...}} is
    // applied through CSSOM and is not governed by this directive.
    "style-src 'self'",
    "img-src 'self' data: blob: https:",
    "font-src 'self' data:",
    "connect-src 'self' https: http://localhost:* http://127.0.0.1:*",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join("; ");
}

/**
 * CSP for proxied API/JSON/file responses: they are never documents the admin
 * UI renders, so make any HTML/SVG an upstream could return inert (no scripts,
 * unique origin) if someone navigates to a `/backend-api/...` URL directly.
 */
export const API_RESPONSE_CSP =
  "default-src 'none'; frame-ancestors 'none'; sandbox";

export const HSTS_VALUE = "max-age=31536000; includeSubDomains";

/** Headers that are identical for every response (static assets included). */
export function baseSecurityHeaders(env: Env): Array<[string, string]> {
  const headers: Array<[string, string]> = [
    ["X-Frame-Options", "DENY"],
    ["X-Content-Type-Options", "nosniff"],
    ["Referrer-Policy", "strict-origin-when-cross-origin"],
    ["Permissions-Policy", "camera=(), microphone=(), geolocation=()"],
  ];
  // Production only: HSTS is ignored over plain http and must not be sent by
  // local dev. includeSubDomains is safe here: it only scopes to subdomains of
  // the admin host itself (e.g. x.carr-admin.onrender.com), never to the
  // shared onrender.com parent; no `preload` (hard to undo).
  if (isProduction(env)) headers.push(["Strict-Transport-Security", HSTS_VALUE]);
  return headers;
}

export function applyBaseSecurityHeaders(headers: Headers, env: Env): void {
  for (const [k, v] of baseSecurityHeaders(env)) headers.set(k, v);
}

/** Security headers for an HTML page response. */
export function applyPageSecurityHeaders(
  headers: Headers,
  env: Env,
  nonce?: string,
): void {
  applyBaseSecurityHeaders(headers, env);
  headers.set("Content-Security-Policy", buildCsp(env, nonce));
}

/** Security headers for proxied API / JSON / blob responses. */
export function applyApiSecurityHeaders(headers: Headers, env: Env): void {
  applyBaseSecurityHeaders(headers, env);
  headers.set("Content-Security-Policy", API_RESPONSE_CSP);
}
