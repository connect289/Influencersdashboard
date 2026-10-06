import "server-only";
import { createClient } from "@supabase/supabase-js";
import { supabaseUrl } from "@/lib/env";

let client: ReturnType<typeof make> | null = null;

function make() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error("Missing environment variable SUPABASE_SERVICE_ROLE_KEY. See b2b-crm/web/.env.example.");
  return createClient(supabaseUrl(), key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    db: { schema: "b2b" },
  });
}

/**
 * Service-role client, schema b2b. Server only, and used only for: what a signed-out visitor needs (logging sign-in
 * attempts, the lockout check, the reset-link allowlist check) and the private partner-file bucket, after
 * assertAdmin() (lib/programme-file.ts). Everything else runs as the user under RLS.
 */
export function adminClient() {
  client ??= make();
  return client;
}
