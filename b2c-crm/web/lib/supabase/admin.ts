import "server-only";
import { createClient } from "@supabase/supabase-js";
import { supabaseUrl } from "@/lib/env";

let client: ReturnType<typeof make> | null = null;

function make() {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw new Error("Missing environment variable SUPABASE_SERVICE_ROLE_KEY. See b2c-crm/web/.env.example.");
  return createClient(supabaseUrl(), key, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    // The database ends a call after 8 seconds; 15 s here only cuts one whose answer never arrives ({ data: null, error }, not a throw).
    db: { schema: "b2c", timeout: 15_000 },
  });
}

/**
 * Service-role client, schema b2c. Server only, and used only for: signed-out flows (sign-in log, lockout, issuing the
 * emailed code) and the machine endpoints (B2B webhooks, WhatsApp webhooks, the sync jobs), each of which authenticates
 * its caller first. Everything a person does runs as that person.
 */
export function adminClient() {
  client ??= make();
  return client;
}
