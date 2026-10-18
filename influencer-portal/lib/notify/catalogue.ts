// The notification event catalogue (spec 14): every event the portal sends, who receives it, whether it can be turned
// off, which channels it uses by default and the variables its templates may use. The database copy
// (inf.notification_events) is generated from this file by `npm run gen:sql`, and inf.notify() treats an event as
// mandatory when either the caller or this catalogue says so. Pure.

export const CHANNELS = ["in_app", "email", "whatsapp"] as const;
export type Channel = (typeof CHANNELS)[number];
export const DELIVERY_CHANNELS = ["email", "whatsapp"] as const;
export type DeliveryChannel = (typeof DELIVERY_CHANNELS)[number];

export const EVENT_GROUPS = [
  "account",
  "campaigns",
  "deals",
  "contracts",
  "content",
  "leads",
  "money",
  "messages",
  "announcements",
  "staff",
] as const;
export type EventGroup = (typeof EVENT_GROUPS)[number];

export type Audience = "creator" | "agency" | "staff";

export interface EventDef {
  group: EventGroup;
  audience: readonly Audience[];
  /** Cannot be turned off (spec 14: contract and payout events, and others that carry obligations). */
  mandatory: boolean;
  /** Channels besides in-app that a new user receives by default. */
  channels: readonly DeliveryChannel[];
  /** Event-specific template variables, in addition to the common ones. */
  vars: readonly string[];
}

/** Variables every template may use. */
export const COMMON_VARS = ["name", "title", "body", "link"] as const;

const e = (
  group: EventGroup,
  audience: readonly Audience[],
  opts: { mandatory?: boolean; channels?: readonly DeliveryChannel[]; vars?: readonly string[] } = {},
): EventDef => ({
  group,
  audience,
  mandatory: opts.mandatory ?? false,
  channels: opts.channels ?? ["email"],
  vars: opts.vars ?? [],
});

const C = ["creator"] as const;
const CA = ["creator", "agency"] as const;
const S = ["staff"] as const;
const ALL = ["creator", "agency", "staff"] as const;
const EW = ["email", "whatsapp"] as const;

