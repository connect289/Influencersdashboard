import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
const { email, emailProvider, setEmailSender, smtpPassword } = await import("./index");
const { verificationCodeEmail } = await import("./templates");
const { resetEnvCache } = await import("../env");

describe("smtpPassword", () => {
  it("removes the display spaces from a Google app password", () => {
    expect(smtpPassword("abcd efgh ijkl mnop")).toBe("abcdefghijklmnop");
  });
  it("leaves any other password as typed", () => {
    expect(smtpPassword("my pass word")).toBe("my pass word");
    expect(smtpPassword("abcdefghijklmnop")).toBe("abcdefghijklmnop");
    expect(smtpPassword(undefined)).toBe("");
  });
});

const KEYS = ["APP_ENV", "EMAIL_PROVIDER", "EMAIL_SMTP_HOST", "RESEND_API_KEY", "SUPABASE_SECRET_KEY", "WEB_SESSION_SECRET", "WEB_INTERNAL_KEY"];
const saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
function setEnv(values: Record<string, string | undefined>) {
  for (const k of KEYS) {
    const v = k in values ? values[k] : saved[k];
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  resetEnvCache();
  setEmailSender(null);
}
afterEach(() => {
  setEnv({});
  vi.restoreAllMocks();
});
// Deployed environments refuse to start without these (they are dummies here).
const deployedSecrets = { SUPABASE_SECRET_KEY: "test-secret-key-0123456789", WEB_SESSION_SECRET: "test-session-secret-0123456789abcdef", WEB_INTERNAL_KEY: "test-internal-key-0123456789" };

describe("emailProvider", () => {
  it("is the chosen provider only when its settings are there", () => {
    setEnv({ EMAIL_PROVIDER: "smtp", EMAIL_SMTP_HOST: "smtp.gmail.com" });
    expect(emailProvider()).toBe("smtp");
    setEnv({ EMAIL_PROVIDER: "smtp", EMAIL_SMTP_HOST: undefined });
    expect(emailProvider()).toBe("console");
    setEnv({ EMAIL_PROVIDER: "resend", RESEND_API_KEY: undefined });
    expect(emailProvider()).toBe("console");
    setEnv({ EMAIL_PROVIDER: undefined });
    expect(emailProvider()).toBe("console");
  });
});

describe("console sender", () => {
  const message = verificationCodeEmail("482913", "verify");

  it("prints the message on a developer machine", async () => {
    setEnv({ APP_ENV: "local", EMAIL_PROVIDER: "console" });
    const info = vi.spyOn(console, "info").mockImplementation(() => undefined);
    await expect(email().send("asha@example.com", message)).resolves.toMatchObject({ id: expect.stringMatching(/^console-/) });
    expect(info.mock.calls.flat().join(" ")).toContain("482913");
  });

  it("refuses on a deployed site and never logs the address or the code", async () => {
    for (const APP_ENV of ["preview", "production"]) {
      setEnv({ ...deployedSecrets, APP_ENV, EMAIL_PROVIDER: "smtp", EMAIL_SMTP_HOST: undefined });
      const lines: string[] = [];
      for (const level of ["info", "warn", "error", "log"] as const)
        vi.spyOn(console, level).mockImplementation((...a: unknown[]) => void lines.push(a.map(String).join(" ")));
      await expect(email().send("asha@example.com", message)).rejects.toThrow(/No email provider/);
      expect(lines.join("\n")).toContain("email.not_configured");
      expect(lines.join("\n")).not.toMatch(/482913|asha@example\.com/);
      vi.restoreAllMocks();
    }
  });
});
