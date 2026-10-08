import { formatDateTime } from "@/lib/format";
import {
  ALLOCATION_LABEL, CONSENT_CHANNEL_LABEL, CONSENT_REQUEST_STATUS_LABEL, CONSENT_STATE_LABEL, HOLD_LABEL, OUTLOOK_LABEL, reasonLabel,
  type ConsentState,
} from "@/lib/routing";
import type { AllocationRow, ConsentLedgerRow, LeadRouting, OtherProvider, Reenquiry } from "@/lib/routing-data";

/** The lead drawer's routing decisions in one testable place (Addendum 3): which badges the header shows, which actions the
 *  Routing tab offers and why, the consent panel, the lost grace countdown and the qualification-nurture summary. Pure
 *  functions over b2b.lead_routing's result (W1's LeadRouting); the components only render what these return. Rulebook:
 *  Guiding principle and R2 (the bar has no manual override), PART 5.4, 6.1–6.3, 7; decisions D1, D2, D7–D9, D18, D20, D21,
 *  D30, D34. */

export type BadgeTone = "neutral" | "success" | "warning" | "danger" | "info" | "brand";
export type UiBadge = { key: string; text: string; tone: BadgeTone; title?: string };

/** PART 6.3 / R2: the sentence shown instead of the hidden 'Send to partners' button. */
export const BARRED_SENTENCE = "This lead is partner-barred for ever: it can only be worked by B2C";
/** The toast after allocation_partner_lost succeeds (status 'grace'). */
export const LOST_SUCCESS_TOAST = "Recorded: lost, in grace for 7 days";

const OPEN_PARTNER = ["queued", "pushing", "pushed", "accepted"];
const HELD_KINDS = ["selling", "qualification_nurture"];

// ---------- small formatters ----------

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "3 Oct" / "12 Sep" in IST (three-letter months on every runtime); null for a missing or unreadable date. */
export function shortDate(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Kolkata", day: "numeric", month: "numeric" }).formatToParts(d);
  const day = parts.find((p) => p.type === "day")?.value ?? "";
  const month = Number(parts.find((p) => p.type === "month")?.value ?? "0") - 1;
  return `${day} ${MONTHS[month] ?? ""}`.trim();
}

/** Time left until `until`: "5 d 3 h left", "3 h 20 min left", "12 min left" or "ended"; null when there is no date. */
export function remainingText(until: string | null | undefined, now: number = Date.now()): string | null {
  if (!until) return null;
  const ms = new Date(until).getTime() - now;
  if (!Number.isFinite(ms)) return null;
  if (ms <= 0) return "ended";
  const days = Math.floor(ms / 86_400_000);
  const hours = Math.floor((ms % 86_400_000) / 3_600_000);
  const minutes = Math.floor((ms % 3_600_000) / 60_000);
  if (days >= 1) return hours > 0 ? `${days} d ${hours} h left` : `${days} d left`;
  if (hours >= 1) return minutes > 0 ? `${hours} h ${minutes} min left` : `${hours} h left`;
  return `${Math.max(1, minutes)} min left`;
}

const providerName = (p: { partner_name?: string | null; partner_id?: number | null }) => p.partner_name ?? (p.partner_id != null ? `partner #${p.partner_id}` : "a partner");

type ProviderLike = { partner_id?: number | null; partner_name?: string | null; first_had_at?: string | null };

/** PART 5.4: "Already with other providers: X since 12 Sep, Y date not given" (first_had_at null = the partner gave no date).
 *  Takes lead_other_providers rows or the providers recorded with a bar. */
export function providersSentence(providers: (ProviderLike | OtherProvider)[] | null | undefined): string | null {
  if (!providers || providers.length === 0) return null;
  const parts = providers.map((p) => {
    const d = shortDate(p.first_had_at);
    return d ? `${providerName(p)} since ${d}` : `${providerName(p)} date not given`;
  });
  return `Already with other providers: ${parts.join(", ")}`;
}

/** The header badge of a partner bar: "Partner-barred (duplicate, 3 Oct)" or "Partner-barred (lost by X, 3 Oct)". */
export function barText(bar: NonNullable<LeadRouting["bar"]>): string {
  const date = shortDate(bar.barred_at);
  const what = bar.reason === "lost" ? `lost by ${providerName(bar.providers?.[0] ?? {})}` : "duplicate";
  return `Partner-barred (${what}${date ? `, ${date}` : ""})`;
}

