"use client";
import Link from "next/link";
import { useActionState } from "react";
import { ArrowLeft } from "lucide-react";
import { Field, Input } from "@/components/ui/Field";
import { Notice } from "@/components/ui/Notice";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { requestPasswordReset } from "../actions";

export default function ForgotPage() {
  const [state, action] = useActionState(requestPasswordReset, undefined);
  return (
    <div>
      <Link href="/login" className="mb-8 inline-flex items-center gap-1.5 text-[13px] text-muted hover:text-fg">
        <ArrowLeft className="size-3.5" /> Back to sign in
      </Link>
      <h1 className="text-2xl font-semibold tracking-tight text-fg">Reset your password</h1>
      <p className="mt-1.5 text-sm text-muted">We'll email a link to set a new one.</p>
      <div className="mt-6 space-y-3">
        {state?.error && <Notice tone="error">{state.error}</Notice>}
        {state?.notice && <Notice tone="success">{state.notice}</Notice>}
      </div>
      {!state?.notice && (
        <form action={action} className="mt-6 space-y-4" noValidate>
          <Field label="Email" htmlFor="email">
            <Input id="email" name="email" type="email" autoComplete="username" required />
          </Field>
          <SubmitButton size="lg" className="w-full justify-center" pendingLabel="Sending…">Send reset link</SubmitButton>
        </form>
      )}
    </div>
  );
}
