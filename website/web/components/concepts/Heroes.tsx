import Link from "next/link";
import { ArrowRight, Search } from "lucide-react";
import { Atmosphere } from "@/components/fx/Atmosphere";
import { WittyOrb } from "@/components/witty/WittyOrb";
import { WittyHeroOrb } from "@/components/witty/WittyChatHead";
import { KineticHeadline } from "./KineticHeadline";
import { TrustLine } from "./TrustLine";

export const WITTY_GREETING =
  "Hi, I'm Witty, Eduwit's AI admissions assistant. Tell me what you'd like to study, and I'll help you find a programme that fits.";
export const STARTERS = [
  "Find an online MBA under ₹2L",
  "Which degree after 12th?",
  "Is online BCA valid for jobs?",
  "MBA for working professionals",
];

type Stats = { universities: number; programmes: number; allDeb: boolean };

/** Concept A: Witty at the centre of a living aurora; the chat surface is the banner. */
export function HeroA({ stats }: { stats: Stats }) {
  return (
    <section className="grain relative isolate overflow-hidden">
      <Atmosphere variant="aurora" />
      <div className="container-site relative flex min-h-[calc(100dvh-4rem)] flex-col items-center justify-center gap-5 py-10 text-center sm:gap-7 sm:py-14">
        <TrustLine {...stats} />
        <KineticHeadline
          text="Your next degree, found in a conversation."
          className="text-text max-w-4xl text-[length:var(--text-5xl)]"
        />
        <div className="flex flex-col items-center gap-3">
          <WittyHeroOrb href="/concepts/a/chat" />
          <p className="text-muted max-w-xl text-base sm:text-lg">{WITTY_GREETING}</p>
        </div>
        <Link
          href="/concepts/a/chat"
          className="glass-strong hairline-lumen group flex w-full max-w-2xl items-center gap-3 rounded-[var(--radius-2xl)] p-2 pl-5 text-left transition-shadow hover:shadow-[var(--glow-amber)]"
        >
          <span className="text-subtle flex-1 truncate text-base">Ask Witty anything about degrees and admissions…</span>
          <span className="bg-primary text-on-primary grid size-12 place-items-center rounded-full shadow-[var(--glow-amber)]">
            <ArrowRight className="size-5 transition-transform group-hover:translate-x-0.5" aria-hidden />
          </span>
        </Link>
        <ul className="flex max-w-2xl flex-wrap justify-center gap-2" aria-label="Suggested questions">
          {STARTERS.map((s) => (
            <li key={s}>
              <Link
                href={`/concepts/a/chat?start=${encodeURIComponent(s)}`}
                className="border-border bg-surface text-muted hover:border-border-strong hover:text-text inline-flex min-h-10 items-center rounded-full border px-4 text-sm backdrop-blur transition-colors"
              >
                {s}
              </Link>
            </li>
          ))}
        </ul>
        <Link
          href="/concepts/a/finder"
          className="text-muted hover:text-text text-sm font-medium underline-offset-4 hover:underline"
        >
          Prefer to browse? Explore all programmes →
        </Link>
      </div>
    </section>
  );
}

/** Concept B: editorial split — headline and search on the left, Witty as a floating companion card on the right. */
export function HeroB({ stats }: { stats: Stats }) {
  return (
    <section className="relative isolate overflow-hidden">
      <Atmosphere variant="prism" />
      <div className="container-site relative grid min-h-[calc(100dvh-4rem)] items-center gap-10 py-14 lg:grid-cols-[1.1fr_0.9fr]">
        <div className="grid gap-6">
          <p className="eyebrow">Eduwit Learning Services · Ghaziabad, Delhi NCR</p>
          <KineticHeadline text="Choose your education wisely." className="text-text text-[length:var(--text-6xl)]" />
          <p className="text-muted max-w-xl text-lg">
            Compare online, distance and on-campus degrees from Eduwit&apos;s partner universities — fees, approvals and
            eligibility side by side — then apply with free support.
          </p>
          <Link
            href="/concepts/b/finder"
            className="border-border-strong bg-bg-elev flex h-14 max-w-xl items-center gap-3 rounded-full border px-5 shadow-[var(--shadow-2)] transition-shadow hover:shadow-[var(--shadow-3)]"
          >
            <Search className="text-subtle size-5" aria-hidden />
            <span className="text-subtle min-w-0 flex-1 truncate">Search MBA, BCA, a university…</span>
            <span className="bg-primary text-on-primary rounded-full px-4 py-2 text-sm font-semibold">Search</span>
          </Link>
          <dl className="border-border grid max-w-xl grid-cols-3 gap-4 border-t pt-6">
            <div>
              <dt className="text-subtle text-xs">Partner universities</dt>
              <dd className="tabular font-display text-3xl font-semibold">{stats.universities}</dd>
            </div>
            <div>
              <dt className="text-subtle text-xs">Programmes</dt>
              <dd className="tabular font-display text-3xl font-semibold">{stats.programmes}</dd>
            </div>
            <div>
              <dt className="text-subtle text-xs">Counselling</dt>
              <dd className="font-display text-3xl font-semibold">Free</dd>
            </div>
          </dl>
        </div>
        <div className="glass-strong hairline-lumen grid gap-4 rounded-[var(--radius-2xl)] p-5 sm:p-6">
          <div className="flex items-center gap-3">
            <WittyOrb size={52} />
            <div>
              <p className="font-display text-lg font-semibold">Witty</p>
              <p className="text-success text-xs">● Online — replies in seconds</p>
            </div>
          </div>
          <p className="border-border bg-surface rounded-[var(--radius-lg)] rounded-tl-md border px-4 py-3 text-[0.9375rem]">
            {WITTY_GREETING}
          </p>
          <ul className="flex flex-wrap gap-2" aria-label="Suggested questions">
            {STARTERS.slice(0, 3).map((s) => (
              <li key={s}>
                <Link
                  href={`/concepts/b/chat?start=${encodeURIComponent(s)}`}
                  className="border-border text-muted hover:border-border-strong hover:text-text inline-flex min-h-10 items-center rounded-full border px-4 text-sm"
                >
                  {s}
                </Link>
              </li>
            ))}
          </ul>
          <Link
            href="/concepts/b/chat"
            className="border-border bg-bg-elev text-subtle flex items-center justify-between gap-3 rounded-full border p-1.5 pl-4"
          >
            Type your question…
            <span className="bg-navy-800 grid size-10 place-items-center rounded-full text-white">
              <ArrowRight className="size-4" aria-hidden />
            </span>
          </Link>
        </div>
      </div>
    </section>
  );
}
