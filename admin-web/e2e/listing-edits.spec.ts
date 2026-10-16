import fs from "node:fs";
import { expect, request as playwrightRequest, test, type BrowserContext } from "@playwright/test";

/**
 * Listing edits (pending revisions of published listings) in the real admin
 * UI, against a real backend:
 *   - /listing-edits is behind the existing admin authentication;
 *   - it is reachable from the admin navigation;
 *   - a seller's pending edit is listed, the public listing is unchanged
 *     until the admin approves, and approving publishes it.
 *
 * Needs a running backend + the two seeds (see e2e/README-listing-edits-e2e.md):
 *   python admin-web/e2e/seed_test_admin.py     (E2E_ADMIN_USERNAME/PASSWORD)
 *   python admin-web/e2e/seed_listing_edit.py   (E2E_SEED_OUT=<json>)
 * Skipped (not faked) when they are not configured.
 *
 * Each authenticated test signs in once through the real /api/admin-session
 * endpoint and then navigates exactly like an admin does (sidebar links,
 * "Review" links). Navigation must never bounce back to /login: that used to
 * happen because the Edge middleware's access-token check always threw, so
 * every request rotated the single-use refresh token and parallel requests
 * raced on it (see "the session survives..." below).
 */

const E2E_ADMIN_USERNAME = process.env.E2E_ADMIN_USERNAME || "";
const E2E_ADMIN_PASSWORD = process.env.E2E_ADMIN_PASSWORD || "";
const SEED_PATH = process.env.E2E_SEED_OUT || "";
const API = process.env.NEXT_PUBLIC_API_BASE || "http://127.0.0.1:5000";
const configured = Boolean(
  E2E_ADMIN_USERNAME && E2E_ADMIN_PASSWORD && SEED_PATH && fs.existsSync(SEED_PATH),
);

test.describe("listing edits - unauthenticated", () => {
  test("redirects to the admin login", async ({ page }) => {
    await page.goto("/listing-edits");
    await expect(page).toHaveURL(/\/login/);
    expect(page.url()).toContain("next=%2Flisting-edits");
    await expect(page.getByRole("heading", { name: "Admin sign in" })).toBeVisible();
  });

  test("review page redirects to the admin login too", async ({ page }) => {
    await page.goto("/listing-edits/00000000-0000-0000-0000-000000000000");
    await expect(page).toHaveURL(/\/login/);
  });
});

