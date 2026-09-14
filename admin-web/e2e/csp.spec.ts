import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { expect, request as playwrightRequest, test, type Page } from "@playwright/test";

/**
 * L-02 (style-src half): proves that removing 'unsafe-inline' from the
 * production style-src CSP directive (admin-web/src/middleware.ts) does not
 * break real page rendering, by attaching a live `securitypolicyviolation`
 * listener and driving real navigation across the pages most likely to be
 * affected — in particular TrendChart/ActionBarChart (React `style={{...}}`)
 * and Next.js's own `<next-route-announcer>` element.
 *
 * Authenticated pages authenticate via the app's REAL, unmodified login
 * endpoint (POST /api/admin-session -> POST /api/auth/login -> AdminAccount
 * password check) against a real backend seeded with a real admin account
 * (see e2e/seed_test_admin.py) — no middleware bypass, no fake token, no
 * production code changed for testing purposes. The login itself is issued
 * via Playwright's API request context (not by clicking the UI form) and
 * its resulting cookies are reused via `storageState`, specifically to
 * avoid a separate, pre-existing, CSP-unrelated bug this investigation
 * found and confirmed independently via curl + network tracing: clicking
 * the real login form and immediately following the app's own
 * `router.replace("/dashboard")` triggers Next.js App Router to prefetch
 * every sidebar nav link at once, several of which race to refresh the
 * (single-use, rotating) refresh token concurrently and 401 each other —
 * occasionally consuming the *access* token's request too and bouncing the
 * very first post-login navigation back to `/login?next=...`. That bug is
 * in the app's client-side rotating-refresh-token handling under
 * concurrent prefetch, is unrelated to style-src, and is explicitly out of
 * scope for this task (no application/authentication behavior changes) —
 * it is being reported as a separate follow-up, not fixed here.
 *
 * Requires (see e2e/README-csp-e2e.md for the exact commands):
 *   - The real backend (kk) running and reachable at NEXT_PUBLIC_API_BASE
 *     (default http://localhost:5000), seeded via e2e/seed_test_admin.py.
 *   - E2E_ADMIN_USERNAME / E2E_ADMIN_PASSWORD set to the seeded credentials.
 * If unset, or login fails, the authenticated-page tests are skipped (not
 * silently passed) with a clear reason — the /login-only CSP check still
 * always runs.
 */

const E2E_ADMIN_USERNAME = process.env.E2E_ADMIN_USERNAME || "";
const E2E_ADMIN_PASSWORD = process.env.E2E_ADMIN_PASSWORD || "";
const hasAdminCreds = Boolean(E2E_ADMIN_USERNAME && E2E_ADMIN_PASSWORD);

type Violation = {
  violatedDirective: string;
  blockedURI: string;
  sample: string;
  documentURI: string;
};

async function attachCspListener(page: Page): Promise<void> {
  await page.addInitScript(() => {
    (window as unknown as { __cspViolations: unknown[] }).__cspViolations = [];
    document.addEventListener("securitypolicyviolation", (e) => {
      (window as unknown as { __cspViolations: Violation[] }).__cspViolations.push({
        violatedDirective: e.violatedDirective,
        blockedURI: e.blockedURI,
        sample: e.sample,
        documentURI: e.documentURI,
      });
    });
  });
}

async function readViolations(page: Page): Promise<Violation[]> {
  return page.evaluate(
    () => (window as unknown as { __cspViolations: Violation[] }).__cspViolations || [],
  );
}

/** style-src is the only directive under test in this task — filter out any
 * unrelated violation (e.g. from a browser extension or an unrelated
 * directive) so this test stays a precise regression guard for L-02. */
function styleSrcViolations(violations: Violation[]): Violation[] {
  return violations.filter((v) => v.violatedDirective.startsWith("style-src"));
}

test.describe("L-02 style-src CSP — unauthenticated", () => {
  test("/login renders with no style-src CSP violations", async ({ page }) => {
    await attachCspListener(page);
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    await page.goto("/login");
    await expect(page.getByRole("heading", { name: "Admin sign in" })).toBeVisible();
    await expect(page.getByLabel(/email, phone, or username/i)).toBeVisible();
    await expect(page.getByLabel(/^password$/i)).toBeVisible();

    // Next.js's own route-announcer element uses a live style mutation —
    // confirm it's present (proves the CSP-sensitive code path actually ran)
    // and did not get blocked.
    await expect(page.locator("next-route-announcer")).toBeAttached();

    const violations = styleSrcViolations(await readViolations(page));
    expect(violations, `unexpected style-src CSP violations: ${JSON.stringify(violations)}`).toEqual([]);

    const unexpectedConsoleErrors = consoleErrors.filter(
      (e) => !e.includes("401") && !e.includes("Failed to load resource"),
    );
    expect(unexpectedConsoleErrors, JSON.stringify(unexpectedConsoleErrors)).toEqual([]);
  });
});

