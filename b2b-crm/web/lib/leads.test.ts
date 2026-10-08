import { describe, expect, it } from "vitest";
import {
  CLEAR_FILTERS, DESTINATIONS, DESTINATION_HINT, DESTINATION_LABEL, EXPORT_COLUMNS, FLAG_DESTINATIONS, PAID_FILTERS, ROUTING_DESTINATIONS,
  bulkRouteToast, formatPhone, hasFilters, humanize, leadsHref, parseLeadId, parseLeadQuery, reroutePreview, rerouteToast, rowBadges,
  sendToPartnersPreview, shortDate, statusTone, toCsv, toRpcParams, toggle, whatsappLink, type LeadRow,
} from "./leads";

const DEFAULT_QUERY = { q: "", stage: [], source: [], status: [], dest: null, paid: null, sort: "created_at", dir: "desc", test: false, bin: false };

describe("parseLeadQuery", () => {
  it("defaults to newest first, live leads, no tests", () => {
    expect(parseLeadQuery({})).toEqual(DEFAULT_QUERY);
  });

  it("reads every filter", () => {
    const q = parseLeadQuery({ q: "  ravi ", stage: "new,qualifying", source: "whatsapp_direct", status: "hot,warm", dest: "partner", paid: "meta", sort: "name", dir: "asc", test: "1", view: "bin" });
    expect(q).toEqual({ q: "ravi", stage: ["new", "qualifying"], source: ["whatsapp_direct"], status: ["HOT", "WARM"], dest: "partner", paid: "meta", sort: "name", dir: "asc", test: true, bin: true });
  });

  it("rejects unknown enums and caps sizes", () => {
    const q = parseLeadQuery({ sort: "id; drop", dir: "sideways", dest: "x", paid: "yes", q: "a".repeat(500), stage: Array.from({ length: 50 }, (_, i) => `s${i}`).join(",") });
    expect(q.sort).toBe("created_at");
    expect(q.dir).toBe("desc");
    expect(q.dest).toBeNull();
    expect(q.paid).toBeNull();
    expect(q.q).toHaveLength(100);
    expect(q.stage).toHaveLength(20);
  });

  it("de-duplicates and drops empty list items; takes the first of repeated params", () => {
    expect(parseLeadQuery({ stage: "a,,a, b ", q: ["first", "second"] })).toMatchObject({ stage: ["a", "b"], q: "first" });
  });

  it("accepts the Addendum 3 flags as dest values and the three paid filters", () => {
    for (const d of ["barred", "qualification_nurture", "awaiting_consent", "reenquired", "lost_grace"]) expect(parseLeadQuery({ dest: d }).dest).toBe(d);
    for (const p of ["meta", "google", "any"]) expect(parseLeadQuery({ paid: p }).paid).toBe(p);
    expect(DESTINATIONS).toEqual([...ROUTING_DESTINATIONS, ...FLAG_DESTINATIONS]);
    expect(PAID_FILTERS).toEqual(["meta", "google", "any"]);
  });
});

describe("parseLeadId", () => {
  it("accepts positive integers only", () => {
    expect(parseLeadId({ lead: "1218" })).toBe(1218);
    expect(parseLeadId({ lead: "0" })).toBeNull();
    expect(parseLeadId({ lead: "-3" })).toBeNull();
    expect(parseLeadId({ lead: "12abc" })).toBeNull();
    expect(parseLeadId({})).toBeNull();
  });
});

describe("leadsHref", () => {
  const base = parseLeadQuery({});
  it("leaves defaults out", () => {
    expect(leadsHref(base)).toBe("/leads");
  });
  it("round-trips through parseLeadQuery", () => {
    const q = parseLeadQuery({ q: "a&b=c", stage: "new", status: "HOT", dest: "unrouted", paid: "google", sort: "last_activity", dir: "asc", test: "1", view: "bin" });
    const sp = Object.fromEntries(new URLSearchParams(leadsHref(q).split("?")[1]));
    expect(parseLeadQuery(sp)).toEqual(q);
  });
  it("round-trips a flag view", () => {
    const q = parseLeadQuery({ dest: "lost_grace" });
    expect(leadsHref(q)).toBe("/leads?dest=lost_grace");
    expect(parseLeadQuery(Object.fromEntries(new URLSearchParams(leadsHref(q).split("?")[1])))).toEqual(q);
  });
  it("applies a patch and the open lead", () => {
    expect(leadsHref(base, { bin: true }, 7)).toBe("/leads?view=bin&lead=7");
    expect(leadsHref(parseLeadQuery({ dest: "barred", paid: "any", q: "x" }), CLEAR_FILTERS)).toBe("/leads");
  });
});