test.describe("listing edits - authenticated admin", () => {
  test.skip(
    !configured,
    "E2E_ADMIN_USERNAME/E2E_ADMIN_PASSWORD/E2E_SEED_OUT not set - see e2e/README-listing-edits-e2e.md",
  );
  test.describe.configure({ mode: "serial" });

  async function signIn(context: BrowserContext) {
    const res = await context.request.post("/api/admin-session", {
      data: { username: E2E_ADMIN_USERNAME, password: E2E_ADMIN_PASSWORD },
      headers: { "Content-Type": "application/json" },
    });
    expect(res.status(), "real admin login").toBe(200);
  }

  const seed = () =>
    JSON.parse(fs.readFileSync(SEED_PATH, "utf-8")) as {
      public_id: string;
      title: string;
      old_price: number;
      new_price: number;
      new_description: string;
    };

  async function publicCar(id: string) {
    const api = await playwrightRequest.newContext();
    try {
      const res = await api.get(`${API}/api/cars/${id}`);
      return { status: res.status(), car: (await res.json())?.car };
    } finally {
      await api.dispose();
    }
  }

  test("is reachable through the admin navigation, without logging in again", async ({
    page,
    context,
  }) => {
    await signIn(context);
    await page.goto("/dashboard");
    const nav = page.getByRole("navigation");
    const link = nav.getByRole("link", { name: /^Listing edits/ });
    await expect(link).toBeVisible();
    await expect(link).toHaveAttribute("href", "/listing-edits");

    // Normal client-side navigation, back and forth, on ONE login.
    await link.click();
    await expect(page).toHaveURL(/\/listing-edits$/);
    await expect(page.getByRole("heading", { name: "Listing edits" }).first()).toBeVisible();
    for (const [name, url] of [
      [/^Listings/, /\/listings$/],
      [/^Listing edits/, /\/listing-edits$/],
      [/^Users/, /\/users$/],
      [/^Listing edits/, /\/listing-edits$/],
    ] as const) {
      await nav.getByRole("link", { name }).click();
      await expect(page).toHaveURL(url);
    }
    await expect(page).not.toHaveURL(/\/login/);
    await expect(page.getByRole("heading", { name: "Listing edits" }).first()).toBeVisible();
  });

  test("the session survives parallel page loads, with a fresh or an expired access token", async ({
    context,
  }) => {
    await signIn(context);
    const paths = ["/dashboard", "/listing-edits", "/listings", "/users"];
    const burst = () =>
      Promise.all(
        Array.from({ length: 12 }, (_, i) =>
          context.request.get(paths[i % paths.length], { maxRedirects: 0 }),
        ),
      );

    // Fresh token: every page loads (no redirect to /login) and nothing is
    // rotated -- the access token must verify at the edge.
    for (const res of await burst()) {
      expect(res.status(), res.url()).toBe(200);
      expect(res.headers()["set-cookie"] ?? "", res.url()).toBe("");
    }

    // Expired access token (only the refresh cookie left): the refresh token
    // is single-use, yet a burst of parallel requests must all succeed.
    await context.clearCookies({ name: "carzo_admin_jwt" });
    for (const res of await burst()) {
      expect(res.status(), res.url()).toBe(200);
    }
    // ...and the rotated session keeps working.
    for (const res of await burst()) {
      expect(res.status(), res.url()).toBe(200);
    }
  });

  test("a pending edit is listed while the public listing is unchanged", async ({
    page,
    context,
  }) => {
    const s = seed();
    const before = await publicCar(s.public_id);
    expect(before.status).toBe(200);
    expect(Number(before.car.price)).toBe(s.old_price);

    await signIn(context);
    await page.goto("/listing-edits");
    const row = page.getByRole("row").filter({ hasText: s.title });
    await expect(row).toBeVisible({ timeout: 15000 });
    await expect(row).toContainText(/price/);
    await expect(row.getByRole("link", { name: "Review" })).toBeVisible();

    // viewing the queue changes nothing publicly
    expect(Number((await publicCar(s.public_id)).car.price)).toBe(s.old_price);
  });

  test("the review page shows approved vs proposed, and approving publishes", async ({
    page,
    context,
  }) => {
    const s = seed();
    await signIn(context);
    await page.goto("/dashboard");
    await page.getByRole("navigation").getByRole("link", { name: /^Listing edits/ }).click();
    const review = page
      .getByRole("row")
      .filter({ hasText: s.title })
      .getByRole("link", { name: "Review" });
    await expect(review).toBeVisible({ timeout: 15000 });
    expect(await review.getAttribute("href")).toMatch(/^\/listing-edits\/[0-9a-f-]{36}$/);
    await review.click(); // client-side navigation, same login
    await expect(page).toHaveURL(/\/listing-edits\/[0-9a-f-]{36}$/);
    await expect(page.getByRole("heading", { name: "Review listing edit" })).toBeVisible();

    const table = page.locator("table").first();
    await expect(table).toContainText(/15,?000/);
    await expect(table).toContainText(/12,?345/);
    await expect(table).toContainText(s.new_description);

    // Still the approved version for the public.
    expect(Number((await publicCar(s.public_id)).car.price)).toBe(s.old_price);

    await page.getByRole("button", { name: /^Approve & publish$/ }).first().click();
    // confirm dialog
    await page.getByRole("button", { name: /^Approve & publish$/ }).last().click();

    await expect
      .poll(async () => Number((await publicCar(s.public_id)).car.price), { timeout: 15000 })
      .toBe(s.new_price);
    const after = await publicCar(s.public_id);
    expect(after.status).toBe(200);
    expect(after.car.description).toBe(s.new_description);
    // same listing id, no duplicate
    expect(after.car.id).toBe(s.public_id);

    // the queue is empty again (same session)
    await page.goto("/listing-edits");
    await expect(page.getByRole("heading", { name: "Listing edits" }).first()).toBeVisible();
    await expect(page.getByRole("row").filter({ hasText: s.title })).toHaveCount(0);
  });
});
