import { beforeEach, describe, expect, it, vi } from "vitest";

// M34i: the lockout check sends the client IP and the step; the gate applies the 12-hour idle rule on the server.
const rpc = vi.fn();
const meRpc = vi.fn();
let seen: string | undefined;

vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({ cookies: async () => ({ get: (n: string) => (n === "b2b_seen" && seen !== undefined ? { name: n, value: seen } : undefined) }) }));
vi.mock("next/navigation", () => ({ redirect: (to: string) => { throw new Error(`redirect:${to}`); } }));
vi.mock("@/lib/supabase/admin", () => ({ adminClient: () => ({ rpc }) }));
vi.mock("@/lib/supabase/server", () => ({ createClient: async () => ({ schema: () => ({ rpc: meRpc }) }) }));

const ADMIN = { user_id: "u1", email: "a@x.in", aal: "aal2", allowlisted: true, role: "admin", require_totp: true, is_admin: true };
const now = () => Math.floor(Date.now() / 1000);

beforeEach(() => {
  vi.resetModules();
  rpc.mockReset();
  meRpc.mockReset();
  meRpc.mockResolvedValue({ data: ADMIN, error: null });
  seen = undefined;
});

describe("isLocked (M34i)", () => {
  it("asks sign_in_locked with the email, the client IP and the step", async () => {
    const { isLocked } = await import("./auth");
    rpc.mockResolvedValue({ data: false, error: null });
    expect(await isLocked("a@x.in", "203.0.113.7", "password")).toBe(false);
    expect(rpc).toHaveBeenCalledWith("sign_in_locked", { p_email: "a@x.in", p_ip: "203.0.113.7", p_step: "password" });
    rpc.mockResolvedValue({ data: true, error: null });
    expect(await isLocked("a@x.in", null, "totp")).toBe(true);
    expect(rpc).toHaveBeenLastCalledWith("sign_in_locked", { p_email: "a@x.in", p_ip: null, p_step: "totp" });
  });
  it("fails closed when the check cannot run", async () => {
    const { isLocked } = await import("./auth");
    rpc.mockResolvedValue({ data: null, error: { code: "PGRST202" } });
    await expect(isLocked("a@x.in", "203.0.113.7", "password")).rejects.toThrow(/lockout check failed \(PGRST202\)/);
  });
});

describe("requireAdmin and assertAdmin: the 12-hour idle rule (M34i)", () => {
  it("sends a session idle for more than 12 hours to /login before reading anything", async () => {
    const { requireAdmin } = await import("./auth");
    seen = String(now() - 12 * 3600 - 5);
    await expect(requireAdmin()).rejects.toThrow("redirect:/login?reason=idle");
    expect(meRpc).not.toHaveBeenCalled();
  });
  it("lets an active session through, and a missing cookie is not idle", async () => {
    const { requireAdmin } = await import("./auth");
    seen = String(now() - 60);
    expect(await requireAdmin()).toEqual({ me: ADMIN });
    vi.resetModules();
    seen = undefined;
    const again = await import("./auth");
    expect(await again.requireAdmin()).toEqual({ me: ADMIN });
  });
  it("refuses a server action from an idle session", async () => {
    const { assertAdmin } = await import("./auth");
    seen = String(now() - 13 * 3600);
    await expect(assertAdmin()).rejects.toThrow("not allowed");
    expect(meRpc).not.toHaveBeenCalled();
    seen = String(now() - 30);
    expect(await assertAdmin()).toEqual(ADMIN);
  });
});
