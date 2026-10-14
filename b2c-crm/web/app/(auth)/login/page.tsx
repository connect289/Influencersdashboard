import type { Metadata } from "next";
import { safeNext } from "@/lib/security";
import { LoginForm } from "./LoginForm";

export const metadata: Metadata = { title: "Sign in" };

const ERRORS: Record<string, string> = {
  setup: "Sign-in worked, but the app cannot reach its data yet. The Admin must expose the b2c schema in Supabase (README step 1).",
  domain: "Only @eduwit.in accounts can sign in. The attempt was logged.",
  oauth: "Google sign-in was cancelled or failed. Try again.",
  link: "That sign-in link is invalid or has expired.",
  locked: "Too many failed attempts. Sign-in is locked for 15 minutes.",
};
const NOTICES: Record<string, string> = {
  idle: "You were signed out after 12 hours without activity.",
  signed_out: "You are signed out.",
};

export default async function LoginPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  return (
    <LoginForm
      next={safeNext(sp.next)}
      error={sp.error ? ERRORS[sp.error] ?? "Sign-in failed. Try again." : null}
      notice={sp.reason ? NOTICES[sp.reason] ?? null : null}
    />
  );
}
