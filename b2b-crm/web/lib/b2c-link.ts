/** The B2C CRM link screen (/b2c): the B2C CRM reads and writes leads only through the B2B CRM (m22, m23), under contract
 *  version 3 (Addendum 3, m31j: docs/b2c-contract.md). Shapes mirror b2b.b2c_link_overview, b2b.sync_cadence, b2b.b2c_link_lead
 *  and the record b2b.b2c_record builds. */
import { MISSING_LABEL } from "@/lib/lead-routing-ui";
import {
  ASSIGNMENT_LABEL, CONSENT_CHANNEL_LABEL, CONSENT_REQUEST_STATUS_LABEL, CONSENT_STATE_LABEL, HOLD_LABEL, JOB_LABEL, reasonLabel, type Lane,
} from "@/lib/routing";

/** The contract the record and every b2c.* envelope carry (b2b.api_b2c_schema result.contract_version). */
export const CONTRACT_VERSION = 3;
export const CONTRACT_DOC = "docs/b2c-contract.md";

export type FieldKind = "text" | "email" | "phone" | "int" | "numeric" | "pct" | "ts" | "date" | "uuid" | "stage" | "temperature" | "bool" | "json" | "list";
export type LinkField = { field: string; column: string; group: string; kind: FieldKind; write: "b2c" | "b2b"; max: number | null };
export type LinkSettings = { enabled: boolean; scope: "held" | "all"; writable: string[]; delivery?: "realtime" | "batched" };

export type LinkLogRow =
  | { dir: "out"; at: string; lead_id: number; name: string | null; type: "upserted" | "released"; version: number; origin: string | null;
      delivery: { status: string; error: string | null; attempts: number } | null }
  | { dir: "in"; at: string; lead_id: number | null; name: string | null; type: "update" | "activity"; status: "applied" | "unchanged" | "conflict" | "rejected";
      http_status: number; error: string | null; actor: Record<string, string>; changes: Record<string, unknown>; request_id: string; version: number | null };

/** b2c_link_overview.checks, plus two the page computes: production (sync_cadence delivery) and golive_events (the endpoint's
 *  subscription covers the routing go-live gate, D10 c). */
export type LinkChecks = { endpoint: boolean; secret: boolean; subscribed: boolean; ping: boolean; active: boolean; key: boolean; key_used: boolean;
                           first_delivery: boolean; first_write: boolean; production?: boolean; golive_events?: boolean };

/** What syncs when (b2b.sync_cadence). */
export type SyncCadence = {
  interval_minutes: number;
  b2c: { delivery: "realtime" | "batched"; last_batch_at: string | null; last_batch_leads: number | null; last_batch_parts: number | null;
         next_batch_at: string | null; waiting: number | null };
  partners: { id: number; name: string; adapter: string; live: boolean; poll: boolean; live_minutes: number; sandbox_minutes: number;
              own_minutes: boolean; last_poll_at: string | null }[];
};

export type LinkOverview = {
  settings: LinkSettings;
  fields: LinkField[];
  endpoint: null | { id: number; name: string; url: string; active: boolean; events: string[]; has_secret: boolean; last_success_at: string | null;
                     last_failure_at: string | null; last_error: string | null; subscribed: boolean };
  keys: { id: number; name: string; prefix: string; scopes: string[]; last_used_at: string | null }[];
  checks: LinkChecks;
  sync: { in_scope: number; held_now: number; changes_24h: number; last_change_at: string | null; last_seq: number | null;
          tick: { at?: string; last_run?: string; scanned?: number; changed?: number } | null };
  deliveries: { by_status: Record<string, number>; waiting: number; lag_seconds_avg: number | null; lag_seconds_max: number | null };
  writes: { by_status: Record<string, number>; last_at: string | null };
  log: LinkLogRow[];
  /** The contract version the link publishes. b2c_link_overview (m22c) does not return it yet: contractVersion() falls back to CONTRACT_VERSION. */
  contract_version?: number;
  /** When the Admin last re-sent every lead (b2c.link_resync). Not returned yet: resyncNote() reads the activity log instead. */
  last_resync_at?: string | null;
};

// ---------- the version-3 record (b2b.b2c_record) ----------

