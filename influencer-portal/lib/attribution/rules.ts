// Attribution rules (spec 9.2, all configurable). Given one lead's facts and the creator touches found for it, decide
// which creator is credited and why the others are not. Pure and deterministic: the sweep, the backfill tool and the
// admin "re-run" all call this, and manual decisions by staff are never overwritten.
//
// A touch is a creator code seen for the lead: a link click (Route A access code), a typed code (Route B referral
// code), or a code in the lead's touchpoint attribution. For each touch:
//   1. self-referral: the lead's phone or email matches the creator's own or a flagged family contact → self_referral
//   2. duplicate: the lead already existed before the touch (beyond a short grace) → duplicate, unless the lead
//      re-enquired after the configured gap (then the re-enquiry is the lead moment)
//   3. window: the lead appeared more than N days after the touch → outside_window
//   4. otherwise eligible.
// Among eligible creators the model picks the winner: first touch (earliest), last touch (latest), or first touch with
// the others recorded as assisted (not paid). At most one creator is credited per lead.

export const ATTRIBUTION_STATUSES = [
  "credited",
  "duplicate",
  "outside_window",
  "self_referral",
  "fraud_suspected",
  "manually_rejected",
  "manually_credited",
] as const;
export type AttributionStatus = (typeof ATTRIBUTION_STATUSES)[number];

/** Statuses staff or the fraud review set; a re-run never changes them. */
export const STICKY: readonly AttributionStatus[] = [
  "fraud_suspected",
  "manually_rejected",
  "manually_credited",
];

export const REASONS = [
  "existing_lead",
  "another_creator",
  "outside_window",
  "self_referral",
] as const;
export type Reason = (typeof REASONS)[number];

export type TouchKind = "first" | "last" | "assisted" | "none";
export type EvidenceSource = "click" | "referral_code" | "touchpoint" | "access_code";
export type Model = "first_touch" | "last_touch" | "first_touch_with_assisted";

export interface Touch {
  code: string;
  link_id: string;
  creator_id: string;
  deal_id: string | null;
  deliverable_id: string | null;
  campaign_id: string | null;
  /** When the creator touch happened (the click, or the message carrying the code). */
  at: string;
  source: EvidenceSource;
}

export interface LeadFacts {
  created_at: string;
  /** When a closed lead came back (a new enquiry cycle), if it did. */
  reopened_at: string | null;
  touches: readonly Touch[];
  /** Creators whose own (or flagged family) phone or email matches the lead. */
  self_referral_creators: readonly string[];
}

export interface Rules {
  window_days: number;
  model: Model;
  duplicate_grace_minutes: number;
  /** A lead that re-enquires at least this many days after it first appeared can be credited to a new touch; null = never. */
  reenquiry_credit_after_days: number | null;
}

export interface Existing {
  creator_id: string;
  status: AttributionStatus;
}

export interface Decision {
  creator_id: string;
  link_id: string;
  code: string;
  deal_id: string | null;
  deliverable_id: string | null;
  campaign_id: string | null;
  touch: TouchKind;
  status: AttributionStatus;
  reason: Reason | null;
  touch_at: string;
  evidence_source: EvidenceSource;
}

const MIN = 60_000;
const DAY = 86_400_000;
const ms = (iso: string) => Date.parse(iso);

type Judged = {
  touch: Touch;
  status: "eligible" | "duplicate" | "outside_window" | "self_referral";
  reason: Reason | null;
};

function judge(t: Touch, lead: LeadFacts, r: Rules): Judged {
  if (lead.self_referral_creators.includes(t.creator_id))
    return { touch: t, status: "self_referral", reason: "self_referral" };
  const grace = r.duplicate_grace_minutes * MIN;
  let leadAt = ms(lead.created_at);
  if (leadAt < ms(t.at) - grace) {
    // The lead existed before this touch. A re-enquiry after the configured gap counts as a new lead moment.
    const reopened = lead.reopened_at ? ms(lead.reopened_at) : null;
    const gapOk =
      r.reenquiry_credit_after_days !== null &&
      reopened !== null &&
      reopened - leadAt >= r.reenquiry_credit_after_days * DAY &&
      reopened >= ms(t.at) - grace;
    if (!gapOk) return { touch: t, status: "duplicate", reason: "existing_lead" };
    leadAt = reopened;
  }
  if (leadAt - ms(t.at) > r.window_days * DAY)
    return { touch: t, status: "outside_window", reason: "outside_window" };
  return { touch: t, status: "eligible", reason: null };
}

