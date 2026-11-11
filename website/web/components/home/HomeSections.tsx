import Link from "next/link";
import {
  ArrowRight,
  ArrowUpRight,
  Compass,
  FileCheck2,
  Mail,
  MessagesSquare,
  Phone,
  Quote,
  ShieldCheck,
  Sparkles,
} from "lucide-react";
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
/** Icon tiles cycle through the palette's three lights (styling only). */
const TILE_HUES = ["var(--primary)", "var(--lumen-cyan)", "var(--lumen-violet)"];

export function PopularProgrammes({ groups }: { groups: ProgrammeGroup[] }) {
  if (!groups.length) return null;
  return (
    <section className="container-site grid gap-8 pt-20 pb-8" aria-labelledby="popular" data-reveal>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Popular right now</p>
          <h2 id="popular" className="text-display mt-3 text-[length:var(--text-3xl)] font-semibold">
            Programmes students compare most
          </h2>
        </div>
        <Link
          href="/programmes"
          className="glass text-text hover:bg-surface-hover group inline-flex h-10 items-center gap-1.5 rounded-full px-4 text-sm font-medium"
        >
          All programmes <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
        </Link>
      </div>
      {/* Focusable scroll region so keyboard users can scroll the carousel (WCAG 2.1.1). */}
      <div
        role="region"
        aria-label="Popular programmes"
        tabIndex={0}
        className="-mx-[var(--gutter)] [scrollbar-width:thin] overflow-x-auto px-[var(--gutter)] pt-2 pb-6"
      >
        <ul className="flex snap-x snap-mandatory gap-4">
          {groups.slice(0, 8).map((g) => (
            <li
              key={g.key}
              className="glass hairline-lumen lift group w-[18rem] shrink-0 snap-start rounded-[var(--radius-xl)]"
            >
              <Link
                href={`/programmes?programme=${g.programme_id}&spec=${g.spec_ids.join(",")}`}
                className="grid h-full gap-1 p-6"
              >
                <span className="flex items-start justify-between gap-3">
                  <span className="eyebrow">{g.level_label}</span>
                  <ArrowUpRight
                    className="text-subtle group-hover:text-amber-text size-5 shrink-0 transition-[color,translate] group-hover:translate-x-0.5 group-hover:-translate-y-0.5"
                    aria-hidden
                  />
                </span>
                <p className="font-display text-text mt-2 text-xl leading-tight font-semibold tracking-tight">
                  {g.programme_name} <span className="text-muted font-medium">· {g.spec_name}</span>
                </p>
                {g.fee_min && g.fee_max ? (
                  <p className="tabular font-display text-text mt-4 text-lg font-semibold">
                    {formatInrRange(g.fee_min, g.fee_max)}
                  </p>
                ) : (
                  <p className="text-muted mt-4">Fee on request</p>
                )}
                <p className="text-subtle text-xs">
                  {g.universities} {g.universities === 1 ? "university" : "universities"}
                  {g.fee_min ? " · Easy EMI available" : ""}
                </p>
                {g.best_naac ? (
                  <Badge tone="verified" className="mt-2 justify-self-start">
                    Up to NAAC {g.best_naac}
                  </Badge>
                ) : null}
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
    <section className="py-12" aria-labelledby="partners">
      <hr className="rule-lumen container-site mb-12" />
      <div className="container-site grid gap-6">
        <h2 id="partners" className="eyebrow text-center">
          Partner universities
        </h2>
        <ul className="flex flex-wrap justify-center gap-x-2.5 gap-y-2.5">
          {universities.map((u) => (
            <li key={u.slug}>
              <Link
                href={`/universities/${u.slug}`}
                className="border-border bg-surface text-muted hover:text-text hover:border-border-strong hover:bg-surface-hover inline-flex items-center gap-2 rounded-full border py-1 pr-3.5 pl-1 text-sm backdrop-blur transition-colors"
              >
                <UniversityMark name={u.name} short={u.short} logo={u.logo} size={28} />
                {u.name}
              </Link>
            </li>
          ))}
        </ul>
        <p className="text-subtle text-center text-xs">
          University logos appear only with each university&apos;s permission.
        </p>
      </div>
      <hr className="rule-lumen container-site mt-12" />
    </section>
  );
}

export function HowItWorks() {
  return (
    <section className="container-site grid gap-12 py-24" aria-labelledby="how" data-reveal>
      <div className="text-center">
        <p className="eyebrow">How it works</p>
        <h2 id="how" className="text-display mt-3 text-[length:var(--text-4xl)] font-semibold">
          Explore. Get matched. <span className="text-gradient-lumen">Apply with support.</span>
        </h2>
      </div>
      <ol className="grid gap-4 md:grid-cols-3">
        {HOW_IT_WORKS.map((s, i) => {
          const Icon = STEP_ICONS[i]!;
          return (
            <li
              key={s.title}
              className="glass hairline-lumen relative grid content-start gap-4 overflow-hidden rounded-[var(--radius-xl)] p-7"
            >
              <span className="flex items-center justify-between">
                <span
                  className="icon-tile"
                  style={{ "--tile": TILE_HUES[i % TILE_HUES.length] } as React.CSSProperties}
                >
                  <Icon className="size-5" aria-hidden />
                </span>
                <span className="tabular font-display numeral-ghost text-6xl leading-none font-bold" aria-hidden>
                  0{i + 1}
                </span>
              </span>
              <h3 className="mt-2 text-xl font-semibold">{s.title}</h3>
              <p className="text-muted">{s.body}</p>
            </li>
          );
        })}
      </ol>
      <p className="text-center">
        <Link
          href="/how-it-works"
          className="glass text-text hover:bg-surface-hover group inline-flex h-11 items-center gap-1.5 rounded-full px-5 text-sm font-medium"
        >
          More about how Eduwit works{" "}
          <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
        </Link>
      </p>
    </section>
  );
}

export function WhyEduwit() {
  return (
    <section className="container-site grid gap-4 pb-24 md:grid-cols-6" aria-labelledby="why" data-reveal>
      <div className="glass hairline-lumen relative grid content-between gap-8 overflow-hidden rounded-[var(--radius-2xl)] p-7 sm:p-9 md:col-span-4 md:row-span-2">
        <span
          aria-hidden
          className="pointer-events-none absolute -top-24 -right-24 size-72 rounded-full bg-[radial-gradient(circle,color-mix(in_oklab,var(--primary)_22%,transparent),transparent_68%)]"
        />
        <div>
          <p className="eyebrow">Why Eduwit</p>
          <h2 id="why" className="text-display mt-3 text-[length:var(--text-3xl)] font-semibold">
            {BRIDGE.title}
          </h2>
          <p className="text-muted mt-4 max-w-xl">{BRIDGE.body}</p>
        </div>
        <ul className="border-border grid gap-5 border-t pt-6 sm:grid-cols-3">
          {PRINCIPLES.map((p) => (
            <li key={p.title} className="grid content-start gap-1.5">
              <span className="text-text flex items-center gap-1.5 text-sm font-semibold">
                <ShieldCheck className="text-success size-4" aria-hidden /> {p.title}
              </span>
              <span className="text-subtle text-xs leading-relaxed">{p.body}</span>
            </li>
          ))}
        </ul>
      </div>
      {SERVICES.map((s, i) => (
        <div
          key={s.title}
          className={
            i === 2
              ? "glass grid content-start gap-3 rounded-[var(--radius-xl)] p-6 md:col-span-6 md:grid-cols-[auto_1fr] md:items-center md:gap-x-5 md:[&>p]:col-start-2 md:[&>span]:row-span-2"
              : "glass grid content-start gap-3 rounded-[var(--radius-xl)] p-6 md:col-span-2"
          }
        >
          <span
            className="icon-tile"
            style={{ "--tile": TILE_HUES[(i + 1) % TILE_HUES.length] } as React.CSSProperties}
          >
            <Sparkles className="size-5" aria-hidden />
          </span>
          <h3 className="text-lg font-semibold">{s.title}</h3>
          <p className="text-muted text-sm">{s.body}</p>
        </div>
      ))}
    </section>
  );
}

export function Stories({ testimonials }: { testimonials: HomeContent["testimonials"] }) {
  if (!testimonials.length) return null;
  return (
    <section className="container-site grid gap-6 pb-20" aria-labelledby="stories" data-reveal>
      <div>
        <p className="eyebrow">Student stories</p>
        <h2 id="stories" className="text-display mt-3 text-[length:var(--text-3xl)] font-semibold">
          In their words
        </h2>
      </div>
      <ul className="grid gap-4 md:grid-cols-3">
        {testimonials.slice(0, 6).map((t, i) => (
          <li key={i} className="glass hairline-lumen grid content-between gap-4 rounded-[var(--radius-xl)] p-6">
            <span className="icon-tile">
              <Quote className="size-5" aria-hidden />
            </span>
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
    <section className="container-site pb-24" aria-labelledby="guided-teaser" data-reveal>
      <div className="glass hairline-lumen relative grid items-center gap-6 overflow-hidden rounded-[var(--radius-2xl)] p-7 sm:p-9 md:grid-cols-[1fr_auto]">
        <span
          aria-hidden
          className="pointer-events-none absolute -bottom-28 -left-20 size-72 rounded-full bg-[radial-gradient(circle,color-mix(in_oklab,var(--lumen-azure)_22%,transparent),transparent_68%)]"
        />
        <div>
          <p className="eyebrow">Prefer not to chat?</p>
          <h2 id="guided-teaser" className="text-display mt-3 text-[length:var(--text-3xl)] font-semibold">
            Answer three questions, see what fits
          </h2>
          <p className="text-muted mt-2">
            Your qualification, your goal and your budget. Results narrow as you answer, and you can change any answer.
          </p>
        </div>
        <Link
          href="/programmes?guided=1"
          className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 justify-self-start rounded-full px-6 font-semibold"
        >
          <Compass className="size-4" aria-hidden /> Start the guided finder
        </Link>
      </div>
    </section>
  );
}

export function ResourcesTeaser({ resources }: { resources: HomeContent["resources"] }) {
  if (!resources.length) return null;
  return (
    <section className="container-site grid gap-6 pb-20" aria-labelledby="resources" data-reveal>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="eyebrow">Guides</p>
          <h2 id="resources" className="text-display mt-3 text-[length:var(--text-3xl)] font-semibold">
            Before you choose
          </h2>
        </div>
        <Link href="/resources" className="text-accent text-sm font-medium hover:underline">
          All guides
        </Link>
      </div>
      <ul className="grid gap-4 md:grid-cols-3">
        {resources.map((r) => (
          <li key={r.slug}>
            <Link href={`/resources/${r.slug}`} className="glass lift grid h-full gap-2 rounded-[var(--radius-xl)] p-6">
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
    <section className="container-site grid gap-8 pb-24 lg:grid-cols-[1fr_1.4fr]" aria-labelledby="faq" data-reveal>
      <div>
        <p className="eyebrow">Questions</p>
        <h2 id="faq" className="text-display mt-3 text-[length:var(--text-3xl)] font-semibold">
          Good to know
        </h2>
      </div>
      <Disclosure name="faq" items={faqs.map((f, i) => ({ id: String(i), title: f.q, content: f.a }))} />
    </section>
  );
}

export function FinalCta({ advisorEnabled, whatsapp }: { advisorEnabled: boolean; whatsapp: string }) {
  return (
    <section className="container-site pb-24" data-reveal>
      <div className="grain glass-strong hairline-lumen relative isolate grid gap-6 overflow-hidden rounded-[var(--radius-2xl)] p-8 text-center sm:p-14">
        <span
          aria-hidden
          className="pointer-events-none absolute inset-x-0 -top-40 -z-10 mx-auto h-80 w-[min(48rem,100%)] rounded-full bg-[radial-gradient(closest-side,color-mix(in_oklab,var(--primary)_30%,transparent),transparent)]"
        />
        <span
          aria-hidden
          className="pointer-events-none absolute inset-x-0 -bottom-48 -z-10 mx-auto h-80 w-[min(56rem,100%)] rounded-full bg-[radial-gradient(closest-side,color-mix(in_oklab,var(--lumen-azure)_24%,transparent),transparent)]"
        />
        <h2 className="text-display text-[length:var(--text-4xl)] font-semibold">Not sure where to start?</h2>
        <p className="text-muted mx-auto max-w-xl">
          {advisorEnabled
            ? "Ask Witty, or get free counselling from Eduwit's team."
            : "Get free counselling from Eduwit's team."}
        </p>
        <div className="flex flex-wrap justify-center gap-3">
          {advisorEnabled ? (
            <AskWitty enabled whatsapp={whatsapp} variant="primary" />
          ) : (
            <Link
              href="/contact#enquiry"
              className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold"
            >
              Get free counselling
            </Link>
          )}
          <Link
            href="/contact"
            className="glass text-text hover:bg-surface-hover inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold"
          >
            <Phone className="size-4" aria-hidden /> Contact us
          </Link>
          <a
            href={`mailto:${COMPANY.email}`}
            className="glass text-text hover:bg-surface-hover inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold"
          >
            <Mail className="size-4" aria-hidden /> {COMPANY.email}
          </a>
        </div>
      </div>
    </section>
  );
}