describe("toRpcParams", () => {
  it("maps the URL query to the database arguments", () => {
    const p = toRpcParams(parseLeadQuery({ dest: "in_house", test: "1" }), { after: { v: "x", id: "9" }, limit: 10 });
    expect(p).toMatchObject({ destination: "in_house", include_test: true, bin: false, limit: 10, after: { v: "x", id: "9" }, q: undefined, paid: undefined });
  });
  it("passes the Addendum 3 destination flags and the paid filter (lead_filter_sql keys)", () => {
    expect(toRpcParams(parseLeadQuery({ dest: "awaiting_consent", paid: "any" }))).toMatchObject({ destination: "awaiting_consent", paid: "any" });
    expect(toRpcParams(parseLeadQuery({ dest: "reenquired" }))).toMatchObject({ destination: "reenquired", paid: undefined });
  });
});

describe("helpers", () => {
  it("toggle adds and removes", () => {
    expect(toggle(["a"], "b")).toEqual(["a", "b"]);
    expect(toggle(["a", "b"], "a")).toEqual(["b"]);
  });
  it("hasFilters ignores sort, tests and bin, and counts paid and the flags", () => {
    expect(hasFilters(parseLeadQuery({ sort: "name", test: "1", view: "bin" }))).toBe(false);
    expect(hasFilters(parseLeadQuery({ status: "HOT" }))).toBe(true);
    expect(hasFilters(parseLeadQuery({ paid: "meta" }))).toBe(true);
    expect(hasFilters(parseLeadQuery({ dest: "barred" }))).toBe(true);
  });
  it("humanize", () => {
    expect(humanize("whatsapp_direct")).toBe("WhatsApp direct");
    expect(humanize("EARN_IT")).toBe("Earn it");
    expect(humanize("(none)")).toBe("None");
    expect(humanize("pg")).toBe("PG");
    expect(humanize(null)).toBe("None");
  });
  it("statusTone", () => {
    expect(statusTone("hot")).toBe("danger");
    expect(statusTone("WARM")).toBe("warning");
    expect(statusTone("COLD")).toBe("info");
    expect(statusTone(null)).toBe("neutral");
  });
  it("formatPhone and whatsappLink", () => {
    expect(formatPhone("919800000012")).toBe("+91 98000 00012");
    expect(formatPhone("9800000012")).toBe("+91 98000 00012");
    expect(formatPhone("+1 555 0100")).toBe("+1 555 0100");
    expect(formatPhone(null)).toBe("—");
    expect(whatsappLink("+91 98000-00012")).toBe("https://wa.me/919800000012");
    expect(whatsappLink("9800000012")).toBe("https://wa.me/919800000012");
    expect(whatsappLink("123")).toBeNull();
  });
  it("shortDate is the IST day and month", () => {
    expect(shortDate("2026-10-12T10:00:00Z")).toBe("12 Oct");
    expect(shortDate("2026-10-12T20:30:00Z")).toBe("13 Oct"); // 02:00 IST the next day
    expect(shortDate(null)).toBe("—");
    expect(shortDate("not a date")).toBe("—");
  });
  it("every dest value has a label and every flag view a description", () => {
    for (const d of DESTINATIONS) expect(DESTINATION_LABEL[d]).toBeTruthy();
    for (const d of [...FLAG_DESTINATIONS, "not_passed"]) expect(DESTINATION_HINT[d]).toBeTruthy();
  });
});

// ---------- row badges ----------

function row(over: Partial<LeadRow> = {}): LeadRow {
  return {
    id: 1, created_at: "2026-10-01T05:00:00Z", student_name: "Ravi", whatsapp_number: "919800000012", email_id: null, city: null, state: null,
    interested_course: "MBA", interested_specialization: null, program_level: null, study_mode_preference: null, lead_source: "witty", channel: null,
    campaign: null, lead_status: null, temperature: null, stage: "new", sub_stage: null, lead_stage: null, destination_type: null, partner_id: null,
    last_activity_at: null, deleted_at: null, is_opted_out: false, is_test: false, partner_consent: false, is_bot_paused: null, not_passed: null,
    partner_bar_reason: null, partner_barred_at: null, other_providers_count: 0, other_providers: null, b2c_lane: null, allocation_reason: null,
    hold_kind: null, reenquired_open: false, paid_platform: null, consent_state: "none", lost_grace_until: null,
    ...over,
  };
}
const texts = (r: LeadRow) => rowBadges(r).map((b) => b.text);

