/**
 * Edge-compatible HS256 verification for Flask-JWT-Extended access tokens.
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

export type AdminJwtCheck =
  | { ok: true; sub: string }
  | { ok: false; reason: string };

/**
 * Verify an access JWT.
 * When `secret` is set, signature must match (HS256).
 * When `secret` is empty, only structure + exp are checked (dev fallback).
 */
export async function verifyAdminAccessJwt(
  token: string,
  secret: string,
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
  }>(payloadB64);
  if (!header || !payload) return { ok: false, reason: "decode" };
  if ((header.alg || "HS256") !== "HS256") {
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

  if (!secret) {
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
    const sigBuf = signature.slice().buffer;
    const valid = await crypto.subtle.verify("HMAC", key, sigBuf, data);
    if (!valid) return { ok: false, reason: "signature" };
    return { ok: true, sub };
  } catch {
    return { ok: false, reason: "verify_error" };
  }
}
