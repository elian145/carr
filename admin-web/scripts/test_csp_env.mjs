/**
 * Smoke test for L-02: production CSP must omit 'unsafe-eval' from
 * script-src while development retains it; 'unsafe-inline' (script-src and
 * style-src) and all other directives must be unchanged in both modes.
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
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob: https:",
    "font-src 'self' data:",
    "connect-src 'self' https: http://localhost:* http://127.0.0.1:*",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "form-action 'self'",
  ].join("; ");
}

const prodByNodeEnv = buildCsp({ NODE_ENV: "production" });
const prodByAppEnv = buildCsp({ NODE_ENV: "", APP_ENV: "Production" });
const devByNodeEnv = buildCsp({ NODE_ENV: "development" });
const devByUnset = buildCsp({});

for (const csp of [prodByNodeEnv, prodByAppEnv]) {
  assert.match(csp, /script-src 'self' 'unsafe-inline'(?!.*unsafe-eval)/);
  assert.equal(csp.includes("unsafe-eval"), false, `production CSP must not contain unsafe-eval: ${csp}`);
  assert.ok(csp.includes("style-src 'self' 'unsafe-inline'"), "production CSP must retain style-src unsafe-inline");
}

for (const csp of [devByNodeEnv, devByUnset]) {
  assert.ok(
    csp.includes("script-src 'self' 'unsafe-inline' 'unsafe-eval'"),
    `development CSP must retain unsafe-eval: ${csp}`,
  );
  assert.ok(csp.includes("style-src 'self' 'unsafe-inline'"), "development CSP must retain style-src unsafe-inline");
}

// All other directives must be byte-for-byte identical between prod and dev —
// only script-src's unsafe-eval suffix should differ.
const unrelatedDirectives = [
  "default-src 'self'",
  "img-src 'self' data: blob: https:",
  "font-src 'self' data:",
  "connect-src 'self' https: http://localhost:* http://127.0.0.1:*",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
];
for (const directive of unrelatedDirectives) {
  assert.ok(prodByNodeEnv.includes(directive), `prod CSP missing unrelated directive: ${directive}`);
  assert.ok(devByNodeEnv.includes(directive), `dev CSP missing unrelated directive: ${directive}`);
}

console.log("OK: CSP prod/dev unsafe-eval smoke passed");
