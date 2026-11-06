/** Shared stubs for the F-19 admin-web tests (framework modules only). */
import { createHmac } from "node:crypto";

export class StubNextResponse extends Response {
  constructor(body, init) {
    super(body, init);
    this.cookieCalls = [];
    this.cookies = {
      set: (name, value, opts) => this.cookieCalls.push({ name, value, opts }),
    };
  }

  static json(body, init = {}) {
    const headers = new Headers(init.headers);
    headers.set("content-type", "application/json");
    return new StubNextResponse(JSON.stringify(body), { ...init, headers });
  }

  static next(init) {
    const r = new StubNextResponse(null, { status: 200 });
    r.requestHeaders = init?.request?.headers;
    return r;
  }

  static redirect(url, status = 307) {
    return new StubNextResponse(null, { status, headers: { location: String(url) } });
  }
}

export function mintHs256(secret, payload) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const data = `${b64({ alg: "HS256", typ: "JWT" })}.${b64(payload)}`;
  return `${data}.${createHmac("sha256", secret).update(data).digest("base64url")}`;
}

export function adminPayload(extra = {}) {
  return {
    sub: "admin-public-id",
    type: "access",
    is_admin: true,
    account_scope: "admin",
    exp: Math.floor(Date.now() / 1000) + 3600,
    ...extra,
  };
}

/** Run `fn` with temporary process.env overrides (undefined => delete). */
export async function withEnv(overrides, fn) {
  const saved = {};
  for (const [k, v] of Object.entries(overrides)) {
    saved[k] = process.env[k];
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  try {
    return await fn();
  } finally {
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  }
}
