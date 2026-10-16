"use client";
import Link from "next/link";
import { useActionState } from "react";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { requestPasswordLink } from "../actions";

/** First time, or forgot the password: we email a one-time link to the company inbox. */
export function PasswordRequestForm({ expired }: { expired: boolean }) {
  const [state, action] = useActionState(requestPasswordLink, undefined);
  const error = state?.error ?? (expired ? "That link has expired or was already used. Ask for a new one." : null);
  return (
    <div className="stack">
      <div>
        <h1>Set your password</h1>
        <p className="muted small">First time here, or forgot your password? We email a link to your company inbox. It works once, for one hour.</p>
      </div>
      {error && <div className="banner danger" role="alert">{error}</div>}
      {state?.notice && !state.error && <div className="banner info" role="status">{state.notice}</div>}
      <form action={action} className="stack" noValidate>
        <label className="field">
          <span>Email</span>
          <input className="input" name="email" type="email" autoComplete="username" inputMode="email" required placeholder="you@eduwit.in" />
        </label>
        <SubmitButton className="btn primary block" pendingLabel="Sending…">Email me a link</SubmitButton>
      </form>
      <Link href="/login" className="small">Back to sign in</Link>
    </div>
  );
}
