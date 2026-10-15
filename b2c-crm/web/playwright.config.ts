import { defineConfig, devices } from "@playwright/test";

/**
 * Browser tests against staging (test people and test leads from e2e/seed.mjs). The app runs locally in dev mode with
 * LIVE_MODE off, so nothing is ever sent. `npm run e2e` runs everything; `npm run e2e:seed` refreshes the test data.
 */
// @ts-expect-error plain JavaScript shared with the seed script
import { assertStagingKey } from "./e2e/fixtures.mjs";

const PORT = Number(process.env.E2E_PORT ?? 3100);
assertStagingKey(process.env.SUPABASE_SERVICE_ROLE_KEY); // the local app gets this key too: staging only

export default defineConfig({
  testDir: "e2e",
  timeout: 90_000,
  expect: { timeout: 15_000 },
  fullyParallel: false,
  workers: 2,
  retries: 0,
  reporter: [["list"], ["html", { open: "never" }]],
  use: { baseURL: `http://localhost:${PORT}`, trace: "retain-on-failure", screenshot: "only-on-failure" },
  projects: [
    { name: "setup", testMatch: /auth\.setup\.ts/ },
    { name: "laptop", dependencies: ["setup"], testIgnore: /auth\.setup\.ts/, use: { ...devices["Desktop Chrome"], viewport: { width: 1366, height: 820 } } },
    { name: "phone", dependencies: ["setup"], testIgnore: /auth\.setup\.ts/, use: { ...devices["Pixel 7"] } },
  ],
  webServer: {
    command: `npx next dev -p ${PORT}`,
    url: `http://localhost:${PORT}/login`,
    reuseExistingServer: true,
    timeout: 180_000,
    env: { LIVE_MODE: "off", NEXT_PUBLIC_SITE_URL: `http://localhost:${PORT}`, SMTP_HOST: "" }, // no email ever leaves a local test run
  },
});
