"use client";
import { useActionState, useState, useTransition } from "react";
import { KeyRound, Smartphone } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { Field, Input } from "@/components/ui/Field";
import { Notice } from "@/components/ui/Notice";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { startTotpEnrollment, verifyTotp, type Enrollment } from "../actions";

export function MfaForm({ mode, next, email }: { mode: "verify" | "enroll"; next: string; email: string }) {
  const [state, action] = useActionState(verifyTotp, undefined);
  const [enrollment, setEnrollment] = useState<Enrollment | null>(null);
  const [starting, startTransition] = useTransition();
  const ready = mode === "verify" || (enrollment !== null && !("error" in enrollment));

  return (
    <div>
      <div className="mb-6 grid size-11 place-items-center rounded-xl border border-border bg-surface-2">
        {mode === "verify" ? <KeyRound className="size-5 text-primary" /> : <Smartphone className="size-5 text-primary" />}
      </div>
      <h1 className="text-2xl font-semibold tracking-tight text-fg">{mode === "verify" ? "Enter your code" : "Set up two-step verification"}</h1>
      <p className="mt-1.5 text-sm text-muted">
        {mode === "verify"
          ? "Open your authenticator app and enter the 6-digit code for Eduwit Partner CRM."
          : "The Partner CRM requires a code from an authenticator app (Google Authenticator, Microsoft Authenticator, 1Password…) at every sign-in."}
      </p>
      <p className="mt-1 truncate text-xs text-subtle">{email}</p>

      {state?.error && <Notice tone="error" className="mt-6">{state.error}</Notice>}
      {enrollment && "error" in enrollment && <Notice tone="error" className="mt-6">{enrollment.error}</Notice>}

      {mode === "enroll" && !ready && (
        <Button size="lg" className="mt-6 w-full justify-center" disabled={starting} onClick={() => startTransition(async () => setEnrollment(await startTotpEnrollment()))}>
          {starting ? "Preparing…" : "Set up authenticator app"}
        </Button>
      )}

      {mode === "enroll" && enrollment && !("error" in enrollment) && (
        <div className="mt-6 rounded-xl border border-border bg-surface p-4">
          <p className="text-[13px] font-medium text-fg">1. Scan this QR code</p>
          {/* data: URI from Supabase; allowed by the CSP img-src */}
          <img src={enrollment.qr} alt="QR code for your authenticator app" width={176} height={176} className="mx-auto my-3 size-44 rounded-lg bg-white p-2" />
          <p className="text-xs text-muted">Can't scan? Enter this key manually:</p>
          <code className="tabular mt-1 block break-all rounded-md bg-surface-2 px-2 py-1.5 text-[12px] text-fg">{enrollment.secret}</code>
          <p className="mt-4 text-[13px] font-medium text-fg">2. Enter the 6-digit code it shows</p>
        </div>
      )}

      {ready && (
        <form action={action} className="mt-4 space-y-4" noValidate>
          <input type="hidden" name="next" value={next} />
          {enrollment && !("error" in enrollment) && <input type="hidden" name="factorId" value={enrollment.factorId} />}
          <Field label="Code" htmlFor="code">
            <Input id="code" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="\d{6}" maxLength={6} required autoFocus className="tabular text-center text-lg tracking-[0.5em]" />
          </Field>
          <SubmitButton size="lg" className="w-full justify-center" pendingLabel="Verifying…">Verify</SubmitButton>
        </form>
      )}

      <form action="/auth/signout" method="post" className="mt-8 text-center">
        <button type="submit" className="text-xs font-medium text-muted hover:text-fg">Use a different account</button>
      </form>
    </div>
  );
}