export type BarReason = "duplicate" | "lost";
export type HoldKind = "barred" | "qualification_nurture" | "selling";
export type ConsentState = "given" | "refused" | "withdrawn" | "requested" | "queued" | "expired" | "stamp_uncovered" | "none";
export type LeadClass = "junk" | "mismatch" | "qualified" | "unqualified";

/** PART 5.4 badge: a partner that proved the student was already its lead. first_had_at null = the partner gave no date. */
export type Provider = { partner_id: number; partner_name: string; first_had_at: string | null; existing_record_id: string | null; claimed_at: string | null };
/** b2b.b2c_hold: the B2C hold this lead is under. */
export type RecordHold = { kind: HoldKind; open: boolean; allocation_id: number | null; lane: Lane | null; reason: string | null; owner_assigned: boolean };
/** consent.partner_share_request: the latest consent request of the lead's current enquiry. */
export type ConsentRequest = { id: number; status: string; channel: string; context: string; created_at: string; expires_at: string | null; answer: "yes" | "no" | null };

export type RecordAllocation = {
  destination: string | null; allocation_id: number | null; reference: string | null; b2c_lane: Lane | null; reason: string | null; cause: string | null;
  allocated_at: string | null; status: string | null; partner: { id: number; name: string } | null;
  partner_barred_at: string | null; partner_bar_reason: BarReason | null; already_with_providers: Provider[]; hold: RecordHold | null;
  job: string | null; assignment: string | null; first_contact_script: string | null; nurture_first_message_at: string | null; b2c_actions: string[];
};

/** The record the B2C CRM keeps a copy of. Field groups (student, education, …) are open objects under the B2C names; the
 *  version-3 keys are typed. Older copies (version 2) lack them, so every reader goes through recordSummary(). */
export type LinkRecord = {
  id: number; cycle_no: number; created_at: string; updated_at: string | null; is_test: boolean; deleted: boolean; merged_into_id: number | null;
  held_by_b2c: boolean; contract_version?: number;
  interest?: Record<string, unknown> & { other_courses?: string[] | null };
  consent?: Record<string, unknown> & { partner_share_given?: boolean | null; state?: ConsentState | null; partner_share_request?: ConsentRequest | null };
  qualification?: Record<string, unknown> & { class?: LeadClass | null; missing?: string[] | null };
  allocation?: Partial<RecordAllocation> | null;
  campaign?: Record<string, unknown> | null;
  [group: string]: unknown;
};

export type LinkLead = {
  lead_id: number; name: string | null; held_by_b2c: boolean; shared: boolean; version: number | null; seq: number | null; changed_at: string | null;
  origin: string | null; record: LinkRecord;
  deliveries: { id: number; type: string; version: number; status: string; attempts: number; error: string | null; created_at: string; delivered_at: string | null }[];
  writes: { at: string; kind: string; status: string; http_status: number; error: string | null; actor: Record<string, string>; changes: Record<string, unknown>; version: number | null }[];
};

export const BAR_REASON_LABEL: Record<BarReason, string> = { duplicate: "Duplicate at partners", lost: "A partner marked it lost" };
export const SCRIPT_LABEL: Record<string, string> = { neutral_adviser: "Neutral adviser (“Eduwit can help you compare options”)", standard: "Standard" };
export const CLASS_LABEL: Record<LeadClass, string> = { junk: "Junk", mismatch: "Programme Eduwit does not offer", qualified: "Qualified", unqualified: "Not yet qualified" };
export const B2C_ACTION_LABEL: Record<string, string> = {
  welcome_explore_programmes: "Send the explore-programmes WhatsApp from the B2C number (Meta-approved template)",
};

/** Events on the link, in short, for delivery lists and logs: everything b2b.api_b2c_schema publishes or accepts. */
export const EVENT_SHORT: Record<string, string> = {
  "b2c.lead_upserted": "Lead sent", "b2c.lead_released": "Lead released", "b2c.leads_batch": "Batch",
  "b2c.lead_handed_off": "Handed to B2C", "b2c.lead_reenquired": "Enquired again", "b2c.lead_requalified": "Requalified, back to routing",
  "b2c.lead_reengaged": "Re-engaged, still unqualified", "b2c.consent_requested": "Consent request to send", "b2c.consent_closed": "Consent request closed",
  "b2c.lead_flagged": "Flagged", "b2c.lead_close_agreed": "Close agreed", "b2b.lead_routed_to_partner": "Accepted by a partner", ping: "Test ping",
  "b2ccrm.partner_consent": "Consent answer", "b2ccrm.consent_request_sent": "Consent request sent", "b2ccrm.lead_assigned": "Counsellor assigned",
  "b2ccrm.stage_changed": "Stage changed", "b2ccrm.enrolled": "Enrolled", "b2ccrm.opted_out": "Opted out", "b2ccrm.erasure_requested": "Erasure requested",
};
export function eventLabel(type: string): string {
  return EVENT_SHORT[type] ?? type;
}

