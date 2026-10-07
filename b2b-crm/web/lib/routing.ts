import { z } from "zod";
import type { ScoringMode } from "@/lib/segments";

/** Routing: labels, decision types and form parsing shared by the routing screen, the lead drawer and the tests. */

export const REASON_LABEL: Record<string, string> = {
  no_partner_consent: "No partner-sharing consent",
  no_partner_offers_programme: "No partner offers this programme",
  no_capacity: "Every eligible partner is excluded or at capacity",
  duplicate_cascade: "Duplicate or rejection limit reached",
  partners_unreachable: "Partner attempt limit reached",
  import_choice: "Import chose B2C",
  manual: "Sent to B2C by the Admin",
  paid_campaign: "Paid campaign",
  b2c_created: "Created in the B2C CRM",
  not_qualified: "Not qualified",
  partner_lost: "Partner marked it lost",
  manual_route_failed: "Sent to partners by hand, none could take it",
  b2c_held: "Already with B2C",
  rule: "Routing rule",
};

/** Why a lead is not passed to any CRM (Addendum 2). */
export const NOT_PASSED_LABEL: Record<string, string> = {
  junk: "Junk (Witty)",
  program_mismatch: "Programme mismatch",
  invalid_phone: "Invalid phone",
  blocked_phone: "Blocked phone",
};

export const LANE_LABEL: Record<string, string> = { sales: "B2C sales", nurture: "B2C nurture" };

export const MODE_LABEL: Record<string, string> = {
  commission_first: "Highest commission",
  exploration: "Exploration lane",
  minimum: "Contract minimum",
  rule: "Routing rule",
  manual: "Manual",
  fallback: "B2C fallback",
  performance: "Performance",
  holdout: "Holdout",
};

export const ACTION_LABEL: Record<string, string> = { fix_partner: "Always send to", narrow: "Only consider", exclude: "Never send to", to_b2c: "Send to B2C" };

export const ALLOCATION_LABEL: Record<string, string> = {
  queued: "Queued for push",
  pushing: "Pushing",
  pushed: "Pushed, hold window",
  accepted: "Accepted",
  duplicate: "Duplicate",
  rejected: "Rejected",
  failed: "Push failed",
  recalled: "Recalled",
  handed_off: "Handed to B2C",
  closed: "Closed",
};

export type Interest = {
  course_key: string | null;
  specialization: string | null;
  level: string | null;
  mode: string | null;
  university_id: number | null;
  university_text: string | null;
  segment: string;
};

export type Candidate = {
  partner_id: number;
  name: string;
  status: string;
  offers: number;
  cpe: number | null;
  has_rate: boolean;
  ncpl: number | null;
  daily_cap: number | null;
  monthly_cap: number | null;
  leads_today: number;
  leads_month: number;
  leads_week: number;
  segment_leads: number;
  eligible: boolean;
  /** M24 statistics (absent on decisions made before performance routing). */
  p_hat?: number; alpha?: number; beta?: number; refund_rate?: number; sla_compliance?: number | null; speed?: number; reliability?: number;
  weight?: number; win_share?: number; stats_segment?: string | null; stats_rollup?: boolean; matured_in_segment?: number; leads_in_segment?: number;
};

export type Decision = {
  lead_id: number;
  is_test: boolean;
  readiness: { ready: boolean; missing: string[]; is_test: boolean; class?: string; class_reason?: string | null; not_qualified?: string[]; paid?: string | null };
  interest: Interest;
  destination: "partner" | "in_house" | "not_passed";
  b2c_lane?: "sales" | "nurture" | null;
  /** Why a manual route to partners failed (the fallback it hit). */
  cause?: string | null;
  /** What made the lead a paid-campaign lead. */
  paid?: string | null;
  reason: string | null;
  mode: string;
  partner_id: number | null;
  partner_name: string | null;
  cpe: number | null;
  has_rate: boolean | null;
  candidates: Candidate[];
  excluded: { partner_id: string; name: string; why: string }[];
  rules: { id: number; name: string; action: string; effect: string }[];
  draw: number | null;
  exploration_share: number;
  selection_probability: number;
  already_routed: boolean;
  committed: boolean;
  reference?: string;
  /** M24: scoring mode, AI holdout, seed (replay), policy version, pin and Monte Carlo draws. */
  scoring_mode?: ScoringMode | null;
  holdout?: boolean;
  seed?: number | null;
  policy_version?: number | null;
  pinned?: boolean;
  mc_draws?: number | null;
  why?: string | null;
};

