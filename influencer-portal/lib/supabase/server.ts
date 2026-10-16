import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "@/lib/database.types";
import { publicEnv } from "@/lib/env-public";
import { forwardedHeaders, requestContext } from "@/lib/request-context";

/**
 * Supabase client acting as the signed-in person: RLS and every inf.* permission check apply. One per request.
 * The browser's IP, user agent and a request id are forwarded so the audit log records them.
 */
export async function createClient() {
  const store = await cookies();
  const ctx = await requestContext();
  return createServerClient<Database, "inf">(publicEnv.supabaseUrl, publicEnv.supabaseKey, {
    db: { schema: "inf" },
    global: { headers: forwardedHeaders(ctx) },
    cookies: {
      getAll: () => store.getAll(),
      setAll(toSet) {
        try {
          for (const { name, value, options } of toSet) store.set(name, value, options);
        } catch {
          // Server Components can't set cookies; proxy.ts refreshes the session on every request.
        }
      },
    },
  });
}

export type ServerSupabase = Awaited<ReturnType<typeof createClient>>;
