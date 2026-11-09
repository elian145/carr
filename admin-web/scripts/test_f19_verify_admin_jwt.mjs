/**
 * F-19: admin edge JWT verification (ES256 public-key mode + legacy HS256).
 * Exercises the real src/lib/verify-admin-jwt.ts and
 * src/lib/admin-session-auth.ts::resolveAdminAccessToken.
 * Run: node --test scripts/test_f19_verify_admin_jwt.mjs
 */
import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { createTsLoader } from "./ts-loader.mjs";
import { mintHs256, adminPayload, withEnv, ADMIN_AUD } from "./f19-stubs.mjs";

const loader = createTsLoader({ "next/server": { NextResponse: class {} } });
const { verifyAdminAccessJwt } = loader.load("src/lib/verify-admin-jwt.ts");
const { resolveAdminAccessToken } = loader.load("src/lib/admin-session-auth.ts");

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
function ec() {
  const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  return { privateKey, pem: publicKey.export({ type: "spki", format: "pem" }).toString() };
}
function mintEs256(privateKey, payload, header = { alg: "ES256", typ: "JWT" }, dsaEncoding = "ieee-p1363") {
  const data = `${b64(header)}.${b64(payload)}`;
  const sig = sign("sha256", Buffer.from(data), { key: privateKey, dsaEncoding });
  return `${data}.${sig.toString("base64url")}`;
}

const good = ec();
const other = ec();

test("ES256: valid admin token verifies with ONLY the public key (no shared secret)", async () => {
  const tok = mintEs256(good.privateKey, adminPayload());
  assert.deepEqual(await verifyAdminAccessJwt(tok, "", good.pem), { ok: true, sub: "admin-public-id" });
  // also fine when a legacy secret is still configured
  assert.equal((await verifyAdminAccessJwt(tok, "legacy", good.pem)).ok, true);
});

test("ES256: PEM with literal \\n (dashboard style), bare base64 body all import", async () => {
  const tok = mintEs256(good.privateKey, adminPayload());
  const escaped = good.pem.trim().replace(/\n/g, "\\n");
  assert.equal((await verifyAdminAccessJwt(tok, "", escaped)).ok, true);
  const bare = good.pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  assert.equal((await verifyAdminAccessJwt(tok, "", bare)).ok, true);
});

test("ES256: wrong key, tampered payload, truncated/DER signature, expired, not admin are rejected", async () => {
  const tok = mintEs256(good.privateKey, adminPayload());
  assert.equal((await verifyAdminAccessJwt(mintEs256(other.privateKey, adminPayload()), "", good.pem)).reason, "signature");
  const [h, , s] = tok.split(".");
  const tampered = `${h}.${b64(adminPayload({ sub: "someone-else" }))}.${s}`;
  assert.equal((await verifyAdminAccessJwt(tampered, "", good.pem)).reason, "signature");
  assert.equal((await verifyAdminAccessJwt(`${tok.slice(0, -6)}`, "", good.pem)).ok, false);
  const der = mintEs256(good.privateKey, adminPayload(), undefined, "der");
  assert.equal((await verifyAdminAccessJwt(der, "", good.pem)).ok, false);
  const expired = mintEs256(good.privateKey, adminPayload({ exp: Math.floor(Date.now() / 1000) - 5 }));
  assert.equal((await verifyAdminAccessJwt(expired, "", good.pem)).reason, "expired");
  const notAdmin = mintEs256(good.privateKey, { sub: "u", type: "access", exp: Math.floor(Date.now() / 1000) + 60 });
  assert.equal((await verifyAdminAccessJwt(notAdmin, "", good.pem)).ok, false);
  // validly signed but only is_admin (no account_scope=admin) is not an admin session
  const flagOnly = mintEs256(good.privateKey, adminPayload({ account_scope: undefined }));
  assert.equal((await verifyAdminAccessJwt(flagOnly, "", good.pem)).reason, "not_admin");
  const refresh = mintEs256(good.privateKey, adminPayload({ type: "refresh" }));
  assert.equal((await verifyAdminAccessJwt(refresh, "", good.pem)).reason, "type");
});

test("ES256 without a configured public key is never trusted", async () => {
  const tok = mintEs256(good.privateKey, adminPayload());
  assert.equal((await verifyAdminAccessJwt(tok, "", "")).reason, "no_public_key");
  assert.equal((await verifyAdminAccessJwt(tok, "legacy-secret", "")).reason, "no_public_key");
  assert.equal((await verifyAdminAccessJwt(tok, "", "not a key")).ok, false);
});

test("migrated state (public key, no secret): HS256 tokens - even validly structured - are rejected", async () => {
  const hs = mintHs256("whatever-secret", adminPayload());
  assert.equal((await verifyAdminAccessJwt(hs, "", good.pem)).reason, "hs256_unverifiable");
});

