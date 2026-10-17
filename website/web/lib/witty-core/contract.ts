/**
 * Witty's qualification contract, exactly as published in production (docs/discovery/witty.md §4–5): fact keys, ops,
 * asks, phases, answer modes, intents, classification, readiness, eligibility, languages. Channel-agnostic; no Next,
 * React or n8n dependencies, so Witty's own build can import this module (docs/AGENT_ARCHITECTURE.md §3.1).
 */
export const CONTRACT_VERSION = "witty-2.0-observed-2026-10-17";

export const FACT_KEYS = [
  "student_name",
  "last_name",
  "email_id",
  "interested_course",
  "specialization",
  "field_of_interest",
  "program_level",
  "highest_qualification",
  "current_study",
  "academic_score",
  "annual_budget",
  "enrollment_timeline",
  "primary_motivation",
  "study_mode_preference",
  "current_city_country",
  "study_destination",
  "university_preference",
  "work_experience_years",
  "current_job_role",
  "chosen_program",
] as const;
export type FactKey = (typeof FACT_KEYS)[number];

export const OPS = ["set", "correct", "confirm", "negate", "declined", "unsure"] as const;
export type Op = (typeof OPS)[number];
export const SUBJECTS = ["self", "child", "sibling", "other"] as const;
export type Subject = (typeof SUBJECTS)[number];
export const SCALES = ["percent", "cgpa10", "gpa4", "unknown"] as const;
export type Scale = (typeof SCALES)[number];
export const CONFIDENCE = ["HIGH", "MEDIUM", "LOW"] as const;
export type Confidence = (typeof CONFIDENCE)[number];

export const ASKS = [
  "ASK_NAME",
  "ASK_LAST_NAME",
  "CONFIRM_NAME",
  "ASK_QUALIFICATION",
  "ASK_SCORE",
  "ASK_QUAL_AND_SCORE",
  "ASK_QUAL_AND_COURSE",
  "ASK_COURSE",
  "ASK_SPECIALIZATION",
  "ASK_EMAIL",
  "ASK_BUDGET",
  "ASK_TIMELINE",
  "ASK_STUDY_MODE",
  "ASK_MOTIVATION",
  "ASK_UNIVERSITY",
  "CONFIRM_COURSE",
  "OFFER_HANDOFF",
  "NONE",
] as const;
export type Ask = (typeof ASKS)[number];

export const PHASES = ["EARN_IT", "QUALIFY_IT", "ENRICH_IT", "ESCALATION", "SUPPORT"] as const;
export type Phase = (typeof PHASES)[number];

/** LLM-written modes, then fixed-text modes. */
export const LLM_MODES = ["ACK", "DIRECTIONAL", "PROGRAMS", "NO_MATCH", "NOT_ELIGIBLE", "ANSWER", "CLOSE", "SUPPORT"] as const;
export const FIXED_MODES = ["GREETING", "GATE", "HANDOFF"] as const;
export type AnswerMode = (typeof LLM_MODES)[number] | (typeof FIXED_MODES)[number];

export const INTENTS = [
  "asks_programs",
  "asks_fees",
  "asks_eligibility",
  "asks_human",
  "wants_to_apply",
  "pay_after_placement",
  "general_question",
  "already_enrolled",
  "wants_alternatives",
  "complaint",
  "not_interested",
  "closing",
  "stop",
  "declines_sharing",
  "erasure_request",
  "accepted_offer",
] as const;
export type Intent = (typeof INTENTS)[number];

export const CLASSIFICATIONS = ["UNQUALIFIED", "HOT", "WARM", "COLD", "PROGRAM_MISMATCH", "JUNK"] as const;
export type Classification = (typeof CLASSIFICATIONS)[number];
export const READINESS = ["EXPLORING", "PLANNING", "READY_NOW"] as const;
export type Readiness = (typeof READINESS)[number];
/** NOT_ELIGIBLE is implied by answer mode NOT_ELIGIBLE (witty.md §4.3); the others are observed values. */
export const ELIGIBILITY = ["INSUFFICIENT_DATA", "LIKELY_ELIGIBLE", "ELIGIBLE", "NOT_ELIGIBLE", "PROGRAM_MISMATCH"] as const;
export type Eligibility = (typeof ELIGIBILITY)[number];
export const LANGUAGES = ["english", "hinglish", "hindi"] as const;
export type Language = (typeof LANGUAGES)[number];

/** CRM event types, in precedence order (witty.md §4.5). */
export const EVENT_TYPES = ["lead.escalated", "lead.qualified", "classification_changed", "lead.updated", "chat.turn", "lead.interest"] as const;
export type EventType = (typeof EVENT_TYPES)[number];

/** Placeholder fields the counselor may use (counselor prompt rule 1). */
export const PLACEHOLDER_FIELDS = [
  "program",
  "university",
  "mode",
  "specialization",
  "fee",
  "fee_yearly",
  "fee_semester",
  "fee_total",
  "fee_exam",
  "fee_registration",
  "min_pct",
  "brochure",
] as const;
export type PlaceholderField = (typeof PLACEHOLDER_FIELDS)[number];

/** A catalogue row as returned by w2_search_programs (witty.md §6). */
export interface CatalogRow {
  id: number;
  university: string;
  university_short?: string | null;
  level?: string | null;
  course?: string | null;
  specialization?: string | null;
  program_name?: string | null;
  mode?: string | null;
  fee_yearly?: number | null;
  fee_semester?: number | null;
  fee_total?: number | null;
  fee_exam?: number | null;
  fee_registration?: number | null;
  min_qualification?: string | null;
  min_pct_general?: number | null;
  min_pct_reserved?: number | null;
  brochure_url?: string | null;
  dual?: boolean | null;
  fee_emi?: number | null;
  pay_after_placement?: boolean | null;
  loan_available?: boolean | null;
  match?: number | null;
  uni_match?: boolean | null;
}

export interface SearchResult {
  rows: CatalogRow[];
  total_for_course?: number | null;
  visible_total?: number | null;
  course_key?: string | null;
  specializations?: string[] | null;
  modes?: string[] | null;
  spec_matched?: boolean | null;
  mode_matched?: boolean | null;
  universities?: { name: string; short_name?: string | null }[] | null;
}

export interface Knowledge {
  ref: string;
  doc: string;
  text: string;
}
