import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const set = vi.fn();
vi.mock("next/headers", () => ({
  cookies: async () => ({ set, get: () => undefined, delete: vi.fn() }),
  headers: vi.fn(),
}));

const { deviceId, setStudentSession, STUDENT_COOKIE, DEVICE_COOKIE } = await import("./student-session");
const { resetEnvCache } = await import("./env");

const KEYS = ["APP_ENV", "SUPABASE_SECRET_KEY", "WEB_SESSION_SECRET", "WEB_INTERNAL_KEY"];
const saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
function setEnv(values: Record<string, string>) {
  for (const k of KEYS) {
    const v = k in values ? values[k] : saved[k];
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  resetEnvCache();
}
afterEach(() => {
  setEnv({});
  set.mockClear();
});

const sid = "6f1c2b9e-4d3a-4b8e-9f0a-1c2d3e4f5a6b";
const deployed = {
  SUPABASE_SECRET_KEY: "test-secret-key-0123456789",
  WEB_SESSION_SECRET: "test-session-secret-0123456789abcdef",
  WEB_INTERNAL_KEY: "test-internal-key-0123456789",
};

describe("student cookies", () => {
  it("are Secure on production and on preview deployments", async () => {
    for (const APP_ENV of ["production", "preview"]) {
      setEnv({ ...deployed, APP_ENV });
      await setStudentSession(sid);
      await deviceId();
      const byName = Object.fromEntries(
        set.mock.calls.map(([name, , opts]) => [name, opts as { secure: boolean; httpOnly: boolean }]),
      );
      expect(byName[STUDENT_COOKIE]).toMatchObject({ secure: true, httpOnly: true });
      expect(byName[DEVICE_COOKIE]).toMatchObject({ secure: true, httpOnly: true });
      set.mockClear();
    }
  });
  it("stay usable over plain http on a developer machine", async () => {
    setEnv({ APP_ENV: "local" });
    await setStudentSession(sid);
    expect(set.mock.calls[0]![2]).toMatchObject({ secure: false });
  });
});
