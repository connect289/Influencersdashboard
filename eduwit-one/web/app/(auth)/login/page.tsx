import { type Metadata } from "next";
import { buttonClass } from "@/components/ui/button.tsx";
import { Banner } from "@/components/ui/state.tsx";
import { safeNext } from "@/lib/security.ts";

export const metadata: Metadata = { title: "Sign in" };

const errors: Record<string, string> = {
  domain: "Only @eduwit.in Google accounts can sign in. The attempt was logged.",
  oauth: "Google sign-in did not complete. Try again.",
  not_configured:
    "The app is not connected to its database yet: set ONE_SUPABASE_URL and ONE_SUPABASE_ANON_KEY in the Vercel project (Setup item one_app_env).",
  schema_not_exposed:
    "Sign-in worked, but the app cannot reach its data: in Supabase, add one under Project settings → Data API → Exposed schemas (Setup item supabase_api_schema).",
  unreachable: "The database did not answer. Try again in a minute.",
};
const reasons: Record<string, string> = {
  idle: "You were signed out after 12 hours without activity.",
  signed_out: "You are signed out.",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>;
}) {
  const params = await searchParams;
  const error = params.error ? (errors[params.error] ?? errors.oauth) : null;
  const reason = params.reason ? reasons[params.reason] : null;
  return (
    <div className="grid gap-4">
      <div>
        <h1 className="text-xl font-semibold">Sign in</h1>
        <p className="mt-1 text-sm text-fg-muted">
          With your @eduwit.in Google account, then a code sent to your inbox.
        </p>
      </div>
      {error ? <Banner tone="p1">{error}</Banner> : null}
      {reason ? <Banner tone="p3">{reason}</Banner> : null}
      <form method="post" action="/auth/google">
        <input type="hidden" name="next" value={safeNext(params.next)} />
        <button type="submit" className={buttonClass("primary", "md", "w-full")}>
          Continue with Google
        </button>
      </form>
    </div>
  );
}
