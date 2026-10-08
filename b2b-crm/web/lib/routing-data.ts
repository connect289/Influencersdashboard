import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { ProgrammeLabel } from "@/lib/programmes-data";
import type {
  Attribution, AttributionSettings, B2cHold, ConsentState, Decision, GoliveItem, Interest, Lane, Outlook, PartnerBar, PartnerConsent, Readiness, StoredDecisionCore,
} from "@/lib/routing";
import type { EffortWeights, RoutingSegments, ScoringMode, SegmentDetail, SlaWeights, Stage } from "@/lib/segments";

/** Routing reads as the signed-in Admin; every b2b.routing_* / lead_routing function re-checks b2b.is_admin(). Shapes mirror
 *  m31l (admin reads), m31e (go-live check) and m31f (decisions). */

/** One row of a decision list: decision_json minus candidates, excluded, rules, interest, features and shadow (routing_overview,
 *  routing_decisions). */
export type DecisionRow = {
  id: number; lead_id: number; lead_name: string | null; cycle_no: number; segment: string | null; mode: string; destination_type: "partner" | "in_house";
  winner_partner_id: number | null; partner_name: string | null; reason: string | null; selection_probability: number | null; is_test: boolean;
  actor_type: string; actor_id: string | null; created_at: string; b2c_lane: Lane | null;
  /** Addendum 3 columns (C128: scoring_mode and stage on every row). */
  scoring_mode: ScoringMode | null; stage: Stage | null; score: number | null; eval_segment: string | null; segment_exact: string | null;
  class: string | null; how: string | null; holdout: boolean; holdout_share: number | null; draw: number | null; interest_rank: number | null;
  model_version: string | null; feature_hash: string | null; seed: number | string | null; settings_version: number | null; policy_version: number | null; stats_at: string | null;
  attribution: Attribution | null; bar: PartnerBar | null; hold: B2cHold | null;
  allocation: StoredDecisionCore["allocation"];
};

/** A full stored decision (routing_decision, lead_routing.decisions): decision_json with candidates, excluded, rules and interest. */
export type StoredDecision = DecisionRow & StoredDecisionCore & { interest: Interest; candidates: Decision["candidates"]; excluded: Decision["excluded"]; rules: Decision["rules"] };

export type Rule = {
  id: number; name: string; priority: number; conditions: Record<string, unknown>; action: string; partner_ids: number[]; partner_names: string[] | null;
  b2c_lane: Lane | null;
  active: boolean; version: number; updated_at: string;
};

export type Rate = {
  id: number; scope: string; partner_id: number; partner_name: string | null; programme_id: number | null; programme: ProgrammeLabel | null; university_id: number | null;
  rate_type: string; fee_base: string; value: number | null; tiers?: { from_pct: number; pct: number }[] | null; gst_inclusive: boolean; valid_from: string; valid_to: string | null; source: string; note: string | null;
};

/** engine.a3_fixed (m31a): the rulebook's numbers, overwritten on every application and refused by every save (D24). */
export type A3Fixed = {
  stage_b_min_leads: number; stage_b_min_age_days: number; stage_c_min_matured: number; stage_c_min_partners: number; matured_days: number;
  learn_leads: number; exploration_share: number; exact_segment_min_leads: number; tier_projected_min_matured: number;
  effort_range: [number, number]; sla_range: [number, number]; sla_step_range: [number, number]; weight_range: [number, number];
  factor_window_days: number; attempt_limit: number; partner_limit: number; hold_minutes_sync: number; hold_minutes_async: number;
  duplicate_window_hours: number; push_retry_seconds: number[]; lost_grace_days: number; consent_wait_hours: number; witty_idle_minutes: number;
  auto_pause_breaches: number; auto_pause_sync_minutes: number; cpe_aggregate: string;
};

