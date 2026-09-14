/**
 * Smoke test for L-02: production CSP must omit 'unsafe-eval' from
 * script-src while development retains it; script-src's 'unsafe-inline'
 * and every other directive are unchanged between modes.
 *
 * L-02 (style-src half): style-src must be exactly `style-src 'self'` — no
 * 'unsafe-inline' — in BOTH production and development. Unlike script-src's
 * 'unsafe-eval' (dev-server Fast Refresh/HMR only), style-src's
 * 'unsafe-inline' was found to have no demonstrated requirement in either
 * environment (no CSS-in-JS/styled-jsx/inline <style>; React's style={{...}}
 * usage is applied via per-property CSSOM mutation, not a literal `style`
 * attribute string), so it is dropped uniformly, not gated by env.
 *
 * This mirrors admin-web/src/middleware.ts::securityHeaders()'s env check
 * and CSP string construction exactly, the same way
 * test_verify_admin_jwt.mjs mirrors verify-admin-jwt.ts, so it can run as a
 * plain Node script without a TypeScript/Next.js build step.
 *
 * Run from repo root: node admin-web/scripts/test_csp_env.mjs
 */
import assert from "node:assert/strict";

function buildCsp(env) {
  const isProd =
    (env.NODE_ENV || "").trim() === "production" ||
    (env.APP_ENV || "").trim().toLowerCase() === "production";
  const scriptSrc = isProd
    ? "script-src 'self' 'unsafe-inline'"
    : "script-src 'self' 'unsafe-inline' 'unsafe-eval'";
  return [
    "default-src 'self'",
    scriptSrc,
    "style-src 'self'",
    "img-src 'self' data: blob: https:",
    "font-src 'self' data:",
    "connect-src 'self' https: http://localhost:* http://127.0.0.1:*",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join("; ");
}

/** Split a CSP header string into its individual directives (trimmed), for
 * exact-match assertions instead of loose substring checks — a substring
 * check for "style-src 'self'" would also match "style-src 'self'
 * 'unsafe-inline'", silently passing even if the regression it's guarding
 * against were reintroduced. */
function directives(csp) {
  return csp.split("; ").map((d) => d.trim());
}

const prodByNodeEnv = buildCsp({ NODE_ENV: "production" });
const prodByAppEnv = buildCsp({ NODE_ENV: "", APP_ENV: "Production" });
const devByNodeEnv = buildCsp({ NODE_ENV: "development" });
const devByUnset = buildCsp({});

// --- script-src: unchanged behavior (this task must not touch it) ---
for (const csp of [prodByNodeEnv, prodByAppEnv]) {
  const ds = directives(csp);
  assert.ok(ds.includes("script-src 'self' 'unsafe-inline'"), `production script-src must be exactly 'self' 'unsafe-inline': ${csp}`);
  assert.equal(csp.includes("unsafe-eval"), false, `production CSP must not contain unsafe-eval: ${csp}`);
}
for (const csp of [devByNodeEnv, devByUnset]) {
  const ds = directives(csp);
  assert.ok(
    ds.includes("script-src 'self' 'unsafe-inline' 'unsafe-eval'"),
    `development script-src must retain unsafe-eval: ${csp}`,
  );
}

// --- style-src: L-02 fix under test — 'unsafe-inline' removed, both envs ---
for (const csp of [prodByNodeEnv, prodByAppEnv, devByNodeEnv, devByUnset]) {
  const ds = directives(csp);
  assert.ok(ds.includes("style-src 'self'"), `CSP must contain the exact directive style-src 'self': ${csp}`);
  assert.equal(
    csp.includes("style-src 'self' 'unsafe-inline'"),
    false,
    `CSP must NOT contain style-src 'self' 'unsafe-inline' (L-02 style-src regression): ${csp}`,
  );
  assert.equal(csp.includes("style-src"), csp.match(/style-src/g)?.length === 1, "style-src must appear exactly once");
}

// All other directives must be byte-for-byte identical between prod and dev,
// and identical to their original (pre-L-02-style-src-fix) values — only
// script-src's unsafe-eval suffix and style-src's unsafe-inline removal
// should ever differ.
const unrelatedDirectives = [
  "default-src 'self'",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data:",
  "connect-src 'self' https: http://localhost:* http://127.0.0.1:*",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
];
for (const csp of [prodByNodeEnv, devByNodeEnv]) {
  const ds = directives(csp);
  for (const directive of unrelatedDirectives) {
    assert.ok(ds.includes(directive), `CSP missing unrelated directive (must be byte-for-byte unchanged): ${directive} in: ${csp}`);
  }
  // Exactly 9 directives total (no accidental duplicate/extra directive introduced).
  assert.equal(ds.length, 9, `CSP must have exactly 9 directives, got ${ds.length}: ${csp}`);
}

console.log("OK: CSP prod/dev unsafe-eval + L-02 style-src unsafe-inline removal smoke passed");
