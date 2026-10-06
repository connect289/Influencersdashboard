import "server-only";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

/**
 * Reads run as the signed-in Admin; RLS (b2b.is_admin()) is the gate. Each helper is one round trip, memoised per
 * request with React cache() so the layout and the page never repeat the same query.
 */

export type LiveSwitch = { scope: string; live: boolean; reason: string | null; switched_at: string | null };
export type B2bEvent = { id: number; occurred_at: string; type: string; actor_type: string; payload: Record<string, unknown> };
export type SignInRow = { id: number; at: string; email: string | null; method: string; outcome: string; ip: string | null; user_agent: string | null };
export type Session = { id: string; created_at: string; updated_at: string | null; refreshed_at: string | null; aal: string | null; user_agent: string | null; ip: string | null; current: boolean };

export const liveSwitches = cache(async (): Promise<LiveSwitch[]> => {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").from("live_switches").select("scope, live, reason, switched_at").order("scope");
  if (error) throw new Error(error.message);
  return data ?? [];
});

export async function recentEvents(limit = 8): Promise<B2bEvent[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").from("events")
    .select("id, occurred_at, type, actor_type, payload").order("occurred_at", { ascending: false }).limit(limit);
  if (error) throw new Error(error.message);
  return data ?? [];
}

export async function signInHistory(limit = 25): Promise<SignInRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").from("sign_in_log")
    .select("id, at, email, method, outcome, ip, user_agent").order("at", { ascending: false }).limit(limit);
  if (error) throw new Error(error.message);
  return (data ?? []) as SignInRow[];
}

export async function mySessions(): Promise<Session[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.schema("b2b").rpc("my_sessions");
  if (error) throw new Error(error.message);
  return (data ?? []) as Session[];
}
