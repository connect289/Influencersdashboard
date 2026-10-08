/** Lead intake (spec B4, B4.1, B17): the import wizard's file handling and mapping, and the Intake screen's types. */

export type FieldKey =
  | "full_name" | "first_name" | "last_name" | "phone" | "email" | "alternate_phone" | "city" | "state" | "country"
  | "course" | "specialization" | "university" | "programme_level" | "study_mode" | "other_courses" | "highest_qualification"
  | "academic_score" | "work_experience" | "annual_budget" | "enrollment_timeline" | "preferred_language"
  | "guardian_name" | "guardian_phone" | "enquirer_relation" | "preferred_call_time" | "notes"
  | "utm_source" | "utm_medium" | "utm_campaign" | "utm_content" | "utm_term" | "campaign" | "source_detail" | "referral_code";

/** Lead fields a column can map to, in the order the mapping step lists them. */
export const IMPORT_FIELDS: { key: FieldKey; label: string; group: "Student" | "Interest" | "Background" | "Attribution"; synonyms: string[] }[] = [
  { key: "full_name", label: "Full name", group: "Student", synonyms: ["name", "full name", "student name", "candidate name", "lead name", "fullname"] },
  { key: "first_name", label: "First name", group: "Student", synonyms: ["first name", "firstname", "given name", "fname"] },
  { key: "last_name", label: "Last name", group: "Student", synonyms: ["last name", "lastname", "surname", "family name", "lname"] },
  { key: "phone", label: "Phone (required)", group: "Student", synonyms: ["phone", "mobile", "mobile number", "phone number", "contact", "contact number", "whatsapp", "whatsapp number", "mobile no", "phone no", "cell"] },
  { key: "email", label: "Email", group: "Student", synonyms: ["email", "email id", "email address", "e-mail", "mail"] },
  { key: "alternate_phone", label: "Alternate phone", group: "Student", synonyms: ["alternate phone", "alternate mobile", "other phone", "secondary phone", "alt phone"] },
  { key: "city", label: "City", group: "Student", synonyms: ["city", "town", "location", "current city"] },
  { key: "state", label: "State", group: "Student", synonyms: ["state", "region", "province"] },
  { key: "country", label: "Country", group: "Student", synonyms: ["country", "nation"] },
  { key: "course", label: "Course", group: "Interest", synonyms: ["course", "program", "programme", "course interested", "interested course", "course name", "program name", "degree"] },
  { key: "specialization", label: "Specialisation", group: "Interest", synonyms: ["specialization", "specialisation", "stream", "branch", "major", "elective"] },
  { key: "university", label: "University", group: "Interest", synonyms: ["university", "college", "institute", "university name", "preferred university"] },
  { key: "programme_level", label: "Level (UG/PG…)", group: "Interest", synonyms: ["level", "program level", "programme level", "ug pg", "degree level"] },
  { key: "study_mode", label: "Study mode", group: "Interest", synonyms: ["mode", "study mode", "mode of study", "online offline"] },
  { key: "other_courses", label: "Other courses (comma-separated)", group: "Interest", synonyms: ["other courses", "other course", "also interested", "also interested in", "alternatives", "alternative courses", "secondary course", "secondary courses", "other programmes", "other programs", "backup course"] },
  { key: "highest_qualification", label: "Highest qualification", group: "Background", synonyms: ["qualification", "highest qualification", "education", "last qualification", "highest education"] },
  { key: "academic_score", label: "Score / percentage", group: "Background", synonyms: ["percentage", "score", "marks", "cgpa", "gpa", "graduation percentage"] },
  { key: "work_experience", label: "Work experience", group: "Background", synonyms: ["work experience", "experience", "years of experience", "work exp", "exp"] },
  { key: "annual_budget", label: "Budget", group: "Background", synonyms: ["budget", "annual budget", "fee budget"] },
  { key: "enrollment_timeline", label: "When they want to start", group: "Background", synonyms: ["timeline", "start date", "intake", "admission timeline", "when"] },
  { key: "preferred_language", label: "Language", group: "Background", synonyms: ["language", "preferred language"] },
  { key: "guardian_name", label: "Parent / guardian name", group: "Background", synonyms: ["parent name", "guardian name", "father name", "mother name"] },
  { key: "guardian_phone", label: "Parent / guardian phone", group: "Background", synonyms: ["parent phone", "guardian phone", "father phone", "parent mobile"] },
  { key: "enquirer_relation", label: "Enquiring for", group: "Background", synonyms: ["relation", "enquiring for", "relationship"] },
  { key: "preferred_call_time", label: "Best time to call", group: "Background", synonyms: ["call time", "best time to call", "preferred time"] },
  { key: "notes", label: "Notes", group: "Background", synonyms: ["notes", "remarks", "comments", "comment", "remark"] },
  { key: "campaign", label: "Campaign", group: "Attribution", synonyms: ["campaign", "campaign name"] },
  { key: "utm_source", label: "UTM source", group: "Attribution", synonyms: ["utm source", "utm_source", "source"] },
  { key: "utm_medium", label: "UTM medium", group: "Attribution", synonyms: ["utm medium", "utm_medium", "medium"] },
  { key: "utm_campaign", label: "UTM campaign", group: "Attribution", synonyms: ["utm campaign", "utm_campaign"] },
  { key: "utm_content", label: "UTM content", group: "Attribution", synonyms: ["utm content", "utm_content"] },
  { key: "utm_term", label: "UTM term", group: "Attribution", synonyms: ["utm term", "utm_term", "keyword"] },
  { key: "source_detail", label: "Source detail", group: "Attribution", synonyms: ["source detail", "sub source", "lead source detail"] },
  { key: "referral_code", label: "Referral code", group: "Attribution", synonyms: ["referral code", "ref code", "referral", "coupon"] },
];

