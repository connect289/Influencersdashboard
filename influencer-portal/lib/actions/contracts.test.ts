// Deciding a compensation counter-offer: one locked database step that also marks the request decided, then the
// contract is generated; a failed generation says the terms are agreed and offers a retry that writes no deal version.
import { beforeEach, describe, expect, it, vi } from "vitest";
import type * as CounterModule from "@/lib/contracts/counter";
import messages from "@/messages/en.json";

const CONTRACT = "00000000-0000-4000-8000-0000000000c1";
const REQUEST = "00000000-0000-4000-8000-0000000000a1";
const DEAL = "00000000-0000-4000-8000-0000000000d1";
const BASE = "00000000-0000-4000-8000-0000000000b1";

const h = vi.hoisted(() => {
  const request: Record<string, unknown> = {};
  return { rpc: vi.fn(), generate: vi.fn(), request };
});

vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("next-intl/server", async () => {
  const { createTranslator } = await import("next-intl");
  return { getTranslations: () => Promise.resolve(createTranslator({ locale: "en", messages })) };
});
vi.mock("@/lib/auth/guards", () => ({
  fetchMe: () => Promise.resolve({ signed_in: true, session: { verified: true, revoked: false } }),
}));
vi.mock("@/lib/supabase/server", () => ({ createClient: () => Promise.resolve({ rpc: h.rpc }) }));
vi.mock("@/lib/contracts/data", () => ({
  loadContract: () => Promise.resolve({ id: CONTRACT, deal_id: DEAL, requests: [h.request] }),
  loadContractSource: () => Promise.resolve({ deal: { comp_config: { fixed: [] }, current_version_id: BASE } }),
}));
vi.mock("@/lib/contracts/generate", () => ({ generateVersion: h.generate }));
vi.mock("@/lib/contracts/counter", async (original) => ({
  ...(await original<typeof CounterModule>()),
  applyCounter: () => ({ ok: true, config: { fixed: [{ amount_paise: 2_000_000 }] } }),
}));
vi.mock("@/lib/log", () => ({ log: { info: vi.fn(), warn: vi.fn(), error: vi.fn() } }));

import { decideCompRequest, retryCounterGeneration } from "./contracts";

const changes = [{ key: "fixed.signing", value: 2_000_000 }];

beforeEach(() => {
  h.rpc.mockReset().mockResolvedValue({ data: "dv2", error: null });
  h.generate.mockReset().mockResolvedValue({ ok: true, versionId: "cv2", missing: [] });
  h.request = {
    id: REQUEST,
    kind: "compensation",
    status: "pending",
    proposed_terms: { changes },
    resolved_in_version_id: null,
  };
});

describe("decideCompRequest", () => {
  it("decides in one database step, with the base terms, then generates the contract", async () => {
    const r = await decideCompRequest({ requestId: REQUEST, contractId: CONTRACT, decision: "accepted" });
    expect(r).toMatchObject({ ok: true });
    expect(h.rpc).toHaveBeenCalledTimes(1);
    expect(h.rpc).toHaveBeenCalledWith("deal_version_from_counter", {
      p_request: REQUEST,
      p_config: { fixed: [{ amount_paise: 2_000_000 }] },
      p_status: "accepted",
      p_note: undefined,
      p_base_version: BASE,
    });
    // The request is already decided in the database, so the version does not resolve it again.
    expect(h.generate.mock.calls[0]?.[2]).not.toHaveProperty("resolve");
  });

  it("passes a counter's note", async () => {
    await decideCompRequest({
      requestId: REQUEST,
      contractId: CONTRACT,
      decision: "countered",
      terms: { changes },
      note: "We can do 18k",
    });
    expect(h.rpc.mock.calls[0]?.[1]).toMatchObject({ p_status: "countered", p_note: "We can do 18k" });
  });

  it("refuses a request that is no longer pending without touching the database", async () => {
    h.request.status = "accepted";
    const r = await decideCompRequest({ requestId: REQUEST, contractId: CONTRACT, decision: "accepted" });
    expect(r).toEqual({ ok: false, error: messages.contracts.errors.notPending });
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("maps a decision raced by another one to a clear error and generates nothing", async () => {
    h.rpc.mockResolvedValue({ data: null, error: { code: "22023", message: "change request is not pending" } });
    const r = await decideCompRequest({ requestId: REQUEST, contractId: CONTRACT, decision: "accepted" });
    expect(r).toEqual({ ok: false, error: messages.contracts.errors.notPending });
    expect(h.generate).not.toHaveBeenCalled();
  });

  it("maps terms that moved meanwhile", async () => {
    h.rpc.mockResolvedValue({
      data: null,
      error: { code: "40001", message: "the deal terms changed while this was being decided; reload and decide again" },
    });
    const r = await decideCompRequest({ requestId: REQUEST, contractId: CONTRACT, decision: "accepted" });
    expect(r).toEqual({ ok: false, error: messages.contracts.errors.termsChanged });
  });

  it("says the terms are agreed when generation fails", async () => {
    h.generate.mockResolvedValue({ ok: false, error: "no_terms", detail: [] });
    const r = await decideCompRequest({ requestId: REQUEST, contractId: CONTRACT, decision: "accepted" });
    expect(r.ok).toBe(false);
    expect(!r.ok && r.error).toContain("The new terms are agreed and saved");
    expect(!r.ok && r.error).toContain(messages.contracts.errors.noTerms);
  });
});

describe("retryCounterGeneration", () => {
  it("generates again for an agreed request without a version, never writing a deal version", async () => {
    h.request.status = "accepted";
    const r = await retryCounterGeneration(CONTRACT, REQUEST);
    expect(r).toMatchObject({ ok: true });
    expect(h.generate).toHaveBeenCalledTimes(1);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("does nothing for a request that is pending or already in a version", async () => {
    expect(await retryCounterGeneration(CONTRACT, REQUEST)).toEqual({
      ok: false,
      error: messages.contracts.errors.nothingToRetry,
    });
    h.request.status = "accepted";
    h.request.resolved_in_version_id = "00000000-0000-4000-8000-0000000000e1";
    expect((await retryCounterGeneration(CONTRACT, REQUEST)).ok).toBe(false);
    expect(h.generate).not.toHaveBeenCalled();
  });
});
