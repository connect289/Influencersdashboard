"use client";

import { useRouter } from "next/navigation";
import { safeLocalPath } from "@/lib/security/paths";
import { useEffect, useRef, useState } from "react";
import { Loader2 } from "lucide-react";
import { signInResendAction, signInStartAction, signInVerifyAction } from "@/app/actions/account";
import { Honeypot, useTurnstile } from "@/components/forms/Guard";
import { CodeInput } from "@/components/ui/CodeInput";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { normaliseEmail } from "@/lib/forms/validate";

/** Student sign-in with a 6-digit email code (spec 12: the same identity as the Witty gate and the forms). */
export function SignInForm({ next }: { next: string }) {
  const router = useRouter();
  const [emailValue, setEmail] = useState("");
  const [phase, setPhase] = useState<"email" | "code">("email");
  const [attempt, setAttempt] = useState<string | null>(null);
  const [masked, setMasked] = useState("");
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [resendIn, setResendIn] = useState(0);
  const [honeypot, setHoneypot] = useState("");
  const idem = useRef<string | null>(null);
  const turnstile = useTurnstile();

  useEffect(() => {
    if (resendIn <= 0) return;
    const t = setTimeout(() => setResendIn((s) => s - 1), 1000);
    return () => clearTimeout(t);
  }, [resendIn]);

  async function start(e: React.FormEvent) {
    e.preventDefault();
    const em = normaliseEmail(emailValue);
    if (!em) return setError("Enter a valid email address.");
    setBusy(true);
    setError(null);
    try {
      idem.current ??= crypto.randomUUID();
      const r = await signInStartAction({ email: em, idempotencyKey: idem.current, turnstileToken: await turnstile.ready(), website: honeypot });
      if (r.status === "error") {
        turnstile.reset();
        return setError(r.message);
      }
      if (r.status === "verified") return router.replace(safeLocalPath(next, "/account"));
      setAttempt(r.attemptId);
      setMasked(r.maskedEmail);
      setResendIn(r.resendIn);
      setPhase("code");
    } finally {
      setBusy(false);
    }
  }

  async function verify(v = code) {
    if (!attempt || v.length !== 6) return;
    setBusy(true);
    setError(null);
    try {
      const r = await signInVerifyAction(attempt, v);
      if (r.status === "verified") {
        router.replace(safeLocalPath(next, "/account"));
        router.refresh();
      } else if (r.status === "wrong_code") {
        setCode("");
        setError(`That code didn't match. ${r.attemptsLeft} ${r.attemptsLeft === 1 ? "try" : "tries"} left.`);
      } else setError(r.message);
    } finally {
      setBusy(false);
    }
  }

  if (phase === "code") {
    return (
      <div className="grid gap-4">
        <p className="text-muted text-sm">
          We sent a 6-digit code to {masked}. It expires in 10 minutes. Can&apos;t see it? Check your spam or promotions folder.
        </p>
        <CodeInput value={code} onValueChange={setCode} onComplete={(v) => void verify(v)} invalid={!!error} disabled={busy} label="6-digit code from your email" />
        {error ? <p role="alert" className="text-danger text-sm">{error}</p> : null}
        <div className="flex flex-wrap items-center gap-3">
          <button type="button" disabled={busy || code.length !== 6} onClick={() => void verify()} className="bg-primary text-on-primary inline-flex h-11 items-center gap-2 rounded-full px-5 text-sm font-semibold disabled:opacity-60">
            {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null} Sign in
          </button>
          <button
            type="button"
            disabled={resendIn > 0 || busy}
            onClick={async () => {
              if (!attempt) return;
              const r = await signInResendAction(attempt);
              if (r.status === "code_sent") setResendIn(r.resendIn);
              else if (r.status === "error") setError(r.message);
            }}
            className="text-accent text-sm font-medium disabled:text-subtle"
          >
            {resendIn > 0 ? `Resend code in ${resendIn}s` : "Resend code"}
          </button>
          <button
            type="button"
            onClick={() => {
              setPhase("email");
              setCode("");
              idem.current = null;
            }}
            className="text-muted text-sm hover:underline"
          >
            Change email
          </button>
        </div>
      </div>
    );
  }

  return (
    <form onSubmit={start} className="grid gap-4" noValidate>
      <Field label="Email" hint="Use the email you gave us in a form or chat with Witty." error={error ?? undefined}>
        {(f) => (
          <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} type="email" inputMode="email" autoComplete="email" value={emailValue} onChange={(e) => setEmail(e.target.value)} />
        )}
      </Field>
      <Honeypot value={honeypot} onChange={setHoneypot} />
      {turnstile.widget}
      <button type="submit" disabled={busy} className="bg-primary text-on-primary inline-flex h-12 items-center justify-center gap-2 rounded-full px-6 text-sm font-semibold disabled:opacity-60">
        {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null} Email me a code
      </button>
    </form>
  );
}