test("alg=none / unknown algs are rejected in every configuration", async () => {
  const none = `${b64({ alg: "none", typ: "JWT" })}.${b64(adminPayload())}.`;
  const rs = `${b64({ alg: "RS256", typ: "JWT" })}.${b64(adminPayload())}.AAAA`;
  for (const [secret, pub] of [["", ""], ["s", ""], ["", good.pem], ["s", good.pem]]) {
    assert.equal((await verifyAdminAccessJwt(none, secret, pub)).reason, "alg");
    assert.equal((await verifyAdminAccessJwt(rs, secret, pub)).reason, "alg");
  }
});

test("legacy HS256 behaviour is unchanged when only JWT_SECRET_KEY is configured", async () => {
  const hs = mintHs256("s3cret", adminPayload());
  assert.equal((await verifyAdminAccessJwt(hs, "s3cret")).ok, true);
  assert.equal((await verifyAdminAccessJwt(hs, "wrong")).reason, "signature");
  // F-32: no secret, no key => fail closed unless the dev opt-in is explicit
  assert.equal((await verifyAdminAccessJwt(hs, "")).reason, "unverifiable");
  assert.equal((await verifyAdminAccessJwt(hs, "", "", { allowUnsignedDev: true })).ok, true);
  const es = mintEs256(good.privateKey, adminPayload());
  assert.equal((await verifyAdminAccessJwt(es, "s3cret")).reason, "no_public_key");
});

// ---- session resolution (production fail-closed rules) ---------------------------
const jarOf = (access) => ({ get: (n) => (n === "carzo_admin_jwt" && access ? { value: access } : undefined) });

test("production with ONLY the public key: ES256 session accepted, HS256 session not", async () => {
  await withEnv({ NODE_ENV: "production", JWT_SECRET_KEY: undefined, ADMIN_JWT_PUBLIC_KEY: good.pem }, async () => {
    const es = mintEs256(good.privateKey, adminPayload());
    assert.equal(await resolveAdminAccessToken(jarOf(es)), es);
    const hs = mintHs256("x", adminPayload());
    assert.equal(await resolveAdminAccessToken(jarOf(hs)), null);
  });
});

test("production with NEITHER secret nor public key fails closed", async () => {
  await withEnv({ NODE_ENV: "production", JWT_SECRET_KEY: undefined, ADMIN_JWT_PUBLIC_KEY: undefined }, async () => {
    assert.equal(await resolveAdminAccessToken(jarOf(mintHs256("x", adminPayload()))), null);
    assert.equal(await resolveAdminAccessToken(jarOf(mintEs256(good.privateKey, adminPayload()))), null);
  });
});

test("production legacy (secret only) still works; dual (secret + public key) accepts both", async () => {
  await withEnv({ NODE_ENV: "production", JWT_SECRET_KEY: "s3cret", ADMIN_JWT_PUBLIC_KEY: undefined }, async () => {
    const hs = mintHs256("s3cret", adminPayload());
    assert.equal(await resolveAdminAccessToken(jarOf(hs)), hs);
  });
  await withEnv({ NODE_ENV: "production", JWT_SECRET_KEY: "s3cret", ADMIN_JWT_PUBLIC_KEY: good.pem }, async () => {
    const hs = mintHs256("s3cret", adminPayload());
    const es = mintEs256(good.privateKey, adminPayload());
    assert.equal(await resolveAdminAccessToken(jarOf(hs)), hs);
    assert.equal(await resolveAdminAccessToken(jarOf(es)), es);
  });
});

// ---- F-32 ------------------------------------------------------------------------
test("F-32: tokens without a numeric exp are rejected (HS256 and ES256)", async () => {
  const { exp: _drop, ...noExp } = adminPayload();
  assert.equal((await verifyAdminAccessJwt(mintHs256("s3cret", noExp), "s3cret")).reason, "no_exp");
  assert.equal((await verifyAdminAccessJwt(mintEs256(good.privateKey, noExp), "", good.pem)).reason, "no_exp");
  assert.equal(
    (await verifyAdminAccessJwt(mintHs256("s3cret", adminPayload({ exp: "9999999999" })), "s3cret")).reason,
    "no_exp",
  );
});

