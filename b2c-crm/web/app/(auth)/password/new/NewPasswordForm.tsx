"use client";
import { useActionState } from "react";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { setPassword } from "../../actions";

export function NewPasswordForm({ email }: { email: string }) {
  const [state, action] = useActionState(setPassword, undefined);
  return (
    <div className="stack">
      <div>
        <h1>New password</h1>
        <p className="muted small">For {email}. At least 12 characters; a short sentence is easy to remember. Then we email you a 6-digit code as usual.</p>
      </div>
      {state?.error && <div className="banner danger" role="alert">{state.error}</div>}
      <form action={action} className="stack">
        <input type="email" name="username" autoComplete="username" value={email} readOnly hidden />
        <label className="field">
          <span>New password</span>
          <input className="input" name="password" type="password" autoComplete="new-password" required minLength={12} maxLength={128} />
        </label>
        <label className="field">
          <span>Again</span>
          <input className="input" name="again" type="password" autoComplete="new-password" required minLength={12} maxLength={128} />
        </label>
        <SubmitButton className="btn primary block" pendingLabel="Saving…">Save password</SubmitButton>
      </form>
    </div>
  );
}