/** Fields the B2C CRM may always write on a lead it holds, whatever the Admin ticked (api_b2c_schema: other_courses, max 9). */
export const ALWAYS_WRITABLE_FIELDS: readonly string[] = ["other_courses"];
export function isWritable(settings: Pick<LinkSettings, "writable">, field: string): boolean {
  return ALWAYS_WRITABLE_FIELDS.includes(field) || settings.writable.includes(field);
}

/** Which leads the B2C CRM sees (b2c_link.scope; m31j b2c_in_scope). */
export const SCOPE_LABEL: Record<LinkSettings["scope"], { label: string; hint: string }> = {
  held: { label: "Only leads it holds", hint: "Leads the engine hands to B2C (sales or nurture). A lead that goes to a partner is released from its copy." },
  all: { label: "Every lead, read-only", hint: "All leads except Not passed and test leads (a test hand-off made for it still arrives): unrouted and partner-held leads too, for lookups and reporting, but it can write only the leads it holds." },
};

/** The connection checklist, in the order the Admin and the B2C developer work through it. */
export const CHECK_STEPS: { key: keyof LinkChecks; label: string; hint: string; where: string }[] = [
  { key: "endpoint", label: "B2C CRM's webhook address registered", hint: "The HTTPS address that receives lead changes.", where: "/system?tab=integrations" },
  { key: "secret", label: "Signing secret issued", hint: "Shared with the B2C developer through a secure channel.", where: "/system?tab=integrations" },
  { key: "subscribed", label: "Subscribed to lead sync", hint: "b2c.* (or b2c.lead_upserted and b2c.lead_released).", where: "/system?tab=integrations" },
  { key: "golive_events", label: "Subscribed to hand-offs and consent requests", hint: "b2c.lead_handed_off and b2c.consent_requested (b2c.* covers both): routing cannot go live without them.", where: "/system?tab=integrations" },
  { key: "ping", label: "Test ping delivered", hint: "Send test on the endpoint; the B2C CRM must verify the signature.", where: "/system?tab=integrations" },
  { key: "active", label: "Endpoint switched on", hint: "Nothing is delivered before this.", where: "/system?tab=integrations" },
  { key: "key", label: "API key with the B2C link scope", hint: "For reads, the change feed, updates and activities.", where: "/system?tab=integrations" },
  { key: "key_used", label: "The B2C CRM has called the API", hint: "Usually the first feed call that builds its copy.", where: "" },
  { key: "first_delivery", label: "First lead change delivered", hint: "A lead handed to B2C arrives within seconds.", where: "" },
  { key: "first_write", label: "First update written back", hint: "A counsellor's change reached the lead through the API.", where: "" },
  { key: "production", label: "Switched to the production cadence", hint: "After full testing: changes go in one batch every sync interval, to save API calls.", where: "/b2c#cadence" },
];

export const GROUP_LABEL: Record<string, string> = {
  student: "Student", education: "Education", interest: "Interest", consent: "Consent", source: "Source and campaign",
  qualification: "Qualification", pipeline: "Pipeline", application: "Application", enrolment: "Enrolment", lost: "Lost", other: "Other",
  allocation: "Allocation (B2B only)", campaign: "Paid attribution (B2B only)",
};

export const KIND_LABEL: Record<FieldKind, string> = {
  text: "text", email: "email", phone: "phone", int: "whole number", numeric: "number", pct: "percentage", ts: "date and time", date: "date",
  uuid: "user ID (UUID)", stage: "stage key", temperature: "hot / warm / cold", bool: "true / false", json: "object", list: "list of names",
};

