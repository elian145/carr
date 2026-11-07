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
import { mintHs256, adminPayload, withEnv } from "./f19-stubs.mjs";

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
  // dev fallback (no secret, no key): structure only, exactly as before
  assert.equal((await verifyAdminAccessJwt(hs, "")).ok, true);
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
