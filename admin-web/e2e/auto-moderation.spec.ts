import fs from "node:fs";
import { expect, test, type BrowserContext, type Page } from "@playwright/test";

/**
 * Auto Moderation page in the real admin UI, against a real backend:
 *   - behind the admin authentication (signed-out -> /login);
 *   - role permissions: super_admin (everything), moderator (read + engage the
 *     kill switch only), support (no access, UI and API);
 *   - shadow mode is explained honestly when no AI provider is configured;
 *   - settings cannot enable live mode, and the AI check cannot be unlocked
 *     from the dashboard;
 *   - kill switch engage / persist / release, and who may release it;
 *   - the decision history (reasons + audit events) of recorded decisions.
 *
 * Needs a running backend + seed (see e2e/seed_auto_moderation.py). The
 * backend must run WITHOUT AUTO_MODERATION_ALLOW_LIVE and without an AI
 * provider (the production state today). Skipped (not faked) otherwise.
 */

const SEED_PATH = process.env.E2E_SEED_OUT || "";
const configured = Boolean(SEED_PATH && fs.existsSync(SEED_PATH));

type Seed = {
  password: string;
  admins: { super_admin: string; moderator: string; support: string };
  listings: Record<string, { car_id: number; public_id: string; title: string; outcome: string; decision: string }>;
};
const seed = (): Seed => JSON.parse(fs.readFileSync(SEED_PATH, "utf-8"));

async function signIn(context: BrowserContext, role: keyof Seed["admins"]) {
  const s = seed();
  const res = await context.request.post("/api/admin-session", {
    data: { username: s.admins[role], password: s.password },
    headers: { "Content-Type": "application/json" },
  });
  expect(res.status(), `real ${role} login`).toBe(200);
}

const settingsApi = (context: BrowserContext) =>
  context.request.get("/backend-api/api/admin/auto-moderation/settings");

async function gotoTab(page: Page, tab: "Overview" | "Decisions" | "Settings") {
  await page.getByRole("button", { name: tab, exact: true }).click();
}

test.describe("auto moderation - unauthenticated", () => {
  test("redirects to the admin login", async ({ page }) => {
    await page.goto("/auto-moderation");
    await expect(page).toHaveURL(/\/login/);
    expect(page.url()).toContain("next=%2Fauto-moderation");
  });
});

