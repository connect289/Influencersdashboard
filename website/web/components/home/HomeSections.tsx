import Link from "next/link";
import { ArrowRight, Compass, FileCheck2, Mail, MessagesSquare, Phone, Quote, ShieldCheck, Sparkles } from "lucide-react";
import { UniversityMark } from "@/components/finder/UniversityMark";
import { AskWitty } from "@/components/finder/AskWitty";
import { Badge } from "@/components/ui/Badge";
import { Disclosure } from "@/components/ui/Disclosure";
import { BRIDGE, HOW_IT_WORKS, PRINCIPLES, SERVICES } from "@/content/home";
import { COMPANY } from "@/content/site";
import { formatDate, formatInrRange } from "@/lib/format";
import type { ProgrammeGroup, UniversitySummary } from "@/lib/search/types";
import type { HomeContent } from "@/lib/server/content";

const STEP_ICONS = [Compass, MessagesSquare, FileCheck2];

export function PopularProgrammes({ groups }: { groups: ProgrammeGroup[] }) {
  if (!groups.length) return null;
  return (
    <section className="container-site grid gap-6 py-16" aria-labelledby="popular">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Popular right now</p>
          <h2 id="popular" className="mt-2 text-[length:var(--text-3xl)] font-semibold">Programmes students compare most</h2>
        </div>
        <Link href="/programmes" className="text-accent inline-flex items-center gap-1 text-sm font-medium hover:underline">
          All programmes <ArrowRight className="size-4" aria-hidden />
        </Link>
      </div>
      {/* Focusable scroll region so keyboard users can scroll the carousel (WCAG 2.1.1). */}
      <div role="region" aria-label="Popular programmes" tabIndex={0} className="-mx-[var(--gutter)] overflow-x-auto px-[var(--gutter)] pb-2">
        <ul className="flex snap-x snap-mandatory gap-4">
          {groups.slice(0, 8).map((g) => (
            <li key={g.key} className="glass hairline-lumen w-[17rem] shrink-0 snap-start rounded-[var(--radius-xl)]">
              <Link href={`/programmes?programme=${g.programme_id}&spec=${g.spec_ids.join(",")}`} className="grid h-full gap-1 p-5">
                <p className="eyebrow">{g.level_label}</p>
                <p className="font-display text-text mt-1 text-xl leading-tight font-semibold">
                  {g.programme_name} <span className="text-muted">· {g.spec_name}</span>
                </p>
                {g.fee_min && g.fee_max ? <p className="tabular text-text mt-3 font-semibold">{formatInrRange(g.fee_min, g.fee_max)}</p> : <p className="text-muted mt-3">Fee on request</p>}
                <p className="text-subtle text-xs">
                  {g.universities} {g.universities === 1 ? "university" : "universities"}
                  {g.fee_min ? " · Easy EMI available" : ""}
                </p>
                {g.best_naac ? <Badge tone="verified" className="mt-2 justify-self-start">Up to NAAC {g.best_naac}</Badge> : null}
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

export function UniversityStrip({ universities }: { universities: UniversitySummary[] }) {
  if (!universities.length) return null;
  return (
    <section className="border-border border-y py-10" aria-labelledby="partners">
      <div className="container-site grid gap-5">
        <h2 id="partners" className="eyebrow text-center">Partner universities</h2>
        <ul className="flex flex-wrap justify-center gap-x-3 gap-y-3">
          {universities.map((u) => (
            <li key={u.slug}>
              <Link href={`/universities/${u.slug}`} className="border-border bg-surface text-muted hover:text-text hover:border-border-strong inline-flex items-center gap-2 rounded-full border py-1 pr-3.5 pl-1 text-sm">
                <UniversityMark name={u.name} short={u.short} logo={u.logo} size={28} />
                {u.name}
              </Link>
            </li>
          ))}
        </ul>
        <p className="text-subtle text-center text-xs">University logos appear only with each university&apos;s permission.</p>
      </div>
    </section>
  );
}

export function HowItWorks() {
  return (
    <section className="container-site grid gap-10 py-20" aria-labelledby="how">
      <div className="text-center">
        <p className="eyebrow">How it works</p>
        <h2 id="how" className="mt-2 text-[length:var(--text-4xl)] font-semibold">
          Explore. Get matched. <span className="text-gradient-lumen">Apply with support.</span>
        </h2>
      </div>
      <ol className="grid gap-4 md:grid-cols-3">
        {HOW_IT_WORKS.map((s, i) => {
          const Icon = STEP_ICONS[i]!;
          return (
            <li key={s.title} className="glass hairline-lumen relative grid gap-3 rounded-[var(--radius-xl)] p-6">
              <span className="tabular font-display text-gradient-lumen text-5xl font-semibold" aria-hidden>0{i + 1}</span>
              <Icon className="text-amber-text size-6" aria-hidden />
              <h3 className="text-xl font-semibold">{s.title}</h3>
              <p className="text-muted">{s.body}</p>
            </li>
          );
        })}
      </ol>
      <p className="text-center">
        <Link href="/how-it-works" className="text-accent inline-flex items-center gap-1 text-sm font-medium hover:underline">
          More about how Eduwit works <ArrowRight className="size-4" aria-hidden />
        </Link>
      </p>
    </section>
  );
}

export function WhyEduwit() {
  return (
    <section className="container-site grid gap-4 pb-20 md:grid-cols-6" aria-labelledby="why">
      <div className="glass hairline-lumen grid content-between gap-6 rounded-[var(--radius-2xl)] p-7 md:col-span-4 md:row-span-2">
        <div>
          <p className="eyebrow">Why Eduwit</p>
          <h2 id="why" className="mt-2 text-[length:var(--text-3xl)] font-semibold">{BRIDGE.title}</h2>
          <p className="text-muted mt-4 max-w-xl">{BRIDGE.body}</p>
        </div>
        <ul className="grid gap-3 sm:grid-cols-3">
          {PRINCIPLES.map((p) => (
            <li key={p.title} className="grid gap-1">
              <span className="text-text flex items-center gap-1.5 text-sm font-semibold"><ShieldCheck className="text-success size-4" aria-hidden /> {p.title}</span>
              <span className="text-subtle text-xs leading-relaxed">{p.body}</span>
            </li>
          ))}
        </ul>
      </div>
      {SERVICES.map((s, i) => (
        <div key={s.title} className={i === 2 ? "glass grid content-start gap-2 rounded-[var(--radius-xl)] p-6 md:col-span-6 lg:col-span-2" : "glass grid content-start gap-2 rounded-[var(--radius-xl)] p-6 md:col-span-2"}>
          <Sparkles className="text-amber-text size-5" aria-hidden />
          <h3 className="font-semibold">{s.title}</h3>
          <p className="text-muted text-sm">{s.body}</p>
        </div>
      ))}
    </section>
  );
}

export function Stories({ testimonials }: { testimonials: HomeContent["testimonials"] }) {
  if (!testimonials.length) return null;
  return (
    <section className="container-site grid gap-6 pb-20" aria-labelledby="stories">
      <div>
        <p className="eyebrow">Student stories</p>
        <h2 id="stories" className="mt-2 text-[length:var(--text-3xl)] font-semibold">In their words</h2>
      </div>
      <ul className="grid gap-4 md:grid-cols-3">
        {testimonials.slice(0, 6).map((t, i) => (
          <li key={i} className="glass grid content-between gap-4 rounded-[var(--radius-xl)] p-6">
            <Quote className="text-amber-text size-6" aria-hidden />
            <blockquote className="text-text">{t.quote}</blockquote>
            <p className="text-muted text-sm">
              <span className="text-text font-semibold">{t.name}</span>
              {t.detail ? ` · ${t.detail}` : ""}
            </p>
          </li>
        ))}
      </ul>
    </section>
  );
}

export function GuidedTeaser() {
  return (
    <section className="container-site pb-20" aria-labelledby="guided-teaser">
      <div className="glass hairline-lumen grid items-center gap-6 rounded-[var(--radius-2xl)] p-7 md:grid-cols-[1fr_auto]">
        <div>
          <p className="eyebrow">Prefer not to chat?</p>
          <h2 id="guided-teaser" className="mt-2 text-[length:var(--text-3xl)] font-semibold">Answer three questions, see what fits</h2>
          <p className="text-muted mt-2">Your qualification, your goal and your budget. Results narrow as you answer, and you can change any answer.</p>
        </div>
        <Link href="/programmes?guided=1" className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 justify-self-start rounded-full px-6 font-semibold">
          <Compass className="size-4" aria-hidden /> Start the guided finder
        </Link>
      </div>
    </section>
  );
}

export function ResourcesTeaser({ resources }: { resources: HomeContent["resources"] }) {
  if (!resources.length) return null;
  return (
    <section className="container-site grid gap-6 pb-20" aria-labelledby="resources">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Guides</p>
          <h2 id="resources" className="mt-2 text-[length:var(--text-3xl)] font-semibold">Before you choose</h2>
        </div>
        <Link href="/resources" className="text-accent text-sm font-medium hover:underline">All guides</Link>
      </div>
      <ul className="grid gap-4 md:grid-cols-3">
        {resources.map((r) => (
          <li key={r.slug}>
            <Link href={`/resources/${r.slug}`} className="glass grid h-full gap-2 rounded-[var(--radius-xl)] p-6">
              <h3 className="text-text font-semibold">{r.title}</h3>
              {r.summary ? <p className="text-muted text-sm">{r.summary}</p> : null}
              {r.published_at ? <p className="text-subtle text-xs">{formatDate(r.published_at)}</p> : null}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}

export function HomeFaq({ faqs }: { faqs: HomeContent["faqs"] }) {
  if (!faqs.length) return null;
  return (
    <section className="container-site grid gap-6 pb-20 lg:grid-cols-[1fr_1.4fr]" aria-labelledby="faq">
      <div>
        <p className="eyebrow">Questions</p>
        <h2 id="faq" className="mt-2 text-[length:var(--text-3xl)] font-semibold">Good to know</h2>
      </div>
      <Disclosure name="faq" items={faqs.map((f, i) => ({ id: String(i), title: f.q, content: f.a }))} />
    </section>
  );
}

export function FinalCta({ advisorEnabled, whatsapp }: { advisorEnabled: boolean; whatsapp: string }) {
  return (
    <section className="container-site pb-20">
      <div className="grain glass-strong hairline-lumen relative isolate grid gap-6 overflow-hidden rounded-[var(--radius-2xl)] p-8 text-center sm:p-12">
        <h2 className="text-[length:var(--text-4xl)] font-semibold">Not sure where to start?</h2>
        <p className="text-muted mx-auto max-w-xl">{advisorEnabled ? "Ask Witty, or get free counselling from Eduwit's team." : "Get free counselling from Eduwit's team."}</p>
        <div className="flex flex-wrap justify-center gap-3">
          {advisorEnabled ? (
            <AskWitty enabled whatsapp={whatsapp} variant="primary" />
          ) : (
            <Link href="/contact#enquiry" className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold shadow-[var(--glow-amber)]">
              Get free counselling
            </Link>
          )}
          <Link href="/contact" className="border-border-strong text-text inline-flex h-12 items-center gap-2 rounded-full border px-6 font-semibold">
            <Phone className="size-4" aria-hidden /> Contact us
          </Link>
          <a href={`mailto:${COMPANY.email}`} className="border-border-strong text-text inline-flex h-12 items-center gap-2 rounded-full border px-6 font-semibold">
            <Mail className="size-4" aria-hidden /> {COMPANY.email}
          </a>
        </div>
      </div>
    </section>
  );
}