/** The `engine` setting (m31a seed): the editable keys engine_settings_save accepts, the hand-off keys handoff_settings_save
 *  owns, and the read-only a3_fixed block. The retired keys (kill_switch, fixed_split, speed/reliability, paid_rule,
 *  exploration_share, limits, cpe_aggregate…) are gone from the type: the saves refuse them. */
export type EngineSettings = {
  enabled?: boolean;
  consent_policy?: "ask" | "b2c_sales";
  consent_admin_yes?: boolean;
  consent_requests_per_hour?: number;
  witty_unqualified_idle_hours?: number;
  reenquiry_quiet_hours?: number;
  max_interests?: number;
  criteria_unknown?: "pass" | "fail";
  welcome_for_all_nurture?: boolean;
  require_verified_phone_sources?: string[];
  effort_factor?: { enabled?: boolean; bounds?: [number, number]; weights?: Partial<EffortWeights>; min_sample?: number };
  sla_factor?: { enabled?: boolean; floor?: number; ceiling?: number; step?: number; weights?: Partial<SlaWeights> };
  requalify?: { enabled?: boolean; wait_for_chat_gate?: boolean; max_per_run?: number };
  guard?: { duplicate_rate_pause?: boolean };
  half_life_days?: number; prior_weight?: number; default_p_enroll?: number;
  /** Read-only. */
  a3_fixed?: A3Fixed;
  /** Hand-off card (handoff_settings_save, m31g). */
  b2c_sources?: string[]; blocked_phones?: string[]; junk_capi_signal?: boolean;
  spam?: { use_witty_blocks?: boolean; disposable_email_domains?: string[]; max_leads_per_ip_hour?: number; max_leads_per_fingerprint_hour?: number };
};

/** A passed lead that Witty later classified junk or mismatch, waiting for the Admin (Addendum 2). */
export type ReviewFlag = {
  id: number; lead_id: number; lead_name: string | null; lead_status: string | null; destination_type: "partner" | "in_house";
  reference: string | null; partner_name: string | null; created_at: string;
};

/** b2b.not_passed row (to_jsonb; m31a adds detail and override). */
export type NotPassed = {
  lead_id: number; reason: string; lead_status: string | null; requested_course: string | null; lead_source: string | null;
  decided_at: string; passed_at: string | null; passed_by?: string | null; pass_note: string | null; times: number;
  /** 'spam:<rule>' or 'course_not_in_catalogue' (m31d lead_class.detail). */
  detail?: string | null;
  /** The Admin passed it: lead_class judges on fields until the fingerprint changes. */
  override?: boolean;
  fingerprint?: string | null;
};

export type RoutingOverview = {
  switch: { live: boolean; reason?: string | null; switched_at?: string | null };
  engine: { value: EngineSettings; version: number; updated_at: string };
  /** The go-live checklist (m31e routing_golive_check); routing cannot go live while a blocking item fails. */
  golive: GoliveItem[];
  live_partners: number;
  partners: { id: number; name: string; status: string; live: boolean; test_endpoint: boolean; offers: number; proposed: number;
              paused_reason: string | null; auto_paused_at: string | null }[];
  today: {
    to_partners: number; to_b2c: number; tests: number; errors: number; nurture: number; sales: number; not_passed: number;
    b2c_reasons: Record<string, number>;
    b2c_reasons_by_lane: { sales: Record<string, number>; nurture: Record<string, number> };
    requalified_to_partners: number; manual_to_partners: number;
    reenquiries: { partner: number; b2c_selling: number; barred: number; qualification_nurture: number };
    barred: number;
    consent: { requested: number; queued: number; yes: number; no: number; expired: number };
    stages: { A: number; B: number; C: number };
    lost_in_grace: number;
  };
  not_passed_open: number;
  flags_open: ReviewFlag[];
  decisions: DecisionRow[];
  rules: Rule[];
  rates: Rate[];
};

