/** The Mapping studio (spec B8.3): types of b2b.mapping_studio, suggestions, the transform syntax and schema uploads. */

export type Direction = "in" | "out" | "both";

export type Canonical = {
  key: string;
  grp: "lead" | "sales";
  label: string;
  data_type: "text" | "number" | "date" | "datetime" | "boolean" | "phone" | "email" | "picklist";
  allowed: string[] | null;
  lead_column: string | null;
  owner: "witty" | "intake" | "b2b";
  outbound: boolean;
  inbound: boolean;
  required_out: boolean;
  required_in: boolean;
  sort: number;
};

export type Condition = { field: string; op: "eq" | "neq" | "in" | "empty" | "not_empty"; value?: string | string[] };
export type Transform = { op: string } & Record<string, string | number>;

export type StatusRule = {
  id: number;
  pipeline_key: string | null;
  partner_stage: string;
  partner_sub_stage: string | null;
  conditions: Condition[];
  stage: string | null;
  sub_stage: string | null;
  lost_reason: string | null;
  is_reopen: boolean;
  ignore: boolean;
  ignore_reason: string | null;
  priority: number;
};

export type FieldRule = {
  id: number;
  partner_field: string | null;
  canonical_key: string;
  direction: Direction;
  transforms: Transform[];
  out_transforms: Transform[];
  trusted: boolean;
  required: boolean;
  not_available: boolean;
  note: string | null;
};

export type ValueRule = { id: number; canonical_key: string; partner_value: string; canonical_value: string; direction: Direction };
export type ActivityRule = { id: number; partner_type: string; partner_outcome: string | null; kind: string; outcome: string | null };
export type Pipeline = { id: number; key: string; label: string | null };

export type CoverageItem = { group: "stage" | "out" | "in" | "values" | "fields"; item: string; key?: string; required: boolean; done: boolean; detail?: string | null };
export type Coverage = { items: CoverageItem[]; required_total: number; required_done: number; total: number; done: number; stages_seen: number };
export type GoldenResult = { id: number; name: string; pass: boolean; actual?: unknown; error?: string };
export type Golden = { id: number; name: string; input: { kind: string; data: Record<string, unknown> }; expected: Record<string, unknown> };

export type Profile = {
  id: number;
  version: number | null;
  status: "draft" | "active" | "retired";
  note: string | null;
  created_at: string;
  activated_at: string | null;
  activated_by: string | null;
  based_on: number | null;
  rules: number;
};

export type QueueItem = {
  id: number;
  kind: "stage" | "field" | "value" | "activity" | "drift";
  item: string;
  sample: Record<string, unknown> | null;
  first_seen: string;
  last_seen: string;
  seen_count: number;
  status: "open" | "mapped" | "ignored";
  resolution: string | null;
  leads: number;
  lead_sample: number[];
};

export type PartnerSchema = {
  fields?: { name: string; label?: string; type?: string; values?: string[] }[];
  stages?: { stage: string; sub_stages?: string[] }[];
  pipelines?: string[];
  activities?: { type: string; outcomes?: string[] }[];
};
export type Drift = { what: "new_stage" | "removed_stage" | "new_field" | "removed_field" | "type_changed" | "removed_value"; item: string; detail: string | null; required: boolean };

export type Discovered = {
  stages: { stage: string; sub_stages: string[]; count: number }[];
  fields: { name: string; count: number; values: string[] }[];
  activities: { type: string; outcomes: string[]; count: number }[];
  pipelines: string[];
};

export type Editing = {
  id: number;
  status: "draft" | "active";
  version: number | null;
  pipeline_field: string;
  pipelines: Pipeline[];
  status_rules: StatusRule[];
  field_rules: FieldRule[];
  value_rules: ValueRule[];
  activity_rules: ActivityRule[];
  coverage: Coverage;
  goldens: GoldenResult[];
};

export type Studio = {
  partner: { id: number; name: string; slug: string; adapter_type: string; status: string };
  profiles: Profile[];
  editing: Editing | null;
  canonical: Canonical[];
  target_stages: string[];
  sub_stages: Record<string, string[]>;
  lost_reasons: string[];
  transform_ops: string[];
  snapshot: { id: number; source: string; created_at: string; schema: PartnerSchema; drift: Drift[] | null } | null;
  discovered: Discovered;
  queue: QueueItem[];
  goldens: Golden[];
  samples: { id: number; type: string; received_at: string; status: string; data: Record<string, unknown> }[];
  held_events: number;
  learned: { partner_field: string; canonical_key: string; partners: number }[];
  backfill: { count: number; by_change: { from: string; to: string; n: number }[]; sample: unknown[] } | null;
};