test.describe("auto moderation - authenticated", () => {
  test.skip(!configured, "E2E_SEED_OUT not set - run e2e/seed_auto_moderation.py first");
  test.describe.configure({ mode: "serial" });

  test("super admin: reachable from the navigation, shadow mode explained without an AI provider", async ({
    page,
    context,
  }) => {
    await signIn(context, "super_admin");
    await page.goto("/dashboard");
    const link = page.getByRole("navigation").getByRole("link", { name: /^Auto moderation/ });
    await expect(link).toHaveAttribute("href", "/auto-moderation");
    await link.click();
    await expect(page).toHaveURL(/\/auto-moderation/);
    await expect(page).not.toHaveURL(/\/login/);

    await expect(page.getByText(/Effective mode: Shadow/)).toBeVisible();
    const readiness = page.getByTestId("am-readiness");
    await expect(readiness).toContainText("Can anything be auto-approved right now?");
    await expect(readiness).toContainText("No");
    await expect(readiness).toContainText("No AI provider is configured");
    await expect(readiness).toContainText("Shadow mode cannot measure");
    await expect(readiness).toContainText("Nothing is published automatically");
    await expect(page.getByText(/AI provider: none/)).toBeVisible();

    // The API agrees: nothing is possible, live is not allowed.
    const body = await (await settingsApi(context)).json();
    expect(body.effective_mode).toBe("shadow");
    expect(body.readiness.auto_approval_possible).toBe(false);
    expect(body.readiness.blockers).toContain("ai_provider_not_configured");
    expect(body.environment.live_allowed).toBe(false);
    expect(body.environment.rules_only_allowed).toBe(false);
  });

  test("super admin: decision history shows reasons and audit events; nothing was published", async ({
    page,
    context,
  }) => {
    const s = seed();
    await signIn(context, "super_admin");
    await page.goto("/auto-moderation?tab=queue&view=all");
    for (const l of Object.values(s.listings)) {
      await expect(page.getByText(l.title)).toBeVisible();
    }
    // shadow rows only
    await expect(page.getByRole("cell", { name: "shadow", exact: true }).first()).toBeVisible();

    const scamRow = page.getByRole("row").filter({ hasText: s.listings.scam.title });
    await expect(scamRow).toContainText("Needs review");
    await expect(scamRow).toContainText("scam_language");
    await scamRow.getByRole("button", { name: "Inspect" }).click();
    await expect(page.getByRole("heading", { name: "Why" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "History" })).toBeVisible();
    await expect(page.getByText("AI output is advisory only")).toBeVisible();
    await expect(page.getByText(/^decision_recorded|^evaluated|^shadow/).first()).toBeVisible();

    // the public listing is untouched: still pending (not publicly visible)
    for (const l of Object.values(s.listings)) {
      const r = await context.request.get(`/backend-api/api/admin/cars/${l.public_id}`);
      expect(r.status()).toBe(200);
      const car = (await r.json())?.car ?? (await r.json());
      expect(String(car.status).toLowerCase()).toBe("pending");
    }
  });

  test("super admin: settings cannot turn the AI check off or enable live mode", async ({ page, context }) => {
    await signIn(context, "super_admin");
    await page.goto("/auto-moderation?tab=settings");
    const locked = page.getByTestId("am-ai-required");
    await expect(locked).toContainText("AI check is required");
    await expect(locked.locator("input")).toBeChecked();
    await expect(locked.locator("input")).toBeDisabled();
    await expect(page.getByText(/Live mode is not permitted by the server environment/)).toBeVisible();

    // the server refuses to accept 'false' even if the dashboard were bypassed
    const bypass = await context.request.patch("/backend-api/api/admin/auto-moderation/settings", {
      data: { require_ai_for_auto_approve: false },
    });
    expect(bypass.status()).toBe(400);

    // trying to go live from the UI is refused and the mode stays shadow
    await page.locator('label:has(> span:text-is("Mode")) select').selectOption("live");
    await page.getByRole("button", { name: "Save settings" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Enable live mode" }).click();
    await expect(page.getByRole("status").filter({ hasText: /./ }).first()).toBeVisible();
    const after = await (await settingsApi(context)).json();
    expect(after.settings.mode).toBe("shadow");
    expect(after.effective_mode).toBe("shadow");

    // an allowed change persists: more AI photo coverage
    await page.reload();
    await page.getByLabel("Most photos the AI checks per listing (more → manual review)").fill("14");
    await page.getByRole("button", { name: "Save settings" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Settings saved" })).toBeVisible();
    const saved = await (await settingsApi(context)).json();
    expect(saved.settings.ai.max_total_images).toBe(14);
    expect(saved.settings.mode).toBe("shadow");
  });

  test("super admin: kill switch engages, persists across reloads and releases", async ({ page, context }) => {
    await signIn(context, "super_admin");
    await page.goto("/auto-moderation");
    await page.getByRole("button", { name: "Engage kill switch" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByRole("textbox").fill("e2e rehearsal");
    await dialog.getByRole("button", { name: "Engage kill switch" }).click();
    await expect(page.getByText(/KILL SWITCH ACTIVE/)).toBeVisible();
    await expect(page.getByText(/Reason: e2e rehearsal/)).toBeVisible();
    expect((await (await settingsApi(context)).json()).kill_switch_active).toBe(true);

    await page.reload();
    await expect(page.getByText(/KILL SWITCH ACTIVE/)).toBeVisible();
    await expect(page.getByTestId("am-readiness")).toContainText("Kill switch is active");

    await page.getByRole("button", { name: "Release kill switch" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Release" }).click();
    await expect(page.getByText(/KILL SWITCH ACTIVE/)).toHaveCount(0);
    expect((await (await settingsApi(context)).json()).kill_switch_active).toBe(false);
  });

  test("moderator: can read and engage the kill switch, cannot release it or change settings", async ({
    page,
    context,
  }) => {
    await signIn(context, "moderator");
    await page.goto("/auto-moderation");
    await expect(page.getByText(/Effective mode: Shadow/)).toBeVisible();

    await page.getByRole("button", { name: "Engage kill switch" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Engage kill switch" }).click();
    await expect(page.getByText(/KILL SWITCH ACTIVE/)).toBeVisible();

    // releasing needs super_admin: the server refuses and the switch stays on
    await page.getByRole("button", { name: "Release kill switch" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Release" }).click();
    await expect(page.getByText(/KILL SWITCH ACTIVE/)).toBeVisible();
    expect((await (await settingsApi(context)).json()).kill_switch_active).toBe(true);
    const direct = await context.request.post("/backend-api/api/admin/auto-moderation/kill-switch", {
      data: { enabled: false },
    });
    expect(direct.status()).toBe(403);

    // settings are read-only
    await gotoTab(page, "Settings");
    await expect(page.getByText("You can view these settings but not change them.")).toBeVisible();
    await expect(page.getByRole("button", { name: "Save settings" })).toHaveCount(0);
    const write = await context.request.patch("/backend-api/api/admin/auto-moderation/settings", {
      data: { min_photos: 1 },
    });
    expect(write.status()).toBe(403);

    // decisions are visible to a moderator
    await gotoTab(page, "Decisions");
    await expect(page.getByText(seed().listings.scam.title).first()).toBeVisible();
  });

  test("super admin releases the switch the moderator engaged", async ({ context }) => {
    await signIn(context, "super_admin");
    const r = await context.request.post("/backend-api/api/admin/auto-moderation/kill-switch", {
      data: { enabled: false },
    });
    expect(r.status()).toBe(200);
    expect((await (await settingsApi(context)).json()).kill_switch_active).toBe(false);
  });

  test("support role: no navigation entry, no page, no API access", async ({ page, context }) => {
    await signIn(context, "support");
    await page.goto("/dashboard");
    await expect(page.getByRole("navigation").getByRole("link", { name: /^Auto moderation/ })).toHaveCount(0);
    await page.goto("/auto-moderation");
    await expect(page).not.toHaveURL(/\/login/);
    await expect(page.getByText("You do not have access to automated moderation.")).toBeVisible();
    for (const path of ["settings", "stats", "runs"]) {
      const r = await context.request.get(`/backend-api/api/admin/auto-moderation/${path}`);
      expect(r.status(), path).toBe(403);
    }
  });
});
