import { scrub } from "@/lib/security/scrub";

/**
 * The only analytics events the site sends (spec 9.1A, 13.3). Parameters are allow-listed per event and scrubbed;
 * personal data never reaches GA4, Meta or Clarity.
 */
export const EVENTS = {
  search: ["query_length", "results", "zero_results", "parsed_filters"],
  filter_apply: ["facet", "value_count"],
  programme_view: ["programme", "specialisation", "level"],
  offering_view: ["offering_id", "programme", "university_id"],
  compare_add: ["offering_id", "count"],
  shortlist_add: ["offering_id", "count"],
  advisor_gate_open: ["surface"],
  gate_submitted: ["surface"],
  email_code_sent: ["surface", "resend"],
  email_verified: ["surface"],
  advisor_message: ["turn", "mode"],
  lead_created: ["surface", "event_id"],
  counsellor_click: ["surface", "channel"],
  callback_booked: ["surface"],
  form_view: ["form", "offering_id"],
  form_step_complete: ["form", "step"],
  form_submit: ["form", "offering_id", "event_id"],
  hero_view: ["variant"],
  panel_open: ["kind"],
} as const;

export type EventName = keyof typeof EVENTS;
export type EventParams = Record<string, string | number | boolean | undefined>;

/** Keeps only the allow-listed parameters for the event, scrubbed and length-limited. */
export function sanitiseEvent(name: EventName, params: EventParams = {}): Record<string, string | number | boolean> {
  const allowedKeys = EVENTS[name] as readonly string[];
  const out: Record<string, string | number | boolean> = {};
  for (const k of allowedKeys) {
    const v = params[k];
    if (v === undefined || v === null) continue;
    out[k] = typeof v === "string" ? scrub(v).slice(0, 100) : v;
  }
  return out;
}

/** Funnel steps recorded server-side for the admin insights (spec 11). */
export const FUNNEL_STEPS: Partial<
  Record<EventName, { funnel: "gate" | "form" | "enquiry" | "finder"; step: string }>
> = {
  hero_view: { funnel: "gate", step: "hero_view" },
  advisor_gate_open: { funnel: "gate", step: "gate_open" },
  gate_submitted: { funnel: "gate", step: "gate_submitted" },
  email_code_sent: { funnel: "gate", step: "email_code_sent" },
  email_verified: { funnel: "gate", step: "email_verified" },
  advisor_message: { funnel: "gate", step: "first_message" },
  panel_open: { funnel: "form", step: "panel_open" },
  form_view: { funnel: "form", step: "form_start" },
  form_step_complete: { funnel: "form", step: "step" },
  form_submit: { funnel: "form", step: "submitted" },
};