export type OverviewRow = {
  id: number;
  name: string;
  slug: string;
  adapter_type: string;
  status: string;
  active_version: number | null;
  active_at: string | null;
  has_draft: boolean;
  coverage: { required_done: number; required_total: number; done: number; total: number } | null;
  ready: boolean;
  queue_open: number;
  held_events: number;
  last_snapshot_at: string | null;
};

export const STAGE_LABEL: Record<string, string> = {
  contacted: "Contacted", counselled: "Counselled", applied: "Applied", enrolled: "Enrolled", lost: "Lost (to B2C nurture)",
  duplicate_at_partner: "Duplicate at partner",
};
export const DIRECTION_LABEL: Record<Direction, string> = { in: "Partner → Eduwit", out: "Eduwit → partner", both: "Both ways" };
export const QUEUE_KIND_LABEL: Record<QueueItem["kind"], string> = { stage: "Stage", field: "Field", value: "Value", activity: "Activity", drift: "Schema change" };
export const DRIFT_LABEL: Record<Drift["what"], string> = {
  new_stage: "New stage", removed_stage: "Stage removed", new_field: "New field", removed_field: "Field removed", type_changed: "Type changed",
  removed_value: "Picklist value removed",
};
export const ACTIVITY_KINDS = ["call", "whatsapp", "email", "sms", "meeting", "note", "task", "stage_change"] as const;
export const COVERAGE_GROUP_LABEL: Record<CoverageItem["group"], string> = {
  stage: "Partner stages", out: "Sent to the partner", in: "Sales fields from the partner", values: "Picklist values on test leads", fields: "Partner fields (optional)",
};

// ---------- suggestions ----------

/** Lower case, no "mx_" prefix (LeadSquared custom fields), letters and digits only. */
export function normalizeName(s: string): string {
  return s.toLowerCase().replace(/^mx_/, "").replace(/[^a-z0-9]/g, "");
}

