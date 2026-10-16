import { describe, expect, it } from "vitest";
import { parseEnv } from "./env";

const base = {
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54421",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "x".repeat(40),
  SUPABASE_SERVICE_ROLE_KEY: "y".repeat(40),
  NEXT_PUBLIC_SITE_URL: "http://localhost:3200",
  INF_INTERNAL_API_KEY: "z".repeat(32),
};

describe("environment", () => {
  it("accepts a minimal local configuration with safe defaults", () => {
    const env = parseEnv(base);
    expect(env.LIVE_MODE).toBe("off");
    expect(env.EMAIL_PROVIDER).toBe("mock");
  });

  it("requires a long internal key", () => {
    expect(() => parseEnv({ ...base, INF_INTERNAL_API_KEY: "short" })).toThrow(/INF_INTERNAL_API_KEY/);
  });

  it("requires provider credentials for the chosen provider", () => {
    expect(() => parseEnv({ ...base, EMAIL_PROVIDER: "resend" })).toThrow(/RESEND_API_KEY/);
    expect(() => parseEnv({ ...base, WHATSAPP_PROVIDER: "meta" })).toThrow(/WHATSAPP_TOKEN/);
  });

  it("refuses the mock email provider in production", () => {
    expect(() => parseEnv({ ...base, NODE_ENV: "production" })).toThrow(/mock/);
  });

  it("never echoes secret values in errors", () => {
    try {
      parseEnv({ ...base, SUPABASE_SERVICE_ROLE_KEY: "secret-value", INF_INTERNAL_API_KEY: "short-secret" });
    } catch (e) {
      expect(String(e)).not.toContain("short-secret");
    }
  });
});
