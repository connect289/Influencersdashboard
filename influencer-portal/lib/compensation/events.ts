// The event stream the engine replays (spec 6.3). Events come from deliverables, contracts, attribution, the CRMs'
// enrolment and commission data, and admin actions; Phase 7's runner turns domain events into these.
import { z } from "zod";

const ref = z.string().min(1).max(80);
const base = { id: z.string().min(1).max(120), at: z.iso.datetime({ offset: true }) };

export const engineEvent = z.discriminatedUnion("type", [
  z.object({ ...base, type: z.literal("contract_signed") }),
  z.object({ ...base, type: z.literal("brief_acknowledged") }),
  z.object({ ...base, type: z.literal("concept_approved"), deliverable: ref }),
  z.object({ ...base, type: z.literal("draft_approved"), deliverable: ref }),
  z.object({ ...base, type: z.literal("deliverable_due"), deliverable: ref, due_at: z.iso.datetime({ offset: true }) }),
  z.object({ ...base, type: z.literal("deliverable_live"), deliverable: ref }),
  z.object({ ...base, type: z.literal("deliverable_cancelled"), deliverable: ref }),
  /** Cumulative metric reading (views or reach) for a deliverable. */
  z.object({
    ...base,
    type: z.literal("metric"),
    deliverable: ref,
    metric: z.enum(["views", "reach"]),
    value: z.number().int().min(0),
  }),
  z.object({
    ...base,
    type: z.literal("lead"),
    lead: ref,
    link: ref.optional(),
    deliverable: ref.optional(),
    programme_id: z.number().int().optional(),
    university_id: z.number().int().optional(),
    level: z.string().max(20).optional(),
    junk: z.boolean().default(false),
    duplicate: z.boolean().default(false),
  }),
  z.object({ ...base, type: z.literal("lead_qualified"), lead: ref }),
  z.object({ ...base, type: z.literal("lead_applied"), lead: ref }),
  z.object({ ...base, type: z.literal("lead_rejected"), lead: ref }),
  z.object({
    ...base,
    type: z.literal("enrolled"),
    lead: ref,
    enrollment: ref,
    programme_id: z.number().int().optional(),
    university_id: z.number().int().optional(),
    level: z.string().max(20).optional(),
    link: ref.optional(),
    deliverable: ref.optional(),
    fee_paise: z.number().int().min(0).optional(),
    /** Eduwit's expected commission on this enrolment, GST-inclusive (from the catalogue's partner rates). */
    expected_commission_gross_paise: z.number().int().min(0).optional(),
  }),
  z.object({ ...base, type: z.literal("enrollment_cancelled"), enrollment: ref }),
  /** Eduwit's partner commission received for an enrolment (GST-inclusive). `full` marks the final receipt. */
  z.object({
    ...base,
    type: z.literal("commission_received"),
    enrollment: ref,
    gross_paise: z.number().int().min(0),
    full: z.boolean(),
  }),
  z.object({ ...base, type: z.literal("campaign_ended") }),
  z.object({ ...base, type: z.literal("deal_completed") }),
  /** Admin releases a manual milestone: "<component id>.<milestone id>". */
  z.object({ ...base, type: z.literal("manual_release"), milestone: ref }),
  z.object({ ...base, type: z.literal("leaderboard_rank"), window: ref, rank: z.number().int().min(1) }),
  z.object({ ...base, type: z.literal("disclosure_flag"), deliverable: ref }),
  z.object({ ...base, type: z.literal("breach") }),
]);
export type EngineEvent = z.infer<typeof engineEvent>;
export type EngineEventInput = z.input<typeof engineEvent>;

// IST helpers (India has no daylight saving: always UTC+05:30).
const IST_MS = 330 * 60_000;
const DAY_MS = 86_400_000;

export function istDate(iso: string): string {
  return new Date(Date.parse(iso) + IST_MS).toISOString().slice(0, 10);
}
export function istMonth(iso: string): string {
  return istDate(iso).slice(0, 7);
}
/** Midnight IST at the start of a date, as an ISO instant. */
export function istMidnight(date: string): string {
  return new Date(Date.parse(`${date}T00:00:00.000Z`) - IST_MS).toISOString();
}
export function addDays(date: string, n: number): string {
  return new Date(Date.parse(`${date}T00:00:00.000Z`) + n * DAY_MS).toISOString().slice(0, 10);
}
export function addMs(iso: string, ms: number): string {
  return new Date(Date.parse(iso) + ms).toISOString();
}
export function addMonths(date: string, n: number): string {
  const [y, m, d] = date.split("-").map(Number) as [number, number, number];
  const target = new Date(Date.UTC(y, m - 1 + n, 1));
  const last = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(d, last));
  return target.toISOString().slice(0, 10);
}
export function nextMonth(month: string): string {
  return addMonths(`${month}-01`, 1).slice(0, 7);
}
export const DAY = DAY_MS;