/** b2b.allocations row (to_jsonb) plus partner_name, as lead_routing lists them. */
export type AllocationRow = {
  id: number; lead_id: number; cycle_no: number; reference: string | null; status: string; destination_type: "partner" | "in_house"; partner_id: number | null;
  partner_name: string | null; mode: string; reason: string | null; cause: string | null; b2c_lane: Lane | null; outcome: string | null; outcome_at: string | null;
  created_at: string; updated_at: string; attempt_no: number; is_test: boolean; segment: string | null; segment_exact: string | null; interest_rank: number | null;
  programme_id: number | null; stage: Stage | null; score_inr: number | null; ncpl_inr: number | null; cpe_net_inr: number | null; p_enroll: number | null;
  effort_factor: number | null; sla_factor: number | null; model_version: string | null; origin: string | null; override: boolean;
  paid: boolean | null; paid_platform: string | null; campaign_id: string | null;
  pushed_at: string | null; accepted_at: string | null; engine_decision_id: number | null;
  /** Lost grace (m31a0, m31i). */
  lost_at: string | null; lost_grace_until: string | null; lost_revived_at: string | null; lost_count: number | null; lost_detail: Record<string, unknown> | null;
  recall_reason: string | null;
} & Record<string, unknown>;

/** A proven duplicate at another provider (b2b.lead_other_providers). first_had_at null = date not given. */
export type OtherProvider = { partner_id: number; partner_name: string; first_had_at: string | null; existing_record_id: string | null; claimed_at: string | null };

/** b2b.lead_consents row (the append-only ledger). */
export type ConsentLedgerRow = {
  id: number; lead_id: number; purpose: string; state: "given" | "refused" | "withdrawn"; at: string; text_version: string | null; source: string;
  request_id: number | null; evidence: Record<string, unknown>; actor: Record<string, unknown> | null; created_at: string;
};

/** b2b.consent_requests row. */
export type ConsentRequestRow = {
  id: number; lead_id: number; cycle_no: number; purpose: string; channel: "b2c_crm" | "witty"; context: "decision" | "nurture" | "admin";
  status: "queued" | "requested" | "sent" | "unsendable" | "answered" | "expired" | "cancelled"; text_version: string; programme: string | null;
  created_at: string; published_at: string | null; sent_at: string | null; expires_at: string | null;
  answer: "yes" | "no" | null; answered_at: string | null; answer_source: string | null; evidence: Record<string, unknown>; closed_at?: string | null; is_test?: boolean;
} & Record<string, unknown>;

/** b2b.lead_reenquiries row plus partner_name (R2–R4 detection, D18). */
export type Reenquiry = {
  id: number; lead_id: number; cycle_no: number | null; allocation_id: number | null; holder: "partner" | "b2c_selling" | "barred" | "qualification_nurture";
  partner_id: number | null; partner_name: string | null; kind: "touchpoint" | "witty_message"; touchpoint_id: number | null; message_id: number | null;
  source_system: string | null; event_type: string | null; campaign: string | null; paid_label: string | null; interest: boolean; occurred_at: string;
  event_id: number | null; acknowledged_at: string | null; acknowledged_by: string | null; note: string | null; created_at: string;
};

/** lead_routing.lost_grace: the current partner allocation marked lost (D34, D35). */
export type LostGrace = {
  allocation_id: number; reference: string | null; partner_id: number | null; lost_at: string; grace_until: string | null; lost_reason: string | null;
  revived: boolean; revived_at: string | null; in_grace: boolean; lost_count: number | null;
};

/** b2b.reroute_check (m31l): whether the open partner allocation may be recalled. */
export type RerouteCheck = {
  allowed: boolean; why: string | null; lost_in_grace: boolean; first_attempt_at: string | null;
  breaches: { sla: string; status: string; due_at: string; met_at: string | null }[];
  allocation_id: number; status: string | null;
};

/** b2b.nurture_watch row (R7 → R9 re-decision, D15). */
export type NurtureWatch = {
  lead_id: number; allocation_id: number | null; fingerprint: string | null; class: string | null; missing: string[] | null; qualified_at: string | null;
  recheck_at: string | null; consent_request_id: number | null; reengaged_at: string | null; checked_at: string | null; times: number;
};