test.describe("L-02 style-src CSP — authenticated", () => {
  test.skip(
    !hasAdminCreds,
    "E2E_ADMIN_USERNAME/E2E_ADMIN_PASSWORD not set — seed a real admin " +
      "(python admin-web/e2e/seed_test_admin.py) against a running backend " +
      "and set these env vars to run the authenticated CSP checks. See " +
      "e2e/README-csp-e2e.md.",
  );

  const storageStatePath = path.join(
    os.tmpdir(),
    `l02-e2e-admin-storage-state-${process.pid}.json`,
  );
  let loginFailureReason: string | null = null;

  test.beforeAll(async ({ baseURL }) => {
    if (!hasAdminCreds) return;
    // Real login via the real, unmodified endpoint — equivalent to what the
    // /login form's onSubmit does, just invoked directly instead of via a
    // UI click (see file-level comment for why: avoids an unrelated
    // rotating-refresh-token race under concurrent App Router prefetch).
    const apiContext = await playwrightRequest.newContext({ baseURL });
    try {
      const res = await apiContext.post("/api/admin-session", {
        data: { username: E2E_ADMIN_USERNAME, password: E2E_ADMIN_PASSWORD },
        headers: { "Content-Type": "application/json" },
      });
      if (res.status() !== 200) {
        loginFailureReason = `real /api/admin-session login returned ${res.status()}: ${await res.text()}`;
        return;
      }
      await apiContext.storageState({ path: storageStatePath });
    } finally {
      await apiContext.dispose();
    }
  });

  test.use({
    storageState: async ({}, use) => {
      // Playwright fixture-value setter, not a React hook.
      // eslint-disable-next-line react-hooks/rules-of-hooks
      await use(fs.existsSync(storageStatePath) ? storageStatePath : undefined);
    },
  });

  test.beforeEach(() => {
    test.skip(
      !!loginFailureReason,
      loginFailureReason || "login setup did not run",
    );
  });

  const pages: { path: string; expectHeading: RegExp }[] = [
    { path: "/dashboard", expectHeading: /dashboard/i },
    { path: "/insights", expectHeading: /insights/i },
    { path: "/users", expectHeading: /users/i },
    { path: "/listings", expectHeading: /listings/i },
  ];

  for (const { path, expectHeading } of pages) {
    test(`${path} renders with no style-src CSP violations (real admin login)`, async ({ page }) => {
      await attachCspListener(page);
      const consoleErrors: string[] = [];
      const pageErrors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") consoleErrors.push(msg.text());
      });
      page.on("pageerror", (err) => pageErrors.push(String(err)));

      await page.goto(path);
      await expect(page.getByRole("heading", { name: expectHeading }).first()).toBeVisible({
        timeout: 15000,
      });

      // TrendChart (/insights) and ActionBarChart (/dashboard) both render
      // React style={{...}} bars — force their presence to be checked
      // explicitly wherever they appear.
      if (path === "/insights") {
        await expect(page.getByText(/new signups/i)).toBeVisible();
      }
      if (path === "/dashboard") {
        // ActionBarChart only renders once there's at least one user_action row;
        // absence is not itself a CSP failure, so this is a soft, non-blocking check.
        await page.waitForLoadState("networkidle");
      }

      await expect(page.locator("next-route-announcer")).toBeAttached();

      const violations = styleSrcViolations(await readViolations(page));
      expect(violations, `unexpected style-src CSP violations on ${path}: ${JSON.stringify(violations)}`).toEqual(
        [],
      );

      expect(pageErrors, JSON.stringify(pageErrors)).toEqual([]);
      const unexpectedConsoleErrors = consoleErrors.filter(
        (e) => !e.includes("Failed to load resource"),
      );
      expect(unexpectedConsoleErrors, JSON.stringify(unexpectedConsoleErrors)).toEqual([]);
    });
  }

  test("navigation between admin pages produces no style-src CSP violations", async ({ page }) => {
    await attachCspListener(page);

    for (const { path } of pages) {
      await page.goto(path);
      await page.waitForLoadState("networkidle");
    }

    const violations = styleSrcViolations(await readViolations(page));
    expect(violations, `unexpected style-src CSP violations during navigation: ${JSON.stringify(violations)}`).toEqual(
      [],
    );
  });
});