const SYNONYMS: Record<string, string[]> = {
  full_name: ["name", "fullname", "studentname", "leadname", "candidatename", "firstname"],
  email: ["email", "emailaddress", "emailid", "mail"],
  phone: ["phone", "mobile", "mobilenumber", "phonenumber", "contactnumber", "whatsapp", "whatsappnumber"],
  alternate_phone: ["alternatephone", "secondaryphone", "altmobile", "alternatemobile"],
  city: ["city", "town", "currentcity"],
  state: ["state", "province", "region"],
  country: ["country"],
  preferred_language: ["language", "preferredlanguage"],
  guardian_name: ["fathername", "parentname", "guardianname", "mothername"],
  guardian_phone: ["fatherphone", "parentphone", "guardianphone", "parentmobile"],
  course: ["course", "program", "programme", "coursename", "programname", "programmename", "courseinterested"],
  specialization: ["specialization", "specialisation", "branch", "stream", "elective"],
  programme_level: ["level", "programlevel", "degreelevel"],
  study_mode: ["mode", "studymode", "learningmode", "deliverymode"],
  partner_course_code: ["coursecode", "programcode", "programmecode"],
  highest_qualification: ["education", "highesteducation", "qualification", "highestqualification", "lastqualification"],
  academic_score_pct: ["percentage", "marks", "score", "cgpa", "gpa", "graduationpercentage"],
  work_experience_years: ["workexperience", "experience", "experienceyears", "totalexperience"],
  current_job_role: ["designation", "jobtitle", "currentrole", "occupation"],
  enrollment_timeline: ["intake", "startdate", "batch", "preferredintake"],
  partner_record_id: ["leadid", "prospectid", "recordid", "id", "leadnumber"],
  counsellor_name: ["owner", "counsellor", "counselor", "assignedto", "leadowner", "salesowner", "ownername", "counsellorname"],
  counsellor_id: ["ownerid", "counsellorid", "userid"],
  counsellor_email: ["owneremail", "counselloremail"],
  counsellor_phone: ["ownerphone", "counsellorphone", "ownermobile"],
  call_outcome: ["calldisposition", "disposition", "calloutcome", "callstatus", "lastcallstatus"],
  call_attempts: ["callattempts", "attempts", "noofcalls", "callcount"],
  last_call_at: ["lastcalldate", "lastcalledon", "lastcalltime", "lastactivitydate"],
  first_call_at: ["firstcalldate", "firstcalledon"],
  next_follow_up_at: ["nextfollowup", "followupdate", "nextcall", "nextactivitydate", "callbackdate", "followupon"],
  counselling_done: ["counsellingdone", "counselingdone", "counselled", "counseled"],
  counselling_at: ["counsellingdate", "counselingdate"],
  application_id: ["applicationid", "applicationnumber", "formnumber", "applicationno"],
  application_status: ["applicationstatus", "formstatus"],
  applied_at: ["applicationdate", "appliedon", "formsubmittedon"],
  documents_status: ["documentstatus", "documentsstatus", "docstatus"],
  fee_amount_inr: ["fee", "totalfee", "coursefee", "feeamount"],
  fee_paid_inr: ["amountpaid", "feepaid", "paidamount", "paymentamount", "feereceived"],
  payment_date: ["paymentdate", "paidon", "feepaiddate"],
  enrollment_id: ["enrollmentno", "enrolmentnumber", "enrollmentnumber", "admissionnumber", "rollno", "enrollmentid"],
  enrollment_date: ["enrollmentdate", "enrolmentdate", "admissiondate", "enrolledon"],
  enrolled_program: ["enrolledprogram", "enrolledcourse", "admittedcourse"],
  enrolled_university: ["enrolleduniversity", "admitteduniversity"],
  enrollment_status: ["enrollmentstatus", "admissionstatus"],
  refund_amount_inr: ["refundamount", "refund"],
  refund_date: ["refunddate", "refundedon"],
  refund_reason: ["refundreason"],
  lost_reason: ["lostreason", "reasonlost", "disqualificationreason", "notinterestedreason", "closurereason"],
  remarks: ["remarks", "notes", "comments", "note", "counsellorremarks"],
};

/** Sørensen–Dice similarity of character bigrams (0 to 1). */
export function similarity(a: string, b: string): number {
  const x = normalizeName(a), y = normalizeName(b);
  if (!x || !y) return 0;
  if (x === y) return 1;
  if (x.length < 2 || y.length < 2) return 0;
  const grams = (s: string) => { const m = new Map<string, number>(); for (let i = 0; i < s.length - 1; i++) m.set(s.slice(i, i + 2), (m.get(s.slice(i, i + 2)) ?? 0) + 1); return m; };
  const gx = grams(x), gy = grams(y);
  let both = 0;
  for (const [g, n] of gx) both += Math.min(n, gy.get(g) ?? 0);
  return (2 * both) / (x.length - 1 + y.length - 1);
}

export type Suggestion = { key: string; confidence: number; why: string };

/** Best Eduwit field for a partner field: other partners on the same CRM first, then synonyms, then similar names. */
export function suggestField(partnerField: string, canonical: Pick<Canonical, "key" | "label">[], learned: Studio["learned"] = []): Suggestion | null {
  const n = normalizeName(partnerField);
  if (!n) return null;
  const known = new Set(canonical.map((c) => c.key));
  const l = learned.filter((x) => normalizeName(x.partner_field) === n && known.has(x.canonical_key)).sort((a, b) => b.partners - a.partners)[0];
  if (l) return { key: l.canonical_key, confidence: 0.95, why: `used by ${l.partners} other partner${l.partners === 1 ? "" : "s"} on this CRM` };
  for (const c of canonical) {
    if (normalizeName(c.key) === n || normalizeName(c.label) === n || (SYNONYMS[c.key] ?? []).includes(n)) {
      return { key: c.key, confidence: 0.9, why: "same name or a known synonym" };
    }
  }
  let best: Suggestion | null = null;
  for (const c of canonical) {
    const s = Math.max(similarity(n, c.key), similarity(n, c.label), ...(SYNONYMS[c.key] ?? []).map((x) => similarity(n, x)));
    if (s >= 0.6 && (!best || s * 0.8 > best.confidence)) best = { key: c.key, confidence: Math.round(s * 80) / 100, why: "similar name" };
  }
  return best;
}

