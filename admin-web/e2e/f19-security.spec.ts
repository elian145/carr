import { expect, test, type Page } from "@playwright/test";

/**
 * F-19 browser-level checks against a running admin-web:
 *  - security headers are present on pages, API routes AND the /backend-api proxy
 *    (the proxy/API routes used to carry no `X-Content-Type-Options`);
 *  - the page boots and hydrates under the production nonce CSP with ZERO
 *    `securitypolicyviolation` events of any directive (script-src included);
 *  - (needs E2E_ADMIN_USERNAME/E2E_ADMIN_PASSWORD, i.e. a backend) signing in through the
 *    real form works, and cross-site state-changing requests are refused with 403.
 */

const E2E_ADMIN_USERNAME = process.env.E2E_ADMIN_USERNAME || "";
const E2E_ADMIN_PASSWORD = process.env.E2E_ADMIN_PASSWORD || "";
const hasAdminCreds = Boolean(E2E_ADMIN_USERNAME && E2E_ADMIN_PASSWORD);
const ADMIN_ORIGIN =
  process.env.ADMIN_WEB_BASE_URL ||
  `http://127.0.0.1:${process.env.ADMIN_WEB_PORT || 3000}`;

async function collectViolations(page: Page) {
  await page.addInitScript(() => {
    const w = window as unknown as { __v: string[] };
    w.__v = [];
    document.addEventListener("securitypolicyviolation", (e) => {
      w.__v.push(`${e.violatedDirective} ${e.blockedURI} ${e.sample}`);
    });
  });
  return async () =>
    page.evaluate(() => (window as unknown as { __v: string[] }).__v);
}

test.describe("F-19 headers", () => {
  test("pages, API routes and the proxy all send nosniff + frame/referrer/permissions headers", async ({
    request,
  }) => {
    for (const url of ["/login", "/api/health", "/backend-api/api/admin/users"]) {
      const res = await request.get(url);
      const h = res.headers();
      expect(h["x-content-type-options"], url).toBe("nosniff");
      expect(h["x-frame-options"], url).toBe("DENY");
      expect(h["referrer-policy"], url).toBe("strict-origin-when-cross-origin");
      expect(h["permissions-policy"], url).toContain("camera=()");
      expect(h["content-security-policy"], url).toContain("frame-ancestors 'none'");
    }
    // unauthenticated proxy call is still a 401 (no open relay)
    expect((await request.get("/backend-api/api/admin/users")).status()).toBe(401);
  });

  test("cross-origin POST to the proxy and to admin-session is 403 without a session too", async ({
    request,
  }) => {
    for (const url of ["/backend-api/api/admin/users", "/api/admin-session"]) {
      const evil = await request.post(url, {
        data: {},
        headers: { Origin: "https://evil.example" },
      });
      expect(evil.status(), url).toBe(403);
      const none = await request.post(url, { data: {} });
      expect(none.status(), `${url} (no Origin)`).toBe(403);
    }
  });

  test("login page hydrates with no CSP violation of any directive", async ({ page }) => {
    const violations = await collectViolations(page);
    await page.goto("/login");
    await expect(page.getByRole("heading", { name: "Admin sign in" })).toBeVisible();
    expect(await violations()).toEqual([]);
    const csp = (await page.request.get("/login")).headers()["content-security-policy"];
    const scriptSrc = csp.split(";").map((d) => d.trim()).find((d) => d.startsWith("script-src")) || "";
    // production: nonce-based, no 'unsafe-inline'; `next dev` (HMR) keeps unsafe-inline/eval
    if (scriptSrc.includes("'unsafe-inline'")) expect(scriptSrc).toContain("'unsafe-eval'");
    else expect(scriptSrc).toMatch(/'nonce-[^']+' 'strict-dynamic'/);
  });
});

test.describe("F-19 authenticated flow", () => {
  test.skip(!hasAdminCreds, "E2E_ADMIN_USERNAME/E2E_ADMIN_PASSWORD not set (needs a backend)");

  test("form login works under the nonce CSP; cross-site writes are 403, same-origin writes pass", async ({
    page,
    context,
  }) => {
    const violations = await collectViolations(page);
    await page.goto("/login");
    await page.getByLabel(/email, phone, or username/i).fill(E2E_ADMIN_USERNAME);
    await page.getByLabel(/^password$/i).fill(E2E_ADMIN_PASSWORD);
    await page.getByRole("button", { name: /sign in/i }).click();
    await expect(page).toHaveURL(/\/dashboard/, { timeout: 30_000 });
    expect(await violations()).toEqual([]);

    const evil = await context.request.post("/backend-api/api/admin/cars/bulk-status", {
      data: {},
      headers: { Origin: "https://evil.example" },
    });
    expect(evil.status()).toBe(403);
    const own = await context.request.post("/backend-api/api/admin/cars/bulk-status", {
      data: {},
      headers: { Origin: ADMIN_ORIGIN },
    });
    expect(own.status()).not.toBe(403);
    expect(own.headers()["x-content-type-options"]).toBe("nosniff");
  });
});
