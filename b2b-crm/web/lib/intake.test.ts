import { describe, expect, it } from "vitest";
import {
  CONSENT_CHANNELS, CONSENT_PURPOSE_LABEL, FIELD_LABEL, IMPORT_FIELDS, OUTLOOK_LABEL, PARTNER_SHARE_LABEL, PREVIEW_LABEL, RECORDED_NOT_PASSED_GROUPS, ROUTE_CHOICE,
  ROUTE_OUTLOOKS, cellText, chunk, consentGolive, consentTextProblems, coveringTexts, formCovers, formSharesWithPartners, mappingProblem, parseCsvRows,
  suggestMapping, tableFromRows, textCovers, toCsv, type ConsentText, type ConsentTextForm,
} from "./intake";

describe("mapping suggestions", () => {
  it("maps common headers", () => {
    expect(suggestMapping(["Student Name", "Mobile No", "Email ID", "Course Interested", "City", "Remarks", "Owner"])).toEqual({
      "Student Name": "full_name", "Mobile No": "phone", "Email ID": "email", "Course Interested": "course", City: "city", Remarks: "notes", Owner: "ignore",
    });
  });
  it("offers other courses (D30) and maps the usual headers to it", () => {
    const f = IMPORT_FIELDS.find((x) => x.key === "other_courses");
    expect(f?.group).toBe("Interest");
    expect(FIELD_LABEL.other_courses).toMatch(/other courses/i);
    expect(suggestMapping(["Course", "Other courses", "Phone"])).toMatchObject({ Course: "course", "Other courses": "other_courses" });
    expect(suggestMapping(["Phone", "Also interested in", "Course Interested"])).toMatchObject({ "Also interested in": "other_courses", "Course Interested": "course" });
    expect(suggestMapping(["Alternatives", "Mobile"])).toMatchObject({ Alternatives: "other_courses" });
    // a lone "Course" column never lands on other_courses
    expect(suggestMapping(["Course", "Mobile"])).toMatchObject({ Course: "course" });
    expect(mappingProblem({ A: "phone", B: "course", C: "other_courses" })).toBeNull();
  });
  it("uses each field once", () => {
    const m = suggestMapping(["Phone", "Phone Number"]);
    expect(Object.values(m).filter((v) => v === "phone")).toHaveLength(1);
  });
  it("keeps split names only without a full name", () => {
    expect(suggestMapping(["First Name", "Last Name", "Mobile"])).toMatchObject({ "First Name": "first_name", "Last Name": "last_name" });
    expect(suggestMapping(["Name", "First Name", "Mobile"])).toMatchObject({ Name: "full_name", "First Name": "ignore" });
  });
  it("finds problems", () => {
    expect(mappingProblem({ Name: "full_name" })).toBe("Map a column to the phone number.");
    expect(mappingProblem({ A: "phone", B: "email", C: "email" })).toBe("Email is mapped from more than one column.");
    expect(mappingProblem({ A: "phone", B: "ignore" })).toBeNull();
  });
});

describe("files", () => {
  it("parses CSV with quotes, semicolons and a BOM", () => {
    expect(parseCsvRows('﻿name;phone\n"Shah, A";"98765 43210"\r\nB;1')).toEqual([["name", "phone"], ["Shah, A", "98765 43210"], ["B", "1"]]);
  });
  it("caps rows", () => {
    expect(parseCsvRows("a,b\n1,2\n3,4\n5,6", 2)).toHaveLength(2);
  });
  it("finds the header and drops blank rows", () => {
    const t = tableFromRows([["Leads export"], [], ["Name", "Phone", "Phone"], ["Asha", 9876543210, ""], [null, "", ""], ["Ravi", "98765 00000", "x"]]);
    expect(t.headers).toEqual(["Name", "Phone", "Phone (2)"]);
    expect(t.rows).toEqual([{ Name: "Asha", Phone: "9876543210", "Phone (2)": "" }, { Name: "Ravi", Phone: "98765 00000", "Phone (2)": "x" }]);
  });
  it("renders cells", () => {
    expect(cellText(919876543210)).toBe("919876543210");
    expect(cellText(new Date("2026-10-01T00:00:00Z"))).toBe("2026-10-01");
    expect(cellText("  a   b ")).toBe("a b");
  });
  it("chunks", () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
  });
  it("writes safe CSV", () => {
    expect(toCsv([{ a: "x,y", b: "=SUM(1)" }, { a: null, b: 2 }], ["a", "b"])).toBe('a,b\r\n"x,y","\'=SUM(1)"\r\n,2');
  });
});

