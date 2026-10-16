import { describe, expect, it } from "vitest";
import { batchDone, chunks, feedEnvelope, intakeBody, singleDone, toBatchItem, type OutboxItem } from "./b2b-map";

const item = (o: Partial<OutboxItem>): OutboxItem => ({
  id: 1, kind: "update", lead_id: 949, request_id: "b2c-u-1", body: {}, occurred_at: "2026-10-14T10:00:00+05:30", actor: { name: "Priya" }, urgent: false, ...o,
});

describe("batch items (contract §3.8, Addendum 4 §2)", () => {
  it("an update carries set and occurred_at", () => {
    expect(toBatchItem(item({ body: { set: { stage: "contacted" } } }))).toEqual({
      op: "update", lead_id: 949, request_id: "b2c-u-1", actor: { name: "Priya" }, set: { stage: "contacted" }, occurred_at: "2026-10-14T10:00:00+05:30",
    });
  });
  it("an activity carries its own fields", () => {
    expect(toBatchItem(item({ kind: "activity", request_id: "b2c-a-1", body: { kind: "call", at: "2026-10-14T10:00:00Z", outcome: "connected" } })))
      .toMatchObject({ op: "activity", lead_id: 949, request_id: "b2c-a-1", kind: "call", outcome: "connected" });
  });
  it("chunks at 200", () => {
    expect(chunks(Array.from({ length: 450 }, (_, i) => i)).map((c) => c.length)).toEqual([200, 200, 50]);
  });
});

describe("answers for b2c.outbox_done", () => {
  const a = item({ id: 1, request_id: "r1" });
  const b = item({ id: 2, request_id: "r2" });
  it("matches batch answers by request_id, in any order", () => {
    const res = batchDone([a, b], 200, { items: [{ request_id: "r2", ok: false, status: 409, error: "stale" }, { request_id: "r1", ok: true, status: 200, version: 8 }] });
    expect(res).toEqual([
      { id: 1, ok: true, status: 200, answer: { request_id: "r1", ok: true, status: 200, version: 8 } },
      { id: 2, ok: false, status: 409, answer: { request_id: "r2", ok: false, status: 409, error: "stale" } },
    ]);
  });
  it("a failed call fails every item with its status, so they retry", () => {
    expect(batchDone([a, b], 503, { ok: false }).map((r) => [r.ok, r.status])).toEqual([[false, 503], [false, 503]]);
  });
  it("an item missing from the answer is retried", () => {
    expect(batchDone([a], 200, { items: [] })[0]).toMatchObject({ ok: false, status: 502 });
  });
  it("a single answer keeps the result, which outbox_after and apply_record read", () => {
    const r = singleDone(item({ kind: "route" }), 200, { ok: true, result: { destination: "partner", reference: "EDW-1" } });
    expect(r.ok).toBe(true);
    expect(r.answer.result).toEqual({ destination: "partner", reference: "EDW-1" });
    expect(r.answer.destination).toBe("partner");
    expect(singleDone(item({}), 422, { ok: false, error_code: "no_consent" })).toMatchObject({ ok: false, status: 422 });
    expect(singleDone(item({}), 200, { ok: false, error: "?" }).ok).toBe(false);
  });
});

describe("intake body (docs/intake-api.md)", () => {
  it("uses only accepted keys and routes back to B2C sales", () => {
    const b = intakeBody({ phone: "919876543210", lead_source: "b2c_created", name: "Asha Test", course: "Online MBA", other_courses: ["BBA", "BCA"], notes: "Walk-in" }, "2026-10-14T10:00:00.000Z");
    expect(Object.keys(b).sort()).toEqual(["b2c_lane", "channel", "lead", "occurred_at", "route", "source"]);
    expect(b).toMatchObject({ source: "b2c_created", route: "b2c", b2c_lane: "sales", channel: "b2c_crm" });
    expect(b.lead).toMatchObject({ phone: "919876543210", full_name: "Asha Test", course: "Online MBA" });
    expect(b.lead.notes).toContain("Also interested in: BBA, BCA");
  });
  it("a WhatsApp newcomer keeps the first message, and consent only with a registered text version", () => {
    const b = intakeBody({ phone: "919000000001", lead_source: "b2c_whatsapp", first_message: "MBA fees?" }, "2026-10-14T10:00:00.000Z");
    expect(b.channel).toBe("whatsapp");
    expect(b.lead.notes).toBe("First message: MBA fees?");
    expect(b.consent).toBeUndefined();
    expect(intakeBody({ phone: "1", consent_text_version: "wa_partner_consent:v1" }, "t").consent).toEqual({ sales_at: "t", partner_share_at: "t", text_version: "wa_partner_consent:v1" });
  });
});

describe("change feed as envelopes", () => {
  it("gets a stable id per seq, so webhook and feed are de-duplicated together", () => {
    expect(feedEnvelope({ type: "b2c.lead_upserted", lead_id: 949, version: 7, seq: 18802, record: { id: 949 } }))
      .toMatchObject({ id: "feed-18802", type: "b2c.lead_upserted", lead_id: 949, data: { version: 7, seq: 18802, record: { id: 949 } } });
  });
});
