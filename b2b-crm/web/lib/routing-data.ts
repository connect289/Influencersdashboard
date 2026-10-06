import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { ProgrammeLabel } from "@/lib/programmes-data";
import type { Candidate, Decision, Interest } from "@/lib/routing";

/** Routing reads as the signed-in Admin; every b2b.routing_* / lead_routing function re-checks b2b.is_admin(). */

export type DecisionRow = {
  id: number; lead_id: number; lead_name: string | null; segment: string | null; mode: string; destination_type: "partner" | "in_house";
  winner_partner_id: number | null; partner_name: string | null; reason: string | null; selection_probability: number | null; is_test: boolean;
  actor_type: string; created_at: string; allocation: { id: number; reference: string; status: string; cpe_net_inr: number | null } | null;
};

export type StoredDecision = DecisionRow & {
  interest: Interest; candidates: Candidate[]; excluded: Decision["excluded"]; rules: Decision["rules"]; seed: number | null; settings_version: number | null;
};

export type Rule = {
  id: number; name: string; priority: number; conditions: Record<string, unknown>; action: string; partner_ids: number[]; partner_names: string[] | null;
  active: boolean; version: number; updated_at: string;
};

export type Rate = {
  id: number; scope: string; partner_id: number; partner_name: string | null; programme_id: number | null; programme: ProgrammeLabel | null;
  rate_type: string; fee_base: string; value: number | null; gst_inclusive: boolean; valid_from: string; valid_to: string | null; source: string; note: string | null;
};

export type EngineSettings = {
  exploration_share?: number; cpe_aggregate?: string; min_learning_leads?: number; attempt_limit?: number; partner_limit?: number;
  witty_idle_minutes?: number; require_partner_consent?: boolean; trusted_sources?: string[]; enabled?: boolean; kill_switch?: boolean;
};

export type RoutingOverview = {
  switch: { live: boolean; reason?: string | null; switched_at?: string | null };
  engine: { value: EngineSettings; version: number; updated_at: string };
  live_partners: number;
  partners: { id: number; name: string; status: string; live: boolean; test_endpoint: boolean; offers: number; proposed: number }[];
  today: { to_partners: number; to_b2c: number; tests: number; b2c_reasons: Record<string, number>; errors: number };
  decisions: DecisionRow[];
  rules: Rule[];
  rates: Rate[];
};

export type LeadRouting = {
  readiness: Decision["readiness"]; interest: Interest; consent: boolean; routing_live: boolean;
  decisions: StoredDecision[];
  allocations: { id: number; reference: string | null; status: string; destination_type: string; partner_name: string | null; mode: string; reason: string | null; created_at: string }[];
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