/** Fields grouped in catalogue order. */
export function groupFields(fields: LinkField[]): { group: string; fields: LinkField[] }[] {
  const out: { group: string; fields: LinkField[] }[] = [];
  for (const f of fields) {
    const g = out.find((x) => x.group === f.group);
    if (g) g.fields.push(f); else out.push({ group: f.group, fields: [f] });
  }
  return out;
}

/** The contract version the link publishes (b2c_link_overview may report it; until then the one this build implements). */
export function contractVersion(o: Pick<LinkOverview, "contract_version">): number {
  return o.contract_version ?? CONTRACT_VERSION;
}

/** D46 step 7: after the Addendum 3 deploy every shared lead is re-sent once (origin 'resync') with the link in batched
 *  delivery, so the B2C CRM's copies gain the version-3 fields in one batch instead of one webhook per lead. Due while no
 *  resend is on record and there is something to resend; null once done. b2c_link_overview does not report resends yet, so
 *  the activity log's 'resync' origin stands in until last_resync_at is returned. */
export function resyncNote(o: Pick<LinkOverview, "log" | "sync" | "last_resync_at">, delivery: "realtime" | "batched"): { batched: boolean } | null {
  if (o.last_resync_at) return null;
  if (o.last_resync_at === undefined && o.log.some((r) => r.dir === "out" && r.origin === "resync")) return null;
  if (o.sync.in_scope === 0 && o.sync.held_now === 0) return null;
  return { batched: delivery === "batched" };
}

/** One badge for the whole link. */
export function linkHealth(o: Pick<LinkOverview, "checks" | "settings" | "deliveries" | "endpoint">): { label: string; tone: "success" | "warning" | "danger" | "neutral" } {
  if (!o.settings.enabled) return { label: "Switched off", tone: "neutral" };
  if (!o.checks.endpoint || !o.checks.secret || !o.checks.active) return { label: "Not connected", tone: "neutral" };
  if ((o.deliveries.by_status.dead ?? 0) > 0) return { label: "Deliveries gave up", tone: "danger" };
  const failing = o.endpoint?.last_failure_at && (!o.endpoint.last_success_at || o.endpoint.last_failure_at > o.endpoint.last_success_at);
  if (failing) return { label: "Failing", tone: "warning" };
  if (!o.checks.subscribed) return { label: "Not subscribed to sync", tone: "warning" };
  return { label: "Live", tone: "success" };
}

export function lagText(s: number | null | undefined): string {
  if (s === null || s === undefined) return "—";
  if (s < 60) return `${s < 10 ? s.toFixed(1) : Math.round(s)} s`;
  return `${Math.round(s / 60)} min`;
}

/** "stage: assigned → counselled, owner_user_id: set" for a write's change list. A list value shows its length. */
export function describeChanges(changes: Record<string, unknown>, max = 4): string {
  const parts = Object.entries(changes).map(([k, v]) => {
    if (v && typeof v === "object" && "to" in (v as Record<string, unknown>)) {
      const to = (v as { to: unknown }).to;
      const show = to === null ? "cleared" : Array.isArray(to) ? (to.length === 0 ? "cleared" : `${to.length} ${to.length === 1 ? "item" : "items"}`)
        : typeof to === "object" ? "updated" : String(to).length > 24 ? String(to).slice(0, 24) + "…" : String(to);
      return `${k} → ${show}`;
    }
    return k;
  });
  return parts.slice(0, max).join(", ") + (parts.length > max ? ` +${parts.length - max}` : "");
}

export function actorText(a: Record<string, string> | null | undefined): string {
  if (!a) return "—";
  return a.name || a.email || a.id || "B2C CRM";
}

/** "call · connected · Wants the weekend batch" for an activity's stored fields. An activity that records a link event
 *  (type or event_type, e.g. b2ccrm.partner_consent) is named by the event. */
export function describeActivity(a: Record<string, unknown>): string {
  const ev = typeof a.type === "string" ? a.type : typeof a.event_type === "string" ? a.event_type : null;
  const parts = [ev && EVENT_SHORT[ev] ? EVENT_SHORT[ev] : null, a.kind, a.outcome,
    typeof a.note === "string" ? (a.note.length > 40 ? a.note.slice(0, 40) + "…" : a.note) : null];
  return parts.filter((x) => typeof x === "string" && x).join(" · ");
}

