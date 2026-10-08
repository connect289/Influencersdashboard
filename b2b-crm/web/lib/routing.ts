import { z } from "zod";
import {
  checkbox, performanceFields, performancePayload, performanceRefine, reqNum, STAGE_FORMULA,
  type CpeBasis, type EffortDetail, type PSource, type ScoringMode, type Stage,
} from "@/lib/segments";

/** Routing (Addendum 3): labels, decision types and form parsing shared by the routing screen, the lead drawer, the pool,
 *  the B2C screens and the tests. The shapes mirror b2b.route_decide / stage_score (m31f), decision_json, lead_routing,
 *  routing_overview (m31l) and the save functions engine_settings_save (m31l), handoff_settings_save and
 *  attribution_settings_save (m31g), routing_rule_save (m31l). */

export type Lane = "sales" | "nurture";

// ---------- labels ----------

/** Reason codes (CONTRACT 1.2): why a lead went to B2C, or what a partner decision was. paid_campaign is legacy only. */
export const REASON_LABEL: Record<string, string> = {
  b2c_created: "Created in the B2C CRM",
  import_choice: "Import chose B2C",
  rule: "Routing rule",
  manual: "Sent to B2C by the Admin",
  manual_route_failed: "Sent to partners by hand, none could take it",
  no_partner_offers_programme: "No partner offers this programme",
  no_capacity: "No eligible partner",
  partners_unreachable: "Partner limit reached (3 partners tried)",
  partner_attempts_exhausted: "Partners rejected it (attempt limit)",
  duplicate_cascade: "Duplicate at partners (partner-barred)",
  no_partner_consent: "Student said NO to sharing",
  partner_barred: "Partner-barred lead enquired again",
  b2c_held: "Already with B2C",
  not_qualified: "Not qualified",
  consent_no_answer: "No answer to the partner-sharing request (48 h)",
  partner_lost: "Partner marked it lost",
  test_handoff: "Test hand-off to B2C",
  test_lead: "Test lead: not routed",
  no_sandbox_partner: "No partner has a sandbox endpoint",
  paid_campaign: "Paid campaign (rule before 7 Oct 2026)",
};

/** Exclusion and failure causes (CONTRACT 1.2 `cause`). */
export const CAUSE_LABEL: Record<string, string> = {
  caps: "every eligible partner is at its daily or monthly cap",
  paused: "the offering partners are paused",
  criteria: "the lead does not meet any partner's criteria",
  rule: "a routing rule excluded every partner",
  duplicate_history: "every partner already had this student",
  tried: "every partner was already tried this cycle",
  duplicate_cascade: "duplicate at partners",
  partner_attempts_exhausted: "partners rejected it (attempt limit)",
  partners_unreachable: "partner limit reached",
  no_partner_offers_programme: "no partner offers this programme",
  no_capacity: "no eligible partner",
  no_partner_consent: "no partner-sharing consent",
};

/** The reason in words; manual_route_failed and no_capacity carry their cause ("No eligible partner: every eligible partner is at its daily or monthly cap"). */
export function reasonLabel(reason: string | null | undefined, cause?: string | null): string {
  if (!reason) return "—";
  const base = REASON_LABEL[reason] ?? reason.replace(/_/g, " ");
  if (cause && (reason === "manual_route_failed" || reason === "no_capacity")) return `${base}: ${CAUSE_LABEL[cause] ?? cause.replace(/_/g, " ")}`;
  return base;
}

/** Why a lead is not passed to any CRM (Addendum 2, kept by R5). */
export const NOT_PASSED_LABEL: Record<string, string> = {
  junk: "Junk",
  program_mismatch: "Programme mismatch",
  invalid_phone: "Invalid phone",
  blocked_phone: "Blocked phone",
};

/** not_passed.detail: the spam rule behind a junk verdict, or why a course is a mismatch (m31d lead_class.detail). */
export const NOT_PASSED_DETAIL_LABEL: Record<string, string> = {
  "spam:witty_block": "phone blocked by Witty",
  "spam:disposable_email": "disposable email domain",
  "spam:ip_burst": "too many leads from one IP address in an hour",
  "spam:fingerprint_burst": "too many leads from one device in an hour",
  course_not_in_catalogue: "course not in the catalogue",
};

/** "Junk (phone blocked by Witty)" from a not_passed reason and its detail. */
export function notPassedLabel(reason: string | null | undefined, detail?: string | null): string {
  if (!reason) return "—";
  const base = NOT_PASSED_LABEL[reason] ?? reason.replace(/_/g, " ");
  if (!detail) return base;
  const d = NOT_PASSED_DETAIL_LABEL[detail] ?? (detail.startsWith("spam:") ? `spam: ${detail.slice(5).replace(/_/g, " ")}` : detail.replace(/_/g, " "));
  return `${base} (${d})`;
}

export const LANE_LABEL: Record<string, string> = { sales: "B2C sales", nurture: "B2C nurture" };

/** allocations.mode / engine_decisions.mode. */
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

