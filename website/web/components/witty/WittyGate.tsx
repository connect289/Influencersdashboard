"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { Loader2 } from "lucide-react";
import { resendCodeAction, startFormAction, verifyCodeAction } from "@/app/actions/forms";
import { Honeypot, useTurnstile } from "@/components/forms/Guard";
import { CodeInput } from "@/components/ui/CodeInput";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { CONSENT } from "@/content/consent";
import { track } from "@/lib/client/analytics";
import { cleanName, normaliseEmail, normaliseIndianMobile, validateContact, type Errors } from "@/lib/forms/validate";

/**
 * The access gate before the first message (spec 7.2): name, phone (+91, validated, not OTP-verified), email and consent
 * in one compact form, then a 6-digit email code inline. The chat starts — and the lead is created — only once the
 * email is verified.
 */
export function WittyGate({ onVerified, onCancel }: { onVerified: () => void; onCancel?: () => void }) {
  const [v, setV] = useState({ name: "", phone: "", email: "", consent: false, marketing: false });
  const [errors, setErrors] = useState<Errors<string>>({});
  const [phase, setPhase] = useState<"form" | "code">("form");
  const [busy, setBusy] = useState(false);
  const [attempt, setAttempt] = useState<string | null>(null);
  const [masked, setMasked] = useState("");
  const [code, setCode] = useState("");
  const [codeError, setCodeError] = useState<string | null>(null);
  const [resendIn, setResendIn] = useState(0);
  const [honeypot, setHoneypot] = useState("");
  const idem = useRef<string | null>(null);
  const first = useRef<HTMLInputElement>(null);
  const turnstile = useTurnstile();

  useEffect(() => {
    track("advisor_gate_open", { surface: "witty" });
    first.current?.focus();
  }, []);
  useEffect(() => {
    if (resendIn <= 0) return;
    const t = setTimeout(() => setResendIn((s) => s - 1), 1000);
    return () => clearTimeout(t);
  }, [resendIn]);

  async function start(e: React.FormEvent) {
    e.preventDefault();
    const errs = validateContact(v);
    setErrors(errs);
    if (Object.keys(errs).length) return;
    setBusy(true);
    try {
      idem.current ??= crypto.randomUUID();
      const r = await startFormAction({
        surface: "gate",
        context: {},
        name: cleanName(v.name)!,
        phone: normaliseIndianMobile(v.phone)!,
        email: normaliseEmail(v.email)!,
        consentVersion: CONSENT.gate.version,
        marketing: v.marketing,
        turnstileToken: await turnstile.ready(),
        website: honeypot,
        idempotencyKey: idem.current,
      });
      if (r.status === "error") {
        turnstile.reset();
        return setErrors({ form: r.message });
      }
      setAttempt(r.attemptId);
      if (r.status === "verified") return onVerified();
      setMasked(r.maskedEmail);
      setResendIn(r.resendIn);
      setPhase("code");
      track("gate_submitted", { surface: "witty" });
      track("email_code_sent", { surface: "witty" });
    } finally {
      setBusy(false);
    }
  }

  async function verify(c = code) {
    if (!attempt || c.length !== 6) return;
    setBusy(true);
    setCodeError(null);
    try {
      const r = await verifyCodeAction(attempt, c);
      if (r.status === "verified") {
        track("email_verified", { surface: "witty" });
        track("lead_created", { surface: "witty_gate", event_id: attempt });
        onVerified();
      } else if (r.status === "wrong_code") {
        setCode("");
        setCodeError(`That code didn't match. ${r.attemptsLeft} ${r.attemptsLeft === 1 ? "try" : "tries"} left.`);
      } else setCodeError(r.message);
    } finally {
      setBusy(false);
    }
  }

  if (phase === "code") {
    return (
      <div className="grid gap-3" aria-labelledby="gate-code-title">
        <h3 id="gate-code-title" className="text-text font-semibold">Check your email</h3>
        <p className="text-muted text-sm">
          We sent a 6-digit code to {masked}. It expires in 10 minutes. Can&apos;t see it? Check your spam or promotions folder.
        </p>
        <CodeInput value={code} onValueChange={setCode} onComplete={(c) => void verify(c)} invalid={!!codeError} disabled={busy} label="6-digit code from your email" />
        {codeError ? <p role="alert" className="text-danger text-sm">{codeError}</p> : null}
        <div className="flex flex-wrap items-center gap-3">
          <button type="button" disabled={busy || code.length !== 6} onClick={() => void verify()} className="bg-primary text-on-primary inline-flex h-11 items-center gap-2 rounded-full px-5 text-sm font-semibold disabled:opacity-60">
            {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null} Verify and start chatting
          </button>
          <button
            type="button"
            disabled={resendIn > 0 || busy}
            onClick={async () => {
              if (!attempt) return;
              const r = await resendCodeAction(attempt);
              if (r.status === "code_sent") setResendIn(r.resendIn);
              else if (r.status === "error") setCodeError(r.message);
            }}
            className="text-accent text-sm font-medium disabled:text-subtle"
          >
            {resendIn > 0 ? `Resend code in ${resendIn}s` : "Resend code"}
          </button>
          <button type="button" onClick={() => setPhase("form")} className="text-muted text-sm hover:underline">
            Change email
          </button>
        </div>
      </div>
    );
  }

  return (
    <form onSubmit={start} noValidate className="grid gap-3" aria-labelledby="gate-title">
      <div>
        <h3 id="gate-title" className="text-text font-semibold">Before we chat</h3>
        <p className="text-muted text-sm">So Witty can save your progress and a counsellor can help if you want. We&apos;ll verify your email with a code.</p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Full name" error={errors.name}>
          {(f) => <Input ref={first} id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} autoComplete="name" value={v.name} onChange={(e) => setV({ ...v, name: e.target.value })} />}
        </Field>
        <Field label="Mobile number" error={errors.phone}>
          {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} type="tel" inputMode="numeric" autoComplete="tel-national" placeholder="10-digit mobile" value={v.phone} onChange={(e) => setV({ ...v, phone: e.target.value })} />}
        </Field>
      </div>
      <Field label="Email" error={errors.email}>
        {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} type="email" inputMode="email" autoComplete="email" value={v.email} onChange={(e) => setV({ ...v, email: e.target.value })} />}
      </Field>
      <label className="text-muted flex items-start gap-3 text-xs leading-relaxed">
        <input type="checkbox" className="accent-[var(--primary)] mt-0.5 size-5 shrink-0" checked={v.consent} aria-invalid={!!errors.consent} onChange={(e) => setV({ ...v, consent: e.target.checked })} />
        <span>
          {CONSENT.gate.text} See the <Link href="/legal/privacy-policy" className="text-accent underline underline-offset-4">Privacy Policy</Link>.
        </span>
      </label>
      {errors.consent ? <p role="alert" className="text-danger -mt-1 text-xs font-medium">{errors.consent}</p> : null}
      <label className="text-muted flex items-start gap-3 text-xs">
        <input type="checkbox" className="accent-[var(--primary)] mt-0.5 size-5 shrink-0" checked={v.marketing} onChange={(e) => setV({ ...v, marketing: e.target.checked })} />
        <span>{CONSENT.marketing} (optional)</span>
      </label>
      <Honeypot value={honeypot} onChange={setHoneypot} />
      {turnstile.widget}
      {errors.form ? <p role="alert" className="text-danger text-sm">{errors.form}</p> : null}
      <div className="flex flex-wrap items-center gap-3">
        <button type="submit" disabled={busy} className="bg-primary text-on-primary inline-flex h-11 items-center gap-2 rounded-full px-5 text-sm font-semibold disabled:opacity-60">
          {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null} Verify email and continue
        </button>
        {onCancel ? (
          <button type="button" onClick={onCancel} className="text-muted text-sm hover:underline">
            Not now
          </button>
        ) : null}
        <Link href="/account/sign-in?next=/witty" className="text-accent text-sm font-medium">
          Already verified? Sign in
        </Link>
      </div>
    </form>
  );
}
