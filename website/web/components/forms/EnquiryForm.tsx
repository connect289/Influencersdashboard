"use client";

import Link from "next/link";
import { useRef, useState } from "react";
import { CheckCircle2, Loader2, MessageCircle } from "lucide-react";
import { CodeInput } from "@/components/ui/CodeInput";
import { Field } from "@/components/ui/Field";
import { Input, Textarea } from "@/components/ui/Input";
import { CONSENT } from "@/content/consent";
import { whatsappLink } from "@/content/site";
import { track } from "@/lib/client/analytics";
import { mockApplicationClient, type ApplicationClient } from "@/lib/forms/client";
import { cleanName, normaliseEmail, normaliseIndianMobile, validateContact, type Errors } from "@/lib/forms/validate";

/**
 * Short enquiry form (spec 9.1): name, phone (validated, not OTP-verified), email (verified by code), programme of
 * interest, message, consent. Same transport and verification flow as the application form.
 */
function newKey() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
}

export function EnquiryForm({ whatsapp, programme = "", client = mockApplicationClient }: { whatsapp: string; programme?: string; client?: ApplicationClient }) {
  const [v, setV] = useState({ name: "", phone: "", email: "", consent: false, marketing: false, programme, message: "" });
  const [errors, setErrors] = useState<Errors<string>>({});
  const [phase, setPhase] = useState<"form" | "code" | "done">("form");
  const [busy, setBusy] = useState(false);
  const [attempt, setAttempt] = useState<string | null>(null);
  const [masked, setMasked] = useState("");
  const [code, setCode] = useState("");
  const [codeError, setCodeError] = useState<string | null>(null);
  const [reference, setReference] = useState<string | null>(null);
  // One idempotency key per form instance, created on the first submit (never during render or prerender).
  const idem = useRef<string | null>(null);

  async function send() {
    const e: Errors<string> = validateContact(v);
    if (v.message.length > 1000) e.message = "Please keep this under 1,000 characters.";
    setErrors(e);
    if (Object.keys(e).length) return;
    setBusy(true);
    try {
      track("form_view", { form: "enquiry" });
      const r = await client.start({ kind: "contact", programmeLabel: v.programme || undefined }, {
        name: cleanName(v.name)!, phone: normaliseIndianMobile(v.phone)!, email: normaliseEmail(v.email)!,
        consentVersion: CONSENT.form.version, marketing: v.marketing, idempotencyKey: (idem.current ??= newKey()),
      });
      if (r.status === "error") return setErrors({ form: r.message });
      setAttempt(r.attemptId);
      if (r.status === "verified") return void finish(r.attemptId);
      setMasked(r.maskedEmail);
      setPhase("code");
    } finally {
      setBusy(false);
    }
  }

  async function finish(id: string) {
    const s = await client.submit(id, { programme: v.programme, message: v.message });
    if (s.ok) {
      setReference(s.reference);
      setPhase("done");
      track("form_submit", { form: "enquiry", event_id: s.reference });
    } else setErrors({ form: s.message });
  }

  async function verify(c = code) {
    if (!attempt || c.length !== 6) return;
    setBusy(true);
    setCodeError(null);
    try {
      const r = await client.verify(attempt, c);
      if (r.status === "verified") {
        track("lead_created", { surface: "enquiry", event_id: r.reference });
        await finish(attempt);
      } else if (r.status === "wrong_code") {
        setCode("");
        setCodeError(`That code didn't match. ${r.attemptsLeft} ${r.attemptsLeft === 1 ? "try" : "tries"} left.`);
      } else setCodeError(r.message);
    } finally {
      setBusy(false);
    }
  }

  if (phase === "done") {
    return (
      <div className="grid gap-3" role="status">
        <CheckCircle2 className="text-success size-8" aria-hidden />
        <h3 className="font-display text-text text-xl font-semibold">Thanks, we&apos;ve got your enquiry</h3>
        <p className="text-muted">Reference <span className="tabular text-text font-semibold">{reference}</span>. A counsellor will contact you soon. A confirmation is on its way to your email.</p>
        <a href={whatsappLink(whatsapp, `Hi Eduwit, my enquiry reference is ${reference}.`)} target="_blank" rel="noopener noreferrer" className="bg-primary text-on-primary inline-flex h-11 items-center gap-2 justify-self-start rounded-full px-5 text-sm font-semibold">
          <MessageCircle className="size-4" aria-hidden /> Message us on WhatsApp
        </a>
      </div>
    );
  }

  if (phase === "code") {
    return (
      <div className="grid gap-3">
        <h3 className="text-text font-medium">Check your email</h3>
        <p className="text-muted text-sm">We sent a 6-digit code to {masked}. It expires in 10 minutes.</p>
        <CodeInput value={code} onValueChange={setCode} onComplete={(c) => void verify(c)} invalid={!!codeError} disabled={busy} label="6-digit code from your email" />
        {codeError ? <p role="alert" className="text-danger text-sm">{codeError}</p> : null}
        <div className="flex gap-3">
          <button type="button" disabled={busy || code.length !== 6} onClick={() => void verify()} className="bg-primary text-on-primary inline-flex h-11 items-center gap-2 rounded-full px-5 text-sm font-semibold disabled:opacity-60">
            {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null} Verify and send
          </button>
          <button type="button" onClick={() => setPhase("form")} className="text-muted text-sm hover:underline">Change email</button>
        </div>
      </div>
    );
  }

  return (
    <form className="grid gap-4" onSubmit={(e) => { e.preventDefault(); void send(); }} noValidate>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Full name" error={errors.name}>
          {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} autoComplete="name" value={v.name} onChange={(e) => setV({ ...v, name: e.target.value })} />}
        </Field>
        <Field label="Mobile number" error={errors.phone}>
          {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} type="tel" inputMode="numeric" autoComplete="tel-national" placeholder="10-digit mobile" value={v.phone} onChange={(e) => setV({ ...v, phone: e.target.value })} />}
        </Field>
      </div>
      <Field label="Email" hint="We'll send a 6-digit code to verify it." error={errors.email}>
        {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} type="email" inputMode="email" autoComplete="email" value={v.email} onChange={(e) => setV({ ...v, email: e.target.value })} />}
      </Field>
      <Field label="Programme you're interested in" optional>
        {(f) => <Input id={f.id} value={v.programme} placeholder="For example: Online MBA" onChange={(e) => setV({ ...v, programme: e.target.value })} />}
      </Field>
      <Field label="Message" optional error={errors.message}>
        {(f) => <Textarea id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} maxLength={1000} value={v.message} onChange={(e) => setV({ ...v, message: e.target.value })} />}
      </Field>
      <label className="text-muted flex items-start gap-3 text-sm">
        <input type="checkbox" className="accent-[var(--primary)] mt-0.5 size-5 shrink-0" checked={v.consent} aria-invalid={!!errors.consent} onChange={(e) => setV({ ...v, consent: e.target.checked })} />
        <span>
          {CONSENT.form.text} See the <Link href="/legal/privacy-policy" className="text-accent underline underline-offset-4">Privacy Policy</Link>.
        </span>
      </label>
      {errors.consent ? <p role="alert" className="text-danger -mt-2 text-xs font-medium">{errors.consent}</p> : null}
      <label className="text-muted flex items-start gap-3 text-sm">
        <input type="checkbox" className="accent-[var(--primary)] mt-0.5 size-5 shrink-0" checked={v.marketing} onChange={(e) => setV({ ...v, marketing: e.target.checked })} />
        <span>{CONSENT.marketing} (optional)</span>
      </label>
      {errors.form ? <p role="alert" className="text-danger text-sm">{errors.form}</p> : null}
      <button type="submit" disabled={busy} className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 justify-self-start rounded-full px-6 text-sm font-semibold disabled:opacity-60">
        {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null} Verify email and send
      </button>
    </form>
  );
}
