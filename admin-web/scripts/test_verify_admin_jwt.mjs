/**
 * Smoke test for admin JWT checks (C-08).
 * Run from repo root: node admin-web/scripts/test_verify_admin_jwt.mjs
 */
import { createHmac } from "node:crypto";
import assert from "node:assert/strict";

function b64urlJson(obj) {
  return Buffer.from(JSON.stringify(obj)).toString("base64url");
}

function mint(secret, payload) {
  const header = b64urlJson({ alg: "HS256", typ: "JWT" });
  const body = b64urlJson(payload);
  const data = `${header}.${body}`;
  const sig = createHmac("sha256", secret).update(data).digest("base64url");
  return `${data}.${sig}`;
}

async function verifyAdminAccessJwt(token, secret) {
  const trimmed = (token || "").trim();
  if (!trimmed) return { ok: false, reason: "empty" };
  const parts = trimmed.split(".");
  if (parts.length !== 3) return { ok: false, reason: "malformed" };
  const [headerB64, payloadB64, sigB64] = parts;
  let header;
  let payload;
  try {
    header = JSON.parse(Buffer.from(headerB64, "base64url").toString("utf8"));
    payload = JSON.parse(Buffer.from(payloadB64, "base64url").toString("utf8"));
  } catch {
    return { ok: false, reason: "decode" };
  }
  if ((header.alg || "HS256") !== "HS256") return { ok: false, reason: "alg" };
  if (payload.type && payload.type !== "access") return { ok: false, reason: "type" };
  if (typeof payload.exp === "number" && payload.exp * 1000 <= Date.now()) {
    return { ok: false, reason: "expired" };
  }
  const sub = payload.sub != null ? String(payload.sub) : "";
  if (!sub) return { ok: false, reason: "sub" };
  const isAdminClaim =
    payload.is_admin === true ||
    String(payload.account_scope || "").toLowerCase() === "admin";
  if (!isAdminClaim) return { ok: false, reason: "not_admin" };
  if (!secret) return { ok: true, sub };

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const pad = "=".repeat((4 - (sigB64.length % 4)) % 4);
  const b64 = (sigB64 + pad).replace(/-/g, "+").replace(/_/g, "/");
  const raw = Buffer.from(b64, "base64");
  const valid = await crypto.subtle.verify("HMAC", key, raw, data);
  if (!valid) return { ok: false, reason: "signature" };
  return { ok: true, sub };
}

const secret = "test-admin-jwt-secret";
const good = mint(secret, {
  sub: "admin-public-id",
  type: "access",
  is_admin: true,
  exp: Math.floor(Date.now() / 1000) + 3600,
});
const nonAdmin = mint(secret, {
  sub: "user-public-id",
  type: "access",
  exp: Math.floor(Date.now() / 1000) + 3600,
});
const badSig = `${good.slice(0, good.lastIndexOf(".") + 1)}deadbeefdeadbeefdeadbeefdeadbeef`;
const expired = mint(secret, {
  sub: "admin-public-id",
  type: "access",
  is_admin: true,
  exp: Math.floor(Date.now() / 1000) - 10,
});

assert.equal((await verifyAdminAccessJwt(good, secret)).ok, true);
assert.equal((await verifyAdminAccessJwt(nonAdmin, secret)).ok, false);
assert.equal((await verifyAdminAccessJwt(badSig, secret)).ok, false);
assert.equal((await verifyAdminAccessJwt(expired, secret)).ok, false);
assert.equal((await verifyAdminAccessJwt("1", secret)).ok, false);
assert.equal((await verifyAdminAccessJwt(good, "wrong-secret")).ok, false);

console.log("OK: admin JWT verification smoke passed");