/** "Down Edu · first had the student on 28 Aug 2026 · their record LS-77001"; a partner that gave no date says so (PART 5.4). */
export function describeProvider(p: Provider, formatDate: (iso: string) => string = (iso) => iso.slice(0, 10)): string {
  const when = p.first_had_at ? `first had the student on ${formatDate(p.first_had_at)}` : "date not given";
  return [p.partner_name || `partner #${p.partner_id}`, when, p.existing_record_id ? `their record ${p.existing_record_id}` : null].filter(Boolean).join(" · ");
}

export type RecordSummary = {
  version: number;
  bar: { reason: BarReason; label: string; since: string | null } | null;
  providers: Provider[];
  hold: { kind: HoldKind; label: string; open: boolean; lane: Lane | null; reason: string | null } | null;
  /** How B2C should handle the lead it holds (null when B2C does not hold it). */
  handling: { reason: string; job: string | null; assignment: string | null; script: string | null; nurture_first_message_at: string | null } | null;
  actions: { code: string; label: string }[];
  qualification: { class: LeadClass | null; label: string | null; missing: { code: string; label: string }[] };
  consent: { given: boolean; state: string; label: string; request: ConsentRequest | null; requestText: string | null };
  other_courses: string[];
};

const arr = <T,>(x: unknown): T[] => (Array.isArray(x) ? (x as T[]) : []);

/** The version-3 facts of a record in words (bar, providers, hold, handling, qualification, consent, other interests). Tolerates
 *  a version-2 record: every section is then empty or null. */
export function recordSummary(r: LinkRecord): RecordSummary {
  const a = r.allocation ?? {};
  const q = r.qualification ?? {};
  const c = r.consent ?? {};
  const cls = (q.class ?? null) as LeadClass | null;
  const state = c.state ?? (c.partner_share_given ? "given" : "none");
  const req = c.partner_share_request ?? null;
  const hold = a.hold ?? null;
  const held = Boolean(r.held_by_b2c);
  return {
    version: typeof r.contract_version === "number" ? r.contract_version : 2,
    bar: a.partner_bar_reason ? { reason: a.partner_bar_reason, label: BAR_REASON_LABEL[a.partner_bar_reason] ?? a.partner_bar_reason, since: a.partner_barred_at ?? null } : null,
    providers: arr<Provider>(a.already_with_providers),
    hold: hold ? { kind: hold.kind, label: HOLD_LABEL[hold.kind] ?? hold.kind, open: Boolean(hold.open), lane: hold.lane ?? null, reason: hold.reason ?? null } : null,
    handling: held && (a.job || a.assignment || a.first_contact_script)
      ? { reason: reasonLabel(a.reason, a.cause), job: a.job ? JOB_LABEL[a.job] ?? a.job : null,
          assignment: a.assignment ? ASSIGNMENT_LABEL[a.assignment] ?? a.assignment : null,
          script: a.first_contact_script ? SCRIPT_LABEL[a.first_contact_script] ?? a.first_contact_script : null,
          nurture_first_message_at: a.nurture_first_message_at ?? null }
      : null,
    actions: arr<string>(a.b2c_actions).map((code) => ({ code, label: B2C_ACTION_LABEL[code] ?? code.replace(/_/g, " ") })),
    qualification: { class: cls, label: cls ? CLASS_LABEL[cls] ?? cls : null,
                     missing: arr<string>(q.missing).map((code) => ({ code, label: MISSING_LABEL[code] ?? code.replace(/_/g, " ") })) },
    consent: { given: Boolean(c.partner_share_given), state, label: CONSENT_STATE_LABEL[state] ?? state, request: req,
               requestText: req ? [CONSENT_REQUEST_STATUS_LABEL[req.status] ?? req.status, `via ${CONSENT_CHANNEL_LABEL[req.channel] ?? req.channel}`,
                                   `asked at the ${req.context === "admin" ? "Admin's request" : req.context === "nurture" ? "nurture recheck" : "routing decision"}`,
                                   req.answer ? `answer ${req.answer.toUpperCase()}` : null].filter(Boolean).join(" · ") : null },
    other_courses: arr<string>(r.interest?.other_courses),
  };
}