test("F-32: dev without secret accepts unsigned claims ONLY with explicit non-production opt-in", async () => {
  const hs = mintHs256("whatever", adminPayload());
  await withEnv({ NODE_ENV: "development", APP_ENV: undefined, JWT_SECRET_KEY: undefined, ADMIN_JWT_PUBLIC_KEY: undefined, ADMIN_ALLOW_UNSIGNED_DEV: undefined }, async () => {
    assert.equal(await resolveAdminAccessToken(jarOf(hs)), null);
  });
  await withEnv({ NODE_ENV: "development", APP_ENV: undefined, JWT_SECRET_KEY: undefined, ADMIN_JWT_PUBLIC_KEY: undefined, ADMIN_ALLOW_UNSIGNED_DEV: "1" }, async () => {
    assert.equal(await resolveAdminAccessToken(jarOf(hs)), hs);
  });
  // the opt-in is ignored in production (which also fails closed without any key)
  await withEnv({ NODE_ENV: "production", JWT_SECRET_KEY: undefined, ADMIN_JWT_PUBLIC_KEY: undefined, ADMIN_ALLOW_UNSIGNED_DEV: "1" }, async () => {
    assert.equal(await resolveAdminAccessToken(jarOf(hs)), null);
  });
  await withEnv({ NODE_ENV: "production", JWT_SECRET_KEY: "s3cret", ADMIN_JWT_PUBLIC_KEY: undefined, ADMIN_ALLOW_UNSIGNED_DEV: "1" }, async () => {
    assert.equal(await resolveAdminAccessToken(jarOf(hs)), null); // wrong signature still rejected
  });
});

test("F-32: cookie Secure flag is forced on in production regardless of x-forwarded-proto", async () => {
  const { cookieSecureFromRequest } = loader.load("src/lib/admin-session-auth.ts");
  const req = (headers, url = "http://admin.example.com/x") => new Request(url, { headers });
  await withEnv({ NODE_ENV: "production", APP_ENV: undefined, ADMIN_COOKIE_ALLOW_HTTP: undefined }, async () => {
    assert.equal(cookieSecureFromRequest(req({})), true);
    assert.equal(cookieSecureFromRequest(req({ "x-forwarded-proto": "http" })), true);
  });
  await withEnv({ NODE_ENV: "production", ADMIN_COOKIE_ALLOW_HTTP: "1" }, async () => {
    assert.equal(cookieSecureFromRequest(req({ "x-forwarded-proto": "http" })), false);
  });
  await withEnv({ NODE_ENV: "development", APP_ENV: undefined }, async () => {
    assert.equal(cookieSecureFromRequest(req({})), false);
    assert.equal(cookieSecureFromRequest(req({ "x-forwarded-proto": "https" })), true);
  });
});

// ---- iss / aud (admin-signed ES256 tokens) --------------------------------------
test("ES256: iss and aud are required and strictly validated", async () => {
  const check = (extra) => verifyAdminAccessJwt(mintEs256(good.privateKey, adminPayload(extra)), "", good.pem);
  assert.equal((await check({})).ok, true);
  assert.equal((await check({ iss: undefined })).reason, "issuer");
  assert.equal((await check({ iss: "evil-api" })).reason, "issuer");
  assert.equal((await check({ iss: ["carnet-api"] })).reason, "issuer");
  assert.equal((await check({ aud: undefined })).reason, "audience");
  assert.equal((await check({ aud: "someone-else" })).reason, "audience");
  assert.equal((await check({ aud: 42 })).reason, "audience");
  assert.equal((await check({ aud: [] })).reason, "audience");
  // RFC 7519: aud may be a list as long as it contains ours
  assert.equal((await check({ aud: ["other", ADMIN_AUD] })).ok, true);
  assert.equal((await check({ aud: ["other"] })).reason, "audience");
  // the legacy secret does not relax the requirement on ES256 tokens
  const noIss = mintEs256(good.privateKey, adminPayload({ iss: undefined }));
  assert.equal((await verifyAdminAccessJwt(noIss, "legacy", good.pem)).reason, "issuer");
});

test("ES256: iss/aud overrides (ADMIN_JWT_ISSUER/AUDIENCE) must match exactly", async () => {
  const tok = mintEs256(good.privateKey, adminPayload({ iss: "custom-iss", aud: "custom-aud" }));
  assert.equal((await verifyAdminAccessJwt(tok, "", good.pem)).reason, "issuer");
  const opts = { issuer: "custom-iss", audience: "custom-aud" };
  assert.equal((await verifyAdminAccessJwt(tok, "", good.pem, opts)).ok, true);
  assert.equal((await verifyAdminAccessJwt(tok, "", good.pem, { ...opts, audience: "x" })).reason, "audience");
  // a default-claims token is rejected once the deployment overrides them
  const dflt = mintEs256(good.privateKey, adminPayload());
  assert.equal((await verifyAdminAccessJwt(dflt, "", good.pem, opts)).reason, "issuer");
});

