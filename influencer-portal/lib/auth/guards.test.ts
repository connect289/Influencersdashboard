// The page guards do their work once per page render (layout and page share one run through React's cache()) and
// in full on every call outside a render (Server Actions, Route Handlers). The permission check is never shared.
import type * as ReactModule from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => {
  /**
   * Stand-in for React's cache(): inside a "render pass" it remembers a function's outcome per first argument, as the
   * server renderer does; outside one it calls straight through, as React does in Server Actions and Route Handlers.
   */
  const state: { pass: Map<unknown, Map<unknown, unknown>> | null } = { pass: null };
  function cache<A extends unknown[], R>(fn: (...args: A) => R): (...args: A) => R {
    return (...args: A): R => {
      if (!state.pass) return fn(...args);
      let byArg = state.pass.get(fn);
      if (!byArg) {
        byArg = new Map<unknown, unknown>();
        state.pass.set(fn, byArg);
      }
      if (!byArg.has(args[0])) byArg.set(args[0], fn(...args));
      return byArg.get(args[0]) as R;
    };
  }
  return { state, cache, createClient: vi.fn(), cookie: { value: undefined as string | undefined } };
});

vi.mock("react", async (original) => ({ ...(await original<typeof ReactModule>()), cache: h.cache }));
vi.mock("next/headers", () => ({
  cookies: () => Promise.resolve({ get: () => (h.cookie.value ? { value: h.cookie.value } : undefined) }),
  headers: () => Promise.resolve(new Headers({ "x-inf-path": "/admin/creators?tab=all" })),
}));
vi.mock("next/navigation", () => ({
  redirect: (to: string) => {
    throw new Error(`REDIRECT ${to}`);
  },
  notFound: () => {
    throw new Error("NOT_FOUND");
  },
}));
vi.mock("@/lib/supabase/server", () => ({ createClient: h.createClient }));
vi.mock("@/lib/log", () => ({ log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() } }));

import { requireAgency, requireCreator, requireStaff } from "./guards";

const uid = "6b0f7b5e-6a3c-4b1e-9b9d-6f2f1d1a2b3c";
const cid = "0e4a1f2b-3c4d-4e5f-8a9b-0c1d2e3f4a5b";
const session = { registered: true, verified: true, revoked: false, verified_via: "email_code" };
const staffMe = {
  signed_in: true,
  user_id: uid,
  email: "a@eduwit.in",
  kind: "staff",
  session,
  // A viewer may read analytics and scorecards, nothing else.
  staff: { full_name: "A", status: "active", is_signatory: false, roles: ["viewer"] },
};
const creatorMe = {
  signed_in: true,
  user_id: uid,
  email: "c@example.com",
  kind: "creator",
  session,
  creator: { id: cid, display_name: "C", handle: "c", status: "active", is_blocked: false, is_test: false },
};
const agencyMe = {
  signed_in: true,
  user_id: uid,
  email: "g@example.com",
  kind: "agency",
  session,
  agency: { id: cid, name: "G", status: "active", member_name: "M", role: "owner", member_status: "active" },
};

interface Fake {
  rpcs: string[];
  signOuts: number;
}

/** One fake client per createClient() call; `me` answers come from the queue (the last one repeats). */
function serve(opts: { signedIn?: boolean; me: unknown[]; trusted?: boolean }): Fake[] {
  const made: Fake[] = [];
  h.createClient.mockImplementation(() => {
    const fake: Fake = { rpcs: [], signOuts: 0 };
    const queue = [...opts.me];
    made.push(fake);
    return Promise.resolve({
      auth: {
        getClaims: () => Promise.resolve({ data: opts.signedIn === false ? null : { claims: { sub: uid } } }),
        signOut: () => {
          fake.signOuts++;
          return Promise.resolve({ error: null });
        },
      },
      rpc: (name: string) => {
        fake.rpcs.push(name);
        if (name === "me") return Promise.resolve({ data: queue.length > 1 ? queue.shift() : queue[0], error: null });
        if (name === "device_trust_check") return Promise.resolve({ data: opts.trusted === true, error: null });
        return Promise.resolve({ data: null, error: null });
      },
    });
  });
  return made;
}

const count = (f: Fake | undefined, name: string) => (f ? f.rpcs.filter((r) => r === name).length : 0);
const message = (p: Promise<unknown>) =>
  p.then(
    () => "resolved",
    (e: unknown) => (e instanceof Error ? e.message : String(e)),
  );

beforeEach(() => {
  h.createClient.mockReset();
  h.cookie.value = undefined;
  h.state.pass = null;
});