const CONSENT_TONE: Record<ConsentState, BadgeTone> = {
  given: "success", refused: "danger", withdrawn: "danger", stamp_uncovered: "warning", requested: "info", queued: "info", expired: "warning", none: "neutral",
};
export const consentTone = (state: ConsentState | string): BadgeTone => CONSENT_TONE[state as ConsentState] ?? "neutral";

// ---------- helpers over the routing result ----------

/** The open partner allocation (queued, pushing, pushed or accepted), newest first as lead_routing lists them. */
export function openPartnerAllocation(r: LeadRouting): AllocationRow | null {
  return r.allocations.find((a) => a.destination_type === "partner" && OPEN_PARTNER.includes(a.status)) ?? null;
}

const allocationById = (r: LeadRouting, id: number | null | undefined) => (id == null ? null : r.allocations.find((a) => a.id === id) ?? null);

/** B2C holds the lead for selling or qualification nurture (b2c_hold open). The 'barred' kind is a hold too, but R2 applies. */
const b2cHeld = (r: LeadRouting) => Boolean(r.hold?.open && HELD_KINDS.includes(r.hold.kind));
const isRouted = (r: LeadRouting) => Boolean(openPartnerAllocation(r)) || Boolean(r.hold?.open) || r.readiness.missing.includes("already routed");

// ---------- header badges ----------

/** The drawer header's Addendum 3 badges: the bar, other providers, the paid label, lost in grace, and the consent state
 *  (including 'consent stamp does not cover admission partners'). With no routing result only the column stamp is known. */
export function drawerBadges(r: LeadRouting | null, lead: { consent_partner_share_at?: unknown } = {}, now: number = Date.now()): UiBadge[] {
  const out: UiBadge[] = [];
  if (!r) {
    if (lead.consent_partner_share_at) {
      out.push({ key: "consent", text: "Partner-sharing consent stamped", tone: "neutral", title: "Whether the stamp covers admission partners is checked in the Routing tab" });
    }
    return out;
  }
  if (r.bar) {
    out.push({ key: "bar", text: barText(r.bar), tone: "danger", title: `${BARRED_SENTENCE}. ${r.bar.reason === "duplicate" ? "Partners reported the student as a duplicate (PART 5.4)." : "A partner marked the lead lost and the 7-day grace ended (PART 6.1)."}` });
  }
  const providers = providersSentence(r.other_providers);
  if (providers) out.push({ key: "providers", text: providers, tone: "warning", title: "Partners that proved they already had this student, with the date they first had them" });
  const paid = r.attribution?.paid ? (r.attribution.label ?? r.attribution.platform) : r.readiness.paid;
  if (paid) out.push({ key: "paid", text: `Paid: ${paid}`, tone: "info", title: "Meta / Google attribution label; it does not change where the lead goes" });
  if (r.lost_grace?.in_grace && !r.lost_grace.revived) {
    const left = remainingText(r.lost_grace.grace_until, now);
    out.push({ key: "lost_grace", text: `Lost, in grace${left ? ` · ${left}` : ""}`, tone: "warning", title: "The partner marked the lead lost. New partner activity brings it back; after 7 days it moves to B2C nurture, partner-barred" });
  }
  const state = r.consent_detail?.state ?? (r.consent ? "given" : "none");
  out.push({ key: "consent", text: CONSENT_STATE_LABEL[state] ?? state, tone: consentTone(state) });
  return out;
}

// ---------- routing actions ----------

export type RoutingActionState = {
  /** The lead is partner-barred (R2): 'Send to partners' is hidden and this sentence is shown instead. */
  barred: boolean;
  barredNote: string | null;
  isTest: boolean;
  /** An open not_passed row: 'Pass to CRM'. */
  passToCrm: boolean;
  /** PART 6.3: only a lead held by B2C, never a barred one; disabled without recorded consent. */
  sendToPartners: { show: boolean; disabledWhy: string | null };
  /** PART 6.2 / D20: follows reroute_check of the open partner allocation; `why` explains both the allowed and the refused case. */
  reroute: { show: boolean; enabled: boolean; why: string | null; allocationId: number | null; partner: string | null };
  /** The partner reports the lead lost (PART 6.1): pushed or accepted and not already in the grace. */
  lost: { show: boolean; allocationId: number | null; partner: string | null };
  /** R1 / D21: explicit test routes for an unrouted test lead. */
  test: { sandbox: boolean; b2cTest: boolean };
};