/** b2b.lead_waits row: when the sweep decides the lead next, and why. */
export type LeadWait = { lead_id: number; decide_after: string; why: string; set_at: string; lead_updated_at: string | null };

/** b2b.route_outlook (m31f). */
export type RouteOutlook = { outlook: Outlook; reason: string | null; lane: Lane | null };

/** b2b.lead_routing (m31l): the lead drawer's Routing tab. */
export type LeadRouting = {
  readiness: Readiness; interest: Interest;
  /** partner_consent.given (kept from m9c); the detail is in consent_detail. */
  consent: boolean;
  routing_live: boolean;
  not_passed: NotPassed | null;
  flags: { id: number; allocation_id: number; lead_status: string | null; destination_type: string; created_at: string; resolved_at: string | null; resolution: string | null }[];
  decisions: StoredDecision[];
  allocations: AllocationRow[];
  /** Messages to the student (m9c). */
  notifications?: {
    id: number; channel: "whatsapp" | "email"; kind: string; language: string; status: string; error: string | null;
    scheduled_for: string | null; sent_at: string | null; created_at: string; partner_name: string | null;
  }[];
  /** Addendum 3. */
  bar: PartnerBar | null;
  other_providers: OtherProvider[];
  hold: B2cHold | null;
  outlook: RouteOutlook;
  consent_detail: { partner_consent: PartnerConsent; state: ConsentState; ledger: ConsentLedgerRow[]; requests: ConsentRequestRow[] };
  reenquiries: Reenquiry[];
  reenquiries_open: number;
  interests: Interest[];
  lost_grace: LostGrace | null;
  reroute: RerouteCheck | null;
  nurture_watch: NurtureWatch | null;
  wait: LeadWait | null;
  golive: GoliveItem[];
  attribution: Attribution;
  is_test: boolean;
};

async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc(fn, args);
  if (error) throw new Error(`${fn} failed (${error.code ?? "unknown"})`);
  return data as T;
}

export const routingOverview = () => rpc<RoutingOverview>("routing_overview");
export const routingDecision = (id: number) => rpc<StoredDecision | null>("routing_decision", { p_id: id });
export const leadRouting = (id: number) => rpc<LeadRouting | null>("lead_routing", { p_lead_id: id });
/** Whether an open partner allocation may be recalled (b2b.reroute_check; callable by every signed-in user, reads only). */
export const rerouteCheck = (allocationId: number) => rpc<RerouteCheck>("reroute_check", { p_allocation_id: allocationId });

export type NotPassedSummary = { by_reason: Record<string, number>; by_source: Record<string, number>; mismatch_courses: { course: string; n: number }[] };
export const notPassedSummary = () => rpc<NotPassedSummary>("not_passed_summary");

export const routingSegments = () => rpc<RoutingSegments>("routing_segments");
/** A 3-part key (course|level|mode) or a 4-part university key (course|level|mode|u<id>). */
export const routingSegment = (segment: string) => rpc<SegmentDetail>("routing_segment", { p_segment: segment });

/** b2b.decision_replay (m31l, C128). A3 decisions re-sort the stored candidates and recompute the exploration lane; legacy
 *  decisions keep the M24 branches; kill-switch and rule / minimum rows are not replayable. */
