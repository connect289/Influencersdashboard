"use client";
import { useActionState, useState } from "react";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { createClient } from "@/lib/supabase/browser";
import { signInWithPassword } from "../actions";

function GoogleIcon() {
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" aria-hidden>
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
        // hd limits Google's account picker to the company domain; the server checks the domain again.
        queryParams: { prompt: "select_account", hd: "eduwit.in" },
      },
    });
    if (oauthError) setGoogle("failed");
  }

  const shownError = state?.error ?? (google === "failed" ? "Google sign-in could not start. Try again." : error);

  return (
    <div className="stack">
      <div>
        <h1>Sign in</h1>
        <p className="muted small">For Eduwit staff with an @eduwit.in account.</p>
      </div>
      {shownError && <div className="banner danger" role="alert">{shownError}</div>}
      {!shownError && notice && <div className="banner info">{notice}</div>}
      <button type="button" className="btn ghost block" onClick={signInWithGoogle} disabled={google === "busy"}>
        <GoogleIcon /> {google === "busy" ? "Opening Google…" : "Continue with Google"}
      </button>
      <div className="or">or with email</div>
      <form action={action} className="stack" noValidate>
        <input type="hidden" name="next" value={next} />
        <label className="field">
          <span>Email</span>
          <input className="input" name="email" type="email" autoComplete="username" inputMode="email" required placeholder="you@eduwit.in" />
        </label>
        <label className="field">
          <span>Password</span>
          <input className="input" name="password" type="password" autoComplete="current-password" required maxLength={128} />
        </label>
        <SubmitButton className="btn primary block" pendingLabel="Signing in…">Sign in</SubmitButton>
      </form>
      <p className="note">There is no sign-up: the Admin adds you. After signing in we email a code to your company inbox, unless this device is trusted.</p>
    </div>
  );
}