/** Why 'Send to partners' is disabled for a held lead without recorded consent (route_to_partners_core raises no_consent). */
export function consentBlockReason(state: ConsentState | string): string {
  switch (state) {
    case "requested": case "queued": return "A consent request is open: wait for the student's answer";
    case "refused": return "The student said NO to sharing with partners";
    case "withdrawn": return "The student withdrew partner-sharing consent";
    case "stamp_uncovered": return "The consent stamp does not cover admission partners: ask for consent first";
    default: return "The student has not consented to sharing with partners: ask for consent first";
  }
}

export function routingActionState(r: LeadRouting): RoutingActionState {
  const barred = Boolean(r.bar);
  const partner = openPartnerAllocation(r);
  const held = b2cHeld(r);
  const consentState = r.consent_detail?.state ?? (r.consent ? "given" : "none");
  const rerouteAlloc = r.reroute ? allocationById(r, r.reroute.allocation_id) ?? partner : null;
  const inGrace = Boolean(r.lost_grace?.in_grace && !r.lost_grace.revived);
  let rerouteWhy: string | null = null;
  if (r.reroute) {
    if (!r.reroute.allowed) rerouteWhy = r.reroute.why ?? "A re-route is not allowed now";
    else if (r.reroute.breaches.length > 0) rerouteWhy = `Allowed: ${r.reroute.breaches.length === 1 ? "an SLA was breached" : `${r.reroute.breaches.length} SLAs were breached`}`;
    else rerouteWhy = "Allowed: the partner has not contacted the student yet";
  }
  return {
    barred,
    barredNote: barred ? BARRED_SENTENCE : null,
    isTest: r.is_test,
    passToCrm: Boolean(r.not_passed && !r.not_passed.passed_at),
    sendToPartners: {
      show: held && !barred && !r.is_test,
      disabledWhy: r.consent ? null : consentBlockReason(consentState),
    },
    reroute: {
      show: Boolean(r.reroute),
      enabled: Boolean(r.reroute?.allowed),
      why: rerouteWhy,
      allocationId: r.reroute?.allocation_id ?? null,
      partner: rerouteAlloc?.partner_name ?? null,
    },
    lost: {
      show: Boolean(partner && ["pushed", "accepted"].includes(partner.status) && !inGrace),
      allocationId: partner?.id ?? null,
      partner: partner?.partner_name ?? null,
    },
    test: { sandbox: r.is_test && !isRouted(r), b2cTest: r.is_test && !isRouted(r) },
  };
}

/** The lost dialog's copy: the 7-day grace, revival and the bar (PART 6.1, D34, D35). */
export function lostDialogCopy(partner: string | null): string {
  const p = partner ?? "the partner";
  return `The lead stays with ${p} as "lost, in grace" for 7 days: B2C sends nothing and assigns no counsellor. If ${p} reports new activity in that time, `
    + `the lead is simply back with them. After 7 days it moves to B2C nurture, unassigned, and is partner-barred for ever.`;
}

/** The routeToPartners (W3) refusal text for the Admin: the function's prefix is dropped, the sentence capitalised. */
export function friendlyRouteError(message: string): string {
  const m = message.replace(/^(partner_barred|no_consent|not_held):\s*/, "").trim();
  if (!m) return "Could not send the lead to partners.";
  return m.charAt(0).toUpperCase() + m.slice(1) + (/[.!?]$/.test(m) ? "" : ".");
}

// ---------- consent panel ----------

export type ConsentPanel = {
  state: ConsentState | string;
  label: string;
  tone: BadgeTone;
  given: { at: string | null; version: string | null; source: string | null } | null;
  refusedAt: string | null;
  stampUncovered: boolean;
  ledger: ConsentLedgerRow[];
  /** The open request (queued, requested, sent or unsendable), else the latest expired one of this cycle. */
  request: {
    id: number; open: boolean; status: string; statusLabel: string; channel: string; channelLabel: string;
    /** 'queued' while the hourly budget holds it back, the time left until it expires, 'expired', or 'could not be sent'. */
    countdown: string | null; expiresAt: string | null; programme: string | null; context: string | null; createdAt: string | null;
  } | null;
  canAsk: boolean; askWhy: string | null;
  canRecordYes: boolean; yesWhy: string | null;
  canRecordNo: boolean; noWhy: string | null;
};

/** PART 7 / D7 / D9: what the consent block shows and which of the three actions are offered. `adminYes` is
 *  engine.consent_admin_yes (read by the Routing tab); a YES by the Admin also needs a written evidence reference. */