const STAGE_HINTS: [RegExp, string][] = [
  [/duplicate|dupe|already exists/i, "duplicate_at_partner"],
  [/lost|dead|junk|not interested|invalid|disqualif|closed[- ]?lost|dnd|do not call|wrong number|not eligible/i, "lost"],
  [/enrol|admission|admitted|converted|\bwon\b|fee paid|seat/i, "enrolled"],
  [/appli|form (filled|submitted)|submitted/i, "applied"],
  [/counsel|interested|hot|warm|prospect|qualified|demo/i, "counselled"],
  [/contact|connected|attempt|rnr|ringing|no answer|call ?back|follow|busy|switched off|not reachable/i, "contacted"],
];

/** A first guess at the Eduwit stage from the partner's wording; always confirmed by a person. */
export function suggestStage(partnerStage: string, subStage?: string | null): Suggestion | null {
  const text = `${partnerStage} ${subStage ?? ""}`;
  for (const [re, stage] of STAGE_HINTS) if (re.test(text)) return { key: stage, confidence: 0.6, why: "keyword in the partner's wording" };
  return null;
}

// ---------- transform chains: "trim | amount | split(sep=' - ', part=last)" ----------

export function parseChain(text: string, ops: readonly string[]): { ok: true; chain: Transform[] } | { ok: false; error: string } {
  const chain: Transform[] = [];
  const src = text.trim();
  if (!src) return { ok: true, chain };
  const parts: string[] = [];
  let cur = "", quote: string | null = null, depth = 0;
  for (const ch of src) {
    if (quote) { cur += ch; if (ch === quote) quote = null; continue; }
    if (ch === "'" || ch === '"') { quote = ch; cur += ch; continue; }
    if (ch === "(") depth++;
    if (ch === ")") depth--;
    if (ch === "|" && depth === 0) { parts.push(cur); cur = ""; continue; }
    cur += ch;
  }
  if (quote || depth !== 0) return { ok: false, error: "Unbalanced quotes or brackets." };
  parts.push(cur);
  for (const raw of parts) {
    const m = /^\s*([a-z_0-9]+)\s*(?:\((.*)\))?\s*$/s.exec(raw);
    if (!m) return { ok: false, error: `Cannot read “${raw.trim()}”.` };
    const op = m[1] ?? "";
    const opts = m[2] ?? "";
    if (!ops.includes(op)) return { ok: false, error: `Unknown transform “${op}”. Use: ${ops.join(", ")}.` };
    const t: Transform = { op };
    if (opts.trim()) {
      const re = /\s*([a-z_]+)\s*=\s*('(?:[^']*)'|"(?:[^"]*)"|[^,]+?)\s*(?:,|$)/gy;
      let a: RegExpExecArray | null;
      let consumed = 0;
      while ((a = re.exec(opts)) !== null) {
        const k = a[1] ?? "";
        let v: string = a[2] ?? "";
        if ((v.startsWith("'") && v.endsWith("'")) || (v.startsWith('"') && v.endsWith('"'))) v = v.slice(1, -1);
        t[k] = /^-?\d+(\.\d+)?$/.test(v) && !["value", "sep", "from", "to"].includes(k) ? Number(v) : v;
        consumed = re.lastIndex;
        if (consumed >= opts.length) break;
      }
      if (consumed < opts.trimEnd().length) return { ok: false, error: `Cannot read the options of “${op}”.` };
    }
    chain.push(t);
  }
  if (chain.length > 8) return { ok: false, error: "At most 8 transforms." };
  return { ok: true, chain };
}

export function formatChain(chain: Transform[] | null | undefined): string {
  return (chain ?? []).map((t) => {
    const args = Object.entries(t).filter(([k]) => k !== "op");
    if (!args.length) return t.op;
    return `${t.op}(${args.map(([k, v]) => `${k}=${typeof v === "number" ? v : `'${String(v)}'`}`).join(", ")})`;
  }).join(" | ");
}