export type DecisionReplay =
  | { replayable: false; why: string }
  /** An Addendum 3 decision (a stage): the lane recomputed from the seed; reproduced = the winner matches. */
  | { replayable: true; stage: Stage; scoring_mode: ScoringMode | null; mode: string; winner: number | null; logged_winner: number | null; reproduced: boolean;
      lane_applied: boolean; draw: number | null; share: number; logged_draw: number | null; selection_probability: number | null; order: number[];
      logged_probability?: undefined; wins?: undefined; draws?: undefined; holdout_draw?: undefined; holdout?: undefined; exploration_draw?: undefined }
  /** A legacy (M24) decision: the Thompson branch carries wins and draws, the commission-first branch the two draws. */
  | { replayable: true; stage?: undefined; scoring_mode: ScoringMode; winner?: number | null; logged_winner: number | null; reproduced?: boolean;
      selection_probability?: number | null; logged_probability?: number | null; wins?: Record<string, number>; draws?: number;
      holdout_draw?: number; holdout?: boolean; exploration_draw?: number; mode?: string;
      lane_applied?: undefined; draw?: undefined; share?: undefined; logged_draw?: undefined; order?: undefined };
export const decisionReplay = (id: number) => rpc<DecisionReplay>("decision_replay", { p_decision_id: id });

/** One version of a setting (b2b.settings_history, C62): what changed against the version before. */
export type SettingsHistoryRow = {
  version: number; at: string; actor: string | null; actor_id: string | null; ai_run_id: number | null; reason: string | null;
  changed: Record<string, { from: unknown; to: unknown }>;
};
export type HistoryKey = "engine" | "engine_policy" | "ml" | "ai" | "attribution" | "lost_nurture_delays" | "golive_acks";
/** Version history of a setting, newest first (limit 1–200, default 30). */
export const settingsHistory = (key: HistoryKey, limit = 30) => rpc<SettingsHistoryRow[]>("settings_history", { p_key: key, p_limit: limit });

/** b2b.routing_decisions (C62): the searchable decision log. q = a lead id (1–9 digits), a phone (10–13 digits) or part of a name. */
export type DecisionQuery = {
  q?: string; partner_id?: number; segment?: string; reason?: string; stage?: Stage; how?: string; destination?: "partner" | "in_house";
  before_id?: number; limit?: number; hide_test?: boolean;
};
export type DecisionPage = { rows: DecisionRow[]; next_before_id: number | null };
export function routingDecisions(p: DecisionQuery = {}): Promise<DecisionPage> {
  const clean = Object.fromEntries(Object.entries(p).filter(([, v]) => v !== undefined && v !== null && v !== ""));
  return rpc<DecisionPage>("routing_decisions", { p: clean });
}

/** The routing go-live checklist (m31e routing_golive_check, granted to authenticated Admins). Falls back to
 *  command_center().golive should the direct call be refused. */
export async function routingGolive(): Promise<GoliveItem[]> {
  try {
    return (await rpc<GoliveItem[] | null>("routing_golive_check")) ?? [];
  } catch {
    const cc = await rpc<{ golive?: GoliveItem[] | null } | null>("command_center");
    return cc?.golive ?? [];
  }
}

/** The `lost_nurture_delays` setting (m31l lost_delays_save; D36): days before B2C's first nurture message after partner_lost. */
export type LostDelays = { default: number; reasons: Record<string, number> };
export async function lostDelays(): Promise<{ value: LostDelays; version: number | null; updated_at: string | null }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").from("settings").select("value, version, updated_at").eq("key", "lost_nurture_delays").maybeSingle();
  if (error) throw new Error(`lost_nurture_delays read failed (${error.code ?? "unknown"})`);
  const v = (data?.value ?? {}) as Partial<LostDelays>;
  return { value: { default: Number(v.default ?? 14), reasons: v.reasons ?? {} }, version: data?.version ?? null, updated_at: data?.updated_at ?? null };
}

/** The `attribution` setting (m31g attribution_settings_save; D38). */
export async function attributionSettings(): Promise<{ value: AttributionSettings; version: number | null; updated_at: string | null }> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").from("settings").select("value, version, updated_at").eq("key", "attribution").maybeSingle();
  if (error) throw new Error(`attribution read failed (${error.code ?? "unknown"})`);
  return { value: (data?.value ?? {}) as AttributionSettings, version: data?.version ?? null, updated_at: data?.updated_at ?? null };
}