/** A decision as stored in b2b.engine_decisions (routing_decision / lead_routing). */
export type StoredDecisionCore = {
  lead_id: number; is_test: boolean; interest: Interest; destination_type: "partner" | "in_house"; reason: string | null; mode: string; b2c_lane?: "sales" | "nurture" | null;
  winner_partner_id: number | null; partner_name: string | null; candidates: Candidate[] | null; excluded: Decision["excluded"] | null;
  rules: Decision["rules"] | null; selection_probability: number | null; allocation: { reference: string; cpe_net_inr: number | null } | null;
  scoring_mode?: ScoringMode | null; holdout?: boolean; seed?: number | null; policy_version?: number | null;
};

/** A stored decision in the shape DecisionView shows. Readiness and the exploration lane are not stored, so they are left out. */
export function fromStored(s: StoredDecisionCore): Decision {
  const candidates = s.candidates ?? [];
  const won = candidates.find((c) => c.partner_id === s.winner_partner_id);
  return {
    lead_id: s.lead_id, is_test: s.is_test, readiness: { ready: true, missing: [], is_test: s.is_test }, interest: s.interest,
    destination: s.destination_type, b2c_lane: s.b2c_lane ?? null, reason: s.reason, mode: s.mode, partner_id: s.winner_partner_id, partner_name: s.partner_name,
    cpe: s.allocation?.cpe_net_inr ?? won?.cpe ?? null, has_rate: won?.has_rate ?? null, candidates, excluded: s.excluded ?? [], rules: s.rules ?? [],
    draw: null, exploration_share: 0, selection_probability: Number(s.selection_probability ?? 1), already_routed: true, committed: true,
    reference: s.allocation?.reference,
    scoring_mode: s.scoring_mode ?? null, holdout: s.holdout ?? false, seed: s.seed ?? null, policy_version: s.policy_version ?? null,
  };
}

/** "mba|PG|Online" → "MBA · PG · Online"; unknown parts read as "any". */
export function segmentLabel(segment: string | null | undefined): string {
  if (!segment) return "—";
  const [course, level, mode] = segment.split("|");
  const part = (v: string | undefined, upper = false) => (!v || v === "*" || v === "?" ? "any" : upper ? v.toUpperCase() : v);
  return `${part(course, true)} · ${part(level)} · ${part(mode)}`;
}

// ---------- forms ----------

const list = (max = 50, chars = 2000) => z.string().max(chars).transform((v) => [...new Set(v.split(/[,\n]/).map((s) => s.trim()).filter(Boolean))].slice(0, max));

export const RuleSchema = z.object({
  id: z.string().regex(/^\d*$/).transform((v) => (v ? Number(v) : null)),
  name: z.string().trim().min(1, "Give the rule a name").max(120),
  priority: z.string().trim().regex(/^\d{1,4}$/, "A whole number").transform(Number),
  action: z.enum(["fix_partner", "narrow", "exclude", "to_b2c"]),
  partner_ids: z.array(z.string().regex(/^\d+$/)).max(50).transform((a) => a.map(Number)),
  b2c_lane: z.enum(["sales", "nurture"]).nullable(),
  sources: list(),
  course_keys: list().transform((a) => a.map((s) => s.toLowerCase().replace(/[^a-z0-9]/g, ""))),
  states: list(),
  modes: z.array(z.enum(["Online", "ODL", "Regular"])).max(3),
  levels: z.array(z.enum(["UG", "PG", "DIPLOMA", "CERTIFICATE"])).max(4),
  campaign_contains: z.string().trim().max(100),
});

