import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end tests run against a production build (`next start`) on port 3100 with the local Supabase stack and
 * Mailpit. Chromium is the preinstalled one (PLAYWRIGHT_BROWSERS_PATH / CHROME_PATH), never downloaded.
 */
try {
  process.loadEnvFile(".env.local");
} catch {
  // CI provides the environment directly
}

const executablePath = process.env.CHROME_PATH || (process.env.CI ? undefined : "/opt/pw-browsers/chromium");

export default defineConfig({
  testDir: "./e2e",
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : [["list"]],
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3100",
    trace: "retain-on-failure",
    launchOptions: executablePath ? { executablePath } : {},
  },
  projects: [
    { name: "laptop", use: { viewport: { width: 1366, height: 820 } } },
    { name: "phone", use: { ...devices["Pixel 7"] } },
  ],
  webServer: process.env.E2E_BASE_URL
    ? undefined
    : {
        command: "npx next start -p 3100",
        url: "http://localhost:3100/api/health",
        reuseExistingServer: true,
        timeout: 120_000,
      },
});
