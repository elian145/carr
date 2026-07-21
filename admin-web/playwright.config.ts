import { defineConfig, devices } from "@playwright/test";

const PORT = Number(process.env.ADMIN_WEB_PORT || 3000);
const baseURL = process.env.ADMIN_WEB_BASE_URL || `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL,
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: process.env.ADMIN_WEB_BASE_URL
    ? undefined
    : {
        command: process.env.CI
          ? `npx next start --port ${PORT}`
          : `npx next dev --port ${PORT}`,
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
        env: {
          ...process.env,
          JWT_SECRET_KEY: process.env.JWT_SECRET_KEY || "ci-admin-jwt-secret",
          NEXT_PUBLIC_API_BASE:
            process.env.NEXT_PUBLIC_API_BASE || "http://127.0.0.1:5000",
        },
      },
});
