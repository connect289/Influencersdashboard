import { describe, expect, it } from "vitest";
import {
  asksDedupeConfirmation, DAYS, derivedHoldMinutes, DUPLICATE_WINDOW_HOURS, hasCriteria, holdWindowText, initials, parsePartnerForm, partnerSaveErrorField,
  SLA_FIELDS, slaMax, slugify, summariseHours, textOn,
} from "./partners";

function form(over: Record<string, string | null> = {}): FormData {
  const f = new FormData();
  const base: Record<string, string> = {
    id: "", name: "Acme Edu", slug: "acme-edu", display_name: "Acme Online", logo_url: "https://acme.test/logo.png", brand_color: "#0b2f5e",
    adapter_type: "leadsquared", api_base_url: "", test_endpoint: "https://sandbox.acme.test/leads", dedupe_mode: "async",
    notify_enabled: "on", daily_cap: "50", monthly_cap: "", contract_min_monthly: "", holidays: "2026-11-01\n2026-10-20, 2026-11-01",
    states_include: "", states_exclude: "Goa, Sikkim", cities_include: "", cities_exclude: "", qualifications_include: "", min_academic_pct: "",
    min_work_experience_years: "", sources_exclude: "", criteria_unknown: "", criteria_other: "", notes: "",
  };
  for (const d of DAYS) Object.assign(base, d === "sun" ? {} : { [`wh_${d}_on`]: "on", [`wh_${d}_open`]: "10:00", [`wh_${d}_close`]: "19:00" });
  for (const s of SLA_FIELDS) if (s.fixed === undefined) base[`sla_${s.key}`] = String(s.def);
  for (const [k, v] of Object.entries({ ...base, ...over })) if (v !== null) f.set(k, v);
  return f;
}

