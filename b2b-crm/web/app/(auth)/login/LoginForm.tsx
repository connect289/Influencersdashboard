"use client";
import Link from "next/link";
import { useActionState, useState } from "react";
import { LoaderCircle } from "lucide-react";
import { LogoMark } from "@/components/brand/Logo";
import { Button } from "@/components/ui/Button";
import { Field, Input } from "@/components/ui/Field";
import { Notice } from "@/components/ui/Notice";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { createClient } from "@/lib/supabase/browser";
import { signInWithPassword } from "../actions";

function GoogleIcon() {
  return (
    <svg viewBox="0 0 24 24" className="size-4" aria-hidden>
      <path fill="#4285F4" d="M22.6 12.3c0-.8-.1-1.5-.2-2.3H12v4.3h5.9a5 5 0 0 1-2.2 3.3v2.8h3.6c2.1-1.9 3.3-4.8 3.3-8.1Z" />
      <path fill="#34A853" d="M12 23c3 0 5.5-1 7.3-2.7l-3.6-2.8c-1 .7-2.2 1.1-3.7 1.1-2.9 0-5.3-1.9-6.2-4.5H2.1v2.9A11 11 0 0 0 12 23Z" />
      <path fill="#FBBC05" d="M5.8 14.1a6.6 6.6 0 0 1 0-4.2V7H2.1a11 11 0 0 0 0 10l3.7-2.9Z" />
      <path fill="#EA4335" d="M12 5.4c1.6 0 3.1.6 4.2 1.7l3.2-3.2A11 11 0 0 0 2.1 7l3.7 2.9C6.7 7.3 9.1 5.4 12 5.4Z" />
    </svg>
  );
}

export function LoginForm({ next, error, notice }: { next: string; error: string | null; notice: string | null }) {
  const [state, action] = useActionState(signInWithPassword, undefined);
  const [google, setGoogle] = useState<"idle" | "busy" | "failed">("idle");

  async function signInWithGoogle() {
    setGoogle("busy");
    const { error: oauthError } = await createClient().auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`,
        queryParams: { prompt: "select_account" },
      },
    });
    if (oauthError) setGoogle("failed");
  }

  const shownError = state?.error ?? (google === "failed" ? "Google sign-in could not start. Try again." : error);

  return (
    <div>
      <div className="mb-8 lg:hidden"><LogoMark size={40} /></div>
      <h1 className="text-2xl font-semibold tracking-tight text-fg">Sign in</h1>
      <p className="mt-1.5 text-sm text-muted">Eduwit Partner CRM · Admin access only</p>

      <div className="mt-6 space-y-3">
        {shownError && <Notice tone="error">{shownError}</Notice>}
        {!shownError && notice && <Notice tone="info">{notice}</Notice>}
      </div>

      <Button variant="secondary" size="lg" className="mt-6 w-full justify-center" onClick={signInWithGoogle} disabled={google === "busy"}>
        {google === "busy" ? <LoaderCircle className="size-4 animate-spin" aria-hidden /> : <GoogleIcon />}
        Continue with Google
      </Button>

      <div className="my-6 flex items-center gap-3 text-xs text-subtle">
        <span className="h-px flex-1 bg-border" /> or with email <span className="h-px flex-1 bg-border" />
      </div>

      <form action={action} className="space-y-4" noValidate>
        <input type="hidden" name="next" value={next} />
        <Field label="Email" htmlFor="email">
          <Input id="email" name="email" type="email" autoComplete="username" inputMode="email" required placeholder="you@eduwit.in" />
        </Field>
        <Field label="Password" htmlFor="password" action={<Link href="/forgot" className="text-xs font-medium text-muted hover:text-fg">Forgot password?</Link>}>
          <Input id="password" name="password" type="password" autoComplete="current-password" required minLength={1} maxLength={128} />
        </Field>
        <SubmitButton size="lg" className="w-full justify-center" pendingLabel="Signing in…">Sign in</SubmitButton>
      </form>

      <p className="mt-8 text-center text-xs leading-5 text-subtle">
        There is no sign-up. Password sign-in always asks for a code from your authenticator app.
      </p>
    </div>
  );
}