export function consentPanel(r: LeadRouting, opts: { adminYes?: boolean; now?: number } = {}): ConsentPanel {
  const now = opts.now ?? Date.now();
  const pc = r.consent_detail?.partner_consent;
  const state = r.consent_detail?.state ?? (r.consent ? "given" : "none");
  const given = pc?.given ? { at: pc.at, version: pc.version, source: pc.source } : null;
  const open = pc?.open_request ?? null;
  const expired = pc?.expired_request ?? null;
  let request: ConsentPanel["request"] = null;
  if (open) {
    const countdown = open.status === "queued" ? "queued" : open.status === "unsendable" ? "could not be sent" : remainingText(open.expires_at, now);
    request = {
      id: open.id, open: true, status: open.status, statusLabel: CONSENT_REQUEST_STATUS_LABEL[open.status] ?? open.status,
      channel: open.channel, channelLabel: CONSENT_CHANNEL_LABEL[open.channel] ?? open.channel,
      countdown, expiresAt: open.expires_at, programme: open.programme ?? null, context: open.context, createdAt: open.created_at,
    };
  } else if (expired) {
    request = {
      id: expired.id, open: false, status: "expired", statusLabel: CONSENT_REQUEST_STATUS_LABEL.expired ?? "Expired",
      channel: expired.channel, channelLabel: CONSENT_CHANNEL_LABEL[expired.channel] ?? expired.channel,
      countdown: "expired", expiresAt: expired.expires_at, programme: expired.programme, context: expired.context, createdAt: expired.created_at,
    };
  }
  const hasRequest = Boolean(open || expired || pc?.last_request);
  const isGiven = Boolean(pc?.given ?? r.consent);
  const refused = Boolean(pc?.refused);

  let askWhy: string | null = null;
  if (isGiven) askWhy = "Consent is already recorded";
  else if (open) askWhy = "A request is already open";
  else if (r.is_test) askWhy = "Test leads are not asked";
  else if (r.bar) askWhy = "Partner-barred: consent would not change where this lead goes";

  let yesWhy: string | null = null;
  if (!opts.adminYes) yesWhy = "Recording a YES given on a call is off (engine setting consent_admin_yes)";
  else if (isGiven) yesWhy = "Consent is already recorded";
  else if (!hasRequest) yesWhy = "There is no consent request to answer: ask for consent first";

  let noWhy: string | null = null;
  if (refused) noWhy = "A refusal is already recorded";
  else if (!hasRequest) noWhy = "There is no consent request to answer: ask for consent first";

  return {
    state, label: CONSENT_STATE_LABEL[state] ?? state, tone: consentTone(state),
    given, refusedAt: pc?.refused_at ?? null, stampUncovered: Boolean(pc?.stamp_uncovered),
    ledger: r.consent_detail?.ledger ?? [],
    request,
    canAsk: askWhy === null, askWhy,
    canRecordYes: yesWhy === null, yesWhy,
    canRecordNo: noWhy === null, noWhy,
  };
}

// ---------- lost grace ----------

export type GraceInfo = {
  allocationId: number; reference: string | null; partner: string | null; lostAt: string; graceUntil: string | null; lostReason: string | null;
  inGrace: boolean; revived: boolean; revivedAt: string | null; lostCount: number | null;
  /** Time left in the grace while it runs, 'ended' once the grace tick is due, null after a revival. */
  remaining: string | null;
};

/** PART 6.1 / D34: the current partner allocation marked lost, with the countdown to the hand-off to B2C nurture. */
export function graceCountdown(r: LeadRouting, now: number = Date.now()): GraceInfo | null {
  const g = r.lost_grace;
  if (!g) return null;
  const inGrace = Boolean(g.in_grace && !g.revived);
  return {
    allocationId: g.allocation_id, reference: g.reference, partner: allocationById(r, g.allocation_id)?.partner_name ?? null,
    lostAt: g.lost_at, graceUntil: g.grace_until, lostReason: g.lost_reason, inGrace, revived: g.revived, revivedAt: g.revived_at, lostCount: g.lost_count,
    remaining: inGrace ? remainingText(g.grace_until, now) ?? "no end date" : null,
  };
}

// ---------- qualification nurture ----------

/** lead_class.missing codes (m31d) in words. */
export const MISSING_LABEL: Record<string, string> = {
  no_name: "name",
  no_email: "email",
  no_course: "course",
  witty_unconfirmed: "Witty has not confirmed the details (no HOT / WARM / COLD)",
  no_valid_contact: "a valid phone or email",
  phone_not_verified: "a verified phone",
  partner_consent: "partner-sharing consent",
};
export const missingText = (codes: string[] | null | undefined): string[] => (codes ?? []).map((c) => MISSING_LABEL[c] ?? c.replace(/_/g, " "));