const byTime = (a: Touch, b: Touch) => ms(a.at) - ms(b.at) || a.code.localeCompare(b.code);

function decision(
  t: Touch,
  touch: TouchKind,
  status: AttributionStatus,
  reason: Reason | null,
): Decision {
  return {
    creator_id: t.creator_id,
    link_id: t.link_id,
    code: t.code,
    deal_id: t.deal_id,
    deliverable_id: t.deliverable_id,
    campaign_id: t.campaign_id,
    touch,
    status,
    reason,
    touch_at: t.at,
    evidence_source: t.source,
  };
}

/** One decision per creator who touched the lead, ordered by touch time. */
export function decide(lead: LeadFacts, r: Rules, existing: readonly Existing[] = []): Decision[] {
  const judged = lead.touches.map((t) => judge(t, lead, r));
  // Per creator: their best touch (an eligible one if any; the earliest for first-touch models, the latest for last).
  const creators = [...new Set(judged.map((j) => j.touch.creator_id))];
  const best = creators.map((c) => {
    const mine = judged.filter((j) => j.touch.creator_id === c);
    const eligible = mine
      .filter((j) => j.status === "eligible")
      .sort((a, b) => byTime(a.touch, b.touch));
    if (eligible.length)
      return r.model === "last_touch" ? (eligible.at(-1) as Judged) : (eligible[0] as Judged);
    return [...mine].sort((a, b) => byTime(a.touch, b.touch))[0] as Judged;
  });
  // A creator staff rejected for this lead can't win it; the credit goes to the next eligible creator.
  const rejected = new Set(
    existing.filter((e) => e.status === "manually_rejected").map((e) => e.creator_id),
  );
  const eligible = best
    .filter((j) => j.status === "eligible" && !rejected.has(j.touch.creator_id))
    .sort((a, b) => byTime(a.touch, b.touch));
  const winner = r.model === "last_touch" ? eligible.at(-1) : eligible[0];

  let out = best.map((j): Decision => {
    if (j.status !== "eligible") return decision(j.touch, "none", j.status, j.reason);
    if (j === winner)
      return decision(j.touch, r.model === "last_touch" ? "last" : "first", "credited", null);
    if (rejected.has(j.touch.creator_id))
      return decision(j.touch, "none", "manually_rejected", null);
    if (r.model === "first_touch_with_assisted")
      return decision(j.touch, "assisted", "credited", null);
    return decision(j.touch, "none", "duplicate", "another_creator");
  });

  // Staff decisions and open fraud reviews stand; a manual credit takes the lead's credit from everyone else.
  const sticky = new Map(
    existing.filter((e) => STICKY.includes(e.status)).map((e) => [e.creator_id, e.status]),
  );
  const manualWinner = existing.find((e) => e.status === "manually_credited")?.creator_id ?? null;
  out = out.map((d) => {
    const s = sticky.get(d.creator_id);
    if (s)
      return {
        ...d,
        status: s,
        touch: s === "manually_rejected" ? "none" : d.touch === "none" ? "first" : d.touch,
      };
    if (manualWinner && d.status === "credited" && d.touch !== "assisted")
      return { ...d, touch: "none", status: "duplicate", reason: "another_creator" };
    return d;
  });
  return out.sort(
    (a, b) => ms(a.touch_at) - ms(b.touch_at) || a.creator_id.localeCompare(b.creator_id),
  );
}

/** The decision that earns the lead (credited first/last touch, or a manual credit), if any. */
export function creditHolder(ds: readonly Decision[]): Decision | null {
  return (
    ds.find((d) => d.status === "manually_credited") ??
    ds.find((d) => d.status === "credited" && (d.touch === "first" || d.touch === "last")) ??
    null
  );
}
