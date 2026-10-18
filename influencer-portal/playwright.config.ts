import { existsSync } from "node:fs";
import { defineConfig, devices } from "@playwright/test";
import { BASE_URL, localEnv } from "./e2e/env";

// The preinstalled Chromium may be a different build than this Playwright expects; use it directly when present.
const chromiumPath =
  process.env.PW_CHROMIUM ?? (existsSync("/opt/pw-browsers/chromium") ? "/opt/pw-browsers/chromium" : undefined);
const launchOptions = chromiumPath ? { executablePath: chromiumPath } : {};

export default defineConfig({
  testDir: "./e2e",
  globalSetup: "./e2e/global-setup.ts",
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: BASE_URL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    locale: "en-IN",
    timezoneId: "Asia/Kolkata",
  },
  projects: [
    { name: "laptop", use: { ...devices["Desktop Chrome"], launchOptions }, testIgnore: /mobile\.spec\.ts/ },
    { name: "phone", use: { ...devices["Pixel 7"], launchOptions }, testMatch: /mobile\.spec\.ts/ },
  ],
  webServer: {
    // A production build: dev mode compiles on demand, which makes timing-sensitive flows flaky.
    command: "npm run build && npm run start",
    // Readiness only: /api/health also reports a stuck job queue (503), which a stale local database can show
    // before global setup resets it.
    url: `${BASE_URL}/login`,
    reuseExistingServer: false,
    timeout: 360_000,
    env: { ...localEnv(), NODE_ENV: "production" },
  },
});