export const TRANSFORM_HELP: Record<string, string> = {
  trim: "remove extra spaces", lower: "lower case", upper: "upper case", title: "Title Case",
  constant: "always value=…", default: "value=… when empty", replace: "from=… to=…", join: "with=<Eduwit field>, sep=…",
  split: "sep=…, part=first|last|rest|<n>", phone_e164: "+91 phone", date: "DD/MM/YYYY or ISO → date", datetime: "→ India time",
  amount: "“2.5 L”, “₹1,20,000”, “50k” → number", cgpa_to_pct: "CGPA × 9.5 (scale=10)", boolean: "yes/no → true/false",
};

// ---------- schema uploads ----------

/** One CSV line into cells (quotes, doubled quotes). */
export function csvCells(line: string): string[] {
  const out: string[] = [];
  let cur = "", q = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (q) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; } else if (ch === '"') q = false; else cur += ch;
    } else if (ch === '"') q = true;
    else if (ch === ",") { out.push(cur.trim()); cur = ""; }
    else cur += ch;
  }
  out.push(cur.trim());
  return out;
}

/**
 * The partner's field list and status export as a schema. Either JSON ({fields, stages, pipelines, activities}) or a CSV
 * with the columns kind, name, parent, type: kind is field, value (parent = its field), stage, sub_stage (parent = its
 * stage), pipeline or activity (outcomes as value rows whose parent is the activity type, kind = outcome).
 */
export function parseSchemaText(text: string): { ok: true; schema: PartnerSchema } | { ok: false; error: string } {
  const src = text.trim();
  if (!src) return { ok: false, error: "Paste the partner's field and stage list." };
  if (src.startsWith("{")) {
    try {
      const j = JSON.parse(src) as PartnerSchema;
      if (j.fields && !Array.isArray(j.fields)) return { ok: false, error: "fields must be a list." };
      if (j.stages && !Array.isArray(j.stages)) return { ok: false, error: "stages must be a list." };
      return { ok: true, schema: { fields: j.fields ?? [], stages: j.stages ?? [], pipelines: j.pipelines ?? [], activities: j.activities ?? [] } };
    } catch {
      return { ok: false, error: "This is not valid JSON." };
    }
  }
  const lines = src.split(/\r?\n/).filter((l) => l.trim());
  const head = csvCells(lines[0] ?? "").map((h) => h.toLowerCase());
  const ki = head.indexOf("kind"), ni = head.indexOf("name"), pi = head.indexOf("parent"), ti = head.indexOf("type");
  if (ki < 0 || ni < 0) return { ok: false, error: "The first row needs the columns kind and name (and parent, type)." };
  const fields = new Map<string, { name: string; type?: string; values: string[] }>();
  const stages = new Map<string, { stage: string; sub_stages: string[] }>();
  const activities = new Map<string, { type: string; outcomes: string[] }>();
  const pipelines = new Set<string>();
  for (let i = 1; i < lines.length; i++) {
    const c = csvCells(lines[i] ?? "");
    const kind = (c[ki] ?? "").toLowerCase(), name = c[ni] ?? "", parent = pi >= 0 ? c[pi] ?? "" : "";
    if (!name) continue;
    if (kind === "field") fields.set(name.toLowerCase(), { ...(fields.get(name.toLowerCase()) ?? { name, values: [] }), name, type: ti >= 0 ? c[ti] || undefined : undefined });
    else if (kind === "value") {
      if (!parent) return { ok: false, error: `Row ${i + 1}: a value needs its field in parent.` };
      const f = fields.get(parent.toLowerCase()) ?? { name: parent, values: [] };
      f.values.push(name); fields.set(parent.toLowerCase(), f);
    } else if (kind === "stage") stages.set(name.toLowerCase(), stages.get(name.toLowerCase()) ?? { stage: name, sub_stages: [] });
    else if (kind === "sub_stage") {
      if (!parent) return { ok: false, error: `Row ${i + 1}: a sub-stage needs its stage in parent.` };
      const s = stages.get(parent.toLowerCase()) ?? { stage: parent, sub_stages: [] };
      s.sub_stages.push(name); stages.set(parent.toLowerCase(), s);
    } else if (kind === "pipeline") pipelines.add(name);
    else if (kind === "activity") activities.set(name.toLowerCase(), activities.get(name.toLowerCase()) ?? { type: name, outcomes: [] });
    else if (kind === "outcome") {
      if (!parent) return { ok: false, error: `Row ${i + 1}: an outcome needs its activity type in parent.` };
      const a = activities.get(parent.toLowerCase()) ?? { type: parent, outcomes: [] };
      a.outcomes.push(name); activities.set(parent.toLowerCase(), a);
    } else return { ok: false, error: `Row ${i + 1}: unknown kind “${c[ki]}” (field, value, stage, sub_stage, pipeline, activity, outcome).` };
  }
  return { ok: true, schema: {
    fields: [...fields.values()].map((f) => ({ name: f.name, ...(f.type ? { type: f.type } : {}), ...(f.values.length ? { values: f.values } : {}) })),
    stages: [...stages.values()], pipelines: [...pipelines], activities: [...activities.values()],
  } };
}

