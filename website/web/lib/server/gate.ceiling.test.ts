import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({
  headers: async () => new Headers({ "x-forwarded-for": "203.0.113.9", "user-agent": "vitest" }),
  cookies: async () => ({ get: () => undefined, set: vi.fn(), delete: vi.fn() }),
}));
const rpc = vi.fn(async (fn: string): Promise<unknown> => {
  if (fn === "web_gate_start" || fn === "web_gate_resend") return { ok: false, reason: "site_busy" };
  if (fn === "web_gate_attempt_info")
    return { key: "enquiry:abcdefgh12", surface: "enquiry", email: "asha@example.com" };
  throw new Error(`unexpected rpc ${fn}`);
});
vi.mock("./db", () => ({ rpc, rpcRead: rpc, dbConfigured: () => true }));

const { resendCode, startVerification } = await import("./gate");
const { CONSENT } = await import("@/content/consent");

function capture() {
  const lines: { level: string; line: string }[] = [];
  for (const level of ["error", "warn", "info"] as const)
    vi.spyOn(console, level).mockImplementation(
      (...a: unknown[]) => void lines.push({ level, line: a.map(String).join(" ") }),
    );
  return lines;
}

describe("site-wide code ceiling (web14)", () => {
  it("tells the visitor to try again later and raises one alert, then warnings", async () => {
    const lines = capture();
    const input = {
      surface: "enquiry" as const,
      name: "Asha Rao",
      phone: "9876543211",
      email: "asha@example.com",
      consentVersion: CONSENT.form.version,
      idempotencyKey: "abcdefgh12",
    };
    const first = await startVerification(input);
    expect(first).toMatchObject({ status: "error", reason: "site_busy" });
    expect(first.status === "error" && first.message).toMatch(/a lot of requests/);
    const again = await resendCode("0d6c3b9a-1e2f-4a5b-8c7d-9e0f1a2b3c4d");
    expect(again).toMatchObject({ status: "error", reason: "site_busy" });
    expect(lines.filter((l) => l.level === "error" && l.line.includes("gate.code_ceiling_reached"))).toHaveLength(1);
    expect(lines.some((l) => l.level === "warn" && l.line.includes("gate.code_ceiling_refused"))).toBe(true);
    expect(lines.map((l) => l.line).join("\n")).not.toContain("asha@example.com");
    vi.restoreAllMocks();
  });
});
