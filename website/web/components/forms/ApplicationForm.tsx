"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { ArrowLeft, Check, CheckCircle2, Loader2, MessageCircle, Pencil } from "lucide-react";
import { CodeInput } from "@/components/ui/CodeInput";
import { Field } from "@/components/ui/Field";
import { Input, NativeSelect, Textarea } from "@/components/ui/Input";
import { CONSENT } from "@/content/consent";
import { INDIAN_STATES } from "@/content/india";
import { whatsappLink } from "@/content/site";
import { track } from "@/lib/client/analytics";
import { eligibility, MIN_QUALIFICATION_LABEL, type Qualification } from "@/lib/finder/eligibility";
import { mockApplicationClient, type ApplicationClient, type FormContext } from "@/lib/forms/client";
import {
  normaliseEmail,
  normaliseIndianMobile,
  cleanName,
  validateAcademic,
  validateContact,
  validatePreferences,
  validateWork,
  type AcademicInput,
  type ContactInput,
  type Errors,
  type PreferencesInput,
  type WorkInput,
} from "@/lib/forms/validate";
import { formatInr } from "@/lib/format";
import type { OfferingCard } from "@/lib/search/types";
import { cn } from "@/lib/utils";

export type FormTarget =
  | { kind: "offering"; offering: OfferingCard }
  | { kind: "group"; groupKey: string; label: string; exploreHref: string; universities: { offeringId: number; name: string; feeTotal?: number; level?: string; minQualification?: string }[] }
  | { kind: "university"; universitySlug: string; universityName: string; programmes: { offeringId: number; label: string; level?: string; minQualification?: string }[] };

export interface FormConfig {
  /** Non-core fields to hide or make optional (admin-configurable, spec 9.1A). Contact and consent are locked. */
  hidden?: string[];
  optional?: string[];
}

const STEPS = ["Contact", "Academic", "Work and goals", "Preferences", "Review"] as const;
const QUALS: { value: Qualification | "studying_12th" | "studying_graduation"; label: string }[] = [
  { value: "10th", label: "Class 10" },
  { value: "12th", label: "Class 12" },
  { value: "diploma", label: "Diploma" },
  { value: "graduation", label: "Graduation" },
  { value: "postgraduation", label: "Post-graduation" },
];
const INTAKES = ["As soon as possible", "Within 3 months", "Within 6 months", "Next year", "Just exploring"];
const BUDGETS = ["Under ₹1 lakh", "₹1–2 lakh", "₹2–3 lakh", "₹3–5 lakh", "Above ₹5 lakh", "Not sure yet"];
const TIMES = ["Morning (9am–12pm)", "Afternoon (12–4pm)", "Evening (4–8pm)", "Any time"];

function newKey() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
}

/**
 * Built-in application/enquiry form (spec 9.1A): five short steps with a sticky progress bar; email verified inline by a
 * 6-digit code after step 1 (the lead is created at that point in Phase 7); steps 2–4 enrich the same lead and save on
 * "Next"; friendly eligibility note; review with edit links; thank-you with a reference number. Never takes payment.
 */
