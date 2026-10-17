import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { connection } from "next/server";
import { env } from "./env";

/**
 * Supabase Auth client for STAFF sessions only (admin). Uses the publishable key and the request cookies; students
 * never sign in through Supabase Auth (D-005).
 */
export async function staffAuth() {
  // Staff sessions are per request: never part of a prerendered shell.
  await connection();
  const store = await cookies();
  const e = env();
  if (!e.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY) throw new Error("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY is not set");
  return createServerClient(e.NEXT_PUBLIC_SUPABASE_URL, e.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (list) => {
        try {
          for (const { name, value, options } of list) store.set(name, value, options);
        } catch {
          // called from a Server Component render: cookies are refreshed by proxy.ts instead
        }
      },
    },
  });
}