/** The scoring stage (D25–D27): what decides between eligible partners. */
export const STAGE_LABEL: Record<Stage, string> = { A: "Commission", B: "Commission × effort × SLA", C: "Commission per lead" };
export const STAGE_HINT: Record<Stage, string> = {
  A: "Highest commission per enrolment wins. 20% of leads go to an under-tested partner (fewer than 30 leads) so its results can be learned.",
  B: "Every competing partner has 20 leads at least 7 days old: commission × sales-effort factor (0.85–1.15) × SLA-adherence factor (0.80–1.00).",
  C: "Two partners have 30 leads older than 60 days: commission × P(enrol) × (1 − refunds) × effort × SLA, the expected commission per lead.",
};

/** b2c_hold.kind (CONTRACT 1.3). */
export const HOLD_LABEL: Record<string, string> = {
  selling: "With B2C sales",
  qualification_nurture: "B2C nurture: qualifying",
  barred: "Partner-barred, with B2C",
};

/** handling.job in the B2C hand-off. */
export const JOB_LABEL: Record<string, string> = { sell: "Sell", nurture: "Nurture", qualify: "Qualify" };

/** handling.assignment in the B2C hand-off (CONTRACT 14). */
export const ASSIGNMENT_LABEL: Record<string, string> = {
  round_robin_now: "Assign a counsellor now (round robin)",
  unassigned_until_interest: "Unassigned until the student shows interest",
  previous_counsellor: "Back to the previous counsellor",
  counsellor_choice: "Counsellor's choice",
  unassigned: "Unassigned",
};

/** consent_state (CONTRACT 1.3) plus the request status 'sent'. */
export const CONSENT_STATE_LABEL: Record<string, string> = {
  given: "Partner-sharing consent given",
  refused: "Student said NO to sharing",
  withdrawn: "Consent withdrawn",
  stamp_uncovered: "Consent stamp does not cover admission partners",
  none: "No partner-sharing consent",
  requested: "Consent requested, waiting for the answer",
  queued: "Consent request queued (rate limit)",
  sent: "Consent request sent, waiting for the answer",
  expired: "Consent request expired (no answer in 48 h)",
};

/** consent_requests.status. */
export const CONSENT_REQUEST_STATUS_LABEL: Record<string, string> = {
  queued: "Queued", requested: "Requested", sent: "Sent", unsendable: "Could not be sent", answered: "Answered", expired: "Expired", cancelled: "Cancelled",
};
export const CONSENT_CHANNEL_LABEL: Record<string, string> = { b2c_crm: "B2C number", witty: "Witty" };

/** route_decide outcome (CONTRACT 1.3). */
export const OUTCOME_LABEL: Record<string, string> = {
  decided: "Decided",
  "re-enquired": "Re-enquired while with B2C",
  with_partner: "Already with a partner",
  consent_requested: "Consent requested",
  consent_pending: "Consent request pending",
  consent_request: "Would ask for consent",
  test_lead: "Test lead",
};