/** Partner stage/sub-stage pairs seen anywhere (schema snapshot, raw events, queue), with whether a rule covers them. */
export function knownStages(s: Studio): { stage: string; sub: string | null; count: number; mapped: boolean }[] {
  const seen = new Map<string, { stage: string; sub: string | null; count: number }>();
  const add = (stage: string, sub: string | null, count = 0) => {
    const k = `${stage.toLowerCase()}\u0000${(sub ?? "").toLowerCase()}`;
    const cur = seen.get(k);
    seen.set(k, { stage: cur?.stage ?? stage, sub: cur?.sub ?? sub, count: (cur?.count ?? 0) + count });
  };
  for (const st of s.snapshot?.schema.stages ?? []) { add(st.stage, null); for (const sub of st.sub_stages ?? []) add(st.stage, sub); }
  for (const st of s.discovered.stages) { add(st.stage, null, st.sub_stages.length ? 0 : st.count); for (const sub of st.sub_stages) add(st.stage, sub); }
  for (const q of s.queue) if (q.kind === "stage" && q.status === "open") { const [a, b] = q.item.split(" / "); add(a ?? q.item, b ?? null, q.seen_count); }
  const rules = s.editing?.status_rules ?? [];
  return [...seen.values()]
    .map((x) => ({ ...x, mapped: rules.some((r) => r.partner_stage.toLowerCase() === x.stage.toLowerCase()
      && (r.partner_sub_stage === null || r.partner_sub_stage.toLowerCase() === (x.sub ?? "").toLowerCase())) }))
    .sort((a, b) => a.stage.localeCompare(b.stage) || (a.sub ?? "").localeCompare(b.sub ?? ""));
}

/** Partner field names seen anywhere, with the rule that maps each (if any) and a suggestion otherwise. */
export function knownFields(s: Studio): { name: string; values: string[]; rule: FieldRule | null; suggestion: Suggestion | null; custom: boolean }[] {
  const seen = new Map<string, { name: string; values: Set<string> }>();
  const add = (name: string, values: string[] = []) => {
    const k = name.toLowerCase();
    const cur = seen.get(k) ?? { name, values: new Set<string>() };
    values.forEach((v) => cur.values.add(v));
    seen.set(k, cur);
  };
  for (const f of s.snapshot?.schema.fields ?? []) add(f.name, f.values ?? []);
  for (const f of s.discovered.fields) add(f.name, f.values);
  for (const q of s.queue) if (q.kind === "field") add(q.item);
  const rules = s.editing?.field_rules ?? [];
  const ignored = new Set(s.queue.filter((q) => q.kind === "field" && q.status === "ignored").map((q) => q.item.toLowerCase()));
  return [...seen.values()].map((f) => {
    const rule = rules.find((r) => r.partner_field?.toLowerCase() === f.name.toLowerCase()) ?? null;
    return { name: f.name, values: [...f.values].slice(0, 20), rule, suggestion: rule ? null : suggestField(f.name, s.canonical, s.learned), custom: ignored.has(f.name.toLowerCase()) };
  }).sort((a, b) => Number(Boolean(a.rule)) - Number(Boolean(b.rule)) || a.name.localeCompare(b.name));
}

export function conditionText(c: Condition): string {
  const v = Array.isArray(c.value) ? c.value.join(" or ") : c.value;
  return c.op === "eq" ? `${c.field} = ${v}` : c.op === "neq" ? `${c.field} ≠ ${v}` : c.op === "in" ? `${c.field} is ${v}`
    : c.op === "empty" ? `${c.field} is empty` : `${c.field} is filled`;
}