// ---------- Addendum 3: consent texts, wording, outlooks (rulebook PART 7.1, D8, D10, D39) ----------
const text = (over: Partial<ConsentText> = {}): ConsentText => ({
  version: "web-form-2026-10", channel: "web_form", purposes: ["sales", "partner_share"], body: "I agree that Eduwit and its admission partners (edtech companies) may contact me.",
  covers_admission_partners: true, active: true, lawyer_approved_at: null, approved_by: null, approval_note: null, created_at: "2026-10-07T10:00:00Z", ...over,
});
const form = (over: Partial<ConsentTextForm> = {}): ConsentTextForm => ({
  version: "web-form-2026-10", channel: "web_form", purposes: ["sales", "partner_share"], body: "I agree that Eduwit and its admission partners (edtech companies) may contact me.",
  covers_admission_partners: true, active: true, approval_note: "", ...over,
});

describe("consent wording", () => {
  it("names the admission partners, not only universities (PART 7.1)", () => {
    expect(PARTNER_SHARE_LABEL).toBe("Share with our admission partners (edtech companies)");
    expect(CONSENT_PURPOSE_LABEL.partner_share).toBe(PARTNER_SHARE_LABEL);
    expect(CONSENT_PURPOSE_LABEL.sales).toBeTruthy();
    expect(CONSENT_PURPOSE_LABEL.marketing).toBeTruthy();
  });
  it("lists every consent_texts channel once", () => {
    expect(CONSENT_CHANNELS.map((c) => c.key).sort()).toEqual(["api", "google_form", "import", "manual", "meta_form", "wa_request", "web_form", "website_agent", "witty"]);
    expect(new Set(CONSENT_CHANNELS.map((c) => c.label)).size).toBe(CONSENT_CHANNELS.length);
  });
  it("says that Route now asks the students without partner sharing, spread over the hour (D39)", () => {
    expect(ROUTE_CHOICE.route.hint).toMatch(/asked for it/);
    expect(ROUTE_CHOICE.route.hint).toMatch(/spread over the hour/);
  });
  it("marks blocked and invalid rows as recorded, not skipped", () => {
    expect([...RECORDED_NOT_PASSED_GROUPS]).toEqual(["blocked", "invalid"]);
    for (const g of RECORDED_NOT_PASSED_GROUPS) expect(PREVIEW_LABEL[g]!.hint).toMatch(/Not passed/);
  });
});

describe("textCovers (mirror of b2b.consent_text_covers)", () => {
  it("needs active, the covering flag and partner_share, not the approval", () => {
    expect(textCovers(text())).toBe(true);
    expect(textCovers(text({ lawyer_approved_at: "2026-10-07T12:00:00Z" }))).toBe(true);
    expect(textCovers(text({ active: false }))).toBe(false);
    expect(textCovers(text({ covers_admission_partners: false }))).toBe(false);
    expect(textCovers(text({ purposes: ["sales"] }))).toBe(false);
    expect(textCovers(null)).toBe(false);
    expect(textCovers(undefined)).toBe(false);
  });
  it("filters the covering texts", () => {
    expect(coveringTexts([text(), text({ version: "old", active: false }), text({ version: "uni-only", covers_admission_partners: false })]).map((t) => t.version)).toEqual(["web-form-2026-10"]);
  });
});

describe("consentGolive (mirror of the consent_texts_approved go-live item)", () => {
  it("passes only when every active covering text is approved and at least one exists", () => {
    expect(consentGolive([])).toEqual({ ok: false, approved: 0, unapproved: [] });
    expect(consentGolive([text()])).toEqual({ ok: false, approved: 0, unapproved: ["web-form-2026-10"] });
    expect(consentGolive([text({ lawyer_approved_at: "2026-10-07T12:00:00Z" })])).toEqual({ ok: true, approved: 1, unapproved: [] });
    expect(consentGolive([text({ lawyer_approved_at: "2026-10-07T12:00:00Z" }), text({ version: "b" }), text({ version: "a" })])).toEqual({ ok: false, approved: 1, unapproved: ["a", "b"] });
    // inactive or non-covering texts do not count either way
    expect(consentGolive([text({ lawyer_approved_at: "2026-10-07T12:00:00Z" }), text({ version: "off", active: false }), text({ version: "uni", covers_admission_partners: false })]))
      .toEqual({ ok: true, approved: 1, unapproved: [] });
  });
});