describe("rowBadges", () => {
  it("shows nothing for a plain unrouted lead", () => {
    expect(rowBadges(row())).toEqual([]);
  });

  it("a duplicate-cascade lead: B2C sales, partner-barred, other providers", () => {
    const b = rowBadges(row({
      destination_type: "in_house", b2c_lane: "sales", allocation_reason: "duplicate_cascade", hold_kind: "barred",
      partner_bar_reason: "duplicate", partner_barred_at: "2026-10-03T06:00:00Z", other_providers_count: 2, other_providers: "Acme Edu; Beta Learning",
    }));
    expect(b.map((x) => x.text)).toEqual(["B2C sales · duplicate cascade", "Partner-barred", "Other providers (2)"]);
    expect(b.map((x) => x.tone)).toEqual(["info", "danger", "danger"]);
    expect(b[0]?.title).toBe("Duplicate at partners (partner-barred)");
    expect(b[1]?.title).toBe("Partner-barred (duplicate at partners) since 3 Oct: B2C only, for ever");
    expect(b[2]?.title).toBe("Already with: Acme Edu; Beta Learning");
  });

  it("a lead lost by a partner after the grace: B2C nurture, barred (lost)", () => {
    const b = rowBadges(row({ destination_type: "in_house", b2c_lane: "nurture", allocation_reason: "partner_lost", hold_kind: "barred", partner_bar_reason: "lost", partner_barred_at: "2026-10-05T06:00:00Z" }));
    expect(b.map((x) => x.text)).toEqual(["B2C nurture · lost by a partner", "Partner-barred"]);
    expect(b[1]?.title).toContain("lost by a partner");
  });

  it("a qualification-nurture lead reads 'qualifying'", () => {
    expect(texts(row({ destination_type: "in_house", b2c_lane: "nurture", allocation_reason: "not_qualified", hold_kind: "qualification_nurture" }))).toEqual(["B2C nurture · qualifying"]);
    expect(texts(row({ destination_type: "in_house", b2c_lane: "nurture", allocation_reason: "consent_no_answer", hold_kind: "qualification_nurture" }))).toEqual(["B2C nurture · qualifying"]);
  });

  it("a re-enquired lead with a partner", () => {
    const b = rowBadges(row({ destination_type: "partner", partner_id: 4, reenquired_open: true }));
    expect(b.map((x) => x.text)).toEqual(["Partner #4", "Re-enquired"]);
    expect(b.map((x) => x.tone)).toEqual(["brand", "danger"]);
  });

  it("a lead lost in grace stays with its partner and shows the grace end", () => {
    const b = rowBadges(row({ destination_type: "partner", partner_id: 4, lost_grace_until: "2026-10-12T10:00:00Z" }));
    expect(b.map((x) => x.text)).toEqual(["Partner #4", "Lost, in grace until 12 Oct"]);
    expect(b[1]?.tone).toBe("danger");
  });

  it("an unrouted lead awaiting consent", () => {
    // consent_state (CONTRACT 1.3) folds sent / unsendable requests into 'requested'; 'queued' waits for the hourly budget.
    for (const state of ["requested", "queued"] as const) {
      const b = rowBadges(row({ consent_state: state }));
      expect(b.map((x) => x.text)).toEqual(["Awaiting consent"]);
      expect(b[0]?.tone).toBe("warning");
    }
    expect(texts(row({ consent_state: "given" }))).toEqual([]);
    expect(texts(row({ consent_state: "expired" }))).toEqual([]);
  });

  it("the Not passed badge carries the spam detail", () => {
    expect(texts(row({ not_passed: { reason: "junk", decided_at: "2026-10-01T05:00:00Z", detail: "spam:witty_block" } }))).toEqual(["Not passed · Junk (phone blocked by Witty)"]);
    expect(texts(row({ not_passed: { reason: "program_mismatch", decided_at: "2026-10-01T05:00:00Z", detail: "course_not_in_catalogue" } }))).toEqual(["Not passed · Programme mismatch (course not in the catalogue)"]);
    expect(texts(row({ not_passed: { reason: "blocked_phone", decided_at: "2026-10-01T05:00:00Z" } }))).toEqual(["Not passed · Blocked phone"]);
  });

  it("the paid label names the platform and never changes the tone of the destination", () => {
    expect(texts(row({ paid_platform: "meta" }))).toEqual(["Paid · Meta"]);
    expect(texts(row({ destination_type: "partner", partner_id: 2, paid_platform: "google" }))).toEqual(["Partner #2", "Paid · Google"]);
    expect(texts(row({ paid_platform: "other" }))).toEqual(["Paid"]);
  });

  it("other B2C reasons fall back to the W1 label, lower-cased", () => {
    expect(texts(row({ destination_type: "in_house", b2c_lane: "sales", allocation_reason: "no_partner_offers_programme", hold_kind: "selling" }))).toEqual(["B2C sales · no partner offers it"]);
    expect(texts(row({ destination_type: "in_house", b2c_lane: "sales", allocation_reason: "some_future_reason", hold_kind: "selling" }))).toEqual(["B2C sales · some future reason"]);
    expect(texts(row({ destination_type: "in_house" }))).toEqual(["B2C CRM"]);
  });
});

