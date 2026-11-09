/**
 * F-19: CSRF/Origin enforcement on the cookie-authenticated proxy
 * (/backend-api/[...path]) and the admin-session route, plus the session
 * cookie attributes. Real route modules; only next/server + next/headers and
 * global fetch are stubbed.
 * Run: node --test scripts/test_f19_proxy_csrf.mjs
 */
import test from "node:test";
import assert from "node:assert/strict";
import { createTsLoader } from "./ts-loader.mjs";
import { StubNextResponse, mintHs256, adminPayload, withEnv } from "./f19-stubs.mjs";

const SECRET = "f19-test-secret";
const HOST = "admin.example.com";
const jar = new Map();
const loader = createTsLoader({
  "next/server": { NextResponse: StubNextResponse },
  "next/headers": { cookies: async () => ({ get: (n) => (jar.has(n) ? { value: jar.get(n) } : undefined) }) },
});
const proxy = loader.load("src/app/backend-api/[...path]/route.ts");
const session = loader.load("src/app/api/admin-session/route.ts");

const ENV = {
  NODE_ENV: "production",
  JWT_SECRET_KEY: SECRET,
  API_PROXY_TARGET: "https://api.example.com",
  ADMIN_ALLOWED_ORIGINS: undefined,
  ADMIN_JWT_PUBLIC_KEY: undefined,
};

function withFetch(handler) {
  const calls = [];
  const real = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    return handler(String(url), init, calls.length);
  };
  return { calls, restore: () => (globalThis.fetch = real) };
}

function proxyRequest(method, headers = {}, body) {
  return new Request(`https://${HOST}/backend-api/api/admin/users?x=1`, {
    method,
    headers: { host: HOST, "x-forwarded-proto": "https", ...headers },
    ...(body !== undefined ? { body, duplex: "half" } : {}),
  });
}
const ctx = { params: Promise.resolve({ path: ["api", "admin", "users"] }) };
const jsonOk = () => new Response('{"ok":true}', { status: 200, headers: { "content-type": "application/json" } });

function login() {
  jar.clear();
  jar.set("carzo_admin_jwt", mintHs256(SECRET, adminPayload()));
}

for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
  test(`proxy ${method}: cross-origin and Origin-less requests get 403 and never reach the API`, async () => {
    await withEnv(ENV, async () => {
      login();
      const f = withFetch(jsonOk);
      try {
        for (const headers of [
          { origin: "https://evil.example" },
          { origin: "null" },
          { referer: "https://evil.example/attack.html" },
          {},
        ]) {
          const res = await proxy[method](proxyRequest(method, headers, "{}"), ctx);
          assert.equal(res.status, 403, JSON.stringify(headers));
          assert.deepEqual(await res.json(), { message: "Cross-site request blocked" });
        }
        assert.equal(f.calls.length, 0, "no request may be forwarded");
      } finally {
        f.restore();
      }
    });
  });

  test(`proxy ${method}: same-origin Origin (or same-origin Referer) is forwarded with the Bearer token`, async () => {
    await withEnv(ENV, async () => {
      login();
      const f = withFetch(jsonOk);
      try {
        for (const headers of [{ origin: `https://${HOST}` }, { referer: `https://${HOST}/users` }]) {
          const res = await proxy[method](proxyRequest(method, headers, "{}"), ctx);
          assert.equal(res.status, 200, JSON.stringify(headers));
        }
        assert.equal(f.calls.length, 2);
        assert.equal(f.calls[0].url, "https://api.example.com/api/admin/users?x=1");
        assert.equal(f.calls[0].init.method, method);
        assert.match(f.calls[0].init.headers.get("authorization"), /^Bearer ey/);
        // the browser's Origin/Cookie are not forwarded upstream
        assert.equal(f.calls[0].init.headers.get("origin"), null);
        assert.equal(f.calls[0].init.headers.get("cookie"), null);
      } finally {
        f.restore();
      }
    });
  });
}

test("proxy GET/HEAD/OPTIONS are unaffected by the Origin check (even cross-origin / no Origin)", async () => {
  await withEnv(ENV, async () => {
    login();
    const f = withFetch(jsonOk);
    try {
      for (const method of ["GET", "HEAD", "OPTIONS"]) {
        for (const headers of [{}, { origin: "https://evil.example" }]) {
          const res = await proxy[method](proxyRequest(method, headers), ctx);
          assert.equal(res.status, 200, `${method} ${JSON.stringify(headers)}`);
        }
      }
      assert.equal(f.calls.length, 6);
    } finally {
      f.restore();
    }
  });
});

