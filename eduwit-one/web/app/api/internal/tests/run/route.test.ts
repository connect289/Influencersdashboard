import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// /api/internal/tests/run with settings it cannot read, or a database that fails (D-137): a clear, logged error
// naming the key, never an unhandled exception. The database, the clients and the test pass are stand-ins.

const tickState = vi.fn();
const runTestsPass = vi.fn();
vi.mock("@/lib/auth.ts", () => ({ internalAuthorized: async () => true }));
vi.mock("@/lib/db.ts", () => ({ SupabaseOneDb: { fromEnv: () => ({ tickState, appSecrets: async () => ({}) }) } }));
vi.mock("@/lib/clients/credentials.ts", () => ({ vaultSecrets: async () => ({}), credentialsFrom: () => ({}) }));
vi.mock("@/lib/clients/index.ts", () => ({ clientsFor: () => ({}) }));
vi.mock("@/lib/tests/run.ts", () => ({ runTestsPass }));

const { POST } = await import("./route.ts");

let lines: string[] = [];
beforeEach(() => {
  tickState.mockReset();
  runTestsPass.mockReset();
  lines = [];
  vi.spyOn(console, "error").mockImplementation((l: unknown) => void lines.push(String(l)));
  vi.spyOn(console, "warn").mockImplementation(() => undefined);
});

afterEach(() => {
  vi.restoreAllMocks();
});

const call = () => POST(new Request("https://one.test/api/internal/tests/run", { method: "POST" }));

describe("POST /api/internal/tests/run", () => {
  it("answers a clear error naming the setting when the settings cannot be read, and logs it", async () => {
    tickState.mockResolvedValue({ settings: { tests: { purge_after_days: "never" } } });
    const res = await call();
    expect(res.status).toBe(500);
    const body = (await res.json()) as { error: string; detail: string };
    expect(body.error).toBe("settings_invalid");
    expect(body.detail).toMatch(/^settings /);
    expect(runTestsPass).not.toHaveBeenCalled();
    expect(lines.some((l) => l.includes('"event":"tests.settings_invalid"'))).toBe(true);
  });

  it("answers 500 and logs when the database fails", async () => {
    tickState.mockRejectedValue(new Error("database app_tick_state failed"));
    const res = await call();
    expect(res.status).toBe(500);
    expect(((await res.json()) as { error: string }).error).toBe("tests_failed");
    expect(lines.some((l) => l.includes('"event":"tests.failed"') && l.includes("app_tick_state"))).toBe(true);
  });
});
