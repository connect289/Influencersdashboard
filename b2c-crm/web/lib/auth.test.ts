import { beforeEach, describe, expect, it, vi } from "vitest";

// Who is signed in, as b2c.me() and b2c.my_role() answer; no network, no Supabase.
const state = vi.hoisted(() => ({ me: null as Record<string, unknown> | null, role: null as string | null, rpcs: [] as string[] }));
vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({ cookies: async () => ({ get: () => undefined }), headers: async () => new Headers() }));
vi.mock("next/navigation", () => ({ redirect: (to: string) => { throw new Error(`redirect ${to}`); } }));
vi.mock("next/cache", () => ({ revalidatePath: () => undefined }));
vi.mock("@/lib/supabase/admin", () => ({ adminClient: () => ({}) }));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    rpc: async (fn: string) => {
      state.rpcs.push(fn);
      if (fn === "me") return { data: state.me, error: null };
      if (fn === "my_role") return { data: state.role, error: null };
      return { data: 1, error: null };
    },
  }),
}));

const { allowed, SIGNED_OUT } = await import("./auth");
const { rateRetire } = await import("@/app/w/money-actions");

const active = { user_id: "u-1", email: "asha@eduwit.in", known: true, active: true, role: "admin", full_name: "Asha", checked: true, interface: "admin" };
beforeEach(() => { state.me = { ...active }; state.role = "admin"; state.rpcs = []; });

describe("a server action called by an ended session (b55)", () => {
  it("answers 'signed out' when the session expired", async () => {
    state.me = { user_id: null, email: null, known: false, active: false, role: null, full_name: null, checked: false, interface: null };
    expect(await allowed()).toEqual({ ok: false, error: SIGNED_OUT });
    expect(SIGNED_OUT).toBe("You were signed out. Sign in again.");
  });

  it("answers 'signed out' when the session was signed out from another device", async () => {
    state.role = null;
    expect(await allowed(["admin"])).toEqual({ ok: false, error: SIGNED_OUT });
  });

  it("answers 'not allowed' for the wrong role, and lets the right one through", async () => {
    expect(await allowed(["counsellor"])).toEqual({ ok: false, error: "You are not allowed to do that." });
    expect(await allowed(["admin"])).toMatchObject({ ok: true, me: { user_id: "u-1" } });
  });

  it("returns the result instead of throwing, so the form keeps what was typed", async () => {
    state.me = { ...active, user_id: null };
    await expect(rateRetire(1, "wrong rate")).resolves.toEqual({ ok: false, error: SIGNED_OUT });
    expect(state.rpcs).not.toContain("university_rate_retire");
    state.me = { ...active };
    await expect(rateRetire(1, "wrong rate")).resolves.toMatchObject({ ok: true });
    expect(state.rpcs).toContain("university_rate_retire");
  });
});