test("ES256 with valid iss/aud is still rejected for wrong alg header, bad signature and expiry", async () => {
  const hdr = (alg) => ({ alg, typ: "JWT" });
  const wrongAlg = mintEs256(good.privateKey, adminPayload(), hdr("RS256"));
  assert.equal((await verifyAdminAccessJwt(wrongAlg, "", good.pem)).reason, "alg");
  const none = `${b64(hdr("none"))}.${b64(adminPayload())}.`;
  assert.equal((await verifyAdminAccessJwt(none, "", good.pem)).reason, "alg");
  // HS256 header on an ES256-signed token cannot be verified without the secret
  const hs256Hdr = mintEs256(good.privateKey, adminPayload(), hdr("HS256"));
  assert.equal((await verifyAdminAccessJwt(hs256Hdr, "", good.pem)).reason, "hs256_unverifiable");
  const forged = mintEs256(other.privateKey, adminPayload());
  assert.equal((await verifyAdminAccessJwt(forged, "", good.pem)).reason, "signature");
  const expired = mintEs256(good.privateKey, adminPayload({ exp: Math.floor(Date.now() / 1000) - 5 }));
  assert.equal((await verifyAdminAccessJwt(expired, "", good.pem)).reason, "expired");
});

test("session (middleware path): ES256 cookie lacking/with wrong iss or aud is not accepted", async () => {
  await withEnv({ NODE_ENV: "production", JWT_SECRET_KEY: undefined, ADMIN_JWT_PUBLIC_KEY: good.pem, ADMIN_JWT_ISSUER: undefined, ADMIN_JWT_AUDIENCE: undefined }, async () => {
    const ok = mintEs256(good.privateKey, adminPayload());
    assert.equal(await resolveAdminAccessToken(jarOf(ok)), ok);
    for (const extra of [{ iss: undefined }, { iss: "x" }, { aud: undefined }, { aud: "x" }]) {
      const bad = mintEs256(good.privateKey, adminPayload(extra));
      assert.equal(await resolveAdminAccessToken(jarOf(bad)), null, JSON.stringify(extra));
    }
  });
  await withEnv({ NODE_ENV: "production", JWT_SECRET_KEY: undefined, ADMIN_JWT_PUBLIC_KEY: good.pem, ADMIN_JWT_ISSUER: "custom-iss", ADMIN_JWT_AUDIENCE: "custom-aud" }, async () => {
    const custom = mintEs256(good.privateKey, adminPayload({ iss: "custom-iss", aud: "custom-aud" }));
    assert.equal(await resolveAdminAccessToken(jarOf(custom)), custom);
    assert.equal(await resolveAdminAccessToken(jarOf(mintEs256(good.privateKey, adminPayload()))), null);
  });
});

test("session (refresh path): the rotated access token is verified too (iss/aud/signature)", async () => {
  const realFetch = globalThis.fetch;
  const refreshJar = (rt) => ({ get: (n) => (n === "carzo_admin_refresh" ? { value: rt } : undefined) });
  const serve = (access) => {
    globalThis.fetch = async () =>
      new Response(JSON.stringify({ access_token: access, refresh_token: "new-refresh" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
  };
  try {
    await withEnv({ NODE_ENV: "production", JWT_SECRET_KEY: undefined, ADMIN_JWT_PUBLIC_KEY: good.pem, ADMIN_JWT_ISSUER: undefined, ADMIN_JWT_AUDIENCE: undefined, API_PROXY_TARGET: "http://api.test" }, async () => {
      const good1 = mintEs256(good.privateKey, adminPayload());
      serve(good1);
      let rotated = null;
      assert.equal(await resolveAdminAccessToken(refreshJar("rt-good"), (a, r) => { rotated = { a, r }; }), good1);
      assert.deepEqual(rotated, { a: good1, r: "new-refresh" });

      const cases = {
        "rt-no-iss": adminPayload({ iss: undefined }),
        "rt-bad-iss": adminPayload({ iss: "evil" }),
        "rt-no-aud": adminPayload({ aud: undefined }),
        "rt-bad-aud": adminPayload({ aud: "evil" }),
        "rt-expired": adminPayload({ exp: Math.floor(Date.now() / 1000) - 5 }),
      };
      for (const [rt, payload] of Object.entries(cases)) {
        serve(mintEs256(good.privateKey, payload));
        let called = false;
        assert.equal(await resolveAdminAccessToken(refreshJar(rt), () => { called = true; }), null, rt);
        assert.equal(called, false, `${rt}: cookies must not be rotated`);
      }
      serve(mintEs256(other.privateKey, adminPayload()));
      assert.equal(await resolveAdminAccessToken(refreshJar("rt-forged")), null);
    });
  } finally {
    globalThis.fetch = realFetch;
  }
});