/** route_outlook.outlook (CONTRACT 1.3): where a lead would go at its decision point. */
export const OUTLOOK_LABEL: Record<string, string> = {
  partners: "To a partner",
  b2c_sales: "B2C sales",
  b2c_nurture: "B2C nurture",
  b2c: "B2C (import choice)",
  b2c_held: "Stays with B2C",
  with_partner: "With a partner",
  not_passed: "Not passed (junk or mismatch)",
  consent_pending: "Awaiting partner-sharing consent",
  consent_request: "Consent will be asked",
  none: "Not routed",
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

/** engine.a3_fixed (m31a): the rulebook's numbers, read-only in the Admin (D24). Keys in display order. */
export const A3_FIXED_LABELS: Record<string, string> = {
  stage_b_min_leads: "Stage B: leads per partner",
  stage_b_min_age_days: "Stage B: age of the first lead (days)",
  stage_c_min_matured: "Stage C: matured leads per partner",
  stage_c_min_partners: "Stage C: partners with matured leads",
  matured_days: "A lead matures after (days)",
  learn_leads: "Under-tested partner: fewer leads than",
  exploration_share: "Exploration lane share",
  exact_segment_min_leads: "University segment used from (leads per partner)",
  tier_projected_min_matured: "Projected commission tier from (matured leads)",
  effort_range: "Sales-effort factor range",
  sla_range: "SLA-adherence factor range",
  sla_step_range: "SLA step range (per 10 points)",
  weight_range: "Weight range",
  factor_window_days: "Factor window (days)",
  attempt_limit: "Duplicate or rejection attempts",
  partner_limit: "Partners tried in total",
  hold_minutes_sync: "Hold window, synchronous partners (minutes)",
  hold_minutes_async: "Hold window, asynchronous partners (minutes)",
  duplicate_window_hours: "Duplicate window (hours)",
  push_retry_seconds: "Push retries (seconds)",
  lost_grace_days: "Lost grace (days)",
  consent_wait_hours: "Consent wait (hours)",
  witty_idle_minutes: "Witty idle before routing (minutes)",
  auto_pause_breaches: "Auto-pause after breaches",
  auto_pause_sync_minutes: "Auto-pause: sync down for (minutes)",
  cpe_aggregate: "Commission across programmes",
};

/** An a3_fixed value in words: 0.2 → "20%", [0.85, 1.15] → "0.85 – 1.15", [10, 60, 300] → "10 s, 1 min, 5 min". */
export function a3FixedText(key: string, value: unknown): string {
  if (value == null) return "—";
  if (key === "exploration_share" && typeof value === "number") return `${Math.round(value * 100)}%`;
  if (key === "push_retry_seconds" && Array.isArray(value)) return value.map((s) => (Number(s) < 60 ? `${s} s` : `${Math.round(Number(s) / 60)} min`)).join(", ");
  if (Array.isArray(value)) return value.map(String).join(" – ");
  return String(value);
}

/** Routing go-live checklist keys (m31e routing_golive_check). */
export const GOLIVE_LABEL: Record<string, string> = {
  consent_texts_approved: "Consent texts approved by the lawyer",
  witty_w1_consent_line: "Witty asks for partner-sharing consent (W1)",
  b2c_endpoint_subscribed: "B2C CRM subscribed to consent requests",
  witty_w2_consent_request: "Witty can send consent requests (W2)",
  live_partner: "At least one live partner",
};

// ---------- types ----------

/** b2b.lead_interest / lead_interest_list item (m31b). */
export type Interest = {
  course_key: string | null;
  course_text?: string | null;
  specialization: string | null;
  level: string | null;
  mode: string | null;
  university_id: number | null;
  university_ids?: number[];
  university_text: string | null;
  segment: string;
  /** course|level|mode|u<id> when exactly one university resolves (D25). */
  segment_exact?: string | null;
  /** 1 = the primary interest; secondary interests follow in position order. */
  rank?: number;
  source?: string;
  position?: number;
  interest_id?: number;
};

/** route_decide's `interests`: every interest tried, in order (D30). */
export type InterestTried = { rank: number; course_key: string | null; course_text: string | null; segment: string | null; outcome: "offered" | "no_offer" | "routed" };

export type ExclusionCause = "caps" | "paused" | "criteria" | "rule" | "duplicate_history" | "tried";

/** A partner in a decision: offer_candidates (m31f) plus stage_score's statistics and score. Candidates excluded in Step 1/2
 *  carry eligible false with `why` and `cause`; the eligible ones are ordered by tie_rank. Legacy M24 keys stay optional. */
export type Candidate = {
  partner_id: number;
  name: string;
  status: string;
  /** M24 rows counted offers here; A3 rows carry offers_count (the offers array is stripped from logged candidates). */
  offers?: number;
  offers_count?: number;
  programmes?: number[];
  cpe: number | null;
  has_rate: boolean;
  cpe_basis?: CpeBasis | null;
  fee_inr?: number | null;
  daily_cap: number | null;
  monthly_cap: number | null;
  contract_min_monthly?: number | null;
  leads_today: number;
  leads_month: number;
  leads_week: number;
  segment_leads?: number;
  eligible: boolean;
  why?: string | null;
  cause?: ExclusionCause | string | null;
  test_endpoint?: boolean;
  /** Stage statistics (stage_score). */
  n_received?: number; first_lead_at?: string | null; n_matured_c?: number; under_tested?: boolean; stats_segment?: string | null;
  p_hat?: number; alpha?: number; beta?: number; prior?: number; prior_weight?: number; half_life_days?: number; w_n?: number; w_enr?: number;
  refund_rate?: number;
  effort_detail?: EffortDetail | null; has_activity?: boolean; effort_raw?: number; effort_factor?: number;
  sla_adherence?: number | null; sla_total?: number; sla_raw?: number; sla_factor?: number;
  /** P(enrol): the model's p (every stage, when a model exists), the one used (Stage C only) and where it came from. */
  p_model?: number | null; p_used?: number | null; p_source?: PSource | null;
  /** Stage C: cpe × p_used × (1 − refund_rate). */
  ncpl?: number | null;
  score?: number; tie_rank?: number; propensity?: number;
  open_backlog?: number; in_hours?: boolean; fch_7d?: number | null; fch_30d?: number | null; connect_30d?: number | null;
  /** Legacy M24 statistics (decisions made before Addendum 3). */
  sla_compliance?: number | null; speed?: number; reliability?: number; weight?: number; win_share?: number; stats_rollup?: boolean;
  matured_in_segment?: number; leads_in_segment?: number;
};

/** route_decide / route_outlook destinations (CONTRACT 1.3): only partner and in_house are ever stored. */
export type Destination = "partner" | "in_house" | "not_passed" | "none" | "consent_requested" | "consent_pending" | "consent_request";
export type DecisionOutcome = "decided" | "with_partner" | "re-enquired" | "consent_requested" | "consent_pending" | "consent_request" | "test_lead";
export type Outlook = "none" | "not_passed" | "b2c_sales" | "b2c_nurture" | "b2c" | "b2c_held" | "with_partner" | "consent_pending" | "consent_request" | "partners";
export type ConsentState = "given" | "refused" | "withdrawn" | "requested" | "queued" | "expired" | "stamp_uncovered" | "none";
export type LeadClassName = "junk" | "mismatch" | "qualified" | "unqualified";

export type ReadinessWait = { kind: "inactivity" | "chatting" | "consent"; why?: string; until?: string | null; last_inbound?: string | null; hours?: number;
                              request_id?: number; status?: string; expires_at?: string | null; context?: string };

/** b2b.lead_readiness (m31d). */
export type Readiness = {
  ready: boolean; missing: string[]; is_test: boolean;
  class?: LeadClassName | string; class_reason?: string | null; class_detail?: string | null; class_basis?: string | null; override?: boolean;
  not_qualified?: string[];
  /** The attribution label when paid (e.g. "Meta Lead Ads"), else null. */
  paid?: string | null; paid_platform?: string | null;
  chat?: boolean; witty?: boolean; gate?: string | null; decide_after?: string | null; last_inbound?: string | null; wait?: ReadinessWait | null;
};

/** b2b.lead_class (m31d). */
export type LeadClass = { class: LeadClassName; reason: string | null; missing: string[]; detail: string | null; override: boolean; basis: string; witty: boolean };

/** b2b.partner_bar (m31b): the permanent bar after a duplicate or a lost (D1, D2). */
export type PartnerBar = {
  reason: "duplicate" | "lost"; barred_at: string; lead_id: number; allocation_id: number | null;
  providers: { partner_id?: number; partner_name?: string; existing_record_id?: string | null; first_had_at?: string | null }[];
  set_by: "engine" | "grace" | "manual_route" | "backfill"; via: "lead" | "merged" | "phone";
};

/** b2b.b2c_hold (m31b). */
export type B2cHold = { kind: "barred" | "qualification_nurture" | "selling"; open: boolean; allocation_id: number | null; lane: Lane | null; reason: string | null; owner_assigned?: boolean };

export type ConsentRequestBrief = { id: number; status: string; channel: "b2c_crm" | "witty"; context: "decision" | "nurture" | "admin"; created_at: string;
                                    published_at?: string | null; sent_at?: string | null; expires_at: string | null; programme?: string | null };

/** b2b.partner_consent (m31b). */
export type PartnerConsent = {
  given: boolean; at: string | null; version: string | null; source: string | null;
  refused: boolean; refused_at: string | null; last_state: string | null; stamp_uncovered: boolean;
  open_request: ConsentRequestBrief | null;
  expired_request: { id: number; channel: string; context: string; created_at: string; expires_at: string | null; closed_at: string | null; programme: string | null } | null;
  last_request: { id: number; status: string; answer: "yes" | "no" | null; answered_at: string | null; created_at: string; expires_at: string | null } | null;
};

/** b2b.lead_attribution (m31b, D38): paid is a label, never a routing input. */
export type Attribution = { paid: boolean; platform: "meta" | "google" | "other" | "none"; signal: string | null; label: string | null; campaign_id: string | null; origin: string | null };

/** consent_request_create's result (m31e), returned by route_decide when R8 asked. */
export type ConsentRequestResult = {
  created: boolean; request_id: number | null; status: string | null; channel: "b2c_crm" | "witty" | null; context: string; programme: string | null;
  programme_course_key: string | null; expires_at: string | null; published: boolean; existing: boolean; why: string | null;
};

/** b2b.route_decide's result (m31f): the live preview and, through fromStored, a stored decision. */
export type Decision = {
  lead_id: number;
  cycle_no?: number;
  is_test: boolean;
  readiness: Readiness;
  interest: Interest;
  interests?: InterestTried[];
  /** The rank of the interest routed ("routed on interest 2 of 3"). */
  interest_rank?: number | null;
  class?: LeadClass | null;
  attribution?: Attribution | null;
  bar?: PartnerBar | null;
  hold?: B2cHold | null;
  consent?: PartnerConsent | null;
  destination: Destination;
  outcome?: DecisionOutcome | null;
  reason: string | null;
  /** Why a manual route failed or no partner had capacity (CONTRACT 1.2 cause). */
  cause?: string | null;
  mode: string;
  scoring_mode?: ScoringMode | null;
  stage?: Stage | null;
  b2c_lane?: Lane | null;
  /** The attribution label when the lead is paid (Meta / Google), else null. */
  paid?: string | null;
  partner_id: number | null;
  partner_name: string | null;
  cpe: number | null;
  ncpl?: number | null;
  has_rate: boolean | null;
  score?: number | null;
  eval_segment?: string | null;
  segment_exact?: string | null;
  how?: string;
  origin?: string;
  candidates: Candidate[];
  excluded: { partner_id: number | string; name: string; why: string; cause?: string | null }[];
  rules: { id: number; name: string; action: string; effect: string }[];
  /** The exploration draw u01(seed, 'explore'): logged only when the lane applied (C128). */
  draw: number | null;
  /** 0.2 only when the lane applied, else 0 (C128). */
  exploration_share: number;
  lane?: { applied: boolean; x_partner_id: number | null } | null;
  selection_probability: number;
  settings_version?: number | null;
  policy_version?: number | null;
  holdout?: boolean;
  holdout_share?: number | null;
  seed?: number | string | null;
  seed_source?: "forced" | "random" | "given" | null;
  stats_at?: string | null;
  model_version?: string | null;
  feature_hash?: string | null;
  shadow?: Record<string, Record<string, number>> | null;
  params_variant?: "base" | "ai" | null;
  why?: string | null;
  already_routed: boolean;
  committed: boolean;
  decision_id?: number | null;
  allocation_id?: number | null;
  reference?: string;
  consent_request?: ConsentRequestResult | null;
};

/** The allocation block decision_json adds to a stored decision (m31l). */
export type DecisionAllocation = {
  id: number; reference: string; status: string; cpe_net_inr: number | null; b2c_lane: Lane | null; outcome: string | null;
  stage: Stage | null; score_inr: number | null; origin: string | null; effort_factor: number | null; sla_factor: number | null;
  p_enroll: number | null; model_version: string | null; cause: string | null; ncpl_inr: number | null;
};

/** A decision as stored in b2b.engine_decisions and returned by decision_json (routing_decision, lead_routing, routing_decisions). */
export type StoredDecisionCore = {
  lead_id: number; is_test: boolean; interest: Interest; destination_type: "partner" | "in_house"; reason: string | null; mode: string; b2c_lane?: Lane | null;
  winner_partner_id: number | null; partner_name: string | null; candidates: Candidate[] | null; excluded: Decision["excluded"] | null;
  rules: Decision["rules"] | null; selection_probability: number | null; allocation: DecisionAllocation | null;
  scoring_mode?: ScoringMode | null; holdout?: boolean; seed?: number | string | null; policy_version?: number | null; settings_version?: number | null; stats_at?: string | null;
  /** Addendum 3 columns (m31a). */
  stage?: Stage | null; score?: number | null; eval_segment?: string | null; segment_exact?: string | null; class?: string | null;
  attribution?: Attribution | null; interest_rank?: number | null; interests?: InterestTried[] | null; hold?: B2cHold | null; bar?: PartnerBar | null;
  how?: string | null; holdout_share?: number | null; draw?: number | null; model_version?: string | null; feature_hash?: string | null;
  shadow?: Record<string, Record<string, number>> | null; features?: Record<string, unknown> | null; features_hash?: string | null;
};

/** A stored decision in the shape DecisionView shows (C112: every display key is stored). Readiness is not stored, so the
 *  class and the paid label are rebuilt from the stored class and attribution; the exploration lane applied iff a draw was logged. */
export function fromStored(s: StoredDecisionCore): Decision {
  const candidates = s.candidates ?? [];
  const won = candidates.find((c) => c.partner_id === s.winner_partner_id);
  const laneApplied = s.draw != null;
  return {
    lead_id: s.lead_id, is_test: s.is_test,
    readiness: { ready: true, missing: [], is_test: s.is_test, class: s.class ?? undefined, paid: s.attribution?.paid ? s.attribution.label : null,
                 paid_platform: s.attribution?.platform ?? null },
    interest: s.interest, interests: s.interests ?? undefined, interest_rank: s.interest_rank ?? null,
    attribution: s.attribution ?? null, bar: s.bar ?? null, hold: s.hold ?? null,
    destination: s.destination_type, outcome: "decided", b2c_lane: s.b2c_lane ?? null, reason: s.reason, cause: s.allocation?.cause ?? null,
    mode: s.mode, scoring_mode: s.scoring_mode ?? null, stage: s.stage ?? null,
    paid: s.attribution?.paid ? s.attribution.label : null,
    partner_id: s.winner_partner_id, partner_name: s.partner_name,
    cpe: s.allocation?.cpe_net_inr ?? won?.cpe ?? null, ncpl: s.allocation?.ncpl_inr ?? won?.ncpl ?? null, has_rate: won?.has_rate ?? null,
    score: s.score ?? s.allocation?.score_inr ?? won?.score ?? null, eval_segment: s.eval_segment ?? null, segment_exact: s.segment_exact ?? null,
    how: s.how ?? undefined, origin: s.allocation?.origin ?? undefined,
    candidates, excluded: s.excluded ?? [], rules: s.rules ?? [],
    draw: s.draw ?? null, exploration_share: laneApplied ? 0.2 : 0, lane: { applied: laneApplied, x_partner_id: laneApplied && s.mode === "exploration" ? s.winner_partner_id : null },
    selection_probability: Number(s.selection_probability ?? 1), settings_version: s.settings_version ?? null,
    already_routed: true, committed: true, reference: s.allocation?.reference, allocation_id: s.allocation?.id ?? null,
    holdout: s.holdout ?? false, holdout_share: s.holdout_share ?? null, seed: s.seed ?? null, policy_version: s.policy_version ?? null, stats_at: s.stats_at ?? null,
    model_version: s.model_version ?? null, feature_hash: s.feature_hash ?? null, shadow: s.shadow ?? null,
  };
}

/** "mba|PG|Online" → "MBA · PG · Online"; a university key adds "· university #12"; unknown parts read as "any". */
export function segmentLabel(segment: string | null | undefined): string {
  if (!segment) return "—";
  const [course, level, mode, uni] = segment.split("|");
  const part = (v: string | undefined, upper = false) => (!v || v === "*" || v === "?" ? "any" : upper ? v.toUpperCase() : v);
  const base = `${part(course, true)} · ${part(level)} · ${part(mode)}`;
  return uni && /^u\d+$/.test(uni) ? `${base} · university #${uni.slice(1)}` : base;
}

/** What decided a decision, for its header and the decision lists (C128). */
export function decisionModeLabel(d: { mode: string; scoring_mode?: string | null; stage?: string | null }): string {
  if (d.scoring_mode === "kill_switch") return "Kill switch (fixed split, retired)";
  if (d.stage && (d.mode === "commission_first" || d.mode === "performance")) return STAGE_LABEL[d.stage as Stage] ?? d.stage;
  return MODE_LABEL[d.mode] ?? d.mode;
}

/** The Result cell of a candidate row (C128): the winner, an excluded partner's reason, or why an eligible partner lost. */
export function decisionResultLabel(d: { mode: string; scoring_mode?: string | null; stage?: string | null; partner_id: number | null },
                                    c: { partner_id: number; eligible: boolean; why?: string | null; cause?: string | null; tie_rank?: number }): string {
  if (c.partner_id === d.partner_id) return "Chosen";
  if (!c.eligible) return c.why ?? (c.cause ? CAUSE_LABEL[c.cause] ?? c.cause : "Excluded");
  if (d.scoring_mode === "kill_switch") return "Eligible, not drawn in the fixed split";
  if (d.mode === "exploration") return c.tie_rank === 1 ? "Highest score; the lead went to the exploration lane" : "Eligible, not the exploration pick";
  if (!d.stage && d.scoring_mode === "performance") return "Eligible, lost the draw";
  if (d.stage === "B" || d.stage === "C") return "Eligible, lower score";
  return "Eligible, lower commission";
}

/** "Stage B: commission × effort × SLA" for a stage, or null. */
export const stageText = (stage: Stage | null | undefined) => (stage ? `Stage ${stage}: ${STAGE_FORMULA[stage]}` : null);

/** A candidate's CPE basis in words: "middle tier · partner fee · median of 3 programmes". */
export function cpeBasisText(b: CpeBasis | null | undefined): string | null {
  if (!b) return null;
  const parts = [b.tier_basis === "projected" ? "projected tier" : "middle tier"];
  if (b.fee_source) parts.push(`${b.fee_source.replace(/_/g, " ")} fee${b.fee_basis ? ` (${b.fee_basis.replace(/_/g, " ")})` : ""}`);
  if (b.offers_with_rate > 1) parts.push(`median of ${b.offers_with_rate} programmes`);
  return parts.join(" · ");
}

/** One item of b2b.routing_golive_check (m31e). An item passes when ok, or when it is acknowledgeable and acknowledged. */
export type GoliveItem = {
  key: string; ok: boolean; blocking: boolean; why: string | null;
  acknowledgeable?: boolean; acked?: boolean; ack?: { reason: string; by: string | null; at: string } | null;
  detail?: Record<string, unknown> | null;
};
export const golivePasses = (i: GoliveItem) => i.ok || ((i.acknowledgeable ?? Boolean(i.ack)) && (i.acked ?? Boolean(i.ack)));
/** The blocking items that do not pass: routing cannot go live while this list is not empty (set_live_switch raises with them). */
export const goliveBlocking = (items: GoliveItem[] | null | undefined): GoliveItem[] => (items ?? []).filter((i) => i.blocking && !golivePasses(i));

// ---------- forms ----------

const list = (max = 50, chars = 2000) => z.string().max(chars).transform((v) => [...new Set(v.split(/[,\n]/).map((s) => s.trim()).filter(Boolean))].slice(0, max));
const ids = (max = 50) => z.array(z.string().regex(/^\d+$/)).max(max).transform((a) => a.map(Number));

export const RuleSchema = z.object({
  id: z.string().regex(/^\d*$/).transform((v) => (v ? Number(v) : null)),
  name: z.string().trim().min(1, "Give the rule a name").max(120),
  priority: z.string().trim().regex(/^\d{1,4}$/, "A whole number").transform(Number),
  action: z.enum(["fix_partner", "narrow", "exclude", "to_b2c"]),
  partner_ids: ids(),
  b2c_lane: z.enum(["sales", "nurture"]).nullable(),
  sources: list(),
  course_keys: list().transform((a) => a.map((s) => s.toLowerCase().replace(/[^a-z0-9]/g, ""))),
  specializations: list(),
  states: list(),
  university_ids: ids(),
  modes: z.array(z.enum(["Online", "ODL", "Regular"])).max(3),
  levels: z.array(z.enum(["UG", "PG", "DIPLOMA", "CERTIFICATE"])).max(4),
  campaign_contains: z.string().trim().max(100),
  /** The attribution label (D38): paid leads only, organic only, or any. */
  paid: z.enum(["yes", "no", "any"]).default("any"),
});

/** The rule form → b2b.routing_rule_save payload (empty conditions are left out, so they match everything). */
export function parseRuleForm(form: FormData) {
  const get = (k: string) => (typeof form.get(k) === "string" ? (form.get(k) as string) : "");
  const parsed = RuleSchema.safeParse({
    id: get("id"), name: get("name"), priority: get("priority") || "100", action: get("action"),
    partner_ids: form.getAll("partner_ids").map(String), b2c_lane: get("b2c_lane") || null, sources: get("sources"), course_keys: get("course_keys"),
    specializations: get("specializations"), states: get("states"), university_ids: form.getAll("university_ids").map(String).filter(Boolean),
    modes: form.getAll("modes").map(String), levels: form.getAll("levels").map(String), campaign_contains: get("campaign_contains"), paid: get("paid") || "any",
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
  if (d.specializations.length) conditions.specializations = d.specializations;
  if (d.states.length) conditions.states = d.states;
  if (d.university_ids.length) conditions.university_ids = d.university_ids;
  if (d.modes.length) conditions.modes = d.modes;
  if (d.levels.length) conditions.levels = d.levels;
  if (d.campaign_contains) conditions.campaign_contains = d.campaign_contains;
  if (d.paid !== "any") conditions.paid = d.paid === "yes";
  const toB2c = d.action === "to_b2c";
  return { ok: true as const, data: { id: d.id, name: d.name, priority: d.priority, action: d.action, partner_ids: toB2c ? [] : d.partner_ids,
    b2c_lane: toB2c ? d.b2c_lane : null, conditions } };
}

/** Plain-language summary of a rule's conditions; university names are optional (ids are shown otherwise). */
export function describeConditions(c: Record<string, unknown>, universityNames: Record<string, string> = {}): string {
  const parts: string[] = [];
  const arr = (k: string) => (Array.isArray(c[k]) ? (c[k] as unknown[]).map(String) : []);
  if (arr("course_keys").length) parts.push(arr("course_keys").map((s) => s.toUpperCase()).join(" or "));
  if (arr("specializations").length) parts.push(arr("specializations").join(" or "));
  if (arr("levels").length) parts.push(arr("levels").join(" or "));
  if (arr("modes").length) parts.push(arr("modes").join(" or "));
  if (arr("university_ids").length) parts.push(`at ${arr("university_ids").map((id) => universityNames[id] ?? `university #${id}`).join(", ")}`);
  if (arr("sources").length) parts.push(`from ${arr("sources").join(", ")}`);
  if (arr("states").length) parts.push(`in ${arr("states").join(", ")}`);
  if (typeof c.campaign_contains === "string" && c.campaign_contains) parts.push(`campaign contains “${c.campaign_contains}”`);
  if (typeof c.paid === "boolean") parts.push(c.paid ? "from paid Meta / Google ads" : "not from paid ads");
  return parts.length ? `Leads for ${parts.join(", ")}` : "Every lead";
}

/** The engine settings form (Addendum 3): only the keys b2b.engine_settings_save accepts, with its ranges (m31l). The rulebook
 *  numbers (engine.a3_fixed) are not here: the save refuses them. Numbers go through reqNum: a blank field is an error, never 0. */
export const EngineSchema = z.object({
  consent_policy: z.enum(["ask", "b2c_sales"], { error: "'ask' (R8 asks the student) or 'B2C sales' (no partners without consent)" }),
  consent_admin_yes: checkbox(),
  consent_requests_per_hour: reqNum("10 to 1000 requests an hour").pipe(z.number().int("A whole number").min(10, "10 to 1000 requests an hour").max(1000, "10 to 1000 requests an hour")),
  witty_unqualified_idle_hours: reqNum("1 to 72 hours").pipe(z.number().min(1, "1 to 72 hours").max(72, "1 to 72 hours")),
  reenquiry_quiet_hours: reqNum("1 to 168 hours").pipe(z.number().int("A whole number").min(1, "1 to 168 hours").max(168, "1 to 168 hours")),
  max_interests: reqNum("1 to 10 interests").pipe(z.number().int("A whole number").min(1, "1 to 10 interests").max(10, "1 to 10 interests")),
  criteria_unknown: z.enum(["pass", "fail"], { error: "send or do not send when the lead's data is unknown" }),
  welcome_for_all_nurture: checkbox(),
  require_verified_phone_sources: list(50).transform((a) => a.map((s) => s.toLowerCase())),
  ...performanceFields,
  requalify_enabled: checkbox(),
  requalify_wait_for_chat_gate: checkbox(),
  requalify_max_per_run: reqNum("10 to 100 leads a run").pipe(z.number().int("A whole number").min(10, "10 to 100 leads a run").max(100, "10 to 100 leads a run")),
  guard_duplicate_rate_pause: checkbox(),
  half_life_days: reqNum("7 to 120 days").pipe(z.number().int("A whole number").min(7, "7 to 120 days").max(120, "7 to 120 days")),
  prior_weight: reqNum("1 to 100 leads").pipe(z.number().min(1, "1 to 100 leads").max(100, "1 to 100 leads")),
  /** A percentage in the form (0.1–50), a share in the payload (0.001–0.5). */
  default_p_enroll: reqNum("0.1 to 50%").pipe(z.number().min(0.1, "0.1 to 50%").max(50, "0.1 to 50%")).transform((v) => Math.round(v * 100) / 10000),
  reason: z.string().trim().min(3, "Say why you are changing the engine").max(300),
}).superRefine(performanceRefine);

export type EngineForm = z.infer<typeof EngineSchema>;
/** Every field name of the engine form (for reading FormData). */
export const ENGINE_FIELDS = Object.keys(EngineSchema.shape) as (keyof EngineForm)[];

/** The parsed engine form → b2b.engine_settings_save's partial update (the reason goes in p_reason). */
export function enginePayload(d: EngineForm) {
  return {
    consent_policy: d.consent_policy,
    consent_admin_yes: d.consent_admin_yes,
    consent_requests_per_hour: d.consent_requests_per_hour,
    witty_unqualified_idle_hours: d.witty_unqualified_idle_hours,
    reenquiry_quiet_hours: d.reenquiry_quiet_hours,
    max_interests: d.max_interests,
    criteria_unknown: d.criteria_unknown,
    welcome_for_all_nurture: d.welcome_for_all_nurture,
    require_verified_phone_sources: d.require_verified_phone_sources,
    ...performancePayload(d),
    requalify: { enabled: d.requalify_enabled, wait_for_chat_gate: d.requalify_wait_for_chat_gate, max_per_run: d.requalify_max_per_run },
    guard: { duplicate_rate_pause: d.guard_duplicate_rate_pause },
    half_life_days: d.half_life_days,
    prior_weight: d.prior_weight,
    default_p_enroll: d.default_p_enroll,
  };
}

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
  gst_inclusive: checkbox(),
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

const DOMAIN_RE = /^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/;

/** Hand-off settings (Addenda 1–3): B2C-created sources, blocked phones, the junk CAPI signal and the spam rules (R5). The
 *  paid rule is gone: paid is an attribution label (D38). */
export const HandoffSchema = z.object({
  b2c_sources: list(30),
  blocked_phones: list(500, 10000).refine((a) => a.every((p) => /^\d{10,15}$/.test(p.replace(/\D/g, ""))), "Each number needs 10 to 15 digits"),
  junk_capi_signal: checkbox(),
  spam_use_witty_blocks: checkbox(),
  spam_disposable_email_domains: list(500, 20000).transform((a) => a.map((d) => d.toLowerCase()))
    .refine((a) => a.every((d) => DOMAIN_RE.test(d)), "Each entry is a domain like mailinator.com"),
  spam_max_leads_per_ip_hour: reqNum("1 to 100 leads an hour").pipe(z.number().int("A whole number").min(1, "1 to 100 leads an hour").max(100, "1 to 100 leads an hour")),
  spam_max_leads_per_fingerprint_hour: reqNum("1 to 100 leads an hour").pipe(z.number().int("A whole number").min(1, "1 to 100 leads an hour").max(100, "1 to 100 leads an hour")),
  reason: z.string().trim().min(3, "Say why you are changing the hand-off rules").max(300),
});
export const HANDOFF_FIELDS = Object.keys(HandoffSchema.shape) as (keyof z.infer<typeof HandoffSchema>)[];

/** The form's flat fields → b2b.handoff_settings_save's payload (m31g). */
export function handoffPayload(d: z.infer<typeof HandoffSchema>) {
  return {
    b2c_sources: d.b2c_sources,
    blocked_phones: d.blocked_phones,
    junk_capi_signal: d.junk_capi_signal,
    spam: {
      use_witty_blocks: d.spam_use_witty_blocks,
      disposable_email_domains: d.spam_disposable_email_domains,
      max_leads_per_ip_hour: d.spam_max_leads_per_ip_hour,
      max_leads_per_fingerprint_hour: d.spam_max_leads_per_fingerprint_hour,
    },
  };
}

const markerList = (name: string) => list(50, 4000).transform((a) => a.map((s) => s.toLowerCase()))
  .refine((a) => a.every((s) => s.length <= 60), `${name}: each entry is at most 60 characters`);

/** Attribution settings (D38; m31g attribution_settings_save): what marks an influencer or referral lead, which campaigns are
 *  never paid, and which Meta ad parameters identify an ad. */
export const AttributionSchema = z.object({
  influencer_lead_sources: markerList("Lead sources"),
  influencer_utm_values: markerList("UTM values"),
  exclude_campaigns: markerList("Excluded campaigns"),
  meta_ad_params: markerList("Meta ad parameters").refine((a) => a.every((s) => /^[a-z0-9_]+$/.test(s)), "Use parameter names like ad_id (letters, digits and underscores)"),
  reason: z.string().trim().min(3, "Say why you are changing attribution").max(300),
});
export const ATTRIBUTION_FIELDS = Object.keys(AttributionSchema.shape) as (keyof z.infer<typeof AttributionSchema>)[];

/** The form's flat fields → b2b.attribution_settings_save's payload. */
export function attributionPayload(d: z.infer<typeof AttributionSchema>) {
  return {
    influencer_markers: { lead_sources: d.influencer_lead_sources, utm_values: d.influencer_utm_values },
    exclude_campaigns: d.exclude_campaigns,
    meta_ad_params: d.meta_ad_params,
  };
}

/** The stored `attribution` setting (m31a seed; attribution_settings_save). */
export type AttributionSettings = {
  influencer_markers?: { lead_sources?: string[]; utm_values?: string[] };
  exclude_campaigns?: string[];
  meta_ad_params?: string[];
} & Record<string, unknown>;