describe("parsePartnerForm", () => {
  it("builds the save payload", () => {
    const r = parsePartnerForm(form());
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data).toMatchObject({
      id: null, slug: "acme-edu", brand_color: "#0B2F5E", hold_minutes: 30, duplicate_window_hours: 24, notify_enabled: true, daily_cap: 50, monthly_cap: null,
      holidays: ["2026-10-20", "2026-11-01"], lead_criteria: { states_exclude: ["Goa", "Sikkim"] }, push_options: { interests_array: false },
      sla: { first_contact_hours: 2, status_update_days: 7, proof_days: 7, duplicate_hours: 24 },
    });
    expect((r.data.working_hours as Record<string, unknown>).sun).toBeNull();
    expect((r.data.working_hours as Record<string, unknown>).mon).toEqual({ open: "10:00", close: "19:00" });
    // the engine default applies when the Admin picked no unknown-data rule: the key is left out
    expect(r.data.lead_criteria).not.toHaveProperty("unknown");
  });

  // D37: the hold follows dedupe_mode and a posted hold_minutes / duplicate_window_hours is ignored
  it("derives the hold window from dedupe_mode and ignores a posted hold or duplicate window", () => {
    const sync = parsePartnerForm(form({ dedupe_mode: "sync", hold_minutes: "45", duplicate_window_hours: "72" }));
    expect(sync.ok && sync.data.hold_minutes).toBe(0);
    expect(sync.ok && sync.data.duplicate_window_hours).toBe(24);
    const async_ = parsePartnerForm(form({ dedupe_mode: "async", hold_minutes: "0" }));
    expect(async_.ok && async_.data.hold_minutes).toBe(30);
    const none = parsePartnerForm(form({ dedupe_mode: "none", hold_minutes: "5" }));
    expect(none.ok && none.data.hold_minutes).toBe(30);
    expect(derivedHoldMinutes("sync")).toBe(0);
    expect(derivedHoldMinutes("async")).toBe(30);
    expect(DUPLICATE_WINDOW_HOURS).toBe(24);
  });

  // D37: a partner on Eduwit's contract confirms duplicate-blocking in the form; a CRM adapter confirms in the Connection tab
  it("sends dedupe_confirmed only for a sync partner without a CRM adapter", () => {
    const generic = parsePartnerForm(form({ adapter_type: "generic_rest", dedupe_mode: "sync", dedupe_confirmed: "on" }));
    expect(generic.ok && generic.data.dedupe_confirmed).toBe(true);
    const unticked = parsePartnerForm(form({ adapter_type: "webhook", dedupe_mode: "sync" }));
    expect(unticked.ok && unticked.data.dedupe_confirmed).toBe(false);
    const crm = parsePartnerForm(form({ adapter_type: "leadsquared", dedupe_mode: "sync", dedupe_confirmed: "on" }));
    expect(crm.ok && "dedupe_confirmed" in crm.data).toBe(false);
    const async_ = parsePartnerForm(form({ adapter_type: "generic_rest", dedupe_mode: "async", dedupe_confirmed: "on" }));
    expect(async_.ok && "dedupe_confirmed" in async_.data).toBe(false);
    expect(asksDedupeConfirmation("generic_rest", "sync")).toBe(true);
    expect(asksDedupeConfirmation("zoho", "sync")).toBe(false);
    expect(asksDedupeConfirmation("generic_rest", "none")).toBe(false);
  });

  it("sla duplicate_hours is always the fixed 24, whatever was posted", () => {
    const r = parsePartnerForm(form({ sla_duplicate_hours: "720" }));
    expect(r.ok && (r.data.sla as Record<string, number>).duplicate_hours).toBe(24);
  });

  // D27 / PART 4: a partner may promise less time than the rulebook, never more (partner_save refuses the same values)
  it("refuses SLAs looser than the rulebook and accepts tighter ones", () => {
    expect(parsePartnerForm(form({ sla_first_contact_hours: "1" })).ok).toBe(true);
    expect(parsePartnerForm(form({ sla_first_contact_hours: "2" })).ok).toBe(true);
    const fch = parsePartnerForm(form({ sla_first_contact_hours: "3" }));
    expect(fch.ok).toBe(false);
    if (!fch.ok) expect(fch.errors.sla_first_contact_hours).toMatch(/cannot be looser than the rulebook/i);
    expect(parsePartnerForm(form({ sla_status_update_days: "7" })).ok).toBe(true);
    const su = parsePartnerForm(form({ sla_status_update_days: "8" }));
    expect(su.ok).toBe(false);
    if (!su.ok) expect(Object.keys(su.errors)).toEqual(["sla_status_update_days"]);
    expect(parsePartnerForm(form({ sla_proof_days: "8" })).ok).toBe(false);
    expect(parsePartnerForm(form({ sla_proof_days: "3" })).ok).toBe(true);
    // the unfixed SLAs keep their own ranges
    expect(parsePartnerForm(form({ sla_first_connect_days: "30" })).ok).toBe(true);
    expect(parsePartnerForm(form({ sla_first_connect_days: "31" })).ok).toBe(false);
    expect(slaMax(SLA_FIELDS.find((f) => f.key === "first_contact_hours")!)).toBe(2);
    expect(slaMax(SLA_FIELDS.find((f) => f.key === "outcome_days")!)).toBe(60);
  });

  it("parses the criteria editor", () => {
    const r = parsePartnerForm(form({
      states_include: "Delhi, Haryana", cities_include: "Gurugram\nNoida, Gurugram", cities_exclude: "Faridabad", qualifications_include: "Graduate, Postgraduate",
      min_academic_pct: "55", min_work_experience_years: "2.5", sources_exclude: "meta_lead_ad", criteria_unknown: "pass", criteria_other: "No diploma holders",
    }));
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.data.lead_criteria).toEqual({
      states_include: ["Delhi", "Haryana"], states_exclude: ["Goa", "Sikkim"], cities_include: ["Gurugram", "Noida"], cities_exclude: ["Faridabad"],
      qualifications_include: ["Graduate", "Postgraduate"], min_academic_pct: 55, min_work_experience_years: 2.5, sources_exclude: ["meta_lead_ad"],
      unknown: "pass", other: "No diploma holders",
    });
    const fail = parsePartnerForm(form({ criteria_unknown: "fail" }));
    expect(fail.ok && (fail.data.lead_criteria as { unknown?: string }).unknown).toBe("fail");
  });

  it("bounds the numeric criteria and the unknown-data rule", () => {
    const r = parsePartnerForm(form({ min_academic_pct: "101", min_work_experience_years: "41", criteria_unknown: "maybe" }));
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(Object.keys(r.errors).sort()).toEqual(["criteria_unknown", "min_academic_pct", "min_work_experience_years"]);
    expect(r.errors.min_academic_pct).toMatch(/0 to 100/);
    expect(parsePartnerForm(form({ min_academic_pct: "0" })).ok).toBe(true);
    expect(parsePartnerForm(form({ min_academic_pct: "100" })).ok).toBe(true);
    expect(parsePartnerForm(form({ min_academic_pct: "-1" })).ok).toBe(false);
    expect(parsePartnerForm(form({ min_academic_pct: "60.55" })).ok).toBe(false);
    expect(parsePartnerForm(form({ min_work_experience_years: "40" })).ok).toBe(true);
  });

  it("refuses a criteria list with a name over 80 characters", () => {
    const r = parsePartnerForm(form({ cities_include: "x".repeat(81) }));
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errors.cities_include).toMatch(/80 characters/);
  });

  // D44
  it("push options: interests[] only when ticked", () => {
    const on = parsePartnerForm(form({ push_interests_array: "on" }));
    expect(on.ok && on.data.push_options).toEqual({ interests_array: true });
    const off = parsePartnerForm(form());
    expect(off.ok && off.data.push_options).toEqual({ interests_array: false });
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

describe("partnerSaveErrorField", () => {
  it("maps m31i partner_save refusals to the field they are about", () => {
    expect(partnerSaveErrorField("the first-contact SLA is 2 working hours at most (Addendum 3)")).toBe("sla_first_contact_hours");
    expect(partnerSaveErrorField("the status-update SLA is every 7 days at most (Addendum 3)")).toBe("sla_status_update_days");
    expect(partnerSaveErrorField("enrolment proof is due within 7 days at most (Addendum 3)")).toBe("sla_proof_days");
    expect(partnerSaveErrorField("sla outcome_days: a number of hours or days")).toBe("sla_outcome_days");
    expect(partnerSaveErrorField("confirm that the CRM rejects duplicates on create (dedupe_confirmed) before choosing a 0-minute hold")).toBe("dedupe_mode");
    expect(partnerSaveErrorField("duplicate handling is sync, async or none")).toBe("dedupe_mode");
    expect(partnerSaveErrorField("unknown lead criterion: cities_near")).toBeNull();
    expect(partnerSaveErrorField("lead criteria cities include: a list of up to 100 names")).toBe("cities_include");
    expect(partnerSaveErrorField("lead criteria qualifications include: a list of up to 100 names")).toBe("qualifications_include");
    expect(partnerSaveErrorField("minimum academic score: 0 to 100 percent")).toBe("min_academic_pct");
    expect(partnerSaveErrorField("minimum work experience: 0 to 40 years")).toBe("min_work_experience_years");
    expect(partnerSaveErrorField("unknown lead data: 'pass' or 'fail'")).toBe("criteria_unknown");
    expect(partnerSaveErrorField("lead criteria other: a short text")).toBe("criteria_other");
    expect(partnerSaveErrorField("push options interests_array: true or false")).toBe("push_interests_array");
    expect(partnerSaveErrorField("slug: 2 to 40 lowercase letters, digits or hyphens")).toBe("slug");
    expect(partnerSaveErrorField("the slug is fixed once a partner leaves onboarding")).toBe("slug");
    expect(partnerSaveErrorField("name is required")).toBe("name");
    expect(partnerSaveErrorField("working hours: each day closed or open < close (HH:MM)")).toBeNull();
    expect(partnerSaveErrorField("partner not found")).toBeNull();
  });
});

describe("helpers", () => {
  it("holdWindowText", () => {
    expect(holdWindowText({ dedupe_mode: "async" })).toBe("30 min");
    expect(holdWindowText({ dedupe_mode: "none", dedupe_confirmed_at: null })).toBe("30 min");
    expect(holdWindowText({ dedupe_mode: "sync", dedupe_confirmed_at: "2026-10-07T10:00:00Z" })).toBe("0 min (confirmed duplicate-blocking CRM)");
    expect(holdWindowText({ dedupe_mode: "sync", dedupe_confirmed_at: null })).toBe("0 min (duplicates refused on create)");
  });
  it("hasCriteria ignores the unknown-data rule alone", () => {
    expect(hasCriteria({})).toBe(false);
    expect(hasCriteria({ unknown: "pass" })).toBe(false);
    expect(hasCriteria({ min_academic_pct: 0 })).toBe(true);
    expect(hasCriteria({ cities_exclude: ["Pune"] })).toBe(true);
    expect(hasCriteria(null)).toBe(false);
  });
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
