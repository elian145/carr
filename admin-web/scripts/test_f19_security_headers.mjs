/**
 * F-19: security headers (CSP nonce, HSTS, nosniff, frame/referrer/permissions)
 * on every middleware response, plus the proxy route's response headers.
 * Exercises the real src/lib/security-headers.ts, src/middleware.ts and
 * src/app/backend-api/[...path]/route.ts with only next/server + next/headers stubbed.
 * Run: node --test scripts/test_f19_security_headers.mjs
 */
import test from "node:test";
import assert from "node:assert/strict";
import { createTsLoader } from "./ts-loader.mjs";
import { StubNextResponse, mintHs256, adminPayload, withEnv } from "./f19-stubs.mjs";

const SECRET = "f19-test-secret";
const jar = new Map();
const stubs = {
  "next/server": { NextResponse: StubNextResponse },
  "next/headers": { cookies: async () => ({ get: (n) => (jar.has(n) ? { value: jar.get(n) } : undefined) }) },
};
const loader = createTsLoader(stubs);
const sh = loader.load("src/lib/security-headers.ts");
const { middleware } = loader.load("src/middleware.ts");
const route = loader.load("src/app/backend-api/[...path]/route.ts");

const PROD = { NODE_ENV: "production", APP_ENV: undefined, JWT_SECRET_KEY: SECRET, ADMIN_JWT_PUBLIC_KEY: undefined };
const DEV = { NODE_ENV: "development", APP_ENV: undefined, JWT_SECRET_KEY: SECRET, ADMIN_JWT_PUBLIC_KEY: undefined };

function directives(csp) {
  return csp.split(";").map((d) => d.trim());
}
function scriptSrc(csp) {
  return directives(csp).find((d) => d.startsWith("script-src"));
}

function nextRequest(pathname, cookies = {}) {
  return {
    url: `https://admin.example.com${pathname}`,
    headers: new Headers({ "x-forwarded-proto": "https" }),
    nextUrl: {
      pathname,
      clone() {
        const c = { pathname, searchParams: new URLSearchParams() };
        c.toString = () => `https://admin.example.com${c.pathname}?${c.searchParams}`;
        return c;
      },
    },
    cookies: { get: (n) => (n in cookies ? { value: cookies[n] } : undefined) },
  };
}

const BASE_HEADERS = {
  "x-frame-options": "DENY",
  "x-content-type-options": "nosniff",
  "referrer-policy": "strict-origin-when-cross-origin",
  "permissions-policy": "camera=(), microphone=(), geolocation=()",
};

function assertBase(res, label, { hsts }) {
  for (const [k, v] of Object.entries(BASE_HEADERS)) {
    assert.equal(res.headers.get(k), v, `${label}: ${k}`);
  }
  const h = res.headers.get("strict-transport-security");
  if (hsts) {
    assert.match(h, /^max-age=(\d+); includeSubDomains$/, label);
    assert.ok(Number(h.match(/max-age=(\d+)/)[1]) >= 31536000, label);
  } else {
    assert.equal(h, null, `${label}: no HSTS expected`);
  }
}

test("production page CSP has no 'unsafe-inline'/'unsafe-eval' in script-src; nonce + strict-dynamic", () => {
  const csp = sh.buildCsp({ NODE_ENV: "production" }, "abc123");
  const s = scriptSrc(csp);
  assert.equal(s, "script-src 'self' 'nonce-abc123' 'strict-dynamic'");
  assert.ok(!s.includes("unsafe-inline") && !s.includes("unsafe-eval"));
  assert.ok(directives(csp).includes("style-src 'self'"));
  assert.ok(directives(csp).includes("frame-ancestors 'none'"));
  assert.ok(directives(csp).includes("base-uri 'self'"));
  assert.ok(directives(csp).includes("form-action 'self'"));
});

test("production CSP without a nonce fails closed (no unsafe-inline)", () => {
  const s = scriptSrc(sh.buildCsp({ NODE_ENV: "production" }));
  assert.equal(s, "script-src 'self'");
});

test("development CSP keeps unsafe-inline/unsafe-eval for HMR", () => {
  const s = scriptSrc(sh.buildCsp({ NODE_ENV: "development" }, "n"));
  assert.equal(s, "script-src 'self' 'unsafe-inline' 'unsafe-eval'");
});

test("HSTS is production-only with max-age>=1y and includeSubDomains", () => {
  const prod = Object.fromEntries(sh.baseSecurityHeaders({ NODE_ENV: "production" }));
  assert.equal(prod["Strict-Transport-Security"], "max-age=31536000; includeSubDomains");
  const viaAppEnv = Object.fromEntries(sh.baseSecurityHeaders({ APP_ENV: "Production" }));
  assert.ok(viaAppEnv["Strict-Transport-Security"]);
  const dev = Object.fromEntries(sh.baseSecurityHeaders({ NODE_ENV: "development" }));
  assert.equal(dev["Strict-Transport-Security"], undefined);
  for (const k of ["X-Frame-Options", "X-Content-Type-Options", "Referrer-Policy", "Permissions-Policy"]) {
    assert.ok(prod[k], k);
  }
});

