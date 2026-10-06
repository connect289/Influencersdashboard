import { describe, expect, it } from "vitest";
import { DAYS, initials, parsePartnerForm, SLA_FIELDS, slugify, summariseHours, textOn } from "./partners";

function form(over: Record<string, string | null> = {}): FormData {
  const f = new FormData();
  const base: Record<string, string> = {
    id: "", name: "Acme Edu", slug: "acme-edu", display_name: "Acme Online", logo_url: "https://acme.test/logo.png", brand_color: "#0b2f5e",
    adapter_type: "leadsquared", api_base_url: "", test_endpoint: "https://sandbox.acme.test/leads", dedupe_mode: "async", hold_minutes: "45",
    duplicate_window_hours: "24", notify_enabled: "on", daily_cap: "50", monthly_cap: "", contract_min_monthly: "", holidays: "2026-11-01\n2026-10-20, 2026-11-01",
    states_include: "", states_exclude: "Goa, Sikkim", sources_exclude: "", criteria_other: "", notes: "",
  };
  for (const d of DAYS) Object.assign(base, d === "sun" ? {} : { [`wh_${d}_on`]: "on", [`wh_${d}_open`]: "10:00", [`wh_${d}_close`]: "19:00" });
  for (const s of SLA_FIELDS) base[`sla_${s.key}`] = String(s.def);
  for (const [k, v] of Object.entries({ ...base, ...over })) if (v !== null) f.set(k, v);
  return f;
}

describe("parsePartnerForm", () => {
  it("builds the save payload", () => {
    const r = parsePartnerForm(form());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data).toMatchObject({
      id: null, slug: "acme-edu", brand_color: "#0B2F5E", hold_minutes: 45, notify_enabled: true, daily_cap: 50, monthly_cap: null,
      holidays: ["2026-10-20", "2026-11-01"], lead_criteria: { states_exclude: ["Goa", "Sikkim"] },
      sla: { first_contact_hours: 2, duplicate_hours: 24 },
    });
    expect((r.data.working_hours as Record<string, unknown>).sun).toBeNull();
    expect((r.data.working_hours as Record<string, unknown>).mon).toEqual({ open: "10:00", close: "19:00" });
  });

  it("forces no hold window when the partner refuses duplicates at once", () => {
    const r = parsePartnerForm(form({ dedupe_mode: "sync", hold_minutes: "45" }));
    expect(r.ok && r.data.hold_minutes).toBe(0);
  });

  it("unticked notify means off", () => {
    const r = parsePartnerForm(form({ notify_enabled: null }));
    expect(r.ok && r.data.notify_enabled).toBe(false);
  });

  it("reports field errors", () => {
    const r = parsePartnerForm(form({ slug: "Bad Slug!", logo_url: "http://insecure.test/x.png", brand_color: "navy", holidays: "tomorrow", wh_mon_open: "20:00", sla_proof_days: "0", daily_cap: "-1" }));
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(Object.keys(r.errors).sort()).toEqual(["brand_color", "daily_cap", "holidays", "logo_url", "sla_proof_days", "slug", "wh_mon"]);
  });

  it("rejects an unknown adapter or id", () => {
    expect(parsePartnerForm(form({ adapter_type: "portal" })).ok).toBe(false);
    expect(parsePartnerForm(form({ id: "1 or 1=1" })).ok).toBe(false);
  });
});

describe("helpers", () => {
  it("summariseHours collapses runs", () => {
    expect(summariseHours({ mon: { open: "10:00", close: "19:00" }, tue: { open: "10:00", close: "19:00" }, wed: { open: "10:00", close: "19:00" }, sat: { open: "10:00", close: "17:00" }, sun: null }))
      .toBe("Mon–Wed 10:00–19:00 · Sat 10:00–17:00");
    expect(summariseHours({})).toBe("Closed every day");
  });
  it("initials", () => {
    expect(initials("Acme Edu Pvt Ltd")).toBe("AE");
    expect(initials("upGrad")).toBe("UP");
    expect(initials("  ")).toBe("?");
  });
  it("textOn picks a readable text colour", () => {
    expect(textOn("#0B2F5E")).toBe("#FFFFFF");
    expect(textOn("#F5A800")).toBe("#0F1729");
    expect(textOn(null)).toBe("#FFFFFF");
  });
  it("slugify", () => {
    expect(slugify("Acme Edu Pvt. Ltd.")).toBe("acme-edu-pvt-ltd");
    expect(slugify("  Jain   Online — Bangalore ")).toBe("jain-online-bangalore");
  });
});