export const EVENTS = {
  // Account
  "creator.approved": e("account", C, { channels: EW }),
  "creator.onboarding_changes": e("account", C),
  "creator.onboarding_submitted": e("account", S),
  "kyc.reviewed": e("account", C, { mandatory: true }),
  "kyc.action_needed": e("account", C, { mandatory: true, channels: EW }),
  "agency.link_requested": e("account", C),
  "task.assigned": e("account", S),
  // Campaigns
  "campaign.invited": e("campaigns", CA, { channels: EW, vars: ["campaign"] }),
  "application.submitted": e("campaigns", S, { vars: ["campaign"] }),
  "application.shortlisted": e("campaigns", CA, { vars: ["campaign"] }),
  "application.countered": e("campaigns", ALL, { vars: ["campaign"] }),
  "application.accepted": e("campaigns", ALL, { channels: EW, vars: ["campaign"] }),
  "application.rejected": e("campaigns", CA, { vars: ["campaign"] }),
  "application.message": e("campaigns", ALL, { vars: ["campaign"] }),
  // Deals
  "deal.created": e("deals", S),
  "deal.proposed": e("deals", CA, { channels: EW, vars: ["deal"] }),
  "deal.accepted": e("deals", S, { vars: ["deal"] }),
  "deal.declined": e("deals", S, { vars: ["deal"] }),
  "deal.proposal_withdrawn": e("deals", CA, { vars: ["deal"] }),
  "deal.amendment_proposed": e("deals", CA, { channels: EW, vars: ["deal"] }),
  // Contracts (mandatory where the creator has something to do or a legal record changes)
  "contract.sent": e("contracts", CA, { mandatory: true, channels: EW, vars: ["contract"] }),
  "contract.updated": e("contracts", CA, { mandatory: true, vars: ["contract"] }),
  "contract.comment": e("contracts", ALL, { vars: ["contract"] }),
  "contract.change_requested": e("contracts", S, { vars: ["contract"] }),
  "contract.change_rejected": e("contracts", CA, { vars: ["contract"] }),
  "contract.ready": e("contracts", CA, { mandatory: true, channels: EW, vars: ["contract"] }),
  "contract.creator_signed": e("contracts", S, { vars: ["contract"] }),
  "contract.awaiting_countersign": e("contracts", S, { mandatory: true, vars: ["contract"] }),
  "contract.active": e("contracts", ALL, { mandatory: true, channels: EW, vars: ["contract"] }),
  "contract.reminder": e("contracts", CA, { channels: EW, vars: ["contract"] }),
  "contract.deadline_passed": e("contracts", ALL, { vars: ["contract"] }),
  "contract.expiring": e("contracts", ALL, { mandatory: true, vars: ["contract"] }),
  // Briefs and deliverables
  "brief.published": e("content", CA, { channels: EW, vars: ["deal"] }),
  "brief.updated": e("content", CA, { vars: ["deal"] }),
  "brief.acknowledged": e("content", S, { vars: ["deal"] }),
  "brief.question": e("content", ALL, { vars: ["deal"] }),
  "deliverable.submitted": e("content", S, { vars: ["deliverable"] }),
  "deliverable.due": e("content", CA, { channels: EW, vars: ["deliverable"] }),
  "deliverable.overdue": e("content", ALL, { channels: EW, vars: ["deliverable"] }),
  "deliverable.changes_requested": e("content", CA, { channels: EW, vars: ["deliverable"] }),
  "deliverable.approved": e("content", CA, { vars: ["deliverable"] }),
  "deliverable.comment": e("content", ALL, { vars: ["deliverable"] }),
  "deliverable.extension_requested": e("content", S, { vars: ["deliverable"] }),
  "deliverable.live": e("content", S, { vars: ["deliverable"] }),
  "deliverable.live_rejected": e("content", CA, { vars: ["deliverable"] }),
  "deliverable.verified": e("content", CA, { vars: ["deliverable"] }),
  "deliverable.metrics_due": e("content", CA, { vars: ["deliverable"] }),
  "deliverable.metrics_overdue": e("content", ALL, { vars: ["deliverable"] }),
  "penalty.approved": e("money", CA, { mandatory: true, vars: ["amount"] }),
  // Leads (never any student contact details)
  "lead.new": e("leads", C, { channels: [], vars: ["lead"] }),
  "lead.enrolled": e("leads", C, { channels: EW, vars: ["lead", "amount"] }),
  "lead.clawed_back": e("leads", C, { mandatory: true, vars: ["lead", "amount"] }),
  // Money
  "ledger.payable": e("money", C, { mandatory: true, vars: ["amount"] }),
  "payout.paid": e("money", C, { mandatory: true, channels: EW, vars: ["amount", "utr"] }),
  "invoice.rejected": e("money", C, { mandatory: true }),
  "tds.certificate": e("money", C, { mandatory: true }),
  // Messages
  "thread.message": e("messages", ALL, { vars: ["subject", "sender"] }),
  "thread.mention": e("messages", S, { vars: ["subject", "sender"] }),
  // Tiers and privacy
  "tier.changed": e("account", C, { vars: ["tier"] }),
  "privacy.export_ready": e("account", C, { mandatory: true }),
  "privacy.request_update": e("account", C, { mandatory: true }),
  "staff.privacy_request": e("staff", S),
  // Announcements and digests
  announcement: e("announcements", C, { vars: [] }),
  "digest.creator": e("announcements", C, { vars: [] }),
  "digest.staff": e("announcements", S, { vars: [] }),
  // Staff queues
  "fraud.flagged": e("staff", S, { vars: ["creator"] }),
  "staff.negotiation_pending": e("staff", S, { vars: ["count"] }),
  "staff.review_pending": e("staff", S, { vars: ["count"] }),
} as const satisfies Record<string, EventDef>;

export type EventKey = keyof typeof EVENTS;
export const EVENT_KEYS = Object.keys(EVENTS) as EventKey[];

export function eventDef(key: string): EventDef | null {
  return (EVENTS as Record<string, EventDef>)[key] ?? null;
}

/** Every variable a template for this event may use. */
export function allowedVars(key: string): string[] {
  return [...COMMON_VARS, ...(eventDef(key)?.vars ?? [])];
}

/** Events a person of this audience can receive (for their preferences page). */
export function eventsFor(audience: Audience): EventKey[] {
  return EVENT_KEYS.filter((k) => EVENTS[k].audience.includes(audience));
}

export interface Preference {
  event: string;
  channel: Channel;
  enabled: boolean;
}

/**
 * Whether a channel is on for an event, as inf.notify() decides: in-app is always on; a mandatory event always uses
 * its default channels (and any other the person switched on); otherwise the person's choice, falling back to the
 * catalogue default.
 */
export function channelOn(key: string, channel: Channel, prefs: readonly Preference[]): boolean {
  if (channel === "in_app") return true;
  const def = eventDef(key);
  const isDefault = (def?.channels ?? ["email"]).includes(channel);
  const p = prefs.find((x) => x.event === key && x.channel === channel);
  if (def?.mandatory) return isDefault || p?.enabled === true;
  return p ? p.enabled : isDefault;
}

/** Whether the person may change a channel for an event (in-app and a mandatory event's default channels are fixed). */
export function channelLocked(key: string, channel: Channel): boolean {
  if (channel === "in_app") return true;
  const def = eventDef(key);
  return def?.mandatory === true && (def.channels as readonly string[]).includes(channel);
}