export type NurtureSummary = {
  /** B2C holds the lead in qualification nurture now (R7, consent_no_answer). */
  active: boolean;
  reason: string | null;
  missing: string[];
  lastCheck: string | null;
  nextCheck: string | null;
  times: number;
  qualifiedAt: string | null;
  reengagedAt: string | null;
  awaitingConsent: boolean;
};

/** R7 → R9 (D15): what B2C still has to get, and when the re-decision last ran. Null when the lead is not in nurture and
 *  was never watched. */
export function nurtureSummary(r: LeadRouting): NurtureSummary | null {
  const active = Boolean(r.hold?.open && r.hold.kind === "qualification_nurture");
  const w = r.nurture_watch;
  if (!active && !w) return null;
  const codes = (w?.missing && w.missing.length > 0 ? w.missing : r.readiness.not_qualified) ?? [];
  return {
    active,
    reason: active ? reasonLabel(r.hold?.reason) : null,
    missing: missingText(codes),
    lastCheck: w?.checked_at ?? null,
    nextCheck: w?.recheck_at ?? null,
    times: w?.times ?? 0,
    qualifiedAt: w?.qualified_at ?? null,
    reengagedAt: w?.reengaged_at ?? null,
    awaitingConsent: Boolean(w?.consent_request_id) && !r.consent,
  };
}

// ---------- readiness, holds, outlook ----------

/** The readiness line: "Waiting for 18 h without a student message · decides 8 Oct, 09:30", "Awaiting partner-sharing consent …",
 *  "Still chatting …"; null when the lead is ready or routed. */
export function waitText(r: LeadRouting): string | null {
  const w = r.readiness.wait;
  const until = w?.until ?? r.readiness.decide_after ?? null;
  const suffix = until ? ` · decides ${formatDateTime(until)}` : "";
  if (w?.kind === "inactivity") return `Waiting for ${w.hours ?? 18} h without a student message${suffix}`;
  if (w?.kind === "consent") return `Awaiting partner-sharing consent${suffix}`;
  if (w?.kind === "chatting") return `Still chatting${suffix}`;
  if (!r.readiness.ready && r.readiness.missing.length > 0) return r.readiness.missing.join(", ");
  return null;
}

/** "With B2C sales · Sent to B2C by the Admin" from b2c_hold; null when B2C does not hold the lead. */
export function holdText(r: LeadRouting): string | null {
  const h = r.hold;
  if (!h) return null;
  const parts = [HOLD_LABEL[h.kind] ?? h.kind];
  if (h.reason) parts.push(reasonLabel(h.reason));
  if (!h.open) parts.push("closed");
  return parts.join(" · ");
}

/** Where the lead would go at its decision point (route_outlook), with the reason when it has one. */
export function outlookText(r: LeadRouting): string {
  const o = r.outlook;
  if (!o) return "—";
  const base = OUTLOOK_LABEL[o.outlook] ?? o.outlook;
  return o.reason ? `${base} · ${reasonLabel(o.reason)}` : base;
}

// ---------- re-enquiries, allocations ----------

/** D18: who held the lead when the student enquired again. */
export function reenquiryHolderText(q: Pick<Reenquiry, "holder" | "partner_name">): string {
  switch (q.holder) {
    case "partner": return `while with ${q.partner_name ?? "a partner"}`;
    case "b2c_selling": return "while with B2C sales";
    case "barred": return "while partner-barred, with B2C";
    case "qualification_nurture": return "while in B2C qualification nurture";
    default: return "";
  }
}

/** "New enquiries while with Acme" for the section title (the holder of the most recent re-enquiry). */
export function reenquiriesTitle(rows: Pick<Reenquiry, "holder" | "partner_name">[]): string {
  const first = rows[0];
  return first ? `New enquiries ${reenquiryHolderText(first)}` : "New enquiries";
}

/** allocations.origin (m31a0, CONTRACT 1.1). */
export const ORIGIN_LABEL: Record<string, string> = {
  auto: "automatic",
  pass: "passed to a CRM",
  to_partners: "sent to partners by hand",
  requalify: "requalified",
  reroute: "Admin re-route",
  sandbox: "test",
};

/** The status badge of an allocation row: lost in grace, lost, or the status label. */
export function allocationStatusText(a: Pick<AllocationRow, "status" | "outcome" | "lost_at" | "lost_revived_at">): string {
  if (a.outcome === "lost") return "Lost at partner";
  if (a.lost_at && !a.lost_revived_at && ["pushed", "accepted"].includes(a.status)) return "Lost, in grace";
  return ALLOCATION_LABEL[a.status] ?? a.status;
}
