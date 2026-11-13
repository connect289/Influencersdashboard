// Inviting creators queues one creator.invite job per invitation and returns how many; nothing is emailed in the
// action itself.
import { beforeEach, describe, expect, it, vi } from "vitest";
import messages from "@/messages/en.json";

const h = vi.hoisted(() => ({
  invited: [] as { creator_id: string; email: string; display_name: string }[],
  upserts: [] as { rows: { kind: string; payload: Record<string, unknown>; idem_key: string }[]; opts: unknown }[],
  upsertError: null as null | { message: string },
  send: vi.fn(),
}));

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("next-intl/server", async () => {
  const { createTranslator } = await import("next-intl");
  return { getTranslations: () => Promise.resolve(createTranslator({ locale: "en", messages })) };
});
vi.mock("@/lib/auth/guards", () => ({
  fetchMe: () => Promise.resolve({ kind: "staff", session: { verified: true, revoked: false } }),
}));
vi.mock("@/lib/supabase/server", () => ({
  createClient: () => Promise.resolve({ rpc: () => Promise.resolve({ data: h.invited, error: null }) }),
}));
vi.mock("@/lib/supabase/admin", () => ({
  adminClient: () => ({
    from: (table: string) => ({
      upsert: (rows: (typeof h.upserts)[number]["rows"], opts: unknown) => {
        expect(table).toBe("jobs");
        h.upserts.push({ rows, opts });
        return Promise.resolve({ error: h.upsertError });
      },
    }),
  }),
}));
vi.mock("@/lib/notify/email", () => ({ emailProvider: () => ({ send: h.send }) }));
vi.mock("@/lib/log", () => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  errorMessage: (e: unknown) => (e instanceof Error ? e.message : String(e)),
}));

import { inviteCreators } from "./onboarding";

const id = (n: number) => `00000000-0000-4000-8000-${n.toString().padStart(12, "0")}`;

beforeEach(() => {
  h.invited = [];
  h.upserts = [];
  h.upsertError = null;
  h.send.mockReset();
});

describe("inviteCreators", () => {
  it("queues one job per invitation, keyed per creator and day, and returns the count", async () => {
    h.invited = [1, 2, 3].map((n) => ({
      creator_id: id(n),
      email: `c${n.toString()}@example.test`,
      display_name: "C",
    }));
    const r = await inviteCreators([id(1), id(2), id(3), id(4)]);
    expect(r).toMatchObject({ ok: true, data: { invited: 3 } });
    expect(r.ok && r.message).toBe(
      "3 invitations are on the way. Each is sent within a few minutes and retried if sending fails. 1 skipped (no email or already signed up).",
    );
    const rows = h.upserts.flatMap((u) => u.rows);
    expect(rows).toHaveLength(3);
    expect(rows[0]).toMatchObject({ kind: "creator.invite", payload: { creator_id: id(1) } });
    expect(rows[0]?.idem_key).toMatch(new RegExp(`^creator_invite:${id(1)}:\\d{4}-\\d{2}-\\d{2}$`));
    expect(h.upserts[0]?.opts).toEqual({ onConflict: "idem_key", ignoreDuplicates: true });
    expect(h.send).not.toHaveBeenCalled();
  });

  it("queues 500 in one request", async () => {
    h.invited = Array.from({ length: 500 }, (_, n) => ({
      creator_id: id(n),
      email: "x@example.test",
      display_name: "X",
    }));
    const r = await inviteCreators(h.invited.map((c) => c.creator_id));
    expect(r).toMatchObject({ ok: true, data: { invited: 500 } });
    expect(h.upserts).toHaveLength(1);
  });

  it("says when nobody qualified", async () => {
    const r = await inviteCreators([id(1)]);
    expect(r.ok && r.message).toBe(messages.onboarding.invite.none);
  });

  it("reports a failure to queue", async () => {
    h.invited = [{ creator_id: id(1), email: "a@example.test", display_name: "A" }];
    h.upsertError = { message: "down" };
    expect(await inviteCreators([id(1)])).toEqual({ ok: false, error: messages.errors.generic });
  });

  it("refuses more than 500", async () => {
    const r = await inviteCreators(Array.from({ length: 501 }, (_, n) => id(n)));
    expect(r.ok).toBe(false);
  });
});
