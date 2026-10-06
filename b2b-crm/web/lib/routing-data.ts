import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { ProgrammeLabel } from "@/lib/programmes-data";
import type { Candidate, Decision, Interest } from "@/lib/routing";

/** Routing reads as the signed-in Admin; every b2b.routing_* / lead_routing function re-checks b2b.is_admin(). */

export type DecisionRow = {
  id: number; lead_id: number; lead_name: string | null; segment: string | null; mode: string; destination_type: "partner" | "in_house";
  winner_partner_id: number | null; partner_name: string | null; reason: string | null; selection_probability: number | null; is_test: boolean;
  actor_type: string; created_at: string; b2c_lane: "sales" | "nurture" | null;
  allocation: { id: number; reference: string; status: string; cpe_net_inr: number | null; b2c_lane: "sales" | "nurture" | null; outcome: string | null } | null;
};

export type StoredDecision = DecisionRow & {
  interest: Interest; candidates: Candidate[]; excluded: Decision["excluded"]; rules: Decision["rules"]; seed: number | null; settings_version: number | null;
};

export type Rule = {
  id: number; name: string; priority: number; conditions: Record<string, unknown>; action: string; partner_ids: number[]; partner_names: string[] | null;
  b2c_lane: "sales" | "nurture" | null;
  active: boolean; version: number; updated_at: string;
};

export type Rate = {
  id: number; scope: string; partner_id: number; partner_name: string | null; programme_id: number | null; programme: ProgrammeLabel | null;
  rate_type: string; fee_base: string; value: number | null; gst_inclusive: boolean; valid_from: string; valid_to: string | null; source: string; note: string | null;
};

export type EngineSettings = {
  exploration_share?: number; cpe_aggregate?: string; min_learning_leads?: number; attempt_limit?: number; partner_limit?: number;
  witty_idle_minutes?: number; require_partner_consent?: boolean; trusted_sources?: string[]; enabled?: boolean; kill_switch?: boolean;
  paid_rule?: { sources?: string[]; click_ids?: string[]; utm_mediums?: string[]; include_campaigns?: string[]; exclude_campaigns?: string[] };
  b2c_sources?: string[]; blocked_phones?: string[]; junk_capi_signal?: boolean;
};

/** A passed lead that Witty later classified junk or mismatch, waiting for the Admin (Addendum 2). */
export type ReviewFlag = {
  id: number; lead_id: number; lead_name: string | null; lead_status: string | null; destination_type: "partner" | "in_house";
  reference: string | null; partner_name: string | null; created_at: string;
};

export type NotPassed = {
  lead_id: number; reason: string; lead_status: string | null; requested_course: string | null; lead_source: string | null;
  decided_at: string; passed_at: string | null; pass_note: string | null; times: number;
};

export type RoutingOverview = {
  switch: { live: boolean; reason?: string | null; switched_at?: string | null };
  engine: { value: EngineSettings; version: number; updated_at: string };
  live_partners: number;
  partners: { id: number; name: string; status: string; live: boolean; test_endpoint: boolean; offers: number; proposed: number }[];
  today: { to_partners: number; to_b2c: number; tests: number; b2c_reasons: Record<string, number>; errors: number; nurture: number; sales: number; not_passed: number };
  not_passed_open: number;
  flags_open: ReviewFlag[];
  decisions: DecisionRow[];
  rules: Rule[];
  rates: Rate[];
};

export type LeadRouting = {
  readiness: Decision["readiness"]; interest: Interest; consent: boolean; routing_live: boolean;
  not_passed: NotPassed | null;
  flags: { id: number; allocation_id: number; lead_status: string | null; destination_type: string; created_at: string; resolved_at: string | null; resolution: string | null }[];
  decisions: StoredDecision[];
  allocations: {
    id: number; reference: string | null; status: string; destination_type: string; partner_name: string | null; mode: string; reason: string | null;
    b2c_lane: "sales" | "nurture" | null; outcome: string | null; created_at: string;
  }[];
  /** Messages to the student (m9c). */
  notifications?: {
    id: number; channel: "whatsapp" | "email"; kind: string; language: string; status: string; error: string | null;
    scheduled_for: string | null; sent_at: string | null; created_at: string; partner_name: string | null;
  }[];
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

export type NotPassedSummary = { by_reason: Record<string, number>; by_source: Record<string, number>; mismatch_courses: { course: string; n: number }[] };
export const notPassedSummary = () => rpc<NotPassedSummary>("not_passed_summary");
