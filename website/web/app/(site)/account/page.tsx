import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { Suspense } from "react";
import { signOutAction } from "@/app/actions/account";
import { rpc } from "@/lib/server/db";
import { currentStudent } from "@/lib/server/student-session";
import { ConsentControls, PrivacyRequests, ShortlistSync } from "./AccountClient";

export const metadata: Metadata = { title: "Your account", robots: { index: false, follow: false } };

interface Account {
  profile: { email: string; name: string | null; phone: string | null; email_verified_at: string | null; created_at: string };
  shortlist: number[];
  comparisons: { id: number; ids: number[]; created_at: string }[];
  applications: { reference: string; kind: string; status: string; programme: string | null; created_at: string; submitted_at: string | null }[];
  consents: { version: string; purposes: string[]; granted_at: string; withdrawn_at: string | null; body: string }[];
  requests: { kind: string; status: string; requested_at: string }[];
}

const date = (s: string) => new Date(s).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Kolkata" });
const STATUS: Record<string, string> = { started: "Started", step_2: "In progress", step_3: "In progress", step_4: "In progress", submitted: "Submitted" };
const REQUEST: Record<string, string> = { delete: "Delete my data", opt_out: "Opt out of contact", export: "Copy of my data" };
const maskPhone = (p: string) => `${p.slice(0, 3)} ••••• ${p.slice(-5)}`;

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="border-border bg-surface grid gap-3 rounded-[var(--radius-xl)] border p-5 sm:p-6">
      <h2 className="font-display text-text text-lg font-semibold">{title}</h2>
      {children}
    </section>
  );
}

async function AccountBody() {
  const student = await currentStudent();
  if (!student) redirect("/account/sign-in?next=/account");
  const a = await rpc<Account>("web_account", { p_student: student.studentId });
  const active = a.consents.filter((c) => !c.withdrawn_at);
  const has = (p: string) => active.some((c) => c.purposes.includes(p));
  return (
    <div className="grid gap-5">
      <Section title="Profile">
        <dl className="grid gap-2 text-sm sm:grid-cols-[10rem_1fr]">
          <dt className="text-muted">Name</dt>
          <dd className="text-text">{a.profile.name ?? "—"}</dd>
          <dt className="text-muted">Email</dt>
          <dd className="text-text">
            {a.profile.email} {a.profile.email_verified_at ? <span className="text-success">· verified</span> : null}
          </dd>
          <dt className="text-muted">Mobile</dt>
          <dd className="text-text">{a.profile.phone ? maskPhone(a.profile.phone) : "—"}</dd>
          <dt className="text-muted">Member since</dt>
          <dd className="text-text">{date(a.profile.created_at)}</dd>
        </dl>
        <p className="text-subtle text-xs">To change your name or number, tell your counsellor or WhatsApp us.</p>
      </Section>

      <Section title="Applications and enquiries">
        {a.applications.length ? (
          <ul className="divide-border grid divide-y">
            {a.applications.map((x) => (
              <li key={x.reference} className="flex flex-wrap items-center justify-between gap-2 py-3 text-sm">
                <span>
                  <span className="tabular text-text font-semibold">{x.reference}</span>
                  <span className="text-muted"> · {x.kind === "application" ? "Application request" : "Enquiry"}{x.programme ? ` · ${x.programme}` : ""}</span>
                </span>
                <span className="text-muted">
                  {STATUS[x.status] ?? x.status} · {date(x.submitted_at ?? x.created_at)}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-muted text-sm">
            None yet. Every programme in the <Link href="/programmes" className="text-accent underline underline-offset-4">finder</Link> has an application form.
          </p>
        )}
      </Section>

      <Section title="Shortlist">
        <ShortlistSync showSummary />
      </Section>

      <Section title="Saved comparisons">
        {a.comparisons.length ? (
          <ul className="grid gap-2 text-sm">
            {a.comparisons.map((c) => (
              <li key={c.id}>
                <Link href={`/compare?ids=${c.ids.join(",")}`} className="text-accent underline underline-offset-4">
                  {c.ids.length} programmes
                </Link>
                <span className="text-muted"> · saved {date(c.created_at)}</span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-muted text-sm">Use “Save comparison” on the compare page to keep one here.</p>
        )}
      </Section>

      <Section title="Consent">
        {a.consents.length ? (
          <ul className="grid gap-3 text-sm">
            {a.consents.map((c, i) => (
              <li key={`${c.version}-${i}`} className="grid gap-1">
                <span className="text-text font-medium">
                  {c.purposes.includes("marketing") ? "Programme updates" : "Contact about my enquiry"}
                  <span className={c.withdrawn_at ? "text-muted" : "text-success"}>
                    {" "}
                    · {c.withdrawn_at ? `withdrawn ${date(c.withdrawn_at)}` : `given ${date(c.granted_at)}`}
                  </span>
                </span>
                <span className="text-muted">“{c.body}” <span className="text-subtle">({c.version})</span></span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-muted text-sm">No consent recorded.</p>
        )}
        <ConsentControls marketing={has("marketing")} contact={has("sales")} />
      </Section>

      <Section title="Your data">
        <p className="text-muted text-sm">
          Ask for a copy of your data, opt out of all contact, or ask us to delete your data. See{" "}
          <Link href="/legal/data-privacy-opt-out" className="text-accent underline underline-offset-4">Data privacy &amp; opt-out</Link>.
        </p>
        {a.requests.length ? (
          <ul className="text-muted grid gap-1 text-sm">
            {a.requests.map((r, i) => (
              <li key={i}>
                {REQUEST[r.kind] ?? r.kind} · {r.status === "open" ? "in progress" : r.status} · {date(r.requested_at)}
              </li>
            ))}
          </ul>
        ) : null}
        <PrivacyRequests />
      </Section>

      <form action={signOutAction}>
        <button type="submit" className="text-muted text-sm font-medium hover:underline">
          Sign out
        </button>
      </form>
    </div>
  );
}

/** /account — profile, applications, shortlist, saved comparisons, consent and data requests (spec 12). */
export default function AccountPage() {
  return (
    <main id="main" className="container-site grid max-w-3xl gap-6 pt-8 pb-16">
      <header>
        <p className="eyebrow">Account</p>
        <h1 className="font-display text-text mt-1 text-3xl font-semibold">Your account</h1>
      </header>
      <Suspense fallback={<div className="h-96" aria-busy="true" />}>
        <AccountBody />
      </Suspense>
    </main>
  );
}
