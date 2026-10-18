"use client";
import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "@/lib/database.types";
import { publicEnv } from "@/lib/env-public";

/** Browser client: sign-in calls and Realtime subscriptions only. Data reads and writes go through the server. */
export function createClient() {
  return createBrowserClient<Database, "inf">(publicEnv.supabaseUrl, publicEnv.supabaseKey, { db: { schema: "inf" } });
}
