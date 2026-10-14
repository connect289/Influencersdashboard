"use client";
import { useActionState } from "react";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { sendCode, verifyCode } from "../actions";

export function VerifyForm({ next, email }: { next: string; email: string }) {
  const [sent, send] = useActionState(sendCode, undefined);
  const [checked, check] = useActionState(verifyCode, undefined);
  const error = checked?.error ?? sent?.error;
  return (
    <div className="stack">
      <div>
        <h1>Check your email</h1>
        <p className="muted small">We send a 6-digit code to {email}. It keeps your account safe if a password leaks.</p>
      </div>
      {error && <div className="banner danger" role="alert">{error}</div>}
      {sent?.notice && !error && <div className="banner info" role="status">{sent.notice}</div>}
      <form action={send}>
        <SubmitButton className="btn ghost block" pendingLabel="Sending…">{sent?.notice ? "Send a new code" : "Email me a code"}</SubmitButton>
      </form>
      <form action={check} className="stack">
        <input type="hidden" name="next" value={next} />
        <label className="field">
          <span>Code</span>
          <input className="input code-input" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="\d{6}" maxLength={6} required />
        </label>
        <label className="checkbox">
          <input type="checkbox" name="trust" /> Trust this device for 30 days
        </label>
        <SubmitButton className="btn primary block" pendingLabel="Checking…">Continue</SubmitButton>
      </form>
      <form action="/auth/signout" method="post">
        <button className="btn quiet sm" type="submit">Use another account</button>
      </form>
    </div>
  );
}