test("proxy without a session is still 401 (same-origin POST) and 403 (cross-origin POST) - no open relay", async () => {
  await withEnv(ENV, async () => {
    jar.clear();
    const f = withFetch(jsonOk);
    try {
      const a = await proxy.POST(proxyRequest("POST", { origin: `https://${HOST}` }, "{}"), ctx);
      assert.equal(a.status, 401);
      const b = await proxy.POST(proxyRequest("POST", { origin: "https://evil.example" }, "{}"), ctx);
      assert.equal(b.status, 403);
      assert.equal(f.calls.length, 0);
    } finally {
      f.restore();
    }
  });
});

test("ADMIN_ALLOWED_ORIGINS lets a configured public origin through and blocks the rest", async () => {
  await withEnv({ ...ENV, ADMIN_ALLOWED_ORIGINS: "https://panel.example.org" }, async () => {
    login();
    const f = withFetch(jsonOk);
    try {
      const ok = await proxy.POST(proxyRequest("POST", { origin: "https://panel.example.org" }, "{}"), ctx);
      assert.equal(ok.status, 200);
      const bad = await proxy.POST(proxyRequest("POST", { origin: `https://${HOST}` }, "{}"), ctx);
      assert.equal(bad.status, 403);
    } finally {
      f.restore();
    }
  });
});

// ---- /api/admin-session -----------------------------------------------------
function sessionRequest(method, headers = {}, body = JSON.stringify({ username: "a", password: "b" })) {
  return new Request(`https://${HOST}/api/admin-session`, {
    method,
    headers: { host: HOST, "x-forwarded-proto": "https", "content-type": "application/json", ...headers },
    ...(method === "POST" ? { body } : {}),
  });
}

function loginUpstream(url) {
  if (url.endsWith("/api/auth/login")) {
    return new Response(JSON.stringify({ access_token: "acc.tok.en", refresh_token: "ref.tok.en" }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }
  return new Response(JSON.stringify({ id: 1, is_admin: true }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

test("admin-session POST/DELETE: cross-origin and Origin-less are 403 and never contact the API", async () => {
  await withEnv(ENV, async () => {
    const f = withFetch(loginUpstream);
    try {
      for (const headers of [{ origin: "https://evil.example" }, { origin: "null" }, {}]) {
        const p = await session.POST(sessionRequest("POST", headers));
        assert.equal(p.status, 403, JSON.stringify(headers));
        const d = await session.DELETE(sessionRequest("DELETE", headers));
        assert.equal(d.status, 403, JSON.stringify(headers));
        assert.equal(d.headers.get("set-cookie"), null, "logout CSRF must not clear cookies");
        assert.deepEqual(d.cookieCalls ?? [], [], "logout CSRF must not clear cookies");
      }
      assert.equal(f.calls.length, 0);
    } finally {
      f.restore();
    }
  });
});

test("admin-session: same-origin login works and sets httpOnly, Secure, SameSite=Lax cookies", async () => {
  await withEnv(ENV, async () => {
    const f = withFetch(loginUpstream);
    try {
      const res = await session.POST(sessionRequest("POST", { origin: `https://${HOST}` }));
      assert.equal(res.status, 200);
      assert.equal(f.calls.length, 2);
      const set = Object.fromEntries(res.cookieCalls.map((c) => [c.name, c]));
      for (const name of ["carzo_admin_jwt", "carzo_admin_refresh"]) {
        assert.equal(set[name].opts.httpOnly, true, name);
        assert.equal(set[name].opts.secure, true, name);
        assert.equal(set[name].opts.sameSite, "lax", name);
        assert.equal(set[name].opts.path, "/", name);
        assert.ok(set[name].opts.maxAge > 0, name);
      }
      const out = await session.DELETE(sessionRequest("DELETE", { origin: `https://${HOST}` }));
      assert.equal(out.status, 200);
      assert.ok(out.cookieCalls.some((c) => c.name === "carzo_admin_jwt" && c.opts.maxAge === 0));
    } finally {
      f.restore();
    }
  });
});