/** The rule form → b2b.routing_rule_save payload (empty conditions are left out, so they match everything). */
export function parseRuleForm(form: FormData) {
  const get = (k: string) => (typeof form.get(k) === "string" ? (form.get(k) as string) : "");
  const parsed = RuleSchema.safeParse({
    id: get("id"), name: get("name"), priority: get("priority") || "100", action: get("action"),
    partner_ids: form.getAll("partner_ids").map(String), b2c_lane: get("b2c_lane") || null, sources: get("sources"), course_keys: get("course_keys"), states: get("states"),
    modes: form.getAll("modes").map(String), levels: form.getAll("levels").map(String), campaign_contains: get("campaign_contains"),
  });
  if (!parsed.success) {
    const errors: Record<string, string> = {};
    for (const i of parsed.error.issues) errors[String(i.path[0])] ??= i.message;
    return { ok: false as const, errors };
  }
  const d = parsed.data;
  if (d.action === "to_b2c" && !d.b2c_lane) return { ok: false as const, errors: { b2c_lane: "Choose sales or nurture" } };
  if (d.action !== "to_b2c" && d.partner_ids.length === 0) return { ok: false as const, errors: { partner_ids: "Choose at least one partner" } };
  const conditions: Record<string, unknown> = {};
  if (d.sources.length) conditions.sources = d.sources;
  if (d.course_keys.length) conditions.course_keys = d.course_keys;
  if (d.states.length) conditions.states = d.states;
  if (d.modes.length) conditions.modes = d.modes;
  if (d.levels.length) conditions.levels = d.levels;
  if (d.campaign_contains) conditions.campaign_contains = d.campaign_contains;
  const toB2c = d.action === "to_b2c";
  return { ok: true as const, data: { id: d.id, name: d.name, priority: d.priority, action: d.action, partner_ids: toB2c ? [] : d.partner_ids,
    b2c_lane: toB2c ? d.b2c_lane : null, conditions } };
}

/** Plain-language summary of a rule's conditions. */
export function describeConditions(c: Record<string, unknown>): string {
  const parts: string[] = [];
  const arr = (k: string) => (Array.isArray(c[k]) ? (c[k] as string[]) : []);
  if (arr("course_keys").length) parts.push(arr("course_keys").map((s) => s.toUpperCase()).join(" or "));
  if (arr("levels").length) parts.push(arr("levels").join(" or "));
  if (arr("modes").length) parts.push(arr("modes").join(" or "));
  if (arr("sources").length) parts.push(`from ${arr("sources").join(", ")}`);
  if (arr("states").length) parts.push(`in ${arr("states").join(", ")}`);
  if (typeof c.campaign_contains === "string" && c.campaign_contains) parts.push(`campaign contains “${c.campaign_contains}”`);
  return parts.length ? `Leads for ${parts.join(", ")}` : "Every lead";
}

export const EngineSchema = z.object({
  exploration_share: z.coerce.number().min(0).max(50).transform((v) => Math.round(v * 10) / 1000),
  cpe_aggregate: z.enum(["median", "mean", "max"]),
  min_learning_leads: z.coerce.number().int().min(1).max(1000),
  attempt_limit: z.coerce.number().int().min(1).max(5),
  partner_limit: z.coerce.number().int().min(1).max(5),
  witty_idle_minutes: z.coerce.number().int().min(5).max(1440),
  require_partner_consent: z.string().optional().transform((v) => v === "on"),
  trusted_sources: list(30),
  reason: z.string().trim().min(3, "Say why you are changing the engine").max(300),
});

