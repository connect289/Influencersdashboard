import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const { env, resetEnvCache } = await import("./env");

const saved = process.env.EMAIL_SMTP_HOST;
afterEach(() => {
  if (saved === undefined) delete process.env.EMAIL_SMTP_HOST;
  else process.env.EMAIL_SMTP_HOST = saved;
  resetEnvCache();
});

describe("env", () => {
  it("ignores stray whitespace pasted into a setting", () => {
    process.env.EMAIL_SMTP_HOST = "\tsmtp.gmail.com \n";
    resetEnvCache();
    expect(env().EMAIL_SMTP_HOST).toBe("smtp.gmail.com");
  });
});