// ---------- bulk actions ----------

describe("bulk toasts", () => {
  it("bulkRouteToast renders the design's sentence", () => {
    expect(bulkRouteToast({ sent: 12, to_partner: 8, consent_requested: 1, back_to_b2c: 3, skipped_barred: 3, skipped_no_consent: 2, skipped_not_held: 1, failed: 0 }))
      .toBe("Sent 12 · to a partner 8 · consent requested 1 · back to B2C 3 · skipped 3 partner-barred · 2 without consent · 1 not with B2C");
  });
  it("bulkRouteToast leaves zero parts out and names failures", () => {
    expect(bulkRouteToast({ sent: 2, to_partner: 2, back_to_b2c: 0, consent_requested: 0, skipped_barred: 0, skipped_no_consent: 0, skipped_not_held: 0, failed: 1 })).toBe("Sent 2 · to a partner 2 · 1 failed");
    expect(bulkRouteToast({ sent: 0, skipped_barred: 3 })).toBe("Nothing sent · skipped 3 partner-barred");
    expect(bulkRouteToast({})).toBe("Nothing sent");
  });
  it("rerouteToast shows every skip kind, lost in grace first", () => {
    expect(rerouteToast({ done: 5, skipped_lost_in_grace: 2, skipped_no_partner_allocation: 1, skipped_contacted_no_breach: 1, skipped_barred: 1, failed: 2 }))
      .toBe("Re-routed 5 · skipped 2 lost, in grace · 1 not with a partner · 1 contacted, no SLA breach · 1 partner-barred · 2 failed");
    expect(rerouteToast({ done: 0, skipped_lost_in_grace: 1 })).toBe("Nothing re-routed · skipped 1 lost, in grace");
    expect(rerouteToast({ done: 3 })).toBe("Re-routed 3");
  });
});

describe("bulk previews", () => {
  const held = row({ id: 1, destination_type: "in_house", b2c_lane: "sales", consent_state: "given" });
  const barred = row({ id: 2, destination_type: "in_house", b2c_lane: "sales", consent_state: "given", partner_bar_reason: "duplicate" });
  const noConsent = row({ id: 3, destination_type: "in_house", b2c_lane: "nurture", consent_state: "none" });
  const withPartner = row({ id: 4, destination_type: "partner", partner_id: 9 });
  const inGrace = row({ id: 5, destination_type: "partner", partner_id: 9, lost_grace_until: "2026-10-12T10:00:00Z" });
  const barredPartner = row({ id: 6, destination_type: "partner", partner_id: 9, partner_bar_reason: "lost" });
  const unrouted = row({ id: 7 });

  it("sendToPartnersPreview counts the rulebook's skips", () => {
    expect(sendToPartnersPreview([held, barred, noConsent, withPartner, unrouted])).toEqual({ sendable: 1, barred: 1, no_consent: 1, not_held: 2 });
    expect(sendToPartnersPreview([])).toEqual({ sendable: 0, barred: 0, no_consent: 0, not_held: 0 });
  });
  it("reroutePreview skips lost-in-grace leads and, towards partners, barred ones", () => {
    expect(reroutePreview([withPartner, inGrace, barredPartner, held], "b2c")).toEqual({ candidates: 2, lost_in_grace: 1, barred: 0, not_with_partner: 1 });
    expect(reroutePreview([withPartner, inGrace, barredPartner, held], "partners")).toEqual({ candidates: 1, lost_in_grace: 1, barred: 1, not_with_partner: 1 });
  });
});

describe("toCsv", () => {
  it("quotes, escapes, adds a BOM and CRLF", () => {
    const csv = toCsv(["a", "b"], [{ a: 'say "hi", ok', b: null }, { a: "line\nbreak", b: 3 }]);
    expect(csv).toBe('﻿a,b\r\n"say ""hi"", ok",\r\n"line\nbreak",3\r\n');
  });
  it("neutralises spreadsheet formulas", () => {
    const csv = toCsv(["a"], [{ a: "=HYPERLINK(\"x\")" }, { a: "+91 98000" }, { a: "-5" }, { a: "@SUM(1)" }, { a: "ok" }]);
    expect(csv.split("\r\n").slice(1, 6)).toEqual(['"\'=HYPERLINK(""x"")"', "'+91 98000", "'-5", "'@SUM(1)", "ok"]);
  });
  it("the export carries the partner-bar and Addendum 3 columns", () => {
    for (const c of ["partner_barred_at", "partner_bar_reason", "other_providers", "hold_kind", "paid_platform"]) expect(EXPORT_COLUMNS).toContain(c);
    expect(new Set(EXPORT_COLUMNS).size).toBe(EXPORT_COLUMNS.length);
  });
});
