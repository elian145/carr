/**
 * F-19: Origin/Referer (CSRF) check. Exercises the real src/lib/origin-guard.ts.
 * Run: node --test scripts/test_f19_origin_guard.mjs
 */
import test from "node:test";
import assert from "node:assert/strict";
import { createTsLoader } from "./ts-loader.mjs";

const { checkSameOrigin, rejectCrossSiteRequest, allowedOriginsFromEnv, canonicalOrigin } =
  createTsLoader().load("src/lib/origin-guard.ts");

const HOST = "admin.example.com";

function req(method, headers = {}, url = `https://${HOST}/backend-api/api/admin/users`) {
  return new Request(url, { method, headers });
}

const NO_ENV = {};

test("safe methods are never checked", () => {
  for (const m of ["GET", "HEAD", "OPTIONS"]) {
    assert.deepEqual(checkSameOrigin(req(m, { origin: "https://evil.example" }), NO_ENV), { ok: true });
    assert.deepEqual(checkSameOrigin(req(m), NO_ENV), { ok: true });
  }
});

for (const method of ["POST", "PUT", "PATCH", "DELETE"]) {
  test(`${method}: same-origin Origin is allowed`, () => {
    const r = req(method, { origin: `https://${HOST}`, host: HOST, "x-forwarded-proto": "https" });
    assert.deepEqual(checkSameOrigin(r, NO_ENV), { ok: true });
  });

  test(`${method}: cross-origin / null / missing / garbage are blocked`, () => {
    const base = { host: HOST, "x-forwarded-proto": "https" };
    assert.equal(checkSameOrigin(req(method, { ...base, origin: "https://evil.example" }), NO_ENV).ok, false);
    assert.equal(checkSameOrigin(req(method, { ...base, origin: "null" }), NO_ENV).ok, false);
    assert.equal(checkSameOrigin(req(method, { ...base, origin: "not a url" }), NO_ENV).ok, false);
    assert.equal(checkSameOrigin(req(method, { ...base, origin: "file:///x" }), NO_ENV).ok, false);
    const missing = checkSameOrigin(req(method, base), NO_ENV);
    assert.deepEqual(missing, { ok: false, reason: "missing_origin" });
  });
}

test("lookalike hosts, other ports and other schemes are blocked", () => {
  const base = { host: HOST, "x-forwarded-proto": "https" };
  for (const o of [
    `https://${HOST}.evil.example`,
    `https://evil-${HOST}`,
    `https://${HOST}:8443`,
    `http://${HOST}`,
    `https://sub.${HOST}`,
  ]) {
    assert.equal(checkSameOrigin(req("POST", { ...base, origin: o }), NO_ENV).ok, false, o);
  }
});

test("Referer fallback when Origin is absent", () => {
  const base = { host: HOST, "x-forwarded-proto": "https" };
  assert.deepEqual(
    checkSameOrigin(req("POST", { ...base, referer: `https://${HOST}/users?x=1` }), NO_ENV),
    { ok: true },
  );
  assert.equal(checkSameOrigin(req("POST", { ...base, referer: "https://evil.example/p" }), NO_ENV).ok, false);
  assert.equal(checkSameOrigin(req("POST", { ...base, referer: "garbage" }), NO_ENV).ok, false);
  // Origin wins over Referer: a bad Origin is not rescued by a good Referer
  assert.equal(
    checkSameOrigin(
      req("POST", { ...base, origin: "https://evil.example", referer: `https://${HOST}/` }),
      NO_ENV,
    ).ok,
    false,
  );
});

test("default origin comes from X-Forwarded-Host/Proto behind a proxy", () => {
  const r = req(
    "POST",
    {
      origin: "https://admin.example.com",
      host: "localhost:10000",
      "x-forwarded-host": "admin.example.com",
      "x-forwarded-proto": "https",
    },
    "http://localhost:10000/backend-api/x",
  );
  assert.deepEqual(checkSameOrigin(r, NO_ENV), { ok: true });
});

test("local http dev origin works without proxy headers", () => {
  const r = req("POST", { origin: "http://localhost:3000" }, "http://localhost:3000/api/admin-session");
  assert.deepEqual(checkSameOrigin(r, NO_ENV), { ok: true });
});

test("ADMIN_ALLOWED_ORIGINS replaces the default allow-list", () => {
  const env = { ADMIN_ALLOWED_ORIGINS: "https://panel.example.org, https://admin.example.com/" };
  assert.deepEqual(allowedOriginsFromEnv(env), ["https://panel.example.org", "https://admin.example.com"]);
  const base = { host: "internal:10000" };
  assert.deepEqual(checkSameOrigin(req("POST", { ...base, origin: "https://panel.example.org" }), env), { ok: true });
  assert.equal(checkSameOrigin(req("POST", { ...base, origin: "https://evil.example" }), env).ok, false);
  // when set, header-derived origin is NOT trusted any more
  const only = { ADMIN_ALLOWED_ORIGINS: "https://panel.example.org" };
  const r = req("POST", { origin: `https://${HOST}`, host: HOST, "x-forwarded-proto": "https" });
  assert.equal(checkSameOrigin(r, only).ok, false);
});

test("canonicalOrigin normalises case and default ports", () => {
  assert.equal(canonicalOrigin("HTTPS://Admin.Example.com:443/path"), "https://admin.example.com");
  assert.equal(canonicalOrigin("null"), null);
  assert.equal(canonicalOrigin(""), null);
});

test("rejectCrossSiteRequest returns a 403 JSON response or null", async () => {
  const saved = process.env.ADMIN_ALLOWED_ORIGINS;
  delete process.env.ADMIN_ALLOWED_ORIGINS;
  try {
    const ok = rejectCrossSiteRequest(req("GET"));
    assert.equal(ok, null);
    const blocked = rejectCrossSiteRequest(req("POST", { origin: "https://evil.example", host: HOST }));
    assert.equal(blocked.status, 403);
    assert.equal(blocked.headers.get("x-content-type-options"), "nosniff");
    assert.deepEqual(await blocked.json(), { message: "Cross-site request blocked" });
  } finally {
    if (saved === undefined) delete process.env.ADMIN_ALLOWED_ORIGINS;
    else process.env.ADMIN_ALLOWED_ORIGINS = saved;
  }
});