test("middleware: EVERY response kind carries the base security headers (prod)", async () => {
  await withEnv(PROD, async () => {
    const good = mintHs256(SECRET, adminPayload());
    const authed = { carzo_admin_jwt: good };
    const cases = [
      ["/backend-api/api/admin/users", {}, "api"],
      ["/backend-api/api/admin/export.csv", authed, "api"],
      ["/api/health", {}, "api"],
      ["/api/admin-session", {}, "api"],
      ["/_next/data/x.json", {}, "asset"],
      ["/favicon.ico", {}, "asset"],
      ["/logo.png", {}, "asset"],
      ["/login", {}, "page"],
      ["/dashboard", authed, "page"],
      ["/dashboard", {}, "page"], // redirect to /login
      ["/login", authed, "page"], // redirect to /dashboard
    ];
    for (const [p, cookies, kind] of cases) {
      const res = await middleware(nextRequest(p, cookies));
      assertBase(res, p, { hsts: true });
      const csp = res.headers.get("content-security-policy");
      if (kind === "api") assert.equal(csp, sh.API_RESPONSE_CSP, p);
      else if (kind === "asset") assert.equal(csp, null, p);
      else {
        assert.match(scriptSrc(csp), /^script-src 'self' 'nonce-[A-Za-z0-9+/=]+' 'strict-dynamic'$/, p);
        assert.ok(!csp.includes("'unsafe-inline' 'unsafe-eval'"), p);
      }
    }
  });
});

test("middleware: authenticated page request forwards the nonce CSP to Next (request headers)", async () => {
  await withEnv(PROD, async () => {
    const res = await middleware(nextRequest("/dashboard", { carzo_admin_jwt: mintHs256(SECRET, adminPayload()) }));
    const reqCsp = res.requestHeaders.get("content-security-policy");
    const nonce = res.requestHeaders.get("x-nonce");
    assert.ok(nonce && nonce.length >= 16);
    assert.match(reqCsp, new RegExp(`'nonce-${nonce.replace(/[+/=]/g, "\\$&")}'`));
    assert.equal(res.headers.get("content-security-policy"), reqCsp);
    // fresh nonce per request
    const res2 = await middleware(nextRequest("/dashboard", { carzo_admin_jwt: mintHs256(SECRET, adminPayload()) }));
    assert.notEqual(res2.requestHeaders.get("x-nonce"), nonce);
  });
});

test("middleware: development has no HSTS and the dev CSP", async () => {
  await withEnv(DEV, async () => {
    const res = await middleware(nextRequest("/login"));
    assertBase(res, "dev /login", { hsts: false });
    assert.match(scriptSrc(res.headers.get("content-security-policy")), /unsafe-eval/);
    const api = await middleware(nextRequest("/backend-api/x"));
    assertBase(api, "dev api", { hsts: false });
  });
});

// ---- proxy route response headers ----------------------------------------
async function proxyOnce(upstreamInit, { method = "GET", body } = {}) {
  const calls = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    return new Response(upstreamInit.body ?? '{"ok":true}', {
      status: upstreamInit.status ?? 200,
      headers: upstreamInit.headers ?? { "content-type": "application/json" },
    });
  };
  try {
    jar.clear();
    jar.set("carzo_admin_jwt", mintHs256(SECRET, adminPayload()));
    const headers = { host: "admin.example.com", "x-forwarded-proto": "https" };
    if (method !== "GET") headers.origin = "https://admin.example.com";
    const request = new Request("https://admin.example.com/backend-api/api/admin/users?x=1", {
      method,
      headers,
      ...(body ? { body, duplex: "half" } : {}),
    });
    const res = await route[method](request, {
      params: Promise.resolve({ path: ["api", "admin", "users"] }),
    });
    return { res, calls };
  } finally {
    globalThis.fetch = realFetch;
  }
}

test("proxied responses keep nosniff and get frame/referrer/permissions/HSTS/sandbox CSP; upstream Set-Cookie and hop-by-hop headers are dropped", async () => {
  await withEnv({ ...PROD, API_PROXY_TARGET: "https://api.example.com" }, async () => {
    const { res, calls } = await proxyOnce({
      headers: {
        "content-type": "text/html",
        etag: '"abc"',
        "set-cookie": "evil=1; Path=/",
        connection: "keep-alive",
        "transfer-encoding": "chunked",
        "x-powered-by": "flask",
        server: "gunicorn",
      },
      body: "<script>alert(1)</script>",
    });
    assert.equal(calls.length, 1);
    assert.equal(res.status, 200);
    assertBase(res, "proxy", { hsts: true });
    assert.equal(res.headers.get("content-security-policy"), sh.API_RESPONSE_CSP);
    assert.match(res.headers.get("content-security-policy"), /sandbox/);
    assert.equal(res.headers.get("content-type"), "text/html");
    assert.equal(res.headers.get("etag"), '"abc"');
    for (const bad of ["set-cookie", "connection", "transfer-encoding", "x-powered-by", "server"]) {
      assert.equal(res.headers.get(bad), null, bad);
    }
    assert.equal(res.headers.get("cache-control"), "private, no-store");
  });
});

test("proxy keeps an upstream Cache-Control instead of overriding it", async () => {
  await withEnv({ ...PROD, API_PROXY_TARGET: "https://api.example.com" }, async () => {
    const { res } = await proxyOnce({
      headers: { "content-type": "application/json", "cache-control": "max-age=60, private" },
    });
    assert.equal(res.headers.get("cache-control"), "max-age=60, private");
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
  });
});