describe("page guards inside one render", () => {
  beforeEach(() => {
    h.state.pass = new Map();
  });

  it("layout and page share one staff guard run, one client and one session touch", async () => {
    const made = serve({ me: [staffMe] });
    const layout = await requireStaff();
    const page = await requireStaff("analytics.read");
    expect(made).toHaveLength(1);
    expect(count(made[0], "me")).toBe(1);
    expect(count(made[0], "session_touch")).toBe(1);
    expect(page.supabase).toBe(layout.supabase);
    expect(page.me.permissions.has("analytics.read")).toBe(true);
  });

  it("still checks each caller's own permission", async () => {
    const made = serve({ me: [staffMe] });
    await expect(requireStaff()).resolves.toBeTruthy();
    expect(await message(requireStaff("payout.approve"))).toBe("NOT_FOUND");
    expect(await message(requireStaff("analytics.read"))).toBe("resolved");
    expect(count(made[0], "me")).toBe(1);
    expect(count(made[0], "session_touch")).toBe(1);
  });

  it("does not touch the session when the only caller lacks the permission", async () => {
    const made = serve({ me: [staffMe] });
    expect(await message(requireStaff("payout.approve"))).toBe("NOT_FOUND");
    expect(count(made[0], "session_touch")).toBe(0);
  });

  it("gives both callers the same redirect when nobody is signed in", async () => {
    const made = serve({ signedIn: false, me: [staffMe] });
    const to = `REDIRECT /login/staff?next=${encodeURIComponent("/admin/creators?tab=all")}`;
    expect(await message(requireStaff())).toBe(to);
    expect(await message(requireStaff("analytics.read"))).toBe(to);
    expect(made).toHaveLength(1);
    expect(made[0]?.rpcs).toEqual([]);
  });

  it("registers an unregistered session once", async () => {
    const made = serve({ me: [{ ...staffMe, session: { ...session, registered: false } }, staffMe] });
    await requireStaff();
    await requireStaff("analytics.read");
    expect(made[0]?.rpcs).toEqual(["me", "session_register", "me", "session_touch"]);
  });

  it("sends an unverified staff session to the code page, or on with a trusted device", async () => {
    const unverified = { ...staffMe, session: { ...session, verified: false } };
    serve({ me: [unverified] });
    const to = `REDIRECT /verify?next=${encodeURIComponent("/admin/creators?tab=all")}`;
    expect(await message(requireStaff())).toBe(to);
    expect(await message(requireStaff("analytics.read"))).toBe(to);

    h.state.pass = new Map();
    h.cookie.value = "device-token";
    const made = serve({ me: [unverified, staffMe], trusted: true });
    await requireStaff();
    await requireStaff("analytics.read");
    expect(made[0]?.rpcs).toEqual(["me", "device_trust_check", "me", "session_touch"]);
  });

  it("signs a revoked session out once and redirects both callers", async () => {
    const made = serve({ me: [{ ...staffMe, session: { ...session, revoked: true } }] });
    expect(await message(requireStaff())).toBe("REDIRECT /login/staff?reason=revoked");
    expect(await message(requireStaff("analytics.read"))).toBe("REDIRECT /login/staff?reason=revoked");
    expect(made).toHaveLength(1);
    expect(made[0]?.signOuts).toBe(1);
    expect(count(made[0], "session_touch")).toBe(0);
  });

  it("gives both callers the same failure when me() fails", async () => {
    const made: Fake[] = [];
    h.createClient.mockImplementation(() => {
      const fake: Fake = { rpcs: [], signOuts: 0 };
      made.push(fake);
      return Promise.resolve({
        auth: { getClaims: () => Promise.resolve({ data: { claims: { sub: uid } } }) },
        rpc: (name: string) => {
          fake.rpcs.push(name);
          return Promise.resolve({
            data: null,
            error: { code: "", message: "AbortError: This operation was aborted" },
          });
        },
      });
    });
    expect(await message(requireStaff())).toBe("me() failed: AbortError: This operation was aborted");
    expect(await message(requireStaff("analytics.read"))).toBe("me() failed: AbortError: This operation was aborted");
    expect(made).toHaveLength(1);
    expect(made[0]?.rpcs).toEqual(["me"]);
  });

  it("creator: one run for layout and page; staff and agency accounts are sent to their own portal", async () => {
    const made = serve({ me: [creatorMe] });
    const layout = await requireCreator();
    const page = await requireCreator();
    expect(page).toBe(layout);
    expect(layout.me.creatorId).toBe(cid);
    expect(made[0]?.rpcs).toEqual(["me", "session_touch"]);

    h.state.pass = new Map();
    serve({ me: [staffMe] });
    expect(await message(requireCreator())).toBe("REDIRECT /admin");
    expect(await message(requireCreator())).toBe("REDIRECT /admin");
    h.state.pass = new Map();
    serve({ me: [agencyMe] });
    expect(await message(requireCreator())).toBe("REDIRECT /agency");
  });

  it("agency: one run for layout and page", async () => {
    const made = serve({ me: [agencyMe] });
    const layout = await requireAgency();
    const page = await requireAgency();
    expect(page).toBe(layout);
    expect(layout.me.isOwner).toBe(true);
    expect(made[0]?.rpcs).toEqual(["me", "session_touch"]);
  });

  it("a new render starts from scratch", async () => {
    const made = serve({ me: [staffMe] });
    await requireStaff();
    h.state.pass = new Map();
    await requireStaff();
    expect(made).toHaveLength(2);
    expect(count(made[1], "me")).toBe(1);
    expect(count(made[1], "session_touch")).toBe(1);
  });
});

describe("page guards outside a render (Server Actions, Route Handlers)", () => {
  it("run in full on every call, as before", async () => {
    const made = serve({ me: [staffMe] });
    await requireStaff("analytics.read");
    await requireStaff("analytics.read");
    expect(made).toHaveLength(2);
    expect(made.map((f) => f.rpcs)).toEqual([
      ["me", "session_touch"],
      ["me", "session_touch"],
    ]);
    expect(await message(requireStaff("payout.approve"))).toBe("NOT_FOUND");
    expect(made).toHaveLength(3);
    expect(made[2]?.rpcs).toEqual(["me"]);
  });

  it("creator and agency guards too", async () => {
    const creators = serve({ me: [creatorMe] });
    await requireCreator();
    await requireCreator();
    expect(creators.map((f) => f.rpcs)).toEqual([
      ["me", "session_touch"],
      ["me", "session_touch"],
    ]);
    const agencies = serve({ me: [agencyMe] });
    await requireAgency();
    await requireAgency();
    expect(agencies).toHaveLength(2);
  });
});
