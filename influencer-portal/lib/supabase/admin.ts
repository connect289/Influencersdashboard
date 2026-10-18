import "server-only";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/database.types";
import { env } from "@/lib/env";

function make() {
  return createClient<Database, "inf">(env().NEXT_PUBLIC_SUPABASE_URL, env().SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    db: { schema: "inf" },
  });
}

let client: ReturnType<typeof make> | null = null;

/**
 * Service-role client (bypasses RLS). Server only, and only for: signed-out flows (lockout, sign-in log, issuing the
 * emailed code), creating auth users for invited people, machine endpoints that authenticate their caller first, and
 * system work that follows a person's completed action (the deal for an accepted offer; Eduwit-only simulator inputs
 * that are never returned to a creator).
 * Everything a person does runs as that person through lib/supabase/server.ts.
 */
export function adminClient() {
  client ??= make();
  return client;
}
