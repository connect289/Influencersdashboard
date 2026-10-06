"use client";
import { useActionState } from "react";
import { Field, Input } from "@/components/ui/Field";
import { Notice } from "@/components/ui/Notice";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { PASSWORD_MIN } from "@/lib/security";
import { updatePassword } from "../actions";

export default function ResetPage() {
  const [state, action] = useActionState(updatePassword, undefined);
  return (
    <div>
      <h1 className="text-2xl font-semibold tracking-tight text-fg">Choose a new password</h1>
      <p className="mt-1.5 text-sm text-muted">At least {PASSWORD_MIN} characters. A passphrase of four or more words works well.</p>
      {state?.error && <Notice tone="error" className="mt-6">{state.error}</Notice>}
      <form action={action} className="mt-6 space-y-4" noValidate>
        <Field label="New password" htmlFor="password">
          <Input id="password" name="password" type="password" autoComplete="new-password" required minLength={PASSWORD_MIN} maxLength={128} />
        </Field>
        <Field label="Repeat it" htmlFor="confirm">
          <Input id="confirm" name="confirm" type="password" autoComplete="new-password" required minLength={PASSWORD_MIN} maxLength={128} />
        </Field>
        <SubmitButton size="lg" className="w-full justify-center" pendingLabel="Saving…">Save password</SubmitButton>
      </form>
    </div>
  );
}