export const FIELD_LABEL = Object.fromEntries(IMPORT_FIELDS.map((f) => [f.key, f.label])) as Record<FieldKey, string>;
export type Mapping = Record<string, FieldKey | "ignore">;

export const MAX_IMPORT_ROWS = 50_000;
export const MAX_IMPORT_BYTES = 15 * 1024 * 1024;
export const CHUNK_ROWS = 2000;

const norm = (s: string) => s.toLowerCase().replace(/[_\-./()]+/g, " ").replace(/\s+/g, " ").trim();

/** A suggested field for every column, by synonyms (exact, then contained); each field is suggested at most once. */
export function suggestMapping(headers: string[]): Mapping {
  const used = new Set<FieldKey>();
  const out: Mapping = {};
  const pick = (h: string, exact: boolean): FieldKey | null => {
    const n = norm(h);
    for (const f of IMPORT_FIELDS) {
      if (used.has(f.key)) continue;
      if (f.synonyms.some((s) => (exact ? n === s : n.length > 2 && (n.includes(s) && s.length > 3)))) return f.key;
    }
    return null;
  };
  for (const h of headers) { const k = pick(h, true); if (k) { out[h] = k; used.add(k); } }
  for (const h of headers) {
    if (out[h]) continue;
    const k = pick(h, false);
    if (k) { out[h] = k; used.add(k); } else out[h] = "ignore";
  }
  // a name in two parts needs both columns, so a lone "Name" stays full name
  if (Object.values(out).includes("full_name")) for (const h of headers) if (out[h] === "first_name" || out[h] === "last_name") out[h] = "ignore";
  return out;
}

/** What is wrong with a mapping, or null. Mirrors b2b.import_create. */
export function mappingProblem(m: Mapping): string | null {
  const used = Object.values(m).filter((v) => v !== "ignore");
  if (!used.includes("phone")) return "Map a column to the phone number.";
  const dup = used.find((v, i) => used.indexOf(v) !== i);
  if (dup) return `${FIELD_LABEL[dup]} is mapped from more than one column.`;
  return null;
}

export type Cell = string | number | boolean | Date | null | undefined;

export function cellText(c: Cell): string {
  if (c === null || c === undefined) return "";
  if (c instanceof Date) return Number.isNaN(c.getTime()) ? "" : c.toISOString().slice(0, 10);
  if (typeof c === "number" && Number.isFinite(c) && Math.abs(c) >= 1e9 && Number.isInteger(c)) return String(c); // phone numbers stored as numbers
  return String(c).replace(/\s+/g, " ").trim();
}

