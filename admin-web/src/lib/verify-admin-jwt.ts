/**
 * Edge-compatible verification for Flask-JWT-Extended access tokens.
 *
 * Two signature schemes (F-19):
 *  - ES256 (preferred): admin-scoped tokens signed by the API with a private key
 *    that admin-web never sees. admin-web verifies with ADMIN_JWT_PUBLIC_KEY, so
 *    compromising admin-web cannot mint any token.
 *  - HS256 (legacy): needs the API's shared JWT_SECRET_KEY on the admin service
 *    (the weakness F-19 removes). Only used while a deployment still configures
 *    that secret; remove it from the admin service after the staged migration.
 */

function b64urlToBytes(input: string): Uint8Array {
  const pad = "=".repeat((4 - (input.length % 4)) % 4);
  const b64 = (input + pad).replace(/-/g, "+").replace(/_/g, "/");
  const raw = atob(b64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i += 1) out[i] = raw.charCodeAt(i);
  return out;
}

function decodeJsonPart<T>(part: string): T | null {
  try {
    return JSON.parse(new TextDecoder().decode(b64urlToBytes(part))) as T;
  } catch {
    return null;
  }
}

const ES256_SIGNATURE_BYTES = 64; // JWS ES256 = raw r||s (IEEE P1363), 32+32

const publicKeyCache = new Map<string, Promise<CryptoKey | null>>();

/** Accepts a PEM (real or with literal `\\n`) or bare base64 SPKI. */
function spkiBytesFromPem(pem: string): Uint8Array | null {
  const body = (pem || "")
    .replace(/\\[rn]/g, "")
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  if (!body) return null;
  try {
    const raw = atob(body.replace(/-/g, "+").replace(/_/g, "/"));
    const out = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i += 1) out[i] = raw.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

function importAdminPublicKey(pem: string): Promise<CryptoKey | null> {
  let cached = publicKeyCache.get(pem);
  if (!cached) {
    const der = spkiBytesFromPem(pem);
    cached = der
      ? crypto.subtle
          .importKey(
            "spki",
            der as unknown as BufferSource,
            { name: "ECDSA", namedCurve: "P-256" },
            false,
            ["verify"],
          )
          .catch(() => null)
      : Promise.resolve(null);
    publicKeyCache.set(pem, cached);
  }
  return cached;
}

export type AdminJwtCheck =
  | { ok: true; sub: string }
  | { ok: false; reason: string };

/**
 * Verify an admin access JWT.
 *  - alg ES256: signature MUST verify against `publicKey` (ADMIN_JWT_PUBLIC_KEY);
 *    without a configured public key the token is rejected (never trusted
 *    unverified) and the token must carry `account_scope=admin`.
 *  - alg HS256 (legacy): when `secret` is set the signature must match. When
 *    `secret` is empty AND no `publicKey` is configured, only structure + exp
 *    are checked (dev fallback; callers refuse this in production). When a
 *    `publicKey` is configured but `secret` is empty (the post-migration state)
 *    HS256 tokens are rejected: admin-web cannot verify them.
 * Requires `is_admin` / `account_scope=admin` claim so a normal user JWT
 * cannot pass the admin edge gate.
 */
export async function verifyAdminAccessJwt(
  token: string,
  secret: string,
  publicKey: string = "",
): Promise<AdminJwtCheck> {
  const trimmed = (token || "").trim();
  if (!trimmed) return { ok: false, reason: "empty" };

  const parts = trimmed.split(".");
  if (parts.length !== 3) return { ok: false, reason: "malformed" };

  const [headerB64, payloadB64, sigB64] = parts;
  const header = decodeJsonPart<{ alg?: string; typ?: string }>(headerB64);
  const payload = decodeJsonPart<{
    exp?: number;
    sub?: string;
    type?: string;
    is_admin?: boolean;
    account_scope?: string;
  }>(payloadB64);
  if (!header || !payload) return { ok: false, reason: "decode" };
  const alg = header.alg || "HS256";
  if (alg !== "HS256" && alg !== "ES256") {
    return { ok: false, reason: "alg" };
  }
  if (payload.type && payload.type !== "access") {
    return { ok: false, reason: "type" };
  }
  if (typeof payload.exp === "number" && payload.exp * 1000 <= Date.now()) {
    return { ok: false, reason: "expired" };
  }
  const sub = payload.sub != null ? String(payload.sub) : "";
  if (!sub) return { ok: false, reason: "sub" };

  const isAdminClaim =
    payload.is_admin === true ||
    String(payload.account_scope || "").toLowerCase() === "admin";
  if (!isAdminClaim) {
    return { ok: false, reason: "not_admin" };
  }

  if (alg === "ES256") {
    if (String(payload.account_scope || "").toLowerCase() !== "admin") {
      return { ok: false, reason: "not_admin" };
    }
    if (!publicKey) return { ok: false, reason: "no_public_key" };
    try {
      const key = await importAdminPublicKey(publicKey);
      if (!key) return { ok: false, reason: "bad_public_key" };
      const signature = b64urlToBytes(sigB64);
      if (signature.length !== ES256_SIGNATURE_BYTES) {
        return { ok: false, reason: "signature" };
      }
      const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
      const valid = await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        key,
        signature as unknown as BufferSource,
        data,
      );
      if (!valid) return { ok: false, reason: "signature" };
      return { ok: true, sub };
    } catch {
      return { ok: false, reason: "verify_error" };
    }
  }

  // HS256 (legacy shared-secret) below.
  if (!secret) {
    // Public key configured, no shared secret: the migrated state. A
    // structure-only pass here would accept ANY forged HS256 token.
    if (publicKey) return { ok: false, reason: "hs256_unverifiable" };
    return { ok: true, sub };
  }

  try {
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
    const signature = b64urlToBytes(sigB64);
    // Pass the Uint8Array itself, NOT `signature.buffer`: in Next's Edge
    // sandbox (on `next start`) the ArrayBuffer belongs to a different realm
    // than the one Node's WebCrypto checks with `instanceof`, so
    // `verify(..., signature.buffer, ...)` throws "3rd argument is not
    // instance of ArrayBuffer". That made EVERY access-token check fail
    // ("verify_error"), so every request fell through to a refresh-token
    // rotation -- and parallel requests (prefetches, page loads) raced on the
    // single-use refresh token and bounced the admin to /login.
    const valid = await crypto.subtle.verify(
      "HMAC",
      key,
      signature as unknown as BufferSource,
      data,
    );
    if (!valid) return { ok: false, reason: "signature" };
    return { ok: true, sub };
  } catch {
    return { ok: false, reason: "verify_error" };
  }
}