describe("consentTextProblems", () => {
  it("accepts a complete covering text", () => {
    expect(consentTextProblems(form())).toEqual({ errors: [], warnings: [], clearsApproval: false });
  });
  it("needs a version id of 1 to 80 characters and a channel", () => {
    expect(consentTextProblems(form({ version: " " })).errors).toContain("Give a version id of 1 to 80 characters.");
    expect(consentTextProblems(form({ version: "x".repeat(81) })).errors).toContain("Give a version id of 1 to 80 characters.");
    expect(consentTextProblems(form({ version: "a\tb" })).errors).toContain("Give a version id of 1 to 80 characters.");
    expect(consentTextProblems(form({ channel: "" })).errors).toContain("Choose the channel the text is shown on.");
    expect(consentTextProblems(form({ purposes: [] })).errors).toContain("Tick at least one purpose.");
  });
  it("covering needs a body and the partner_share purpose (as consent_text_save refuses)", () => {
    expect(consentTextProblems(form({ body: "  " })).errors).toContain("Give the consent wording that names our admission partners (edtech companies).");
    expect(consentTextProblems(form({ purposes: ["sales"] })).errors).toContain("A text that covers admission partners must include partner sharing.");
    expect(consentTextProblems(form({ covers_admission_partners: false, purposes: ["sales"], body: "" })).errors).toEqual([]);
  });
  it("an approval needs a note of 10 characters and a saved wording", () => {
    expect(consentTextProblems(form({ lawyer_approved: true, approval_note: "ok" })).errors).toEqual(["An approval note of at least 10 characters is required (who checked it and when)."]);
    expect(consentTextProblems(form({ lawyer_approved: true, approval_note: "Checked by Adv. Mehta, 7 Oct" })).errors).toEqual([]);
    expect(consentTextProblems(form({ lawyer_approved: true, approval_note: "Checked by Adv. Mehta, 7 Oct", body: "", covers_admission_partners: false })).errors).toEqual(["Save the wording before approving it."]);
  });
  it("warns when a covering text does not say admission partners, or partner sharing is recorded under a non-covering text", () => {
    expect(consentTextProblems(form({ body: "I agree to be contacted by Eduwit and partner universities." })).warnings).toHaveLength(1);
    expect(consentTextProblems(form({ covers_admission_partners: false })).warnings).toEqual([
      "Partner sharing recorded under a text that does not cover admission partners does not count: those students are asked for consent again.",
    ]);
  });
  it("a body or covering change on an approved row clears the approval unless it is re-approved", () => {
    const approved = text({ lawyer_approved_at: "2026-10-07T12:00:00Z", approved_by: "connect@eduwit.in", approval_note: "Checked by Adv. Mehta" });
    expect(consentTextProblems(form(), approved).clearsApproval).toBe(false);
    expect(consentTextProblems(form({ body: approved.body + " Updated." }), approved).clearsApproval).toBe(true);
    expect(consentTextProblems(form({ body: approved.body + " Updated.", lawyer_approved: true, approval_note: "Re-checked by Adv. Mehta" }), approved).clearsApproval).toBe(false);
    expect(consentTextProblems(form({ covers_admission_partners: false }), approved).clearsApproval).toBe(true);
    expect(consentTextProblems(form({ active: false }), approved).clearsApproval).toBe(false);
    // an unapproved row has nothing to clear
    expect(consentTextProblems(form({ body: "other" }), text()).clearsApproval).toBe(false);
    expect(consentTextProblems(form({ body: "other" })).clearsApproval).toBe(false);
  });
});

describe("lead forms and consent (D8)", () => {
  const base = { consent_purposes: ["sales"], settings: null, consent_version: null };
  it("shares with partners as a purpose or through a Meta checkbox", () => {
    expect(formSharesWithPartners(base)).toBe(false);
    expect(formSharesWithPartners({ ...base, consent_purposes: ["sales", "partner_share"] })).toBe(true);
    expect(formSharesWithPartners({ ...base, settings: { consent_checkbox_map: { share_box: { purpose: "partner_share", required: false } } } })).toBe(true);
    expect(formSharesWithPartners({ ...base, settings: { consent_checkbox_map: { mkt: { purpose: "marketing", required: true } } } })).toBe(false);
  });
  it("covers only under a registered covering version", () => {
    const texts = [text(), text({ version: "web-v3", covers_admission_partners: false })];
    expect(formCovers(base, texts)).toBeNull();
    expect(formCovers({ ...base, consent_purposes: ["sales", "partner_share"], consent_version: "web-form-2026-10" }, texts)).toBe(true);
    expect(formCovers({ ...base, consent_purposes: ["sales", "partner_share"], consent_version: "web-v3" }, texts)).toBe(false);
    expect(formCovers({ ...base, consent_purposes: ["sales", "partner_share"], consent_version: null }, texts)).toBe(false);
  });
});

describe("OUTLOOK_LABEL", () => {
  it("covers every route_outlook value (contract 1.3)", () => {
    expect([...ROUTE_OUTLOOKS].sort()).toEqual(["b2c", "b2c_held", "b2c_nurture", "b2c_sales", "consent_pending", "consent_request", "none", "not_passed", "partners", "with_partner"]);
    for (const k of ROUTE_OUTLOOKS) expect(OUTLOOK_LABEL[k], k).toBeTruthy();
    expect(OUTLOOK_LABEL.consent_request).toBe("Consent will be requested");
  });
});