export function ApplicationForm({
  target,
  goals,
  whatsapp,
  client = mockApplicationClient,
  config = {},
}: {
  target: FormTarget;
  goals: { value: string; label: string }[];
  whatsapp: string;
  client?: ApplicationClient;
  config?: FormConfig;
}) {
  const [step, setStep] = useState(0);
  const [phase, setPhase] = useState<"form" | "code" | "done">("form");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [attemptId, setAttemptId] = useState<string | null>(null);
  const [masked, setMasked] = useState("");
  const [code, setCode] = useState("");
  const [codeError, setCodeError] = useState<string | null>(null);
  const [reference, setReference] = useState<string | null>(null);
  const [verifiedRef, setVerifiedRef] = useState<string | null>(null);
  const [resendIn, setResendIn] = useState(0);
  // One idempotency key per form instance, created on the first submit (never during render or prerender).
  const idem = useRef<string | null>(null);
  const top = useRef<HTMLDivElement>(null);

  const [contact, setContact] = useState<ContactInput & { marketing: boolean }>({ name: "", phone: "", email: "", consent: false, marketing: false });
  const [academic, setAcademic] = useState<AcademicInput>({ qualification: "", stream: "", scoreType: "percent", score: "", currentlyStudying: false, yearOfPassing: "", board: "" });
  const [work, setWork] = useState<WorkInput>({ working: "", years: "", role: "", industry: "", goal: "", why: "" });
  const [prefs, setPrefs] = useState<PreferencesInput>({ intake: "", budget: "", emi: "", universities: [], city: "", state: "", contactMode: "", bestTime: "", questions: "" });
  const [errors, setErrors] = useState<Errors<string>>({});

  const hidden = new Set(config.hidden ?? []);
  const optional = new Set(config.optional ?? []);
  const show = (f: string) => !hidden.has(f);

  const context: FormContext = useMemo(
    () =>
      target.kind === "offering"
        ? { kind: "offering", offeringId: target.offering.id, programmeLabel: `${target.offering.programme_name} ${target.offering.spec_name}` }
        : target.kind === "group"
          ? { kind: "group", groupKey: target.groupKey, programmeLabel: target.label }
          : { kind: "university", universitySlug: target.universitySlug },
    [target],
  );
  const formName = `application_${target.kind}`;
  const offeringId = target.kind === "offering" ? target.offering.id : undefined;

  useEffect(() => {
    track("form_view", { form: formName, offering_id: offeringId });
  }, [formName, offeringId]);

  useEffect(() => {
    if (resendIn <= 0) return;
    const t = setTimeout(() => setResendIn((s) => s - 1), 1000);
    return () => clearTimeout(t);
  }, [resendIn]);

  // Eligibility note (spec 9.1A): compares the answer with the selected offering's catalogue requirement; never blocks.
  const selected = useMemo(() => {
    if (target.kind === "offering") return { level: target.offering.level_id, minQ: target.offering.min_qualification };
    const id = Number(prefs.universities[0]);
    const pool = target.kind === "group" ? target.universities : target.programmes;
    const hit = pool.find((p) => p.offeringId === id);
    return hit ? { level: hit.level ?? "", minQ: hit.minQualification } : null;
  }, [target, prefs.universities]);
  const elig = selected && academic.qualification ? eligibility(academic.qualification as Qualification, selected.level, selected.minQ) : null;

  function scrollTop() {
    top.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  async function next() {
    setMessage(null);
    let e: Errors<string> = {};
    if (step === 0) e = validateContact(contact);
    if (step === 1) e = validateAcademic(academic);
    if (step === 2) e = validateWork(work);
    if (step === 3) e = validatePreferences(prefs, target.kind !== "offering");
    for (const k of Object.keys(e)) if (optional.has(k) || hidden.has(k)) delete e[k];
    setErrors(e);
    if (Object.keys(e).length) {
      requestAnimationFrame(() => top.current?.parentElement?.querySelector<HTMLElement>("[aria-invalid=true]")?.focus());
      return;
    }
    setBusy(true);
    try {
      if (step === 0 && !verifiedRef) {
        const r = await client.start(context, {
          name: cleanName(contact.name)!,
          phone: normaliseIndianMobile(contact.phone)!,
          email: normaliseEmail(contact.email)!,
          consentVersion: CONSENT.form.version,
          marketing: contact.marketing,
          idempotencyKey: (idem.current ??= newKey()),
        });
        if (r.status === "error") return setMessage(r.message);
        setAttemptId(r.attemptId);
        if (r.status === "verified") {
          setVerifiedRef(r.attemptId);
          setStep(1);
        } else {
          setMasked(r.maskedEmail);
          setResendIn(r.resendInSeconds);
          setPhase("code");
        }
        return;
      }
      if (attemptId && step >= 1 && step <= 3) {
        const data = step === 1 ? academic : step === 2 ? work : prefs;
        await client.saveStep(attemptId, step + 1, data as unknown as Record<string, unknown>);
        track("form_step_complete", { form: formName, step: step + 1 });
      }
      setStep((s) => s + 1);
      scrollTop();
    } finally {
      setBusy(false);
    }
  }

  async function verify(v = code) {
    if (!attemptId || v.length !== 6) return;
    setBusy(true);
    setCodeError(null);
    try {
      const r = await client.verify(attemptId, v);
      if (r.status === "verified") {
        setVerifiedRef(r.reference);
        track("form_step_complete", { form: formName, step: 1 });
        track("lead_created", { surface: formName, event_id: r.reference });
        setPhase("form");
        setStep(1);
        scrollTop();
      } else if (r.status === "wrong_code") {
        setCode("");
        setCodeError(`That code didn't match. ${r.attemptsLeft} ${r.attemptsLeft === 1 ? "try" : "tries"} left.`);
      } else {
        setCodeError(r.message);
      }
    } finally {
      setBusy(false);
    }
  }

  async function submit() {
    if (!attemptId) return;
    setBusy(true);
    try {
      const r = await client.submit(attemptId, { academic, work, preferences: prefs });
      if (!r.ok) return setMessage(r.message);
      setReference(r.reference);
      setPhase("done");
      track("form_submit", { form: formName, offering_id: offeringId, event_id: r.reference });
      scrollTop();
    } finally {
      setBusy(false);
    }
  }

  const summary =
    target.kind === "offering" ? (
      <div className="border-border rounded-[var(--radius-lg)] border p-3">
        <p className="text-text font-medium">{target.offering.programme_name} · {target.offering.spec_name}</p>
        <p className="text-muted text-sm">{target.offering.university.name}</p>
        {target.offering.fee.total ? (
          <p className="mt-1 text-sm">
            <span className="tabular text-text font-semibold">{formatInr(target.offering.fee.total)}</span> <span className="text-muted">total</span>
            <span className="text-amber-text"> · Easy EMI available</span>
          </p>
        ) : null}
      </div>
    ) : null;

  if (phase === "done") {
    const explore = target.kind === "offering" ? `/programmes?programme=${target.offering.programme_id}&spec=${target.offering.spec_ids.join(",")}` : target.kind === "group" ? target.exploreHref : `/programmes?uni=${target.universitySlug}`;
    return (
      <div ref={top} className="grid gap-4" role="status" aria-live="polite">
        <CheckCircle2 className="text-success size-8" aria-hidden />
        <h3 className="font-display text-text text-xl font-semibold">Application request received</h3>
        <p className="text-muted">
          Your reference is <span className="tabular text-text font-semibold">{reference}</span>. A confirmation is on its way to your email.
        </p>
        <ol className="text-muted grid list-decimal gap-1 pl-5 text-sm">
          <li>A counsellor reviews your details and checks your eligibility.</li>
          <li>They contact you by your chosen method to confirm fees, intake and documents.</li>
          <li>They help you complete the university&apos;s application. Eduwit never asks you to pay on this website.</li>
        </ol>
        <div className="flex flex-wrap gap-2">
          <a href={whatsappLink(whatsapp, `Hi Eduwit, my application reference is ${reference}.`)} target="_blank" rel="noopener noreferrer" className="bg-primary text-on-primary inline-flex h-11 items-center gap-2 rounded-full px-5 text-sm font-semibold">
            <MessageCircle className="size-4" aria-hidden /> Talk to a counsellor
          </a>
          <Link href={explore} className="border-border bg-surface text-text inline-flex h-11 items-center rounded-full border px-5 text-sm font-medium">
            Explore similar programmes
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="grid gap-4">
      <div ref={top} className="bg-[var(--surface-solid)] sticky top-0 z-10 -mx-1 grid gap-2 px-1 pt-1 pb-3">
        <div className="flex items-center justify-between text-xs">
          <span className="text-text font-medium">
            Step {step + 1} of {STEPS.length}: {STEPS[step]}
          </span>
          {verifiedRef ? (
            <span className="text-success inline-flex items-center gap-1">
              <Check className="size-3.5" aria-hidden /> Email verified
            </span>
          ) : null}
        </div>
        <div className="bg-border h-1.5 overflow-hidden rounded-full" role="progressbar" aria-label="Form progress" aria-valuemin={1} aria-valuemax={STEPS.length} aria-valuenow={step + 1}>
          <div className="bg-primary h-full rounded-full transition-[width] duration-300" style={{ width: `${((step + 1) / STEPS.length) * 100}%` }} />
        </div>
      </div>

      {summary}
      {message ? (
        <p role="alert" className="text-danger text-sm">{message}</p>
      ) : null}

      {phase === "code" ? (
        <div className="grid gap-3">
          <h3 className="text-text font-medium">Check your email</h3>
          <p className="text-muted text-sm">We sent a 6-digit code to {masked}. It expires in 10 minutes.</p>
          <CodeInput value={code} onValueChange={setCode} onComplete={(v) => void verify(v)} invalid={!!codeError} disabled={busy} label="6-digit code from your email" />
          {codeError ? <p role="alert" className="text-danger text-sm">{codeError}</p> : null}
          <div className="flex flex-wrap items-center gap-3">
            <button type="button" disabled={busy || code.length !== 6} onClick={() => void verify()} className="bg-primary text-on-primary inline-flex h-11 items-center gap-2 rounded-full px-5 text-sm font-semibold disabled:opacity-60">
              {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null} Verify email
            </button>
            <button
              type="button"
              disabled={resendIn > 0 || busy}
              onClick={async () => {
                if (!attemptId) return;
                const r = await client.resend(attemptId);
                if (r.status === "code_sent") setResendIn(r.resendInSeconds);
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
      ) : step === 0 ? (
        <div className="grid gap-4">
          <Field label="Full name" error={errors.name}>
            {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} autoComplete="name" value={contact.name} onChange={(e) => setContact({ ...contact, name: e.target.value })} />}
          </Field>
          <Field label="Mobile number" hint="Indian mobile; a counsellor may call or WhatsApp you." error={errors.phone}>
            {(f) => (
              <div className="flex">
                <span className="border-border bg-surface text-muted grid place-items-center rounded-l-[var(--radius-md)] border border-r-0 px-3 text-sm">+91</span>
                <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} className="rounded-l-none" type="tel" inputMode="numeric" autoComplete="tel-national" value={contact.phone} onChange={(e) => setContact({ ...contact, phone: e.target.value })} />
              </div>
            )}
          </Field>
          <Field label="Email" hint="We'll send a 6-digit code to verify it." error={errors.email}>
            {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} type="email" inputMode="email" autoComplete="email" value={contact.email} onChange={(e) => setContact({ ...contact, email: e.target.value })} />}
          </Field>
          <label className="text-muted flex items-start gap-3 text-sm">
            <input type="checkbox" className="accent-[var(--primary)] mt-0.5 size-5 shrink-0" checked={contact.consent} aria-invalid={!!errors.consent} onChange={(e) => setContact({ ...contact, consent: e.target.checked })} />
            <span>
              {CONSENT.form.text} See the{" "}
              <Link href="/legal/privacy-policy" className="text-accent underline underline-offset-4">Privacy Policy</Link> and{" "}
              <Link href="/legal/data-privacy-opt-out" className="text-accent underline underline-offset-4">Data privacy &amp; opt-out</Link>.
            </span>
          </label>
          {errors.consent ? <p role="alert" className="text-danger -mt-2 text-xs font-medium">{errors.consent}</p> : null}
          <label className="text-muted flex items-start gap-3 text-sm">
            <input type="checkbox" className="accent-[var(--primary)] mt-0.5 size-5 shrink-0" checked={contact.marketing} onChange={(e) => setContact({ ...contact, marketing: e.target.checked })} />
            <span>{CONSENT.marketing} (optional)</span>
          </label>
        </div>
      ) : step === 1 ? (
        <div className="grid gap-4">
          <Field label="Highest qualification" error={errors.qualification}>
            {(f) => (
              <NativeSelect id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} value={academic.qualification} onChange={(e) => setAcademic({ ...academic, qualification: e.target.value })}>
                <option value="">Choose…</option>
                {QUALS.map((q) => <option key={q.value} value={q.value}>{q.label}</option>)}
              </NativeSelect>
            )}
          </Field>
          {elig ? (
            <p className={cn("rounded-[var(--radius-md)] px-3 py-2 text-sm", elig === "eligible" ? "bg-success-soft text-success" : "bg-warning-soft text-warning")} role="status">
              {elig === "eligible" ? "You meet the eligibility for this programme." : `A counsellor will confirm your eligibility${selected?.minQ ? ` (this programme asks for ${(MIN_QUALIFICATION_LABEL[selected.minQ] ?? selected.minQ).toLowerCase()})` : ""}.`}
            </p>
          ) : null}
          {show("stream") ? (
            <Field label="Stream or subject" optional={optional.has("stream")} hint="For example: Commerce, Science (PCM), B.Com, B.Tech CSE">
              {(f) => <Input id={f.id} aria-describedby={f.describedBy} value={academic.stream} onChange={(e) => setAcademic({ ...academic, stream: e.target.value })} />}
            </Field>
          ) : null}
          {show("score") ? (
            <div className="grid grid-cols-[auto_1fr] items-end gap-3">
              <Field label="Score as">
                {(f) => (
                  <NativeSelect id={f.id} value={academic.scoreType} onChange={(e) => setAcademic({ ...academic, scoreType: e.target.value as "percent" | "cgpa" })}>
                    <option value="percent">Percentage</option>
                    <option value="cgpa">CGPA (10-point)</option>
                  </NativeSelect>
                )}
              </Field>
              <Field label={academic.scoreType === "cgpa" ? "CGPA" : "Percentage"} optional error={errors.score}>
                {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} inputMode="decimal" value={academic.score} onChange={(e) => setAcademic({ ...academic, score: e.target.value })} />}
              </Field>
            </div>
          ) : null}
          {show("yearOfPassing") ? (
            <div className="grid gap-2">
              <label className="text-muted flex items-center gap-2 text-sm">
                <input type="checkbox" className="accent-[var(--primary)] size-4" checked={academic.currentlyStudying} onChange={(e) => setAcademic({ ...academic, currentlyStudying: e.target.checked })} />
                I am currently studying
              </label>
              {!academic.currentlyStudying ? (
                <Field label="Year of passing" optional error={errors.yearOfPassing}>
                  {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} inputMode="numeric" maxLength={4} value={academic.yearOfPassing} onChange={(e) => setAcademic({ ...academic, yearOfPassing: e.target.value })} />}
                </Field>
              ) : null}
            </div>
          ) : null}
          {show("board") ? (
            <Field label="Board or university" optional>
              {(f) => <Input id={f.id} value={academic.board} onChange={(e) => setAcademic({ ...academic, board: e.target.value })} />}
            </Field>
          ) : null}
        </div>
      ) : step === 2 ? (
        <div className="grid gap-4">
          <fieldset className="grid gap-2">
            <legend className="text-text text-sm font-medium">Are you working?</legend>
            <div className="flex gap-2">
              {(["yes", "no"] as const).map((v) => (
                <label key={v} className={cn("border-border flex h-11 flex-1 cursor-pointer items-center justify-center rounded-full border text-sm", work.working === v && "border-primary bg-amber-soft text-text")}>
                  <input type="radio" name="working" className="sr-only" checked={work.working === v} onChange={() => setWork({ ...work, working: v })} />
                  {v === "yes" ? "Yes" : "No"}
                </label>
              ))}
            </div>
            {errors.working ? <p role="alert" className="text-danger text-xs font-medium">{errors.working}</p> : null}
          </fieldset>
          {work.working === "yes" ? (
            <>
              <Field label="Years of work experience" optional error={errors.years}>
                {(f) => <Input id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} inputMode="decimal" value={work.years} onChange={(e) => setWork({ ...work, years: e.target.value })} />}
              </Field>
              {show("role") ? (
                <Field label="Current role" optional>
                  {(f) => <Input id={f.id} autoComplete="organization-title" value={work.role} onChange={(e) => setWork({ ...work, role: e.target.value })} />}
                </Field>
              ) : null}
              {show("industry") ? (
                <Field label="Industry" optional>
                  {(f) => <Input id={f.id} value={work.industry} onChange={(e) => setWork({ ...work, industry: e.target.value })} />}
                </Field>
              ) : null}
            </>
          ) : null}
          {show("goal") ? (
            <Field label="Your main goal" optional>
              {(f) => (
                <NativeSelect id={f.id} value={work.goal} onChange={(e) => setWork({ ...work, goal: e.target.value })}>
                  <option value="">Choose…</option>
                  {goals.map((g) => <option key={g.value} value={g.value}>{g.label}</option>)}
                </NativeSelect>
              )}
            </Field>
          ) : null}
          {show("why") ? (
            <Field label="Why this programme?" optional error={errors.why}>
              {(f) => <Textarea id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} maxLength={1000} value={work.why} onChange={(e) => setWork({ ...work, why: e.target.value })} />}
            </Field>
          ) : null}
        </div>
      ) : step === 3 ? (
        <div className="grid gap-4">
          {target.kind !== "offering" ? (
            <fieldset className="grid gap-2">
              <legend className="text-text text-sm font-medium">{target.kind === "group" ? "Preferred universities" : "Programme you're interested in"}</legend>
              <div className="grid max-h-64 gap-1 overflow-y-auto">
                {(target.kind === "group" ? target.universities.map((u) => ({ id: u.offeringId, label: u.name, meta: u.feeTotal ? formatInr(u.feeTotal) : "" })) : target.programmes.map((p) => ({ id: p.offeringId, label: p.label, meta: "" }))).map((o) => (
                  <label key={o.id} className="hover:bg-surface-hover flex min-h-10 items-center gap-3 rounded-[var(--radius-md)] px-2 text-sm">
                    <input
                      type={target.kind === "group" ? "checkbox" : "radio"}
                      name="pick"
                      className="accent-[var(--primary)] size-4"
                      checked={prefs.universities.includes(String(o.id))}
                      onChange={(e) =>
                        setPrefs({
                          ...prefs,
                          universities: target.kind === "group" ? (e.target.checked ? [...prefs.universities.filter((x) => x !== "help"), String(o.id)] : prefs.universities.filter((x) => x !== String(o.id))) : [String(o.id)],
                        })
                      }
                    />
                    <span className="text-text flex-1">{o.label}</span>
                    <span className="tabular text-subtle text-xs">{o.meta}</span>
                  </label>
                ))}
                {target.kind === "group" ? (
                  <label className="hover:bg-surface-hover flex min-h-10 items-center gap-3 rounded-[var(--radius-md)] px-2 text-sm">
                    <input type="checkbox" className="accent-[var(--primary)] size-4" checked={prefs.universities.includes("help")} onChange={(e) => setPrefs({ ...prefs, universities: e.target.checked ? ["help"] : [] })} />
                    <span className="text-text">Help me choose</span>
                  </label>
                ) : null}
              </div>
              {errors.universities ? <p role="alert" className="text-danger text-xs font-medium">{errors.universities}</p> : null}
            </fieldset>
          ) : null}
          {show("intake") ? (
            <Field label="When would you like to start?" optional>
              {(f) => (
                <NativeSelect id={f.id} value={prefs.intake} onChange={(e) => setPrefs({ ...prefs, intake: e.target.value })}>
                  <option value="">Choose…</option>
                  {INTAKES.map((v) => <option key={v}>{v}</option>)}
                </NativeSelect>
              )}
            </Field>
          ) : null}
          {show("budget") ? (
            <Field label="Budget for the whole programme" optional>
              {(f) => (
                <NativeSelect id={f.id} value={prefs.budget} onChange={(e) => setPrefs({ ...prefs, budget: e.target.value })}>
                  <option value="">Choose…</option>
                  {BUDGETS.map((v) => <option key={v}>{v}</option>)}
                </NativeSelect>
              )}
            </Field>
          ) : null}
          {show("emi") ? (
            <fieldset className="grid gap-2">
              <legend className="text-text text-sm font-medium">Interested in EMI? <span className="text-subtle font-normal">(optional)</span></legend>
              <div className="flex gap-2">
                {(["yes", "no"] as const).map((v) => (
                  <label key={v} className={cn("border-border flex h-10 flex-1 cursor-pointer items-center justify-center rounded-full border text-sm", prefs.emi === v && "border-primary bg-amber-soft text-text")}>
                    <input type="radio" name="emi" className="sr-only" checked={prefs.emi === v} onChange={() => setPrefs({ ...prefs, emi: v })} />
                    {v === "yes" ? "Yes" : "No"}
                  </label>
                ))}
              </div>
            </fieldset>
          ) : null}
          <div className="grid gap-4 sm:grid-cols-2">
            {show("city") ? (
              <Field label="City" optional>
                {(f) => <Input id={f.id} autoComplete="address-level2" value={prefs.city} onChange={(e) => setPrefs({ ...prefs, city: e.target.value })} />}
              </Field>
            ) : null}
            {show("state") ? (
              <Field label="State" optional>
                {(f) => (
                  <NativeSelect id={f.id} autoComplete="address-level1" value={prefs.state} onChange={(e) => setPrefs({ ...prefs, state: e.target.value })}>
                    <option value="">Choose…</option>
                    {INDIAN_STATES.map((s) => <option key={s}>{s}</option>)}
                  </NativeSelect>
                )}
              </Field>
            ) : null}
          </div>
          <fieldset className="grid gap-2">
            <legend className="text-text text-sm font-medium">How should a counsellor contact you?</legend>
            <div className="flex gap-2">
              {(["call", "whatsapp", "email"] as const).map((v) => (
                <label key={v} className={cn("border-border flex h-10 flex-1 cursor-pointer items-center justify-center rounded-full border text-sm", prefs.contactMode === v && "border-primary bg-amber-soft text-text")}>
                  <input type="radio" name="contact" className="sr-only" checked={prefs.contactMode === v} onChange={() => setPrefs({ ...prefs, contactMode: v })} />
                  {v === "call" ? "Call" : v === "whatsapp" ? "WhatsApp" : "Email"}
                </label>
              ))}
            </div>
            {errors.contactMode ? <p role="alert" className="text-danger text-xs font-medium">{errors.contactMode}</p> : null}
          </fieldset>
          {show("bestTime") && prefs.contactMode !== "email" ? (
            <Field label="Best time to reach you" optional>
              {(f) => (
                <NativeSelect id={f.id} value={prefs.bestTime} onChange={(e) => setPrefs({ ...prefs, bestTime: e.target.value })}>
                  <option value="">Choose…</option>
                  {TIMES.map((v) => <option key={v}>{v}</option>)}
                </NativeSelect>
              )}
            </Field>
          ) : null}
          {show("questions") ? (
            <Field label="Any questions?" optional error={errors.questions}>
              {(f) => <Textarea id={f.id} aria-describedby={f.describedBy} aria-invalid={f.invalid} maxLength={1000} value={prefs.questions} onChange={(e) => setPrefs({ ...prefs, questions: e.target.value })} />}
            </Field>
          ) : null}
        </div>
      ) : (
        <div className="grid gap-3 text-sm">
          {[
            { step: 0, title: "Contact", rows: [contact.name, contact.phone && normaliseIndianMobile(contact.phone), contact.email] },
            { step: 1, title: "Academic", rows: [QUALS.find((q) => q.value === academic.qualification)?.label, academic.stream, academic.score && `${academic.score}${academic.scoreType === "cgpa" ? " CGPA" : "%"}`, academic.currentlyStudying ? "Currently studying" : academic.yearOfPassing && `Passed in ${academic.yearOfPassing}`, academic.board] },
            { step: 2, title: "Work and goals", rows: [work.working === "yes" ? `Working${work.years ? `, ${work.years} years` : ""}` : work.working === "no" ? "Not working" : "", work.role, work.industry, goals.find((g) => g.value === work.goal)?.label, work.why] },
            { step: 3, title: "Preferences", rows: [prefs.intake, prefs.budget, prefs.emi && `EMI: ${prefs.emi}`, [prefs.city, prefs.state].filter(Boolean).join(", "), prefs.contactMode && `Contact by ${prefs.contactMode}${prefs.bestTime ? `, ${prefs.bestTime.toLowerCase()}` : ""}`, prefs.questions] },
          ].map((s) => (
            <section key={s.title} className="border-border rounded-[var(--radius-lg)] border p-3">
              <div className="flex items-center justify-between">
                <h4 className="text-text font-medium">{s.title}</h4>
                {s.step > 0 ? (
                  <button type="button" onClick={() => setStep(s.step)} className="text-accent inline-flex items-center gap-1 text-xs font-medium">
                    <Pencil className="size-3.5" aria-hidden /> Edit <span className="sr-only">{s.title}</span>
                  </button>
                ) : null}
              </div>
              <ul className="text-muted mt-1 grid gap-0.5">
                {s.rows.filter(Boolean).map((r, i) => <li key={i}>{r}</li>)}
              </ul>
            </section>
          ))}
          <p className="text-subtle text-xs">Submitting asks a counsellor to help you apply. Eduwit never takes payments on this website.</p>
        </div>
      )}

      {phase === "form" ? (
        <div className="flex items-center gap-3 pt-1">
          {step > 1 ? (
            <button type="button" onClick={() => { setStep((s) => s - 1); scrollTop(); }} className="text-muted hover:text-text inline-flex h-11 items-center gap-1.5 text-sm">
              <ArrowLeft className="size-4" aria-hidden /> Back
            </button>
          ) : null}
          <button
            type="button"
            disabled={busy}
            onClick={() => void (step === 4 ? submit() : next())}
            className="bg-primary text-on-primary ml-auto inline-flex h-12 items-center gap-2 rounded-full px-6 text-sm font-semibold disabled:opacity-60"
          >
            {busy ? <Loader2 className="size-4 animate-spin" aria-hidden /> : null}
            {step === 0 ? (verifiedRef ? "Next" : "Verify email and continue") : step === 4 ? "Submit application request" : "Save and continue"}
          </button>
        </div>
      ) : null}
    </div>
  );
}