/** Tiers as typed by the Admin, "conversion from %: rate %" pairs: "0: 22.42, 7: 20.42, 9: 18.42". Returns the list or what is wrong. */
export function parseTiers(text: string): { from_pct: number; pct: number }[] | string {
  const parts = text.split(/[,;\n]+/).map((x) => x.trim()).filter(Boolean);
  if (parts.length < 2 || parts.length > 10) return "Give 2 to 10 tiers, e.g. 0: 22.42, 7: 20.42, 9: 18.42";
  const tiers: { from_pct: number; pct: number }[] = [];
  for (const part of parts) {
    const m = /^(\d+(?:\.\d+)?)\s*%?\s*[:=]\s*(\d+(?:\.\d+)?)\s*%?$/.exec(part);
    if (!m) return `"${part}" should look like 7: 20.42`;
    const from_pct = Number(m[1]), pct = Number(m[2]);
    if (from_pct > 100 || pct <= 0 || pct > 100) return `"${part}": conversion and rate are percentages`;
    tiers.push({ from_pct, pct });
  }
  tiers.sort((a, b) => a.from_pct - b.from_pct);
  if (tiers[0]!.from_pct !== 0) return "The first tier starts at 0% conversion";
  if (new Set(tiers.map((t) => t.from_pct)).size !== tiers.length) return "Each tier needs its own starting conversion";
  return tiers;
}

export const RateSchema = z.object({
  partner_id: z.string().regex(/^\d+$/, "Choose a partner").transform(Number),
  scope: z.enum(["partner", "partner_university"]).default("partner"),
  university_id: z.string().regex(/^\d*$/).optional().default(""),
  rate_type: z.enum(["percent", "fixed", "tiered"]),
  value: z.string().trim().optional().default(""),
  tiers: z.string().trim().max(300).optional().default(""),
  fee_base: z.enum(["first_year", "total"]),
  gst_inclusive: z.string().optional().transform((v) => v === "on"),
  valid_from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "A date").or(z.literal("")),
  note: z.string().trim().max(300),
}).superRefine((r, ctx) => {
  if (r.scope === "partner_university" && !r.university_id) ctx.addIssue({ code: "custom", path: ["university_id"], message: "Choose a university" });
  if (r.rate_type === "tiered") {
    const t = parseTiers(r.tiers);
    if (typeof t === "string") ctx.addIssue({ code: "custom", path: ["tiers"], message: t });
    return;
  }
  const v = Number(r.value);
  if (!r.value || !Number.isFinite(v) || v <= 0) ctx.addIssue({ code: "custom", path: ["value"], message: "Enter a value above 0" });
  else if (r.rate_type === "percent" && v > 100) ctx.addIssue({ code: "custom", path: ["value"], message: "At most 100%" });
}).transform(({ tiers, value, university_id, ...r }) => ({
  ...r, value: r.rate_type === "tiered" ? null : Number(value), tiers: r.rate_type === "tiered" ? (parseTiers(tiers) as { from_pct: number; pct: number }[]) : null,
  university_id: r.scope === "partner_university" ? Number(university_id) : null,
}));

/** Hand-off settings (Addenda 1 and 2): the paid-campaign rule, B2C-created sources and blocked phones. */
export const HandoffSchema = z.object({
  sources: list(100),
  click_ids: list(100),
  utm_mediums: list(100),
  include_campaigns: list(100),
  exclude_campaigns: list(100),
  b2c_sources: list(30),
  blocked_phones: list(500, 10000).refine((a) => a.every((p) => /^\d{10,15}$/.test(p.replace(/\D/g, ""))), "Each number needs 10 to 15 digits"),
  junk_capi_signal: z.string().optional().transform((v) => v === "on"),
  reason: z.string().trim().min(3, "Say why you are changing the hand-off rules").max(300),
});

/** The form's flat fields → b2b.handoff_settings_save's payload. */
export function handoffPayload(d: z.infer<typeof HandoffSchema>) {
  const { sources, click_ids, utm_mediums, include_campaigns, exclude_campaigns, b2c_sources, blocked_phones, junk_capi_signal } = d;
  return { paid_rule: { sources, click_ids, utm_mediums, include_campaigns, exclude_campaigns }, b2c_sources, blocked_phones, junk_capi_signal };
}
