// Environment access. NEXT_PUBLIC_* names must stay literal so Next.js can inline them into browser code.

function required(name: string, value: string | undefined): string {
  if (!value) throw new Error(`Missing environment variable ${name}. See b2b-crm/web/.env.example.`);
  return value;
}

export function supabaseUrl(): string {
  return required("NEXT_PUBLIC_SUPABASE_URL", process.env.NEXT_PUBLIC_SUPABASE_URL);
}

export function supabasePublishableKey(): string {
  return required("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY);
}

/**
 * How long a Data API (PostgREST) call may wait for its answer: db.timeout on the server-side Supabase clients that make
 * such calls (/api/health has its own 3 s; proxy.ts only uses Auth).
 * The database ends a statement at 8 s (3 s for anon), so 15 s cuts only a stalled network or connection, never a query.
 * A call that is cut does not throw: it comes back as { data: null, error } like any other failed request.
 */
export const DB_TIMEOUT_MS = 15_000;

/** Base URL used in emailed links. Taken from configuration, never from request headers (host-header injection). */
export function siteUrl(): string {
  return required("NEXT_PUBLIC_SITE_URL", process.env.NEXT_PUBLIC_SITE_URL).replace(/\/+$/, "");
}

/** The same, or null when it is not set: for a screen that only offers it as a default (M34j, the CRM web address). */
export function siteUrlIfSet(): string | null {
  const v = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/, "");
  return v ? v : null;
}