/** CSV (comma, semicolon or tab) as rows of cells, up to maxRows rows. Quotes and quoted newlines are handled. */
export function parseCsvRows(text: string, maxRows = MAX_IMPORT_ROWS + 50): string[][] {
  const src = text.replace(/^﻿/, "");
  const first = src.slice(0, Math.max(0, src.search(/\r?\n|$/)));
  const delim = [",", ";", "\t"].map((d) => [d, first.split(d).length] as const).sort((a, b) => b[1] - a[1])[0]![0];
  const rows: string[][] = [];
  let row: string[] = [], cell = "", quoted = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i]!;
    if (quoted) {
      if (ch === '"') { if (src[i + 1] === '"') { cell += '"'; i++; } else quoted = false; }
      else cell += ch;
    } else if (ch === '"' && cell === "") quoted = true;
    else if (ch === delim) { row.push(cell); cell = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && src[i + 1] === "\n") i++;
      row.push(cell); rows.push(row); row = []; cell = "";
      if (rows.length >= maxRows) return rows;
    } else cell += ch;
  }
  if (cell !== "" || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

export type FileTable = { headers: string[]; rows: Record<string, string>[]; truncated: boolean };

/** The first row with at least two filled cells is the header; blank rows are dropped; duplicate headers get " (2)". */
export function tableFromRows(raw: Cell[][]): FileTable {
  const h = Math.max(0, raw.findIndex((r) => r.filter((c) => cellText(c) !== "").length >= 2));
  const seen = new Map<string, number>();
  const headers = (raw[h] ?? []).slice(0, 80).map((c, i) => {
    let name = cellText(c).slice(0, 80) || `Column ${i + 1}`;
    const n = (seen.get(name) ?? 0) + 1;
    seen.set(name, n);
    if (n > 1) name = `${name} (${n})`;
    return name;
  });
  const rows: Record<string, string>[] = [];
  let truncated = false;
  for (let i = h + 1; i < raw.length; i++) {
    const r = raw[i] ?? [];
    if (r.every((c) => cellText(c) === "")) continue;
    if (rows.length >= MAX_IMPORT_ROWS) { truncated = true; break; }
    rows.push(Object.fromEntries(headers.map((name, c) => [name, cellText(r[c])])));
  }
  return { headers, rows, truncated };
}

export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/** Rows as CSV text (for the downloadable lists). */
export function toCsv(rows: Record<string, unknown>[], columns: string[]): string {
  const q = (v: unknown) => {
    const s = v === null || v === undefined ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
    return /[",\n\r]/.test(s) || /^[=+\-@]/.test(s) ? `"${(/^[=+\-@]/.test(s) ? "'" : "") + s.replace(/"/g, '""')}"` : s;
  };
  return [columns.join(","), ...rows.map((r) => columns.map((c) => q(r[c])).join(","))].join("\r\n");
}

// ---------- labels ----------
export const PREVIEW_LABEL: Record<string, { label: string; tone: "success" | "info" | "warning" | "danger" | "neutral" | "brand"; hint: string }> = {
  new: { label: "New", tone: "success", hint: "No lead has this phone yet." },
  merge: { label: "Merge", tone: "info", hint: "Joins the open lead with this phone; existing values are kept, empty ones filled." },
  reopen: { label: "Reopen", tone: "info", hint: "Reopens a lost or enrolled lead as a new enquiry." },
  duplicate_in_file: { label: "Repeat in file", tone: "neutral", hint: "The same phone appears earlier in this file; the rows merge." },
  test: { label: "Test", tone: "brand", hint: "A test phone: imported as a test lead, never routed." },
  blocked: { label: "Blocked", tone: "danger", hint: "On the blocked list: recorded as a lead and marked Not passed, never routed." },
  invalid: { label: "Invalid phone", tone: "danger", hint: "Not a valid phone: recorded as Not passed when the row has a 10–15 digit number, skipped when it has no number at all." },
};

/** Preview groups whose rows are written and then recorded as Not passed (D39: every lead enters). */
export const RECORDED_NOT_PASSED_GROUPS = ["blocked", "invalid"] as const;

export const ROUTE_CHOICE: Record<"route" | "hold" | "b2c", { label: string; hint: string }> = {
  route: {
    label: "Route now",
    hint: "Each lead goes through the normal rules as soon as it is ready: partners, or B2C when the rules say so. Students who have not agreed to partner sharing are asked for it first; those requests are spread over the hour.",
  },
  hold: { label: "Hold for review", hint: "The leads wait in the pre-routing pool until you release the import or route them one by one." },
  b2c: { label: "Send to the B2C CRM", hint: "Every lead goes to Eduwit's own team (junk and programme mismatch are still held back)." },
};

export const SOURCE_LABEL: Record<string, string> = {
  witty: "Witty (WhatsApp)", web_agent: "Website agent", crm: "Old CRM / edits", import: "Imports", api: "Intake API",
  meta: "Meta Lead Ads", google: "Google lead forms", manual: "Manual entry", partner: "Partner updates", b2c: "B2C CRM",
};

export const REQUEST_STATUS: Record<string, { label: string; tone: "success" | "info" | "warning" | "danger" | "neutral" }> = {
  received: { label: "Received", tone: "info" }, fetching: { label: "Fetching", tone: "info" }, held: { label: "Held", tone: "warning" },
  done: { label: "Stored", tone: "success" }, error: { label: "Failed", tone: "danger" }, discarded: { label: "Discarded", tone: "neutral" },
};

export const IMPORT_STATUS: Record<string, { label: string; tone: "success" | "info" | "warning" | "danger" | "neutral" }> = {
  staging: { label: "Not committed", tone: "warning" }, committing: { label: "Importing", tone: "info" }, done: { label: "Done", tone: "success" },
  rolled_back: { label: "Rolled back", tone: "neutral" }, abandoned: { label: "Abandoned", tone: "neutral" },
};

/** b2b.route_outlook(l) ->> 'outlook' (Addendum 3 contract 1.3): what the next routing run would do with the lead. */
export const ROUTE_OUTLOOKS = ["partners", "b2c_sales", "b2c_nurture", "not_passed", "b2c", "consent_request", "consent_pending", "with_partner", "b2c_held", "none"] as const;
export type RouteOutlook = (typeof ROUTE_OUTLOOKS)[number];

export const OUTLOOK_LABEL: Record<RouteOutlook, string> & Record<string, string> = {
  partners: "Partner routing",
  b2c_sales: "B2C sales",
  b2c_nurture: "B2C nurture",
  not_passed: "Not passed (junk or mismatch)",
  b2c: "B2C (as chosen at intake)",
  consent_request: "Consent will be requested",
  consent_pending: "Awaiting partner-sharing consent",
  with_partner: "Already with a partner",
  b2c_held: "Stays with B2C",
  none: "Not routed",
};

// ---------- consent (rulebook PART 7.1, design D8) ----------
export type ConsentPurpose = "sales" | "partner_share" | "marketing";
export const CONSENT_PURPOSES: ConsentPurpose[] = ["sales", "partner_share", "marketing"];

/** The partner-sharing wording every consent line must carry (PART 7.1): admission partners, not only universities. */
export const PARTNER_SHARE_LABEL = "Share with our admission partners (edtech companies)";
export const CONSENT_PURPOSE_LABEL: Record<ConsentPurpose, string> = {
  sales: "Contact about courses",
  partner_share: PARTNER_SHARE_LABEL,
  marketing: "Marketing messages",
};

/** b2b.consent_texts.channel values, in the order the editor lists them. */
export const CONSENT_CHANNELS: { key: ConsentChannel; label: string }[] = [
  { key: "web_form", label: "Website or landing-page form" },
  { key: "website_agent", label: "Website agent" },
  { key: "witty", label: "Witty (WhatsApp)" },
  { key: "wa_request", label: "WhatsApp consent request (one tap)" },
  { key: "meta_form", label: "Meta lead form" },
  { key: "google_form", label: "Google lead form" },
  { key: "import", label: "File import" },
  { key: "manual", label: "Manual entry" },
  { key: "api", label: "Intake API" },
];
export type ConsentChannel = "witty" | "website_agent" | "web_form" | "meta_form" | "google_form" | "import" | "manual" | "api" | "wa_request";
export const CONSENT_CHANNEL_LABEL = Object.fromEntries(CONSENT_CHANNELS.map((c) => [c.key, c.label])) as Record<ConsentChannel, string>;

/** A row of b2b.consent_texts (m31a). The approval is the routing go-live item; coverage does not need it. */
export type ConsentText = {
  version: string; channel: ConsentChannel; purposes: ConsentPurpose[]; body: string | null; covers_admission_partners: boolean; active: boolean;
  lawyer_approved_at: string | null; approved_by: string | null; approval_note: string | null; created_at: string;
};

/** What the editor sends to b2b.consent_text_save. lawyer_approved true approves, false clears, undefined leaves the approval alone. */
export type ConsentTextForm = {
  version: string; channel: ConsentChannel | ""; purposes: ConsentPurpose[]; body: string; covers_admission_partners: boolean; active: boolean;
  lawyer_approved?: boolean; approval_note: string;
};

/** Mirrors b2b.consent_text_covers(version): active, covers admission partners and includes partner sharing. The approval is not needed. */
export function textCovers(t: Pick<ConsentText, "active" | "covers_admission_partners" | "purposes"> | null | undefined): boolean {
  return Boolean(t && t.active && t.covers_admission_partners && t.purposes.includes("partner_share"));
}

/** The versions a form, an import or a manual entry may stamp partner sharing under (lead_form_save refuses the others). */
export function coveringTexts(texts: ConsentText[]): ConsentText[] {
  return texts.filter(textCovers);
}

/** Mirrors the go-live item consent_texts_approved (m31e): every active covering text approved, and at least one. */
export function consentGolive(texts: ConsentText[]): { ok: boolean; approved: number; unapproved: string[] } {
  const covering = texts.filter((t) => t.active && t.covers_admission_partners);
  const unapproved = covering.filter((t) => !t.lawyer_approved_at).map((t) => t.version).sort();
  const approved = covering.length - unapproved.length;
  return { ok: unapproved.length === 0 && approved > 0, approved, unapproved };
}

const CONTROL_CHARS = /[\u0000-\u001f\u007f]/;

/**
 * What is wrong with a consent text before it is saved, mirroring b2b.consent_text_save's refusals; `clearsApproval` says the
 * save would clear the lawyer's approval (the body or the covering flag changed on an approved row without re-approving).
 * `warnings` are advice, not refusals.
 */
export function consentTextProblems(f: ConsentTextForm, stored?: ConsentText | null): { errors: string[]; warnings: string[]; clearsApproval: boolean } {
  const errors: string[] = [];
  const warnings: string[] = [];
  const version = f.version.trim();
  const body = f.body.trim();
  const note = f.approval_note.trim();
  if (!version || version.length > 80 || CONTROL_CHARS.test(version)) errors.push("Give a version id of 1 to 80 characters.");
  if (!f.channel) errors.push("Choose the channel the text is shown on.");
  if (f.purposes.length === 0) errors.push("Tick at least one purpose.");
  if (f.covers_admission_partners && !body) errors.push("Give the consent wording that names our admission partners (edtech companies).");
  if (f.covers_admission_partners && !f.purposes.includes("partner_share")) errors.push("A text that covers admission partners must include partner sharing.");
  if (f.lawyer_approved) {
    if (note.length < 10) errors.push("An approval note of at least 10 characters is required (who checked it and when).");
    if (!body) errors.push("Save the wording before approving it.");
  }
  if (f.covers_admission_partners && body && !/admission partner/i.test(body)) warnings.push("The wording does not say \"admission partners\": PART 7.1 asks for it in so many words.");
  if (f.purposes.includes("partner_share") && !f.covers_admission_partners) warnings.push("Partner sharing recorded under a text that does not cover admission partners does not count: those students are asked for consent again.");
  const clearsApproval = Boolean(stored?.lawyer_approved_at) && f.lawyer_approved !== true
    && ((stored?.body ?? "") !== body || Boolean(stored?.covers_admission_partners) !== f.covers_admission_partners);
  return { errors, warnings, clearsApproval };
}

/** Meta lead-form checkbox key → the consent purpose it ticks (lead_forms.settings.consent_checkbox_map, m31h). */
export type ConsentCheckboxMap = Record<string, { purpose: ConsentPurpose; required: boolean }>;

// ---------- types ----------
/** imports.counts: m17d's created / merged / reopened / imported / skipped / errors, plus m31h's recorded_not_passed (blocked or invalid rows written). */
export type ImportCounts = Record<string, number> & { recorded_not_passed?: number };

export type ImportPreview = {
  import: { id: number; file_name: string; status: string; total_rows: number; counts: ImportCounts; routing_choice: string | null;
            b2c_lane: string | null; source_label: string | null; campaign: string | null; mapping: Mapping; course_choices: Record<string, string>;
            created_at: string; finished_at: string | null; rolled_back_at: string | null };
  preview: Record<string, number>;
  status: Record<string, number>;
  actions: Record<string, number>;
  problems: Record<string, number>;
  sample: { row_no: number; lead: Record<string, string>; problems: string[]; preview: string | null; existing_lead_id: number | null;
            status: string; lead_id: number | null; action: string | null; error: string | null }[];
  can_rollback: boolean;
};

export type CourseMatch = { text: string; rows: number; key: string | null; confidence: number | null; label: string | null; choice: string | null;
                            candidates: { key: string; label: string; s: number }[] };

export type LeadForm = {
  id: number; platform: "meta" | "google"; form_ref: string; name: string; page_ref: string | null; field_map: Record<string, string>;
  defaults: Record<string, string>; campaign: string | null; consent_text: string | null; consent_version: string | null; consent_purposes: string[];
  /** Per-form settings (m31h); `settings` is missing on rows read before the column existed. */
  settings?: { consent_checkbox_map?: ConsentCheckboxMap } | null;
  active: boolean; leads_7d: number; last_at: string | null; updated_at: string;
};

/** Whether the form records partner sharing at all: as a purpose, or through a Meta checkbox mapped to it. */
export function formSharesWithPartners(f: Pick<LeadForm, "consent_purposes" | "settings">): boolean {
  return f.consent_purposes.includes("partner_share") || Object.values(f.settings?.consent_checkbox_map ?? {}).some((m) => m.purpose === "partner_share");
}

/** Whether the form's partner-sharing stamp counts (its version covers admission partners, D8); null when it does not share. */
export function formCovers(f: Pick<LeadForm, "consent_purposes" | "settings" | "consent_version">, texts: ConsentText[]): boolean | null {
  if (!formSharesWithPartners(f)) return null;
  return textCovers(texts.find((t) => t.version === f.consent_version));
}

export type IntakeOverview = {
  sources: { source: string; today: number; week: number; created: number; last_at: string }[];
  requests: Record<string, number>;
  recent: { id: number; source: string; key: string; form_ref: string | null; status: string; error: string | null; lead_id: number | null; action: string | null;
            routing: { status: string; outlook: string; waiting_for: string[] } | null; received_at: string; is_test: boolean; name: string | null }[];
  problems: { id: number; source: string; key: string; form_ref: string | null; status: string; error: string | null; received_at: string; attempts: number }[];
  forms: LeadForm[];
  imports: { id: number; file_name: string; status: string; total_rows: number; counts: ImportCounts; source_label: string | null;
             routing_choice: string | null; b2c_lane: string | null; created_at: string; finished_at: string | null; rolled_back_at: string | null;
             held: number; can_rollback: boolean }[];
  templates: { id: number; name: string; mapping: Mapping; used_at: string | null }[];
  held_manual: number;
  connections: { meta: { verify_token: boolean; app_secret: boolean; page_token: boolean; api_version: string }; google: { key: boolean }; api_keys: number };
};
